"""Combined serialized rental journal, chunk cursor and main-selector model.

Fixed independent storage is intentional. This does NOT prove the proposed
active-box overlap, companion gameplay hooks, legacy conversion or ROM latency.
"""
from __future__ import annotations

import argparse
import json
import random
import struct
from functools import lru_cache
from pathlib import Path

from model_rental_rollback import Phase, fixture, phases, reference
from model_save_metadata import SLOT, DONE, FORWARD, ROLLBACK, encode, publication, select
from model_save_lifecycle import MAIN, PAYLOAD, sealed, unseal, record_writes

HEADER = struct.Struct('<BIIBB')
DESCRIPTOR = struct.Struct('<BHHHB')  # box, start, stride, length, saved length
JSIZE = HEADER.size + 10 * DESCRIPTOR.size + 114 + 5
SELECTOR = MAIN * 2
CURSOR = SELECTOR + SLOT * 2
JSTART = CURSOR + SLOT * 2
BOX = JSTART + JSIZE
TOTAL = BOX + 2244


def chosen(memory):
    data = memory[SELECTOR:CURSOR]
    if all(value == 255 for value in data):
        return None
    try:
        _, (_, mode, generation, slot, undo) = select(data)
    except ValueError:
        # Initial publication may have no valid selector. It never mutates boxes
        # before a validated undo journal exists.
        return None
    if mode != DONE or slot > 1 or undo:
        raise ValueError('invalid main selector')
    body = unseal(memory[slot * MAIN:(slot + 1) * MAIN])
    if body is None or struct.unpack('<I', body[:4])[0] != generation:
        raise ValueError('main selector mismatch')
    return generation, slot, bytes(body[4:])


def serialize(parent, child, slot, groups):
    body = HEADER.pack(1, parent, child, slot, len(groups))
    for box, phase in groups:
        body += DESCRIPTOR.pack(box, phase.start, phase.stride, phase.length,
                                len(phase.saved)) + phase.saved
    assert len(body) <= JSIZE - 5
    return sealed(body.ljust(JSIZE - 5, b'\0'))


def decode(memory):
    return decode_record(bytes(memory[JSTART:BOX]))


@lru_cache(maxsize=64)
def decode_record(record):
    body = unseal(record)
    if body is None:
        return None
    version, parent, child, slot, count = HEADER.unpack_from(body)
    if version != 1 or child != parent + 1 or slot > 1 or not 1 <= count <= 10:
        raise ValueError('invalid journal context')
    offset = HEADER.size
    groups = []
    for _ in range(count):
        box, start, stride, length, size = DESCRIPTOR.unpack_from(body, offset)
        offset += DESCRIPTOR.size
        saved = bytes(body[offset:offset + size])
        offset += size
        if box > 1 or not 1 <= size <= 33 or length < 1 or start + stride + length > 1122:
            raise ValueError('invalid phase bounds')
        literal = (saved[0] - 1 if start == 0 else 255) if stride == 0 else None
        groups.append((box, Phase(start, stride, length, saved, literal)))
    if any(body[offset:]):
        raise ValueError('nonzero journal padding')
    return parent, child, slot, groups


def split_operations(operations, stride):
    width = min(32, max(1, stride - 1))
    return [operations[i:i + width] for i in range(0, len(operations), width)]


def forward_chunks(groups):
    chunks = []
    for box, phase in groups:
        operations = [(BOX + box * 1122 + phase.start + i,
                       None if phase.literal is not None else
                       BOX + box * 1122 + phase.start + i + phase.stride,
                       phase.literal) for i in range(phase.length)]
        chunks.extend(split_operations(operations, phase.stride))
    return chunks


def inverse_chunks(groups, forward_count):
    remaining = sum(len(chunk) for chunk in forward_chunks(groups)[:forward_count])
    completed = []
    for box, phase in groups:
        count = min(remaining, phase.length)
        if count:
            completed.append((box, phase, count))
        remaining -= count
    assert remaining == 0
    chunks = []
    for box, phase, count in reversed(completed):
        copies, literals = [], []
        for dst, src, literal in phase.rollback(None, count):
            op = (BOX + box * 1122 + dst,
                  None if src is None else BOX + box * 1122 + src, literal)
            (literals if src is None else copies).append(op)
        chunks.extend(split_operations(copies, phase.stride))
        # Literal restore sources live in the immutable journal, never box data.
        chunks.extend(split_operations(literals, 33))
    return chunks


@lru_cache(maxsize=64)
def cached_forward(record):
    return forward_chunks(decode_record(record)[3])


