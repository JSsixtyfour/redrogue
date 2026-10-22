"""Composed rental + physical run-reset journal model. No ROM integration."""
from __future__ import annotations

import argparse
import json
import random
import struct
from functools import lru_cache
from pathlib import Path

from model_save_metadata import SLOT, DONE, FORWARD, ROLLBACK, encode, publication, select
from model_save_lifecycle import sealed, unseal, record_writes
from model_save_handoff import (Layout, initial, chosen, gather, physical, outcome,
                               mapped_writes, publish, checksum_writes, handoff,
                               intent as pc_intent, recovery_writes as pc_recovery)
from model_rental_rollback import Phase, phases, reference
from model_rental_transaction import (HEADER, DESCRIPTOR, JSIZE, BOX as VIRTUAL_BOX,
                                     serialize, forward_chunks, inverse_chunks)

RESET = struct.Struct('<BII BBH')
RESET_READY = 0x8000  # count uses fewer than 32768 chunks; no added SRAM byte


class ResetLayout(Layout):
    def __init__(self):
        super().__init__('sum8', descriptor=True, shared_marker=True)
        self.fallen = list(range(physical(*self.sym['sFallenLog']), physical(*self.sym['sFallenLogEnd'])))
        self.tm = list(range(physical(*self.sym['sTMBitfield']), physical(*self.sym['sTMBitfield']) + 7))
        self.headers = [address for box in self.boxes for address in box[:2]]
        assert len(self.fallen) == 660

    def rental_map(self, active):
        return self.boxes[active][self.spill:self.spill + JSIZE]

    def reset_map(self, active):
        # 660 payload bytes use the archive tail; 49 header/payload/CRC/marker
        # bytes use sprite scratch. Marker is COMMON to PC and reset records.
        backup = self.boxes[active][self.spill + JSIZE:self.spill + JSIZE + 660]
        assert len(backup) == 660
        return self.scratch[:RESET.size] + backup + self.scratch[RESET.size:48] + self.scratch[-1:]


@lru_cache(maxsize=128)
def rental_decode(record):
    body = unseal(record)
    if body is None:
        return None
    version, parent, child, slot, count = HEADER.unpack_from(body)
    if version != 1 or child != parent + 1 or slot != 1 or not 1 <= count <= 10:
        raise ValueError('invalid rental journal')
    offset, groups = HEADER.size, []
    for _ in range(count):
        box, start, stride, length, size = DESCRIPTOR.unpack_from(body, offset)
        offset += DESCRIPTOR.size
        saved = body[offset:offset + size]
        offset += size
        if box >= 12 or not 1 <= size <= 33 or start + stride + length > 1122:
            raise ValueError('invalid canonical box phase')
        literal = (saved[0] - 1 if start == 0 else 255) if stride == 0 else None
        groups.append((box, Phase(start, stride, length, saved, literal)))
    return parent, child, groups


@lru_cache(maxsize=128)
def fplan(record):
    return forward_chunks(rental_decode(record)[2])


@lru_cache(maxsize=256)
def iplan(record, count):
    return inverse_chunks(rental_decode(record)[2], count)


def cursor(memory, layout, mode, child, count, undo):
    try:
        writes = publication(gather(memory, layout.rental_cursor), mode, child, count, undo)
    except ValueError:
        writes = record_writes(0, encode(0, mode, child, count, undo))
    return [(layout.rental_cursor[a], v) for a, v in writes]


def expand(memory, layout, chunk):
    def address(virtual):
        box, offset = divmod(virtual - VIRTUAL_BOX, 1122)
        return layout.boxes[box][offset]
    return [(address(dst), literal if src is None else memory[address(src)])
            for dst, src, literal in chunk]


