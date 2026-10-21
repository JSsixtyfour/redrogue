"""Pure storage model, NOT a ROM recovery implementation.

Assumes an atomically durable phase/byte cursor. Tests data replay and inverse
compaction, including unused tails. Torn metadata, bank switching, checksums,
main-slot selection and gameplay ownership hooks are deliberately not modeled.
Run standalone; no emulator dependency and no SRAM layout changes.
"""
from __future__ import annotations

import argparse
import json
import random
from dataclasses import dataclass
from pathlib import Path

SIZE = 1122


@dataclass
class Phase:
    start: int
    stride: int
    length: int
    saved: bytes
    literal: int | None = None

    def forward(self, box: bytearray, offset: int) -> None:
        box[self.start + offset] = (
            self.literal if self.literal is not None
            else box[self.start + offset + self.stride]
        )

    def rollback(self, box: bytearray, completed: int):
        # Descending copies restore original source bytes before the saved prefix.
        if self.literal is None:
            for offset in range(completed - 1, -1, -1):
                yield self.start + offset + self.stride, self.start + offset, None
        for offset in range(min(completed, len(self.saved))):
            yield self.start + offset, None, self.saved[offset]


def phases(box: bytearray, index: int) -> list[Phase]:
    count = box[0]
    assert 0 <= index < count <= 20
    result = [Phase(0, 0, 1, bytes(box[:1]), count - 1)]
    start = 1 + index
    result.append(Phase(start, 1, count - index, bytes(box[start:start + 1])))
    if index == 19:
        start = 682 + index * 11
        result.append(Phase(start, 0, 1, bytes(box[start:start + 1]), 255))
    else:
        # Match _RemovePokemon: OT, structures, nicknames, through physical ends.
        for base, stride in ((682, 11), (22, 33), (902, 11)):
            start = base + index * stride
            result.append(Phase(start, stride, (19 - index) * stride,
                                bytes(box[start:start + stride])))
    return result


def reference(box: bytearray, index: int) -> bytearray:
    """Independent slice-based transcription of the source's physical writes."""
    out = box.copy()
    count = out[0]
    out[0] -= 1
    out[1 + index:count + 1] = box[2 + index:count + 2]
    if index == 19:
        out[682 + index * 11] = 255
    else:
        for base, width in ((682, 11), (22, 33), (902, 11)):
            end = base + 20 * width
            out[base + index * width:end - width] = box[base + (index + 1) * width:end]
    return out


def fixture(count: int, seed: int) -> bytearray:
    rng = random.Random(seed)
    box = bytearray(rng.randbytes(SIZE))
    box[0] = count
    box[1:1 + count] = bytes(rng.randrange(1, 255) for _ in range(count))
    box[1 + count] = 255
    return box


def verify(initial: list[bytearray], removals: list[tuple[int, int]]) -> dict:
    working = [b.copy() for b in initial]
    operations = []
    journals = []
    for box_id, index in removals:
        before = working[box_id].copy()
        group = phases(before, index)
        journals.append(sum(len(p.saved) for p in group))
        for phase in group:
            for offset in range(phase.length):
                operations.append((box_id, phase, offset))
                phase.forward(working[box_id], offset)
        assert working[box_id] == reference(before, index)
    expected = [b.copy() for b in working]
    working = [b.copy() for b in initial]
    inverse_replays = 0
    # Every byte boundary, with the just-written byte also replayed. A repeated
    # write models loss between data publication and abstract cursor advancement.
    for cut in range(len(operations) + 1):
        restored = [b.copy() for b in working]
        completed = []
        for box_id, phase, offset in operations[:cut]:
            if completed and completed[-1][1] is phase:
                completed[-1] = (box_id, phase, offset + 1)
            else:
                completed.append((box_id, phase, offset + 1))
        for box_id, phase, count in reversed(completed):
            box = restored[box_id]
            for dst, src, literal in phase.rollback(box, count):
                value = literal if src is None else box[src]
                box[dst] = value
                # A reset here re-executes this inverse byte using persistent
                # cursor state. Its own source must survive its destination write.
                replay = literal if src is None else box[src]
                assert replay == value
                box[dst] = replay
                inverse_replays += 1
        assert restored == initial, (removals, cut)
        if cut < len(operations):
            box_id, phase, offset = operations[cut]
            phase.forward(working[box_id], offset)
            first = working[box_id].copy()
            phase.forward(working[box_id], offset)
            assert first == working[box_id]
    assert working == expected
    return {"cuts": len(operations) + 1, "inverse_byte_replays": inverse_replays,
            "record_bytes": sum(journals)}


def run() -> dict:
    results = []
    for seed in (7, 91):
        for count in (1, 2, 10, 19, 20):
            for index in sorted({0, count // 2, count - 1}):
                results.append(verify([fixture(count, seed)], [(0, index)]))
        # Both distinct-box and same-box settlement; second index is post-first.
        for first, second in ((0, 0), (19, 18), (9, 4)):
            results.append(verify([fixture(20, seed)], [(0, first), (0, second)]))
            results.append(verify([fixture(20, seed), fixture(20, seed + 1)],
                                  [(0, first), (1, second)]))
    return {"status": "MODEL ONLY: assumes atomic durable cursor",
            "cases": len(results), "forward_cut_boundaries": sum(r['cuts'] for r in results),
            "inverse_byte_replays": sum(r['inverse_byte_replays'] for r in results),
            "max_saved_record_bytes": max(r['record_bytes'] for r in results),
            "not_proven": ["torn metadata", "ROM integration", "migration", "latency",
                           "main generation commit", "companion checksums and owner hooks"]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = run()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    print(json.dumps(report, indent=2))
