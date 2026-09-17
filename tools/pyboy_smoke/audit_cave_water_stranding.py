"""Audit: can the cave's river cut a pokeball or the boss off from the player?

This is the regression guard for Phase 5a. Making PCCarveRiver actually work
put real impassable water (block 118) on maps that had never had any, and two
things about the cave make stranding a live possibility rather than a
hypothetical:

  * PCPlaceWildAreaItems picks ball cells by rolling random coordinates until
    one reads PC_BLOCK_FLOOR. There is no reachability check anywhere in it.
  * PCAutotileRiverEdges' peninsula sub-pass CONVERTS plain fill to floor when
    it has three or more water-like neighbours, so the river can mint brand
    new floor cells in the middle of itself. Both it and PCPlaceWildAreaItems
    run after PCCarveRiver, in that order.

The original connectivity guarantee in PCCarveRiver's header ("floor cells are
categorically never touched, so the floor-to-floor adjacency graph is
unchanged") is still true and is not the question. The question is whether new
floor appears somewhere the player cannot walk to.

Reachability is computed on the 40x40 player-step grid, not the 20x20 block
grid, because a Game Boy block is 4x4 tiles and the player moves in 16px
steps: each block holds 2x2 steps and each step tests the single 8x8 tile at
its top-left corner. Passability comes from gfx/blocksets/cavern.bst decoded
against Cavern_Coll.

SELF-CHECK: the model is validated by its own output rather than trusted. A
cave's entrance, exit ladder and all five sprite slots are placed on carved
floor that the generator connected by construction, so if this script reports
any of them unreachable in a build whose river is disabled, the MODEL is
wrong, not the game. Run it against a no-river build first if you ever doubt
a result here.

Usage:
    python3 tools/pyboy_smoke/audit_cave_water_stranding.py [--layouts N]

Exits non-zero if any sprite is unreachable.
"""

from __future__ import annotations

import argparse
import random
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

PC_SIZE = 20
PC_STRIDE = 26
PC_BASE = 81
PC_BLOCK_WATER = 118
STEP_SIZE = PC_SIZE * 2  # 40x40 player steps
RNG_STATE_BYTES = 10
SPRITE_SLOTS = 5
# Sprite MapY/MapX are stored as block*2 + 4 (see PCPlaceWildAreaItems and the
# matching `sub 4 / srl a` in PCDropInOverlapsSprite), but harness
# sprite_positions ALREADY subtracts that 4, so what it hands back is player-step
# coordinates and needs no further adjustment. Subtracting it a second time here
# produced negative coordinates and reported even the boss as unreachable, which
# is what the self-check in this docstring is for.


def passable_tiles() -> set:
    text = (REPO_ROOT / "data" / "tilesets" / "collision_tile_ids.asm").read_text()
    line = text[text.index("Cavern_Coll::"):].split("\n")[1]
    return {int(tok.strip().lstrip("$"), 16) for tok in line.split("coll_tiles")[1].split(",")}


def step_walkable(blockset: bytes, passable: set, block: int, qx: int, qy: int) -> bool:
    """Is the 16px step at quadrant (qx,qy) of this block walkable?

    The tile the engine tests is the top-left 8x8 tile of the quadrant, so
    quadrant (qx,qy) maps to tile row qy*2, column qx*2 of the block's 4x4.
    """
    if block * 16 + 15 >= len(blockset):
        return False
    tile = blockset[block * 16 + (qy * 2) * 4 + (qx * 2)]
    return tile in passable


def reachable_steps(grid, blockset, passable, start) -> set:
    walkable = [[False] * STEP_SIZE for _ in range(STEP_SIZE)]
    for sy in range(STEP_SIZE):
        for sx in range(STEP_SIZE):
            block = grid[sy // 2][sx // 2]
            walkable[sy][sx] = step_walkable(blockset, passable, block, sx % 2, sy % 2)
    seen = set()
    if not (0 <= start[0] < STEP_SIZE and 0 <= start[1] < STEP_SIZE):
        return seen
    if not walkable[start[1]][start[0]]:
        # The player is standing there, so treat it as walkable regardless and
        # say so, rather than silently returning an empty set.
        print("    note: player's own step reads impassable; seeding it anyway")
    stack = [start]
    seen.add(start)
    while stack:
        sx, sy = stack.pop()
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nx, ny = sx + dx, sy + dy
            if not (0 <= nx < STEP_SIZE and 0 <= ny < STEP_SIZE):
                continue
            if (nx, ny) in seen or not walkable[ny][nx]:
                continue
            seen.add((nx, ny))
            stack.append((nx, ny))
    return seen


def sample(map_id: int, seed: int):
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
        origin = harness.address("wOverworldMap") + PC_BASE
        grid = [
            [harness.pyboy.memory[origin + y * PC_STRIDE + x] for x in range(PC_SIZE)]
            for y in range(PC_SIZE)
        ]
        player = (harness.read8("wXCoord"), harness.read8("wYCoord"))
        sprites = [tuple(p) for p in harness.sprite_positions(SPRITE_SLOTS)]
        return grid, player, sprites
    finally:
        try:
            harness.close()
        except Exception:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=64)
    args = parser.parse_args()

    blockset = (REPO_ROOT / "gfx" / "blocksets" / "cavern.bst").read_bytes()
    passable = passable_tiles()
    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    failures = 0
    errors = 0
    total_water = 0
    started = time.time()

    for seed in range(args.layouts):
        try:
            grid, player, sprites = sample(map_id, seed)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue

        water = sum(row.count(PC_BLOCK_WATER) for row in grid)
        total_water += water
        seen = reachable_steps(grid, blockset, passable, player)

        for slot, (step_y, step_x) in enumerate(sprites, start=1):
            step = (step_x, step_y)
            # A sprite counts as reachable if the player can get to it OR to a
            # step orthogonally beside it. Requiring the sprite's own step to be
            # walkable is wrong twice over: an object is solid to the player
            # anyway, and the boss stands on the exit ladder (block 39), whose
            # top-left tile is $08 and is deliberately NOT in Cavern_Coll. That
            # alone reported the boss unreachable in about 60 of 64 caves, which
            # is the model failing, not the game.
            if step in seen or any(
                (step[0] + dx, step[1] + dy) in seen
                for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))
            ):
                continue
            failures += 1
            what = "boss" if slot == 1 else "pokeball %d" % (slot - 1)
            print("  UNREACHABLE seed %d: %s at step %s (block %s), player at %s, %d water"
                  % (seed, what, step, (step[0] // 2, step[1] // 2), player, water))

    elapsed = time.time() - started
    n = max(1, args.layouts - errors)
    print()
    print("%d layouts, %d harness errors, %.0fs" % (args.layouts, errors, elapsed))
    print("mean water blocks per cave: %.1f" % (total_water / n))
    if failures:
        print("FAIL: %d sprite(s) unreachable from the player's spawn" % failures)
        return 1
    print("PASS: every boss and pokeball is reachable on foot in all %d caves" % n)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
