#!/usr/bin/env python3
"""Find authored Facility assets whose walkable space is split diagonally.

The overworld has no diagonal movement, so two walkable quadrants touching only
at a corner are NOT connected. An asset can look open in a block editor and be
impassable in game. Block ids alone cannot show this; it only appears at
quadrant resolution with a 4-way flood fill.

This expands every authored .blk payload into quadrants and reports any whose
walkable area falls into more than one orthogonally connected group. A room
template legitimately may (a solid centre with a baseboard ring is one group; a
sealed decorative alcove is another matter), so the report distinguishes the
largest group from the remainder and prints the pattern for judgement.

Usage (from the repo root):
    python3 tools/check_facility_diagonal_splits.py [--all]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_facility_premades import (  # noqa: E402
    WALKABLE_TILES,
    QUADRANT_INDEXES,
    _connected_components,
)

REPO_ROOT = Path(__file__).resolve().parents[1]
BLOCKSET = REPO_ROOT / "gfx" / "blocksets" / "facility.bst"
MAPS = REPO_ROOT / "maps"


def dimensions(name: str) -> tuple[int, int] | None:
    """ProceduralFacility_<W>x<H>_<rest>.blk"""
    parts = name.split("_")
    if len(parts) < 2:
        return None
    for token in parts[1:]:
        if "x" in token:
            left, _, right = token.partition("x")
            if left.isdigit() and right.isdigit():
                return int(left), int(right)
    return None


def quadrants(blockset: bytes, payload: bytes, width: int, height: int):
    cells = set()
    for row in range(height):
        for col in range(width):
            base = payload[row * width + col] * 16
            for quadrant_y in range(2):
                for quadrant_x in range(2):
                    index = QUADRANT_INDEXES[quadrant_y * 2 + quadrant_x]
                    if blockset[base + index] in WALKABLE_TILES:
                        cells.add((2 * col + quadrant_x, 2 * row + quadrant_y))
    return cells


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true",
                        help="print every asset, not only split ones")
    args = parser.parse_args()

    blockset = BLOCKSET.read_bytes()
    assets = sorted(MAPS.glob("ProceduralFacility_*.blk"))
    if not assets:
        print("no ProceduralFacility_*.blk assets found")
        return 1

    split = []
    checked = 0
    for path in assets:
        size = dimensions(path.name)
        if size is None:
            continue
        width, height = size
        payload = path.read_bytes()
        if len(payload) != width * height:
            continue  # size-mismatched assets are the premade audit's problem
        checked += 1
        cells = quadrants(blockset, payload, width, height)
        if not cells:
            continue
        components = _connected_components(cells)
        if len(components) > 1 or args.all:
            components.sort(key=len, reverse=True)
            split.append((path.name, width, height, cells, components))

    # A DECOR payload is stamped into the middle of a room and is surrounded by
    # that room's open floor, which rejoins anything this test sees as separate.
    # Only a FULL-ROOM template owns its whole footprint, so only a full-room
    # template can actually strand a quadrant. Judge the two differently or the
    # decor entries read as defects when they are not.
    rooms = [entry for entry in split if "_decor" not in entry[0]]
    decor = [entry for entry in split if "_decor" in entry[0]]

    print(f"checked {checked} sized assets of {len(assets)} found")
    print(f"full-room templates with split walkable space: {len(rooms)}")
    print(f"decor payloads with split walkable space: {len(decor)}"
          " (expected; surrounding room floor rejoins them)\n")
    if not rooms and not args.all:
        print("no FULL-ROOM template has diagonally split walkable space")
        return 0

    for name, width, height, cells, components in (rooms if not args.all else split):
        if len(components) == 1 and not args.all:
            continue
        stranded = sum(len(group) for group in components[1:])
        print(f"{name}  ({width}x{height} blocks)")
        print(f"  walkable quadrants {len(cells)}"
              f"  groups {len(components)}"
              f"  outside the largest group: {stranded}")
        largest = components[0]
        for quadrant_y in range(height * 2):
            line = ""
            for quadrant_x in range(width * 2):
                cell = (quadrant_x, quadrant_y)
                if cell in largest:
                    line += "#"
                elif cell in cells:
                    line += "X"
                else:
                    line += "."
            print("    " + line)
        print()
    print("'#' largest connected group, 'X' walkable but in a separate group,"
          " '.' solid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
