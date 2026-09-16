#!/usr/bin/env python3
"""Decode the Facility wall-DECORATION blocks against facility.bst.

The C6 phase of PROCEDURAL_FACILITY_CONTENT_PLAN.md cannot be designed without
this table. The decoration catalogue is $44->$5C, $46->$5D, $41->$61, $40->$68,
$42->$69, and only $5C/$5D were ever confirmed solid. Guessing the rest is
exactly the mistake R3 made: never infer a block's collision from its name.

Prints each plain wall block beside its decorated variant so the quadrants lost
to decoration are visible directly, plus the corridor floor block for reference.

Usage (from the repo root):
    python3 tools/decode_facility_wall_decor.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from check_facility_premades import (  # noqa: E402
    WALKABLE_TILES,
    QUADRANT_INDEXES,
    block_quadrants,
)

REPO_ROOT = Path(__file__).resolve().parents[1]
BLOCKSET = REPO_ROOT / "gfx" / "blocksets" / "facility.bst"

# plain block, decorated variant, role
CATALOGUE = (
    (0x44, 0x5C, "left wall   (vertical corridor, west side)"),
    (0x46, 0x5D, "right wall  (vertical corridor, east side)"),
    (0x41, 0x61, "top wall    (horizontal corridor, north side)"),
    (0x49, None, "bottom wall (horizontal corridor, south side)"),
    (0x40, 0x68, "TL corner"),
    (0x42, 0x69, "TR corner"),
    (0x48, None, "BL corner"),
    (0x4A, None, "BR corner"),
)

REFERENCE = ((0x0E, "plain floor / what a carved corridor cell becomes"),)


def show(blockset: bytes, block_id: int) -> str:
    top_left, top_right, bottom_left, bottom_right = block_quadrants(blockset, block_id)
    mark = lambda flag: "#" if flag else "."  # noqa: E731
    walkable = sum((top_left, top_right, bottom_left, bottom_right))
    return (
        f"{mark(top_left)}{mark(top_right)}/"
        f"{mark(bottom_left)}{mark(bottom_right)}  {walkable}/4"
    )


def main() -> int:
    blockset = BLOCKSET.read_bytes()
    print(f"{BLOCKSET.relative_to(REPO_ROOT)}  ({len(blockset)} bytes,"
          f" {len(blockset) // 16} blocks)")
    print(f"walkable tile ids: {sorted(WALKABLE_TILES)}")
    print(f"quadrant byte offsets within a block: {list(QUADRANT_INDEXES)}")
    print("\nquadrants shown as TL TR / BL BR, '#' = walkable\n")

    for block_id, label in REFERENCE:
        print(f"  ${block_id:02X}  {show(blockset, block_id):16s}  {label}")
    print()

    print("plain -> decorated                       plain            decorated")
    for plain, decorated, role in CATALOGUE:
        plain_view = show(blockset, plain)
        if decorated is None:
            print(f"  ${plain:02X} -> (none)   {role:42s} {plain_view}")
            continue
        decorated_view = show(blockset, decorated)
        lost = sum(block_quadrants(blockset, plain)) - sum(
            block_quadrants(blockset, decorated)
        )
        print(f"  ${plain:02X} -> ${decorated:02X}      {role:42s}"
              f" {plain_view}   {decorated_view}  lost {lost}")

    print("\nCorridor width, in quadrant rows/columns. A carved corridor cell")
    print("becomes $0E (2 quadrants across), and each flanking wall donates its")
    print("inner row or column. A player occupies ONE quadrant, so anything >= 1")
    print("is walkable.\n")

    def inner(block_id, axis):
        """Quadrant rows (axis='row') or columns (axis='col') a wall donates."""
        if block_id is None:
            return None
        top_left, top_right, bottom_left, bottom_right = block_quadrants(
            blockset, block_id
        )
        if axis == "row":
            return int(top_left or top_right) + int(bottom_left or bottom_right)
        return int(top_left or bottom_left) + int(top_right or bottom_right)

    for label, axis, low, low_dec, high, high_dec in (
        ("vertical corridor, walls $44 west / $46 east",
         "col", 0x44, 0x5C, 0x46, 0x5D),
        ("horizontal corridor, walls $41 north / $49 south",
         "row", 0x41, 0x61, 0x49, None),
    ):
        bare = 2 + inner(low, axis) + inner(high, axis)
        one = 2 + (inner(low_dec, axis) if low_dec else 0) + inner(high, axis)
        both_low = inner(low_dec, axis) if low_dec is not None else inner(low, axis)
        both_high = inner(high_dec, axis) if high_dec is not None else inner(high, axis)
        both = 2 + both_low + both_high
        print(f"  {label}")
        print(f"      undecorated          {bare}")
        print(f"      one side decorated   {one}")
        print(f"      both sides decorated {both}"
              f"   ({'walkable' if both >= 1 else 'BLOCKED'})")
        if high_dec is None:
            print(f"      note: ${high:02X} has NO decoration variant, so that side"
                  " can never be decorated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
