"""Draft format bootstrap/conversion model, not a production converter.

Schema 12 is illustrative, not allocated or written to project constants.
Existing patch-page converter remains authoritative for migration/structure.
"""
from __future__ import annotations

import argparse
import json
import random
import struct
from pathlib import Path

from model_save_metadata import DONE, SLOT, encode
from model_save_lifecycle import PAYLOAD
from model_rental_rollback import fixture
from model_save_handoff import (Layout, chosen, outcome, gather, mapped_writes,
                               physical, checksum_writes, checksum_matches)

LEGACY_HEADER = b'RRSG' + struct.pack('<HH', 11, 11 ^ 0xFFFF)


def classify(memory, layout):
    """Refusal never repairs, initializes or guesses from untrusted records."""
    before = bytes(memory)
    try:
        layout.require_format(memory)
        value = outcome(memory, layout)
        assert checksum_matches(memory, layout)
        result = 'new', value
    except ValueError:
        result = ('legacy' if gather(memory, layout.save_header) == LEGACY_HEADER
                  else 'refused'), None
    assert memory == before
    return result


def legacy_payload(memory, layout):
    if gather(memory, layout.save_header) != LEGACY_HEADER:
        raise ValueError('not the supported legacy schema')
    payload = gather(memory, layout.payload_map)
    stored = memory[physical(*layout.sym['sMainDataCheckSum'])]
    if ((~sum(payload)) & 255) != stored:
        raise ValueError('legacy payload checksum mismatch')
    active = payload[layout.current_offset] & 15
    if active >= 12:
        raise ValueError('invalid legacy box')
    return payload, active


def preparation(layout, payload, active):
    """All new validity markers initialized explicitly before publication."""
    yield layout.descriptor[-1], 0
    for records in (layout.selector, layout.rental_cursor):
        yield records[SLOT - 1], 0
        yield records[-1], 0
    yield layout.journal[-1], 0
    yield layout.main(1, active)[-1], 0
    # Rental journal tail is borrowed ONLY from the ignored active archive.
    yield layout.boxes[active][layout.spill + 210 - 1], 0
    for write in mapped_writes(layout.main0, layout.seal_main(1, payload)):
        yield write
    for write in mapped_writes(layout.selector[:SLOT], encode(
            0, DONE, 1, active << 1, 0)):
        yield write


def finalization(memory, layout):
    for write in checksum_writes(memory, layout):
        yield write
    for write in zip(layout.save_header, layout.new_header):
        yield write
    # Final descriptor publication gates every read of the new format.
    for write in mapped_writes(layout.descriptor, layout.format_record):
        yield write


def first_save(memory, layout, payload):
    # A prototype guard, not the real overwrite-consent/new-game lifecycle.
    if any(value != 255 for value in memory):
        raise ValueError('first-save fixture must be virgin SRAM; no overwrite authorization')
    active = payload[layout.current_offset] & 15
    for write in preparation(layout, payload, active):
        yield write
    for box in layout.boxes:
        yield box[0], 0
        yield box[1], 255
    for write in finalization(memory, layout):
        yield write


def migrate_legacy(source, layout):
    """Yield writes for a PRIVATE copy; original source stays immutable."""
    payload, active = legacy_payload(source, layout)
    private = bytearray(source)
    for address, value in preparation(layout, payload, active):
        private[address] = value
        yield address, value
    for address, value in finalization(private, layout):
        private[address] = value
        yield address, value


def legacy_fixture(layout, seed):
    rng = random.Random(seed)
    memory = bytearray(rng.randbytes(32768))
    active = seed % 12
    for i, box in enumerate(layout.boxes):
        for address, value in zip(box, fixture(20, seed + i)):
            memory[address] = value
    payload = bytearray(rng.randbytes(PAYLOAD))
    payload[layout.current_offset] = active | 0x80
    payload[layout.box_offset:layout.box_offset + 1122] = fixture(19, seed + 100)
    for address, value in zip(layout.payload_map, payload):
        memory[address] = value
    memory[physical(*layout.sym['sMainDataCheckSum'])] = (~sum(payload)) & 255
    for address, value in zip(layout.save_header, LEGACY_HEADER):
        memory[address] = value
    for address, value in checksum_writes(memory, layout):
        memory[address] = value
    return bytes(memory)


