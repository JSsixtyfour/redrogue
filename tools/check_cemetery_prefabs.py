#!/usr/bin/env python3
"""
Offline connectivity checker for the procedural cemetery prefab pool
(custom_functions/procedural_cemetery_gen.asm, PCemPrefabTable).

Connectivity in this blockset is a CELL-level property (each 10x9 block
map is really a 20x18 player-cell grid; a block's collision tile is its
bottom-left cell, see CEMETERY_DESIGN_LAPTOP.md), so a block-level flood
fill can never answer it correctly. This checks the real cell grid against
gfx/blocksets/cemetery.bst, exactly like PCemMarchPath does at runtime.

For every prefab in the pool, for every one of the 4 floors, this:
  1. Applies the same 3-cell stair patch PCemPlaceStaircases writes at
     runtime (col1, col9, and block (4,8) from PCemFloorGeometry).
  2. Floods from the floor's entrance warp cell and checks the exit warp
     cell is reached.
  3. Checks the prefab's authored ball position (PCemPrefabTable) is a
     floor cell (14 or 54) in the RAW template (before the patch, since
     the patch never touches ball positions in practice).

Run after adding/editing a prefab .blk file or PCemPrefabTable entry:
    python tools/check_cemetery_prefabs.py

Exits 1 if any prefab fails on any floor.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN_ASM = ROOT / "custom_functions" / "procedural_cemetery_gen.asm"
BLOCKSET = ROOT / "gfx" / "blocksets" / "cemetery.bst"
MAPS_DIR = ROOT / "maps"

CEMAP_WIDTH = 10
CEMAP_HEIGHT = 9

# Collision tile IDs (bottom-left cell of a block) that are walkable.
# Mirrors the COLL set used throughout the cemetery design work: the
# non-warp floor tile (0x01) plus every stair/warp variant.
WALKABLE_TILES = {0x01, 0x10, 0x13, 0x1b, 0x22, 0x42, 0x52}

# Floor block IDs (raw template, pre-patch) treated as "floor" for the
# ball-position check. Matches PCemIsFloor in the asm.
FLOOR_BLOCKS = {14, 54}

# Entrance/exit warp CELL coordinates per floor, matching the west/east/
# south staircase positions in the live maps.
WARPS = {
    1: ((3, 9), (18, 9)),   # W entry -> E exit
    2: ((18, 9), (3, 9)),   # E entry -> W exit
    3: ((3, 9), (18, 9)),   # W entry -> E exit
    4: ((18, 9), (9, 16)),  # E entry -> S exit
}


def parse_floor_geometry(asm_text):
    """Extract PCemFloorGeometry's 4 rows: (col1_block, col9_block, south_block)."""
    m = re.search(r"^PCemFloorGeometry:\n((?:\tdb.*\n){4})", asm_text, re.MULTILINE)
    if not m:
        sys.exit("ERROR: could not find PCemFloorGeometry in " + str(GEN_ASM))
    rows = []
    for line in m.group(1).splitlines():
        nums = [int(x.strip()) for x in line.split("db", 1)[1].split(";")[0].split(",")]
        rows.append((nums[0], nums[1], nums[2]))  # col1, col9, south
    return rows  # index 0..3 = floor 1..4


def parse_prefab_table(asm_text):
    """Extract PCemPrefabTable rows: (label, ballX, ballY)."""
    m = re.search(r"^PCemPrefabTable:\n((?:\tdb.*\n)+)", asm_text, re.MULTILINE)
    if not m:
        sys.exit("ERROR: could not find PCemPrefabTable in " + str(GEN_ASM))
    entries = []
    for line in m.group(1).splitlines():
        # db BANK(PCemDropA_Blocks), LOW(PCemDropA_Blocks), HIGH(PCemDropA_Blocks), 5, 4
        label_m = re.search(r"BANK\((\w+)\)", line)
        tail = [int(x) for x in line.rstrip().split(",")[-2:]]
        if not label_m or len(tail) != 2:
            sys.exit(f"ERROR: could not parse PCemPrefabTable row: {line!r}")
        entries.append((label_m.group(1), tail[0], tail[1]))
    return entries


