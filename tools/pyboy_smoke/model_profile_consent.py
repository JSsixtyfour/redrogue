"""Consent-before-initialization ordering model. Byte fixtures, not game UI.

Only synthetic/private SRAM images are modified. No production erase flow,
ROM initializer or actual user save file is touched.
"""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from model_save_handoff import Layout, initial, gather, chosen, outcome, mapped_writes
from model_save_bootstrap import first_save, legacy_fixture, legacy_payload, LEGACY_HEADER
from model_save_lifecycle import PAYLOAD


def view(memory, layout):
    excluded = set(layout.selector + layout.rental_cursor + layout.descriptor +
                   layout.shadow + list(layout.main0) + layout.save_header +
                   layout.checksums + layout.scratch)
    for box in layout.boxes:
        excluded.update(box)
    residual = bytes(value for a, value in enumerate(memory) if a not in excluded)
    try:
        core = outcome(memory, layout)
    except ValueError:
        if gather(memory, layout.save_header) != LEGACY_HEADER:
            return None
        payload, active = legacy_payload(memory, layout)
        boxes = tuple(payload[layout.box_offset:layout.box_offset + 1122] if i == active
                      else gather(memory, addresses) for i, addresses in enumerate(layout.boxes))
        core = payload, boxes
    return core, residual


def replacement(memory, layout, template, consent):
    # Cancellation must return BEFORE even a format/header byte is changed.
    if not consent:
        return
    yield layout.descriptor[-1], 0
    # Disable the complete compatibility header before ANY initializer write.
    # Keep it out of the later bulk pass to avoid accidentally reviving legacy.
    for address in layout.save_header:
        yield address, 0
    reserved = set(layout.save_header + layout.descriptor)
    for address, value in enumerate(template):
        if address in reserved or (address % 8192) // 256 == 0x1D:
            continue
        yield address, value
    for write in zip(layout.save_header, layout.new_header):
        yield write
    for write in mapped_writes(layout.descriptor, layout.format_record):
        yield write


def run():
    layout = Layout('sum8', descriptor=True, shared_marker=True)
    payload = bytearray(PAYLOAD)
    payload[layout.box_offset:layout.box_offset + 2] = bytes([0, 255])
    template = bytearray([255]) * 32768
    for address, value in first_save(template, layout, payload):
        template[address] = value
    cases = vetoes = 0
    for old in (initial(layout, 5), bytearray(legacy_fixture(layout, 5))):
        original = bytes(old)
        old_view = view(old, layout)
        assert list(replacement(old, layout, template, False)) == []
        assert bytes(old) == original
        vetoes += 1
        final = old.copy()
        trace = list(replacement(old, layout, template, True))
        for address, value in trace:
            final[address] = value
        new_view = view(final, layout)
        assert new_view is not None and new_view != old_view
        rng = random.Random(11)
        points = {0, len(trace) - 1, *[rng.randrange(len(trace)) for _ in range(100)]}
        for i, (address, value) in enumerate(trace):
            important = address in set(layout.save_header + [layout.descriptor[-1]])
            if important or i in points:
                tears = range(256) if important else {0, 255, value, old[address], rng.randrange(256)}
                for torn in tears:
                    cut = old.copy()
                    cut[address] = torn
                    result = view(cut, layout)
                    assert result is None or result in (old_view, new_view), (i, address, torn)
                    cases += 1
            old[address] = value
        assert view(old, layout) == new_view
    return {'status': 'MODEL ONLY; explicit synthetic discard consent before initializer callback',
            'source_formats': ['draft committed checkpoint', 'schema 11 legacy'],
            'cancelled_cases_unchanged': vetoes, 'fault_cases': cases,
            'recognized_mixed_profiles': 0,
            'accepted_after_cut': 'complete old, complete new, or no profile after explicit discard',
            'limits': ['not in-game prompt or InitPlayerData2 acceptance',
                       'synthetic initializer template, not real new-game defaults',
                       'explicit discard permits loss of the discarded profile',
                       'sampled initializer positions; exhaustive torn bytes on header/marker writes']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = run()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    print(json.dumps(report, indent=2))
