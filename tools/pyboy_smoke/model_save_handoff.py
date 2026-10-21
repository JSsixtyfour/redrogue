"""Physical SRAM overlap model for a candidate box-change handoff.

No declarations/ROM code change. Candidate padding is not allocated. Borrows
one sprite buffer for an undo prefix, requiring recovery BEFORE decompression.
Rental journals must be retired before box exchange; this is a hard precondition.
"""
from __future__ import annotations

import argparse
import json
import random
import re
import struct
from pathlib import Path

from model_save_metadata import SLOT, DONE, encode, select, publication
from model_save_lifecycle import MAIN, PAYLOAD, sealed, unseal, record_writes
from model_rental_rollback import fixture

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'tools/pyboy_smoke/artifacts/save_writer_fused_2026-10-21_20e709cd'
HEAD = struct.Struct('<BII BBH')  # version, parent, child, old/new box, prefix length


def physical(bank, address):
    return bank * 8192 + address - 0xA000


def symbols():
    result = {}
    for line in (BASE / 'pokered.sym').read_text().splitlines():
        match = re.match(r'([0-9a-fA-F]+):([0-9a-fA-F]+) (\S+)$', line)
        if match:
            bank, address, name = match.groups()
            result[name] = (int(bank, 16), int(address, 16))
    return result


class AddressMap(list):
    """Cache address spans only, never persistent contents or recovery state."""
    def __init__(self, addresses):
        super().__init__(addresses)
        self.spans = []
        for address in self:
            if self.spans and self.spans[-1][1] == address:
                self.spans[-1] = (self.spans[-1][0], address + 1)
            else:
                self.spans.append((address, address + 1))


