#!/usr/bin/env python3
"""Print the walkable-quadrant layout of any Facility block ids, and test
whether a given 2x2 arrangement of blocks is orthogonally traversable.

Two walkable quadrants that touch only DIAGONALLY are not connected - the
overworld has no diagonal movement - so a patch of map can look open and be
impassable. This renders a block arrangement at quadrant resolution and runs an
orthogonal flood fill over it, which is the only way to see that.

Usage (from the repo root):
    python3 tools/decode_facility_blocks.py 44 0D 12 46      # a 2x2 window
    python3 tools/decode_facility_blocks.py --list 33 28 49  # just decode
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_facility_premades import block_quadrants  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[1]
BLOCKSET = REPO_ROOT / "gfx" / "blocksets" / "facility.bst"


def row_pair(blockset: bytes, block_id: int) -> tuple[str, str]:
    top_left, top_right, bottom_left, bottom_right = block_quadrants(blockset, block_id)
    mark = lambda flag: "#" if flag else "."  # noqa: E731
    return (
        f"{mark(top_left)}{mark(top_right)}",
        f"{mark(bottom_left)}{mark(bottom_right)}",
    )


def describe(blockset: bytes, block_id: int) -> str:
    top, bottom = row_pair(blockset, block_id)
    walkable = (top + bottom).count("#")
    return f"${block_id:02X}  {top}/{bottom}  {walkable}/4"


def quadrant_grid(blockset: bytes, blocks: list[list[int]]) -> list[list[bool]]:
    grid: list[list[bool]] = []
    for block_row in blocks:
        upper: list[bool] = []
        lower: list[bool] = []
        for block_id in block_row:
            top_left, top_right, bottom_left, bottom_right = block_quadrants(
                blockset, block_id
            )
            upper += [top_left, top_right]
            lower += [bottom_left, bottom_right]
        grid.append(upper)
        grid.append(lower)
    return grid


def components(grid: list[list[bool]]) -> list[set[tuple[int, int]]]:
    """Orthogonally connected groups of walkable quadrants. No diagonals."""
    seen: set[tuple[int, int]] = set()
    found = []
    for y, row in enumerate(grid):
        for x, walkable in enumerate(row):
            if not walkable or (x, y) in seen:
                continue
            stack = [(x, y)]
            group: set[tuple[int, int]] = set()
            while stack:
                cx, cy = stack.pop()
                if (cx, cy) in group:
                    continue
                group.add((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= ny < len(grid) and 0 <= nx < len(grid[ny]):
                        if grid[ny][nx] and (nx, ny) not in group:
                            stack.append((nx, ny))
            seen |= group
            found.append(group)
    return found


def main() -> int:
    argv = sys.argv[1:]
    if not argv:
        print(__doc__)
        return 1
    blockset = BLOCKSET.read_bytes()

    if argv[0] == "--list":
        for token in argv[1:]:
            print("  " + describe(blockset, int(token, 16)))
        return 0

    ids = [int(token, 16) for token in argv]
    if len(ids) == 4:
        blocks = [[ids[0], ids[1]], [ids[2], ids[3]]]
    elif len(ids) == 2:
        blocks = [[ids[0], ids[1]]]
    else:
        blocks = [ids]

    print("blocks:")
    for token in ids:
        print("  " + describe(blockset, token))

    grid = quadrant_grid(blockset, blocks)
    print("\nquadrant view ('#' walkable, '.' solid):")
    for row in grid:
        print("   " + "".join("#" if cell else "." for cell in row))

    groups = components(grid)
    walkable = sum(sum(1 for cell in row if cell) for row in grid)
    print(f"\nwalkable quadrants: {walkable}")
    print(f"orthogonally connected groups: {len(groups)}")
    if len(groups) > 1:
        print("\n*** DIAGONAL BLOCKAGE ***")
        print("These quadrants look adjacent on screen but cannot be walked")
        print("between, because the overworld has no diagonal movement:")
        for index, group in enumerate(groups, 1):
            cells = ", ".join(f"({x},{y})" for x, y in sorted(group))
            print(f"  group {index}: {cells}")
    elif groups:
        print("all walkable quadrants are mutually reachable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
