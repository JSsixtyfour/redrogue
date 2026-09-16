#!/usr/bin/env python3
"""Print an authored Facility asset as block ids beside its quadrant map.

Written for the C0c repair decision: a stranded quadrant is only visible at
quadrant resolution, but the FIX is a block-id substitution, so both views are
needed side by side to choose one.

Usage (from the repo root):
    python3 tools/show_facility_asset_corner.py <asset.blk> [more.blk ...]
"""

from __future__ import annotations

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

NAMES = {
    0x40: "TL corner", 0x41: "top wall", 0x42: "TR corner",
    0x44: "left wall", 0x46: "right wall",
    0x48: "BL corner", 0x49: "bottom wall", 0x4A: "BR corner",
    0x0E: "plain floor", 0x2E: "void/solid wall",
    0x68: "TL corner DECO (solid)", 0x69: "TR corner DECO (solid)",
    0x0C: "BR corner DECO (solid)",
    0x5C: "left wall DECO (solid)", 0x5D: "right wall DECO (solid)",
    0x61: "top wall DECO (solid)", 0x33: "bottom wall DECO (solid)",
    0x28: "bottom wall DECO (solid)", 0x06: "solid",
}


def dimensions(name: str):
    for token in name.split("_")[1:]:
        if "x" in token:
            left, _, right = token.partition("x")
            if left.isdigit() and right.isdigit():
                return int(left), int(right)
    return None


def quadrant_cells(blockset, payload, width, height):
    cells = set()
    for row in range(height):
        for col in range(width):
            base = payload[row * width + col] * 16
            for qy in range(2):
                for qx in range(2):
                    if blockset[base + QUADRANT_INDEXES[qy * 2 + qx]] in WALKABLE_TILES:
                        cells.add((2 * col + qx, 2 * row + qy))
    return cells


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    blockset = BLOCKSET.read_bytes()

    for argument in sys.argv[1:]:
        path = Path(argument)
        if not path.exists():
            path = MAPS / argument
        size = dimensions(path.name)
        if size is None:
            print(f"{path.name}: cannot parse dimensions")
            continue
        width, height = size
        payload = path.read_bytes()
        cells = quadrant_cells(blockset, payload, width, height)
        components = _connected_components(cells)
        components.sort(key=len, reverse=True)
        largest = components[0] if components else set()
        stranded = cells - largest

        print(f"=== {path.name}  ({width}x{height} blocks) ===")
        print(f"walkable quadrants {len(cells)}, groups {len(components)},"
              f" stranded {len(stranded)}\n")

        print("block ids:")
        for row in range(height):
            line = "  "
            for col in range(width):
                line += f"{payload[row * width + col]:02X} "
            print(line)

        print("\nquadrants  ('#' main group, 'X' STRANDED, '.' solid):")
        for qy in range(height * 2):
            line = "  "
            for qx in range(width * 2):
                cell = (qx, qy)
                line += "#" if cell in largest else ("X" if cell in cells else ".")
            print(line)

        if stranded:
            print("\nstranded quadrant(s) and the block that owns each:")
            for qx, qy in sorted(stranded):
                col, row = qx // 2, qy // 2
                block = payload[row * width + col]
                corner = ("TL", "TR", "BL", "BR")[(qy % 2) * 2 + (qx % 2)]
                print(f"  quadrant ({qx},{qy}) is the {corner} of block"
                      f" ({col},{row}) = ${block:02X}"
                      f" {NAMES.get(block, '')}")
                print("  its orthogonal neighbours:")
                for nx, ny, label in (
                    (qx + 1, qy, "east"), (qx - 1, qy, "west"),
                    (qx, qy + 1, "south"), (qx, qy - 1, "north"),
                ):
                    if not (0 <= nx < width * 2 and 0 <= ny < height * 2):
                        print(f"    {label:5s} outside the footprint")
                        continue
                    ncol, nrow = nx // 2, ny // 2
                    nblock = payload[nrow * width + ncol]
                    state = "WALKABLE" if (nx, ny) in cells else "solid"
                    print(f"    {label:5s} ({nx},{ny}) {state:8s}"
                          f" in block ({ncol},{nrow}) = ${nblock:02X}"
                          f" {NAMES.get(nblock, '')}")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
