#!/usr/bin/env python3
"""Count walkable quadrants that are unreachable from the Facility entrance.

The overworld has no diagonal movement, so two walkable quadrants that touch
only at a corner are NOT connected. A patch of map can therefore look open and
be impassable, and nothing in the block-level view shows it.

The corpus test in test_smoke.py builds the correct 4-way quadrant flood fill,
but its room assertion is `any(cell in reachable ...)` - a room passes if even
ONE of its walkable quadrants is reachable. A stranded pocket inside an
otherwise-connected room is invisible to it, as is a stranded pocket in a
corridor or wall baseboard. This audit asks the stricter question the test does
not: how much walkable floor is cut off, and where.

Anything this reports is a live generator defect, independent of any future
wall-decoration work.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/audit_facility_stranded_quadrants.py [--seeds N]
                                                                  [--show N]
"""

from __future__ import annotations

import argparse
import io
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
BLOCKSET = REPO_ROOT / "gfx" / "blocksets" / "facility.bst"

WALKABLE_TILES = {
    0x01, 0x10, 0x11, 0x13, 0x1B, 0x20, 0x21, 0x22, 0x30,
    0x31, 0x32, 0x42, 0x43, 0x48, 0x52, 0x55, 0x58, 0x5E,
}
QUADRANT_TILE_INDEXES = (5, 7, 13, 15)
# Bottom-left quadrant of block (9,19) since 2026-09-17; the top two
# quadrants of that block are the stage-event NPC pair's arrival cells.
ENTRANCE = (18, 39)


def passable(blockset: bytes, playable) -> set[tuple[int, int]]:
    cells = set()
    for block_y in range(20):
        for block_x in range(20):
            base = playable[block_y * 20 + block_x] * 16
            for quadrant_y in range(2):
                for quadrant_x in range(2):
                    index = QUADRANT_TILE_INDEXES[quadrant_y * 2 + quadrant_x]
                    if blockset[base + index] in WALKABLE_TILES:
                        cells.add((2 * block_x + quadrant_x, 2 * block_y + quadrant_y))
    return cells


def flood(cells: set[tuple[int, int]], start) -> set[tuple[int, int]]:
    if start not in cells:
        return set()
    reachable = {start}
    frontier = [start]
    while frontier:
        col, row = frontier.pop()
        for near in ((col - 1, row), (col + 1, row), (col, row - 1), (col, row + 1)):
            if near in cells and near not in reachable:
                reachable.add(near)
                frontier.append(near)
    return reachable


def groups(cells: set[tuple[int, int]]) -> list[set[tuple[int, int]]]:
    remaining = set(cells)
    found = []
    while remaining:
        seed = next(iter(remaining))
        group = flood(remaining, seed)
        found.append(group)
        remaining -= group
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=64)
    parser.add_argument("--show", type=int, default=3,
                        help="print a quadrant map for the N worst layouts")
    args = parser.parse_args()

    blockset = BLOCKSET.read_bytes()
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    harness.boot_to_lobby()
    harness.call_routine("PFacPreload", limit=60000)
    baseline = io.BytesIO()
    harness.save_state(baseline)

    worst: list[tuple[int, list[int], set, set]] = []
    stranded_totals = []
    layouts_with_strandings = 0
    pocket_sizes: Counter = Counter()

    state = 0x1234_5678
    for index in range(args.seeds):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        seed = [(state >> shift) & 0xFF for shift in (0, 8, 16, 24)]
        harness.load_state(baseline)
        harness.write_sram_bytes("sProcFacilityExitEdge", [index % 3])
        harness.seed_rng(seed)
        harness.call_routine("PFacFinalize", limit=4000)

        block_buffer = harness.read_bytes("wOverworldMap", 601)
        playable = tuple(
            block_buffer[81 + row * 26 + col]
            for row in range(20)
            for col in range(20)
        )
        cells = passable(blockset, playable)
        reachable = flood(cells, ENTRANCE)
        stranded = cells - reachable
        stranded_totals.append(len(stranded))
        if stranded:
            layouts_with_strandings += 1
            for pocket in groups(stranded):
                pocket_sizes[len(pocket)] += 1
            worst.append((len(stranded), seed, cells, reachable))

    total = len(stranded_totals)
    print(f"layouts {total}\n")
    print(f"layouts with at least one stranded walkable quadrant: "
          f"{layouts_with_strandings} ({layouts_with_strandings / total:.0%})")
    if not layouts_with_strandings:
        print("every walkable quadrant is reachable from the entrance")
        return 0
    print(f"stranded quadrants per layout: min {min(stranded_totals)}"
          f"  max {max(stranded_totals)}"
          f"  mean {sum(stranded_totals) / total:.1f}")
    print(f"\nstranded pocket sizes (quadrants: count):")
    for size in sorted(pocket_sizes):
        print(f"  {size:3d} quadrants  x{pocket_sizes[size]}")

    worst.sort(key=lambda entry: -entry[0])
    for count, seed, cells, reachable in worst[: args.show]:
        label = " ".join(f"{byte:02X}" for byte in seed)
        print(f"\n--- seed {label}: {count} stranded quadrants ---")
        print("    '#' reachable, 'X' walkable but STRANDED, '.' solid")
        for row in range(40):
            line = ""
            for col in range(40):
                if (col, row) in reachable:
                    line += "#"
                elif (col, row) in cells:
                    line += "X"
                else:
                    line += "."
            print("    " + line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