@lru_cache(maxsize=256)
def cached_inverse(record, count):
    return inverse_chunks(decode_record(record)[3], count)


def cursor_writes(memory, mode, child, count, undo):
    data = memory[CURSOR:JSTART]
    try:
        writes = publication(data, mode, child, count, undo)
    except ValueError:
        if any(value != 255 for value in data):
            # A torn initial slot can be overwritten before any mutation starts.
            # Valid journal + no valid cursor means no data write was authorized.
            pass
        writes = record_writes(0, encode(0, mode, child, count, undo))
    return [(CURSOR + address, value) for address, value in writes]


def expand(memory, chunk):
    return [(dst, literal if src is None else memory[src]) for dst, src, literal in chunk]


def transaction(memory, same, salt):
    current = chosen(memory)
    parent = current[0] if current else 0
    child = parent + 1
    slot = 1 - current[1] if current else 0
    boxes = [bytearray(memory[BOX + i * 1122:BOX + (i + 1) * 1122]) for i in range(2)]
    groups = []
    targets = (0, 0 if same else 1)
    for removal, box in enumerate(targets):
        index = (boxes[box][0] - 1 if salt % 4 >= 2 else (0 if removal == 0 else 4))
        groups.extend((box, phase) for phase in phases(boxes[box], index))
        boxes[box] = reference(boxes[box], index)
    data = serialize(parent, child, slot, groups)
    for write in record_writes(JSTART, data):
        yield write
    for write in cursor_writes(memory, DONE, child, 0, 0):
        yield write
    chunks = cached_forward(bytes(memory[JSTART:BOX]))
    for i, chunk in enumerate(chunks):
        for write in cursor_writes(memory, FORWARD, child, i, 0):
            yield write
        for write in expand(memory, chunk):
            yield write
    for write in cursor_writes(memory, DONE, child, len(chunks), 0):
        yield write
    payload = bytes((i * 37 + salt + child) & 255 for i in range(PAYLOAD))
    for write in record_writes(slot * MAIN, sealed(struct.pack('<I', child) + payload)):
        yield write
    if current:
        writes = publication(memory[SELECTOR:CURSOR], DONE, child, slot, 0)
    else:
        writes = record_writes(0, encode(0, DONE, child, slot, 0))
    for address, value in writes:
        yield SELECTOR + address, value
    yield BOX - 1, 0


def recover_step(memory):
    intent = decode(memory)
    if intent is None:
        return []
    parent, child, slot, groups = intent
    current = chosen(memory)
    generation = current[0] if current else 0
    if generation == child:
        if current[1] != slot:
            raise ValueError('committed slot mismatch')
        return [(BOX - 1, 0)]
    if generation != parent:
        raise ValueError('stale journal')
    try:
        _, (_, mode, txn, count, undo) = select(memory[CURSOR:JSTART])
    except ValueError:
        return [(BOX - 1, 0)]  # no mutation authorized before first valid cursor
    if txn != child:
        return [(BOX - 1, 0)]  # prior transaction; current journal not started
    chunks = cached_forward(bytes(memory[JSTART:BOX]))
    if count > len(chunks) or (mode == FORWARD and count == len(chunks)):
        raise ValueError('invalid cursor position')
    if mode == FORWARD:
        return expand(memory, chunks[count]) + cursor_writes(memory, ROLLBACK, child, count + 1, 0)
    if mode == DONE and count == 0:
        return [(BOX - 1, 0)]
    inverse = cached_inverse(bytes(memory[JSTART:BOX]), count)
    if mode == DONE:
        return cursor_writes(memory, ROLLBACK, child, count, 0)
    if undo > len(inverse):
        raise ValueError('invalid inverse cursor')
    if undo == len(inverse):
        return cursor_writes(memory, DONE, child, 0, 0)
    return expand(memory, inverse[undo]) + cursor_writes(memory, ROLLBACK, child, count, undo + 1)


def outcome(memory):
    current = chosen(memory)
    return (None if current is None else (current[0], current[2]), bytes(memory[BOX:]))


def recover(memory, rng):
    resets = writes = 0
    for _ in range(100000):
        operations = recover_step(memory)
        if not operations:
            return outcome(memory), resets, writes
        for address, value in operations:
            writes += 1
            if rng.randrange(127) == 0:
                memory[address] = rng.randrange(256)
                resets += 1
                break
            memory[address] = value
    raise AssertionError('recovery did not terminate')