def exercise(memory, writes, layout, expected):
    cases = 0
    marker_addresses = {layout.descriptor[-1], layout.selector[SLOT - 1],
                        layout.selector[-1], layout.main0[-1]}
    rng = random.Random(22)
    for address, value in writes:
        assert (address % 8192) // 256 != 0x1D
        tears = range(256) if address in marker_addresses else {value, rng.randrange(256)}
        for torn in tears:
            cut = memory.copy()
            cut[address] = torn
            status, loaded = classify(cut, layout)
            assert status != 'new' or loaded == expected
            cases += 1
        memory[address] = value
    assert classify(memory, layout) == ('new', expected)
    return cases


def run():
    layout = Layout('sum8', descriptor=True)
    # Byte transport fixture, not a claim of in-ROM new-game acceptance.
    payload = bytearray(PAYLOAD)
    payload[layout.current_offset] = 0
    payload[layout.box_offset:layout.box_offset + 2] = bytes([0, 255])
    blank = bytearray([255]) * 32768
    target = blank.copy()
    trace = []
    for address, value in first_save(target, layout, payload):
        trace.append((address, value))
        target[address] = value
    expected = outcome(target, layout)
    first_cases = exercise(blank, trace, layout, expected)
    migrations = 0
    for seed in (0, 5):
        source = legacy_fixture(layout, seed)
        snapshot = bytes(source)
        payload, active = legacy_payload(source, layout)
        converted = bytearray(source)
        trace = list(migrate_legacy(source, layout))
        for address, value in trace:
            converted[address] = value
        expected = outcome(converted, layout)
        assert expected[0] == payload
        for box, addresses in enumerate(layout.boxes):
            if box != active:
                assert expected[1][box] == gather(source, addresses)
        # Outside explicit new metadata/scratch and derived checksums, every
        # source byte is preserved. No permanent/procedural fields are reset.
        allowed = set(layout.descriptor + layout.selector + layout.rental_cursor +
                      layout.journal + layout.checksums + layout.save_header +
                      list(layout.main0[:4]) + [layout.main0[-1],
                      layout.main(1, active)[-1],
                      layout.boxes[active][layout.spill + 209]])
        assert all(a in allowed or source[a] == converted[a] for a in range(32768))
        migrations += exercise(bytearray(source), trace, layout, expected)
        assert source == snapshot
        # Refuse bad source and avoid modifying a pre-existing profile.
        bad = bytearray(source)
        bad[layout.payload_map[20]] ^= 1
        for operation in (lambda: list(migrate_legacy(bytes(bad), layout)),
                          lambda: list(first_save(bytearray(source), layout, payload))):
            try:
                operation()
            except ValueError:
                pass
            else:
                raise AssertionError('invalid source/overwrite accepted')
    # Retaining sum8 does NOT improve ordinary corruption detection.
    sample = bytearray(payload)
    sample[30] = (sample[30] + 1) & 255
    sample[31] = (sample[31] - 1) & 255
    assert layout.unseal_main(layout.seal_main(1, sample)) is not None
    original_image = bytearray(layout.seal_main(1, payload))
    original_image[4 + 30] = sample[30]
    original_image[4 + 31] = sample[31]
    assert layout.unseal_main(original_image) is not None
    return {'status': 'DRAFT MODEL ONLY; schema 12 illustrative, no project schema bump',
            'first_save_fault_cases': first_cases, 'private_conversion_fault_cases': migrations,
            'migration_fixtures': 2, 'main_record_bytes': layout.main_length,
            'format_descriptor_bytes': len(layout.descriptor), 'selector_bytes': SLOT * 2,
            'rental_cursor_bytes': SLOT * 2, 'shadow_spill_bytes': layout.spill,
            'sprite_journal_bytes': layout.jsize, 'legacy_source_unchanged': True,
            'sum8_balanced_corruption_undetected': True,
            'limits': ['not production converter structural validation',
                       'no interrupted overwrite of an existing profile',
                       'no ROM initialization or boot hook', 'no gameplay/companion transaction integration',
                       'no ROM latency', 'sum8 and CRC collisions not excluded']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = run()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    print(json.dumps(report, indent=2))