class Layout:
    def __init__(self):
        self.sym = symbols()
        budget = json.loads((BASE / 'recovery_budget_candidate.json').read_text())
        pool = []
        for extent in budget['pool_extents']:
            pool.extend(physical(extent['bank'], address)
                        for address in range(extent['start'], extent['end']))
        assert len(pool) == len(set(pool)) == 3645
        self.selector = pool[:SLOT * 2]
        self.rental_cursor = pool[SLOT * 2:SLOT * 4]  # reserved, not reused
        framing = pool[SLOT * 4:SLOT * 4 + 9]
        self.shadow = pool[SLOT * 4 + 9:]
        self.spill = MAIN - len(self.shadow)
        self.boxes = [list(range(physical(*self.sym[f'sBox{i}']),
                                 physical(*self.sym[f'sBox{i}']) + 1122)) for i in range(1, 13)]
        self.main0 = framing[:4] + list(range(physical(*self.sym['sGameData']),
                                             physical(*self.sym['sGameDataEnd']))) + framing[4:]
        assert len(self.main0) == MAIN
        self.main0 = AddressMap(self.main0)
        self.main1 = [AddressMap(self.shadow + addresses[:self.spill]) for addresses in self.boxes]
        self.scratch = list(range(physical(*self.sym['sSpriteBuffer0']),
                                  physical(*self.sym['sSpriteBuffer1'])))
        self.jsize = HEAD.size + self.spill + 5
        self.journal = self.scratch[:self.jsize]
        assert self.jsize <= len(self.scratch) == 392
        self.box_offset = self.sym['sCurBoxData'][1] - self.sym['sGameData'][1]
        self.current_offset = 11 + self.sym['wCurrentBoxNum'][1] - self.sym['wMainDataStart'][1]
        regions = [pool, self.main0[4:-5], self.scratch, *self.boxes]
        flat = [a for region in regions for a in region]
        assert len(flat) == len(set(flat))
        assert all((address % 8192) // 256 != 0x1D for address in flat)

    def main(self, slot, active):
        return self.main0 if slot == 0 else self.main1[active]


def gather(memory, addresses):
    if isinstance(addresses, AddressMap):
        return b''.join(memory[start:end] for start, end in addresses.spans)
    return bytes(memory[a] for a in addresses)


def mapped_writes(addresses, record):
    assert len(addresses) == len(record)
    return [(addresses[a], value) for a, value in record_writes(0, record)]


def chosen(memory, layout):
    _, (_, mode, generation, location, undo) = select(gather(memory, layout.selector))
    slot, active = location & 1, location >> 1
    if mode != DONE or active >= 12 or undo:
        raise ValueError('invalid selector context')
    image = gather(memory, layout.main(slot, active))
    body = unseal(image)
    if body is None or struct.unpack('<I', body[:4])[0] != generation:
        raise ValueError('invalid selected main')
    if body[4 + layout.current_offset] & 15 != active:
        raise ValueError('selector/main active box mismatch')
    return generation, slot, active, image


def publish(memory, layout, generation, slot, active):
    return [(layout.selector[a], value) for a, value in publication(
        gather(memory, layout.selector), DONE, generation, (active << 1) | slot, 0)]


def intent(memory, layout):
    body = unseal(gather(memory, layout.journal))
    if body is None:
        return None
    version, parent, child, old, new, size = HEAD.unpack_from(body)
    if version != 1 or child != parent + 1 or old >= 12 or new >= 12 or old == new or size != layout.spill:
        raise ValueError('invalid handoff journal')
    return parent, child, old, new, body[HEAD.size:]


def outcome(memory, layout):
    _, _, active, image = chosen(memory, layout)
    body = unseal(image)[4:]
    boxes = [body[layout.box_offset:layout.box_offset + 1122] if i == active else
             bytes(memory[addresses[0]:addresses[0] + 1122])
             for i, addresses in enumerate(layout.boxes)]
    return body, tuple(boxes)


def recovery_writes(memory, layout):
    current = chosen(memory, layout)
    journal = intent(memory, layout)
    if journal is None:
        return []
    generation, _, active, _ = current
    parent, child, old, new, before = journal
    if (generation, active) == (child, new):
        return [(layout.journal[-1], 0)]
    if (generation, active) != (parent, old):
        raise ValueError('stale journal/selector disagreement')
    return list(zip(layout.boxes[new][:layout.spill], before)) + [(layout.journal[-1], 0)]


def recover(memory, layout, rng):
    resets = writes = 0
    for _ in range(100000):
        operations = recovery_writes(memory, layout)
        if not operations:
            return outcome(memory, layout), resets, writes
        for address, value in operations:
            writes += 1
            if rng.randrange(127) == 0:
                memory[address] = rng.randrange(256)
                resets += 1
                break
            memory[address] = value
    raise AssertionError('recovery did not terminate')


def handoff(memory, layout, target, live, live_journal=False):
    if live_journal:
        raise ValueError('retire or recover rental journal before exchange')
    generation, slot, old, image = chosen(memory, layout)
    assert old != target and intent(memory, layout) is None
    # Relocate the EXACT SELECTED IMAGE, never the newer live WRAM snapshot.
    if slot == 1:
        for write in mapped_writes(layout.main0, image):
            yield write
        for write in publish(memory, layout, generation, 0, old):
            yield write
    new_box = gather(memory, layout.boxes[target])
    header = HEAD.pack(1, generation, generation + 1, old, target, layout.spill)
    journal = sealed(header + new_box[:layout.spill])
    for write in mapped_writes(layout.journal, journal):
        yield write
    # Existing exchange: archive outgoing live box, load incoming box, clear its
    # source header. WRAM loading itself is represented by new_box, not persisted.
    for write in zip(layout.boxes[old], live):
        yield write
    yield layout.boxes[target][0], 0
    yield layout.boxes[target][1], 255
    payload = bytearray(unseal(image)[4:])
    payload[3] ^= 0x5A  # newer live state, distinct from the selected old snapshot
    payload[layout.current_offset] = target | 0x80
    payload[layout.box_offset:layout.box_offset + 1122] = new_box
    new_image = sealed(struct.pack('<I', generation + 1) + payload)
    for write in mapped_writes(layout.main(1, target), new_image):
        yield write
    for write in publish(memory, layout, generation + 1, 1, target):
        yield write
    yield layout.journal[-1], 0


def initial(layout, seed):
    memory = bytearray([255]) * 32768
    for i, addresses in enumerate(layout.boxes):
        for address, value in zip(addresses, fixture(20, seed + i)):
            memory[address] = value
    active = seed % 12
    payload = bytearray((i * 13 + seed) & 255 for i in range(PAYLOAD))
    payload[layout.current_offset] = active | 0x80
    payload[layout.box_offset:layout.box_offset + 1122] = fixture(20, seed + 100)
    image = sealed(struct.pack('<I', 1) + payload)
    for address, value in mapped_writes(layout.main(1, active), image):
        memory[address] = value
    for address, value in mapped_writes(layout.selector[:SLOT], encode(
            0, DONE, 1, (active << 1) | 1, 0)):
        memory[address] = value
    return memory


def run(trials):
    layout = Layout()
    cases = resets = writes = max_trace = 0
    for trial in range(trials):
        seed = trial * 5  # second fixture crosses the SRAM box-bank boundary
        rng = random.Random(seed)
        memory = initial(layout, seed)
        for exchange in range(2):
            old = outcome(memory, layout)
            active = chosen(memory, layout)[2]
            target = (active + 1 + seed % 10) % 12
            live = fixture(19, seed + exchange + 1000)
            # Ensure a live rental journal prevents any destructive writes.
            try:
                next(handoff(memory, layout, target, live, live_journal=True))
            except ValueError:
                pass
            else:
                raise AssertionError('live rental journal was not blocked')
            final = memory.copy()
            trace = []
            for address, value in handoff(final, layout, target, live):
                trace.append((address, value))
                final[address] = value
            new = outcome(final, layout)
            max_trace = max(max_trace, len(trace))
            assert old != new
            prefix = memory.copy()
            marker_addresses = {layout.main0[-1], layout.main(1, target)[-1],
                                layout.journal[-1], layout.selector[SLOT - 1],
                                layout.selector[-1]}
            for address, value in trace:
                # Every byte boundary; all 256 tears at marker publications,
                # otherwise one seeded arbitrary value plus intended value.
                values = range(256) if address in marker_addresses else {rng.randrange(256), value}
                for torn in values:
                    cut = prefix.copy()
                    cut[address] = torn
                    result, nresets, nwrites = recover(cut, layout, rng)
                    assert result in (old, new), (seed, exchange, address, torn)
                    cases += 1
                    resets += nresets
                    writes += nwrites
                prefix[address] = value
            memory = final
    return {'status': 'MODEL ONLY: physical overlap handoff with sprite scratch',
            'trials': trials, 'box_changes': trials * 2, 'fault_cases': cases,
            'recovery_resets': resets, 'recovery_byte_writes': writes,
            'shadow_spill_bytes': layout.spill, 'sprite_journal_bytes': layout.jsize,
            'sprite_buffer_bytes': len(layout.scratch),
            'max_handoff_byte_writes': max_trace,
            'live_rental_journal_blocked': True,
            'limits': ['candidate padding not allocated', 'no early-boot hook implemented',
                       'no box checksum bookkeeping or gameplay hooks',
                       'two changes per fixture, not all schedules',
                       'no migration or epoch wrap', 'no ROM latency',
                       'CRC collisions not excluded; ordered isolated byte writes']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', type=int, default=2)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    assert args.trials >= 1
    report = run(args.trials)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    print(json.dumps(report, indent=2))