def transaction(memory, layout, same_box, has_rental=True):
    generation, slot, active, image = chosen(memory, layout)
    child = generation + 1
    ids = [(active + 1) % 12, (active + (1 if same_box else 7)) % 12]
    boxes = {box: bytearray(gather(memory, layout.boxes[box])) for box in ids}
    groups = []
    for box, index in (zip(ids, (0, 4)) if has_rental else []):
        groups.extend((box, phase) for phase in phases(boxes[box], index))
        boxes[box] = reference(boxes[box], index)
    record = serialize(generation, child, 1, groups) if has_rental else None
    if record:
        for write in mapped_writes(layout.rental_map(active), record):
            yield write
    for write in cursor(memory, layout, DONE, child, 0, 0):
        yield write
    chunks = fplan(record) if record else []
    for count, chunk in enumerate(chunks):
        for write in cursor(memory, layout, FORWARD, child, count, 0):
            yield write
        for write in expand(memory, layout, chunk):
            yield write
    for write in cursor(memory, layout, DONE, child, len(chunks), 0):
        yield write
    # Move the exact checkpoint before EmptyAllSRAMBoxes touches its prefix.
    if slot == 1:
        for write in mapped_writes(layout.main0, image):
            yield write
        for write in publish(memory, layout, generation, 0, active):
            yield write
    raw = gather(memory, layout.fallen + layout.tm + layout.headers)
    reset = sealed(RESET.pack(2, generation, child, active, active, len(raw)) + raw)
    for write in mapped_writes(layout.reset_map(active), reset):
        yield write
    # A torn write to an invalid marker can manufacture $A5. Authorize reset
    # mutation through the separately redundant cursor only AFTER body validity.
    for write in cursor(memory, layout, DONE, child, len(chunks) | RESET_READY, 0):
        yield write
    for address in layout.fallen + layout.tm:
        yield address, 0
    for box in layout.boxes:
        yield box[0], 0
        yield box[1], 255
    # Byte fixture of the post-reset snapshot, not a live Dorm choreography test.
    payload = bytearray(layout.unseal_main(image)[4:])
    base = layout.sym['sMainData'][1] - layout.sym['sGameData'][1]
    origin = layout.sym['wMainDataStart'][1]
    def at(label):
        return base + layout.sym[label][1] - origin
    keep = [(at('wGymsUsedMask'), 2), (at('wCreditsEarnedThisRun'), 1)]
    saved = [(offset, payload[offset:offset + size]) for offset, size in keep]
    start, end = at('wGameProgressFlags'), at('wGameProgressFlagsEnd')
    payload[start:end] = bytes(end - start)
    for offset, values in saved:
        payload[offset:offset + len(values)] = values
    payload[layout.box_offset:layout.box_offset + 2] = bytes([0, 255])
    party = layout.sym['sPartyData'][1] - layout.sym['sGameData'][1]
    payload[party:party + 2] = bytes([0, 255])
    target = layout.seal_main(child, payload)
    for write in mapped_writes(layout.main(1, active), target):
        yield write
    for write in publish(memory, layout, child, 1, active):
        yield write
    for write in cursor(memory, layout, DONE, child, 0, 0):
        yield write
    yield layout.scratch[-1], 0
    yield layout.rental_map(active)[-1], 0
    for write in checksum_writes(memory, layout):
        yield write


def recovery_step(memory, layout):
    generation, _, active, _ = chosen(memory, layout)
    rmap = layout.rental_map(active)
    rental = gather(memory, rmap)
    try:
        _, (_, mode, txn, count, undo) = select(gather(memory, layout.rental_cursor))
    except ValueError:
        mode, txn, count, undo = DONE, 0, 0, 0
    owns_rental = txn in (generation, generation + 1) and (mode != DONE or count != 0)
    info = rental_decode(rental) if owns_rental else None
    ready = mode == DONE and bool(count & RESET_READY)
    if memory[layout.scratch[-1]] == 0xA5:
        # Dispatch the shared buffer by type. An old committed PC journal may
        # reappear at a torn invalidation before preparing the reset record.
        if memory[layout.scratch[0]] == 1 and pc_intent(memory, layout) is not None:
            return pc_recovery(memory, layout)
        if not ready:
            # No destructive reset could have started without the READY publish.
            # Also handles completed undo after READY was durably cleared.
            return [(layout.scratch[-1], 0)]
        raw = unseal(gather(memory, layout.reset_map(active)))
        if raw is None:
            raise ValueError('valid shared marker but invalid reset body')
        kind, parent, child, old, new, size = RESET.unpack_from(raw)
        if kind != 2 or old != active or new != active or size != 691:
            raise ValueError('bad reset journal')
        if txn != child:
            raise ValueError('reset authorization belongs to another transaction')
        if generation == child:
            return cursor(memory, layout, DONE, child, 0, 0) + [(layout.scratch[-1], 0)]
        if generation != parent:
            raise ValueError('stale reset')
        # IMPORTANT: retire reset before starting rental undo. Otherwise another
        # reset could reapply post-removal counts after rental restored them.
        return list(zip(layout.fallen + layout.tm + layout.headers, raw[RESET.size:])) + cursor(
            memory, layout, DONE, child, count & ~RESET_READY, 0) + [
            (layout.scratch[-1], 0)]
    if memory[layout.scratch[-1]] != 0:
        return [(layout.scratch[-1], 0)]
    if info:
        parent, child, _ = info
        if generation == child:
            return [(rmap[-1], 0)]
        if generation != parent:
            raise ValueError('stale rental')
        if txn != child or (mode == DONE and count == 0):
            return [(rmap[-1], 0)]
        if mode == FORWARD:
            return expand(memory, layout, fplan(rental)[count]) + cursor(
                memory, layout, ROLLBACK, child, count + 1, 0)
        if mode == DONE:
            return cursor(memory, layout, ROLLBACK, child, count, 0)
        inverse = iplan(rental, count)
        if undo == len(inverse):
            return cursor(memory, layout, DONE, child, 0, 0)
        return expand(memory, layout, inverse[undo]) + cursor(
            memory, layout, ROLLBACK, child, count, undo + 1)
    if memory[rmap[-1]] != 0:
        # The new active archive after PC commit can contain arbitrary former
        # box bytes. Without an owning cursor they are NOT a rental journal.
        return [(rmap[-1], 0)]
    return [(a, v) for a, v in checksum_writes(memory, layout) if memory[a] != v]


