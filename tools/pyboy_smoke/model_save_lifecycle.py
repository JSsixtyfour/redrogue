"""Transaction-order model. NOT a ROM format or complete rental integration.

Uses nonoverlapping literal companion patches to isolate journal/selector
ordering from the separately tested rental compaction cursor. Fixed main slots
are abstract storage: the proposed scattered/active-box placement is NOT modeled.
"""
from __future__ import annotations

import argparse
import json
import struct
import zlib
from pathlib import Path

from model_save_metadata import SLOT, VALID, DONE, encode, select, publication

PAYLOAD = 3800
MAIN = 4 + PAYLOAD + 4 + 1
HEADER = struct.Struct('<BIIBH')  # version, parent generation, child generation, slot, count
PATCHES = 32
JOURNAL = HEADER.size + PATCHES * 3 + 5
SELECTOR = MAIN * 2
JSTART = SELECTOR + SLOT * 2
BOX = JSTART + JOURNAL
TOTAL = BOX + 1122


def sealed(body):
    return body + struct.pack('<I', zlib.crc32(body)) + bytes([VALID])


def unseal(record):
    if record[-1] != VALID or zlib.crc32(record[:-5]) != struct.unpack('<I', record[-5:-1])[0]:
        return None
    return record[:-5]


def selector(memory):
    try:
        _, (_, mode, generation, slot, unused) = select(memory[SELECTOR:JSTART])
    except ValueError:
        return None
    if mode != DONE or slot > 1 or unused:
        raise ValueError('invalid selector context')
    body = unseal(memory[slot * MAIN:(slot + 1) * MAIN])
    if body is None or struct.unpack('<I', body[:4])[0] != generation:
        raise ValueError('selected main is invalid: refuse')
    return generation, slot, bytes(body[4:])


def record_writes(address, record):
    return [(address + len(record) - 1, 0)] + list(enumerate(record[:-1], address)) + [
        (address + len(record) - 1, VALID)]


def journal(memory):
    body = unseal(memory[JSTART:BOX])
    if body is None:
        return None
    version, parent, child, slot, count = HEADER.unpack(body[:HEADER.size])
    if version != 1 or slot > 1 or count != PATCHES or child != parent + 1:
        raise ValueError('invalid journal header')
    patches = []
    for offset in range(HEADER.size, len(body), 3):
        address, value = struct.unpack('<HB', body[offset:offset + 3])
        if address >= 1122 or address in [a for a, _ in patches]:
            raise ValueError('invalid patch descriptor')
        patches.append((address, value))
    return parent, child, slot, patches


def recovery_writes(memory):
    current = selector(memory)
    intent = journal(memory)
    if intent is None:
        return []
    parent, child, slot, patches = intent
    generation = current[0] if current else 0
    if generation == child:
        if current[1] != slot:
            raise ValueError('journal selector disagreement')
        return [(BOX - 1, 0)]
    if generation != parent:
        raise ValueError('stale or future journal: refuse')
    return [(BOX + address, old) for address, old in patches] + [(BOX - 1, 0)]


def boot(memory):
    for address, value in recovery_writes(memory):
        memory[address] = value
    current = selector(memory)
    return (None if current is None else (current[0], current[2]), bytes(memory[BOX:]))


def transaction(memory):
    current = selector(memory)
    parent = current[0] if current else 0
    slot = 1 - current[1] if current else 0
    child = parent + 1
    payload = bytes((i * 37 + child * 13) & 255 for i in range(PAYLOAD))
    addresses = [(i * 31 + parent * 7) % 1122 for i in range(PATCHES)]
    body = HEADER.pack(1, parent, child, slot, PATCHES) + b''.join(
        struct.pack('<HB', address, memory[BOX + address]) for address in addresses)
    operations = record_writes(JSTART, sealed(body))
    operations += [(BOX + address, (memory[BOX + address] + child + 1) & 255)
                   for address in addresses]
    operations += record_writes(slot * MAIN, sealed(struct.pack('<I', child) + payload))
    if current is None:
        # No selector exists: publish first selector only after all data is ready.
        operations += record_writes(SELECTOR, encode(0, DONE, child, slot, 0))
    else:
        operations += [(SELECTOR + a, v) for a, v in publication(
            memory[SELECTOR:JSTART], DONE, child, slot, 0)]
    operations += [(BOX - 1, 0)]
    return operations


def run(generations):
    memory = bytearray(TOTAL)
    memory[BOX:] = bytes((i * 17 + 5) & 255 for i in range(1122))
    forward_faults = recovery_faults = 0
    for _ in range(generations):
        old = boot(memory.copy())
        operations = transaction(memory)
        final = memory.copy()
        for address, value in operations:
            final[address] = value
        new = boot(final.copy())
        # Every write boundary. Sample torn values on large main bodies; exhaust
        # all 256 values on journal/selector publications and cleanup.
        for address, value in operations:
            values = range(256) if JSTART <= address < BOX or SELECTOR <= address < JSTART else {
                0, 255, value, memory[address]}
            for torn in values:
                cut = memory.copy()
                cut[address] = torn
                assert boot(cut.copy()) in (old, new)
                forward_faults += 1
            # At each prefix of rollback/cleanup, tear its next write. Literal
            # before-images are repeatable, so restart from serialized storage.
            cut = memory.copy()
            for dst, restore in recovery_writes(cut):
                for torn in {0, 255, restore, cut[dst]}:
                    retry = cut.copy()
                    retry[dst] = torn
                    assert boot(retry) in (old, new)
                    recovery_faults += 1
                cut[dst] = restore
            memory[address] = value
        assert boot(memory.copy()) == new
    # Negative controls: the oracle must detect two unsafe orderings.
    old = boot(memory.copy())
    operations = transaction(memory)
    final = memory.copy()
    for address, value in operations:
        final[address] = value
    new = boot(final.copy())
    unsafe = memory.copy()
    address, value = next((a, v) for a, v in operations if a >= BOX)
    unsafe[address] = value  # companion mutation without a published undo journal
    assert boot(unsafe) not in (old, new)
    unsafe = memory.copy()
    for address, value in operations:
        if SELECTOR <= address < JSTART:
            unsafe[address] = value  # selector before its referenced main exists
    try:
        boot(unsafe)
    except ValueError:
        pass
    else:
        raise AssertionError('premature selector was not rejected')
    return {'status': 'MODEL ONLY: literal patch lifecycle, not rental cursor integration',
            'generations': generations, 'forward_fault_cases': forward_faults,
            'recovery_fault_cases': recovery_faults, 'main_payload_bytes': PAYLOAD,
            'unsafe_ordering_negative_controls_detected': 2,
            'main_record_bytes_each': MAIN, 'selector_bytes': SLOT * 2,
            'journal_bytes_for_32_literal_patches': JOURNAL,
            'limits': ['abstract fixed storage, no SRAM placement',
                       'literal patches, not rental compaction', 'no legacy migration',
                       'CRC32 collisions not excluded', 'ordered isolated byte writes',
                       'no latency or hardware acceptance']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generations', type=int, default=3)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    assert args.generations >= 2
    report = run(args.generations)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    print(json.dumps(report, indent=2))