def overlap_controls():
    # Capacity illustration from the earlier candidate pool, NOT an allocation.
    # Reserve selector/cursor (72 B) and a conservative separate slot-0 header
    # (9 B). Shadow record includes its own 9 B framing in MAIN.
    pool = 3645 - SLOT * 4 - 9
    spill = MAIN - pool
    tail = 1122 - spill
    shadow = sealed(struct.pack('<I', 7) + bytes(i & 255 for i in range(PAYLOAD)))
    archive = bytearray([0x77]) * 1122
    archive[:spill] = shadow[pool:]
    archive[spill:spill + JSIZE] = bytes([0xA5]) * JSIZE
    assert unseal(shadow[:pool] + archive[:spill]) is not None
    exact_copy = bytes(shadow[:pool] + archive[:spill])
    # Existing exchange copies all 1122 live WRAM bytes to this archive.
    archive[:] = bytes([0x33]) * 1122
    assert unseal(shadow[:pool] + archive[:spill]) is None
    assert archive[spill:spill + JSIZE] != bytes([0xA5]) * JSIZE
    assert unseal(exact_copy) is not None
    return {'naive_full_box_write_destroys_selected_shadow': True,
            'naive_full_box_write_destroys_journal': True,
            'illustrative_pool_after_81_reserved_bytes': pool,
            'shadow_archive_spill_bytes': spill, 'archive_tail_bytes': tail,
            'tail_after_rental_journal_bytes': tail - JSIZE,
            'handoff_fault_protocol_proven': False}


def run(trials):
    cases = resets = writes = 0
    max_chunks = max_trace = 0
    for seed in range(trials):
        rng = random.Random(seed)
        memory = bytearray([255]) * TOTAL
        for box in range(2):
            memory[BOX + box * 1122:BOX + (box + 1) * 1122] = fixture(20, seed + box)
        for generation in range(3):
            old = outcome(memory)
            trial = memory.copy()
            trace = []
            # Generator sees each preceding persisted write, including new cursor.
            for address, value in transaction(trial, bool(seed % 2), seed):
                trace.append((address, value))
                trial[address] = value
            new = outcome(trial)
            max_trace = max(max_trace, len(trace))
            # Boundaries in preparation, mutation, main and selector, plus samples.
            positions = {0, len(trace) - 1, *[rng.randrange(len(trace)) for _ in range(20)]}
            for i, (address, value) in enumerate(trace):
                if address in (BOX - 1, SELECTOR + SLOT - 1, SELECTOR + 2 * SLOT - 1,
                               CURSOR + SLOT - 1, CURSOR + 2 * SLOT - 1):
                    # Sample marker events throughout mutation without O(N^2) runs.
                    if address == BOX - 1 or rng.randrange(19) == 0:
                        positions.add(i)
            prefix = memory.copy()
            for i, (address, value) in enumerate(trace):
                if i in positions:
                    for torn in {0, 255, value, prefix[address], rng.randrange(256)}:
                        cut = prefix.copy()
                        cut[address] = torn
                        result, nresets, nwrites = recover(cut, rng)
                        assert result in (old, new), (seed, generation, i)
                        cases += 1
                        resets += nresets
                        writes += nwrites
                    intent = decode(prefix)
                    if intent:
                        max_chunks = max(max_chunks, len(forward_chunks(intent[3])))
                prefix[address] = value
            memory = trial
            assert outcome(memory) == new
    return {'status': 'MODEL ONLY; independent storage; serialized rental lifecycle',
            'trials': trials, 'generations_per_trial': 3, 'fault_cases': cases,
            'recovery_resets': resets, 'recovery_byte_writes': writes,
            'fixed_journal_bytes': JSIZE, 'cursor_bytes': SLOT * 2,
            'selector_bytes': SLOT * 2, 'journal_cursor_selector_subtotal': JSIZE + SLOT * 4,
            'max_forward_chunks': max_chunks, 'max_transaction_byte_writes': max_trace,
            'removal_cases': ['first/middle distinct boxes', 'first/middle same box',
                              'last occupied distinct boxes', 'last occupied same box'],
            'overlap_negative_controls': overlap_controls(),
            'limits': ['seeded fault coverage, not exhaustive', 'independent fixed storage',
                       'no actual SRAM placement', 'no gameplay hooks or box checksums',
                       'no legacy migration or generation wrap', 'no ROM latency',
                       'ordered isolated byte writes; CRC collisions not excluded']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trials', type=int, default=4)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    assert args.trials >= 2
    report = run(args.trials)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    print(json.dumps(report, indent=2))
