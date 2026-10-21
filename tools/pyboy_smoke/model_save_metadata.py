"""Byte-fault model of a candidate two-slot rental recovery cursor.

Not assembled or connected to SRAM. Immutable, already validated transaction
journal and descriptors are supplied by the fixture. No main generation commit,
new-game/legacy bootstrap, corruption guarantee, or timing claim is made.
"""
from __future__ import annotations

import argparse
import json
import random
import struct
import zlib
from pathlib import Path

from model_rental_rollback import fixture, phases

BODY = struct.Struct('<IBIHH')  # sequence, mode, transaction, forward count, undo cursor
SLOT = BODY.size + 5  # CRC32 plus final validity byte
VALID = 0xA5
FORWARD, ROLLBACK, DONE = range(3)


def encode(seq, mode, txn, count, undo):
    body = BODY.pack(seq, mode, txn, count, undo)
    return body + struct.pack('<I', zlib.crc32(body)) + bytes([VALID])


def select(memory):
    valid = []
    for slot in range(2):
        record = memory[slot * SLOT:(slot + 1) * SLOT]
        if record[-1] != VALID:
            continue
        body = record[:BODY.size]
        if zlib.crc32(body) != struct.unpack('<I', record[BODY.size:-1])[0]:
            continue
        fields = BODY.unpack(body)
        if fields[1] > DONE:
            continue
        valid.append((slot, fields))
    if not valid:
        raise ValueError('no valid cursor: refuse, never guess')
    if len(valid) == 1:
        return valid[0]
    a, b = valid
    delta = (b[1][0] - a[1][0]) & 0xFFFFFFFF
    if delta in (0, 0x80000000):
        raise ValueError('ambiguous sequence: refuse')
    return b if delta < 0x80000000 else a


def publication(memory, mode, txn, count, undo):
    slot, old = select(memory)
    target = (1 - slot) * SLOT
    record = encode((old[0] + 1) & 0xFFFFFFFF, mode, txn, count, undo)
    # Invalidate the older slot BEFORE any body write; retain the latest slot.
    return [(target + SLOT - 1, 0)] + list(enumerate(record[:-1], target)) + [
        (target + SLOT - 1, VALID)]


def publication_tests():
    cases = 0
    for seq in (1, 0xFFFFFFFF):
        memory = bytearray(encode((seq - 1) & 0xFFFFFFFF, FORWARD, 7, 3, 0)
                           + encode(seq, FORWARD, 7, 4, 0))
        old = select(memory)[1]
        writes = publication(memory, ROLLBACK, 7, 5, 0)
        new = ((seq + 1) & 0xFFFFFFFF, ROLLBACK, 7, 5, 0)
        for address, value in writes:
            for torn in range(256):
                cut = memory.copy()
                cut[address] = torn
                assert select(cut)[1] in (old, new)
                cases += 1
            memory[address] = value
        assert select(memory)[1] == new
    # Explicit malformed/ambiguous records fail closed.
    for memory in (bytearray(SLOT * 2),
                   bytearray(encode(1, 0, 7, 0, 0) + encode(1, 1, 7, 0, 0))):
        try:
            select(memory)
        except ValueError:
            pass
        else:
            raise AssertionError('malformed metadata accepted')
    return cases


class Reset(Exception):
    pass


def integrated(seed, same_box):
    rng = random.Random(seed)
    initial = [fixture(20, seed), fixture(20, seed + 1)]
    boxes = [b.copy() for b in initial]
    plan = []
    for box_id, index in ((0, 0), (0 if same_box else 1, 9)):
        for phase in phases(boxes[box_id], index):
            for offset in range(phase.length):
                plan.append((box_id, phase, offset))
                phase.forward(boxes[box_id], offset)
    boxes = [b.copy() for b in initial]
    memory = bytearray(encode(0, DONE, 7, 0, 0) + bytes(SLOT))
    resets = writes = 0

    def write(target, address, value, faults):
        nonlocal resets, writes
        writes += 1
        if faults and rng.randrange(41) == 0:
            target[address] = rng.randrange(256)
            resets += 1
            raise Reset
        target[address] = value

    def publish(mode, count, undo, faults):
        for address, value in publication(memory, mode, 7, count, undo):
            write(memory, address, value, faults)

    # Prepare several complete intents; then tear either intent or box data.
    limit = rng.randrange(len(plan))
    for k in range(limit + 1):
        try:
            publish(FORWARD, k, 0, k == limit)
            box_id, phase, offset = plan[k]
            value = phase.literal if phase.literal is not None else boxes[box_id][
                phase.start + offset + phase.stride]
            write(boxes[box_id], phase.start + offset, value, k == limit)
        except Reset:
            break
    else:
        # Reset after the data byte but before any next publication.
        resets += 1

    # Repeated faults during recovery. Rebuild all volatile control from bytes.
    for boot in range(100000):
        _, (_, mode, txn, count, undo) = select(memory)
        assert txn == 7
        if mode == DONE:
            assert boxes == initial
            return resets, writes
        try:
            if mode == FORWARD:
                box_id, phase, offset = plan[count]
                value = phase.literal if phase.literal is not None else boxes[box_id][
                    phase.start + offset + phase.stride]
                write(boxes[box_id], phase.start + offset, value, True)
                publish(ROLLBACK, count + 1, 0, True)
            else:
                completed = []
                for box_id, phase, offset in plan[:count]:
                    if completed and completed[-1][1] is phase:
                        completed[-1] = (box_id, phase, offset + 1)
                    else:
                        completed.append((box_id, phase, offset + 1))
                inverse = []
                for box_id, phase, n in reversed(completed):
                    inverse.extend((box_id, *op) for op in phase.rollback(boxes[box_id], n))
                if undo == len(inverse):
                    publish(DONE, count, undo, True)
                    continue
                box_id, dst, src, literal = inverse[undo]
                value = literal if src is None else boxes[box_id][src]
                write(boxes[box_id], dst, value, True)
                publish(ROLLBACK, count, undo + 1, True)
        except Reset:
            continue
    raise AssertionError('recovery failed to terminate')


def run(trials):
    local = publication_tests()
    totals = [integrated(seed, same) for seed in range(trials) for same in (False, True)]
    return {'status': 'MODEL ONLY; no ROM integration', 'slot_bytes': SLOT,
            'two_cursor_slots_bytes': SLOT * 2, 'record_payload_bytes': 114,
            'subtotal_excluding_descriptors_and_journal_header': SLOT * 2 + 114,
            'publication_torn_byte_cases': local, 'integrated_cases': len(totals),
            'integrated_resets': sum(x[0] for x in totals),
            'integrated_byte_writes': sum(x[1] for x in totals),
            'limits': ['already valid immutable journal assumed', 'ordered single-byte writes',
                       'no collateral SRAM damage', 'no main generation commit',
                       'no legacy/bootstrap protocol', 'CRC32 is not collision-proof',
                       'no ROM timing measurement']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', type=int, default=16)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    assert args.trials > 0
    report = run(args.trials)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    print(json.dumps(report, indent=2))