def parse_incbin_paths(asm_text, labels):
    """Map each label used in PCemPrefabTable to its INCBIN .blk path."""
    paths = {}
    for label in labels:
        m = re.search(rf"^{re.escape(label)}:\s*INCBIN\s+\"([^\"]+)\"", asm_text, re.MULTILINE)
        if not m:
            sys.exit(f"ERROR: no INCBIN found for label {label}")
        paths[label] = ROOT / m.group(1)
    return paths


def load_blockset(path):
    return path.read_bytes()


def collision_tile(blockset, block_id, sx, sy):
    # Each block = 16 bytes = 4x4 tile grid; player cell (sx,sy in 0/1)
    # maps to the bottom-left tile of its 2x2 sub-quadrant.
    return blockset[block_id * 16 + (sy * 2 + 1) * 4 + sx * 2]


def walkable(blockset, block_id, sx, sy):
    return collision_tile(blockset, block_id, sx, sy) in WALKABLE_TILES


def cell_grid(blockset, blocks):
    grid = {}
    for by in range(CEMAP_HEIGHT):
        for bx in range(CEMAP_WIDTH):
            b = blocks[by * CEMAP_WIDTH + bx]
            for sy in (0, 1):
                for sx in (0, 1):
                    grid[(bx * 2 + sx, by * 2 + sy)] = walkable(blockset, b, sx, sy)
    return grid


def flood_reaches(grid, start, target):
    if not grid.get(start):
        return False
    seen = {start}
    stack = [start]
    while stack:
        x, y = stack.pop()
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if grid.get(n) and n not in seen:
                seen.add(n)
                stack.append(n)
    return target in seen


def check_prefab(blockset, geometry, label, path, ball_x, ball_y):
    raw = list(path.read_bytes())
    if len(raw) != CEMAP_WIDTH * CEMAP_HEIGHT:
        return [f"{label}: wrong size ({len(raw)} bytes, expected {CEMAP_WIDTH * CEMAP_HEIGHT})"]

    failures = []

    ball_block = raw[ball_y * CEMAP_WIDTH + ball_x]
    if ball_block not in FLOOR_BLOCKS:
        failures.append(
            f"{label}: authored ball position ({ball_x},{ball_y}) is block {ball_block}, "
            f"not floor ({sorted(FLOOR_BLOCKS)})"
        )

    for floor in (1, 2, 3, 4):
        col1, col9, south = geometry[floor - 1]
        entrance, exit_ = WARPS[floor]
        patched = raw[:]
        patched[4 * CEMAP_WIDTH + 1] = col1
        patched[4 * CEMAP_WIDTH + 9] = col9
        patched[8 * CEMAP_WIDTH + 4] = south
        grid = cell_grid(blockset, patched)
        if not flood_reaches(grid, entrance, exit_):
            failures.append(f"{label}: floor {floor}, entrance {entrance} cannot reach exit {exit_}")

    return failures


def main():
    asm_text = GEN_ASM.read_text()
    blockset = load_blockset(BLOCKSET)
    geometry = parse_floor_geometry(asm_text)
    prefab_rows = parse_prefab_table(asm_text)
    incbin_paths = parse_incbin_paths(asm_text, [label for label, _, _ in prefab_rows])

    all_failures = []
    for label, ball_x, ball_y in prefab_rows:
        path = incbin_paths[label]
        failures = check_prefab(blockset, geometry, label, path, ball_x, ball_y)
        status = "FAIL" if failures else "ok"
        print(f"[{status}] {label}  ({path.name})")
        all_failures.extend(failures)

    print()
    if all_failures:
        print(f"{len(all_failures)} FAILURE(S):")
        for f in all_failures:
            print(f"  - {f}")
        sys.exit(1)
    print(f"All {len(prefab_rows)} prefabs pass on all 4 floors.")


if __name__ == "__main__":
    main()