def view(memory, layout):
    return outcome(memory, layout), gather(memory, layout.fallen + layout.tm)


def recover(memory, layout, rng):
    resets = 0
    for _ in range(100000):
        writes = recovery_step(memory, layout)
        if not writes:
            return view(memory, layout), resets
        for address, value in writes:
            if rng.randrange(257) == 0:
                memory[address] = rng.randrange(256)
                resets += 1
                break
            memory[address] = value
    raise AssertionError('recovery failed to terminate')


def run():
    layout = ResetLayout()
    cases = resets = 0
    cross_cases = cross_resets = 0
    for seed, has_rental in ((0, True), (5, True), (8, False)):
        memory = initial(layout, seed)
        active = chosen(memory, layout)[2]
        memory[layout.rental_map(active)[-1]] = 0
        memory[layout.scratch[-1]] = 0
        for i, address in enumerate(layout.fallen + layout.tm):
            memory[address] = (i * 7 + seed + 1) & 255
        for a, v in checksum_writes(memory, layout):
            memory[a] = v
        # Exercise PC -> rental/reset with a retired old PC body still present.
        image = chosen(memory, layout)[3]
        live = layout.unseal_main(image)[4 + layout.box_offset:4 + layout.box_offset + 1122]
        target = (active + 2) % 12
        for a, v in handoff(memory, layout, target, live):
            memory[a] = v
        recover(memory, layout, random.Random(seed))
        old = view(memory, layout)
        final = memory.copy()
        trace = []
        for a, v in transaction(final, layout, bool(seed), has_rental):
            trace.append((a, v))
            final[a] = v
        new = view(final, layout)
        assert gather(final, layout.fallen + layout.tm) == bytes(667)
        rng = random.Random(seed)
        positions = {0, len(trace) - 1, *[rng.randrange(len(trace)) for _ in range(80)]}
        prefix = memory.copy()
        for i, (a, v) in enumerate(trace):
            important = a in (layout.scratch[-1], layout.selector[SLOT - 1], layout.selector[-1])
            if important or i in positions:
                tears = range(256) if important else {0, 255, v, prefix[a], rng.randrange(256)}
                for torn in tears:
                    cut = prefix.copy()
                    cut[a] = torn
                    result, nresets = recover(cut, layout, rng)
                    assert result in (old, new), (seed, i, a, torn)
                    cases += 1
                    resets += nresets
            prefix[a] = v
        # Exercise reset -> PC, including stale RESET bytes and the shared tag.
        memory = final
        active = chosen(memory, layout)[2]
        old = view(memory, layout)
        image = chosen(memory, layout)[3]
        live = layout.unseal_main(image)[4 + layout.box_offset:4 + layout.box_offset + 1122]
        pc_final = memory.copy()
        pc_trace = []
        for a, v in handoff(pc_final, layout, (active + 3) % 12, live):
            pc_trace.append((a, v))
            pc_final[a] = v
        new = view(pc_final, layout)
        positions = {0, len(pc_trace) - 1, *[rng.randrange(len(pc_trace)) for _ in range(80)]}
        for i, (a, v) in enumerate(pc_trace):
            important = a in (layout.scratch[-1], layout.selector[SLOT - 1], layout.selector[-1])
            if important or i in positions:
                for torn in (range(256) if important else {0, 255, v, memory[a], rng.randrange(256)}):
                    cut = memory.copy()
                    cut[a] = torn
                    result, nresets = recover(cut, layout, rng)
                    assert result in (old, new), ('reset->PC', seed, i, a, torn)
                    cross_cases += 1
                    cross_resets += nresets
            memory[a] = v
    return {'status': 'MODEL ONLY; composed inactive rental removals and physical run reset',
            'fixtures': 3, 'includes_reset_without_rental': True,
            'fault_cases': cases, 'recovery_resets': resets,
            'reset_to_pc_fault_cases': cross_cases, 'reset_to_pc_recovery_resets': cross_resets,
            'rental_journal_bytes': JSIZE, 'fallen_backup_bytes': 660,
            'archive_tail_bytes': 1122 - layout.spill,
            'archive_tail_used': JSIZE + 660,
            'sprite_reset_bytes': 49, 'shared_validity_sprite_offset': 391,
            'physical_fallen_clear_preserved': True,
            'limits': ['sampled schedules, not exhaustive', 'no live Dorm/credits choreography',
                       'no all-companion inventory or ROM hooks', 'no ROM latency',
                       'ordered isolated byte writes; checksum collisions not excluded']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = run()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    print(json.dumps(report, indent=2))
