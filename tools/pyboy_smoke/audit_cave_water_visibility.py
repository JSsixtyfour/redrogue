"""Audit: does the procedural cave's river ever actually carve anything?

Phase 5a measurement. PCCarveRiver is called unconditionally (a testing
override; the design roll is ~25%), so every cave gets a river attempt, yet
water is rare on screen. Two competing explanations, and this separates them:

  (1) the river carves but PCNearClaimed's 2-cell buffer pushes it somewhere
      the player never walks, or
  (2) the river dies on its first step and carves nothing at all.

The complication is that ANY count of block 118 in a finished cave is
ambiguous: PCPlaceDropIn runs AFTER the river and one of its three stamps is
maps/25tilepooldrop.blk, a 2x2 block of 118 inside an autotiled ring. A cave
with four water blocks is almost certainly that pool, not a river. So the grid
is sampled at a hook on PCPlaceDropIn's entry, before the pool can exist, and
again once the map is fully up.

Two premises of the Phase 5 plan that this probe checks rather than assumes:

  * "water sits in cells that were already impassable fill" - block 25 is
    sixteen copies of tile $05, and $05 IS in Cavern_Coll. Plain fill is
    WALKABLE. The player can stroll off the carved corridor right up to the
    water, so distance-from-corridor measures how likely the water is to be
    noticed, not whether it can be reached.
  * "the 2-cell buffer is why you never see it" - this counts how many cells
    are even legal river cells (plain fill with no claimed orthogonal
    neighbour), which is the thing that buffer controls.

Usage:
    python3 tools/pyboy_smoke/audit_cave_water_visibility.py [--layouts N] [--label TEXT]

Always exits 0: this is a measurement, not a contract.

One fresh harness per layout is deliberate, for the reasons
audit_boss_ball_overlap.py documents: boot_to_lobby is not reentrant, and each
boot is otherwise deterministic, so wRandomTable must be scrambled per layout
or N boots produce N identical caves.
"""

from __future__ import annotations

import argparse
import random
import sys
import time
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

# custom_functions/procedural_cave_gen.asm
PC_SIZE = 20
PC_STRIDE = 26
PC_BASE = 81
PC_BLOCK_FLOOR = 1
PC_BLOCK_ENTRANCE = 36
PC_BLOCK_FILL = 25
PC_BLOCK_WATER = 118

RNG_STATE_BYTES = 10

# A block is 4x4 tiles of 8px = 32x32px and the screen is 160x144px, so the
# viewport is 5 blocks wide by 4.5 tall with the player near the middle. Two
# blocks out is the edge of the screen; three is off it.
SEEN_RADIUS = 2

NEIGHBOURS = ((0, -1), (0, 1), (-1, 0), (1, 0))


def read_grid(harness: RedRogueHarness) -> list[list[int]]:
    origin = harness.address("wOverworldMap") + PC_BASE
    return [
        [harness.pyboy.memory[origin + y * PC_STRIDE + x] for x in range(PC_SIZE)]
        for y in range(PC_SIZE)
    ]


def is_claimed(block: int) -> bool:
    """PCIsClaimedCarry: anything that is not plain fill and not water."""
    return block not in (PC_BLOCK_FILL, PC_BLOCK_WATER)


def legal_river_cells(grid: list[list[int]]) -> int:
    """Cells PCCarveRiver could legally write: plain fill, no claimed neighbour."""
    total = 0
    for y in range(PC_SIZE):
        for x in range(PC_SIZE):
            if grid[y][x] != PC_BLOCK_FILL:
                continue
            blocked = False
            for dx, dy in NEIGHBOURS:
                nx, ny = x + dx, y + dy
                if 0 <= nx < PC_SIZE and 0 <= ny < PC_SIZE and is_claimed(grid[ny][nx]):
                    blocked = True
                    break
            if not blocked:
                total += 1
    return total


def cells(grid: list[list[int]], value: int) -> list:
    return [(x, y) for y in range(PC_SIZE) for x in range(PC_SIZE) if grid[y][x] == value]


def sample_cave(map_id: int, seed: int):
    """Returns (grid before PCPlaceDropIn, grid once the map is fully up)."""
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    captured = []
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)
        # Entry hook, so what it sees is the river's own output: the blit, the
        # main autotile, decoration and PCAutotileRiverEdges have all run, and
        # the pool stamp has not.
        harness.register_hook("PCPlaceDropIn", lambda _ctx: captured.append(read_grid(harness)))
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
        final = read_grid(harness)
        return (captured[0] if captured else final), final
    finally:
        try:
            harness.close()
        except Exception:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=64)
    parser.add_argument("--label", default="baseline")
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    river_counts = []
    final_counts = []
    legal_counts = []
    dist_hist = Counter()
    caves_seen = 0
    errors = 0
    started = time.time()

    for seed in range(args.layouts):
        try:
            pre, post = sample_cave(map_id, seed)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue

        river = cells(pre, PC_BLOCK_WATER)
        river_counts.append(len(river))
        final_counts.append(len(cells(post, PC_BLOCK_WATER)))
        legal_counts.append(legal_river_cells(pre))

        corridor = [
            (x, y)
            for y in range(PC_SIZE)
            for x in range(PC_SIZE)
            if pre[y][x] in (PC_BLOCK_FLOOR, PC_BLOCK_ENTRANCE)
        ]
        on_screen = False
        for wx, wy in river:
            best = min(max(abs(wx - cx), abs(wy - cy)) for cx, cy in corridor) if corridor else 99
            dist_hist[best] += 1
            if best <= SEEN_RADIUS:
                on_screen = True
        if on_screen:
            caves_seen += 1

    elapsed = time.time() - started
    n = max(1, args.layouts - errors)
    total_river = sum(river_counts)
    with_river = sum(1 for c in river_counts if c)

    print()
    print("=== cave river audit: %s ===" % args.label)
    print("%d layouts, %d harness errors, %.0fs" % (args.layouts, errors, elapsed))
    print()
    print("RIVER (sampled before PCPlaceDropIn, so the pool stamp cannot inflate it)")
    print("  caves with any river water:  %d/%d (%.1f%%)" % (with_river, n, 100.0 * with_river / n))
    print("  river blocks per cave:       mean %.2f, max %d"
          % (total_river / n, max(river_counts or [0])))
    print("  caves with river water within %d blocks of the carved corridor: %d/%d (%.1f%%)"
          % (SEEN_RADIUS, caves_seen, n, 100.0 * caves_seen / n))
    print("  river block count histogram:", dict(sorted(Counter(river_counts).items())))
    if total_river:
        print("  nearest carved-corridor block, per river block (Chebyshev):")
        for dist in sorted(dist_hist):
            print("    %2d: %5d (%5.1f%%)" % (dist, dist_hist[dist], 100.0 * dist_hist[dist] / total_river))
    print()
    print("CONTEXT")
    print("  water in the FINISHED cave (river + any pool drop-in): mean %.2f, caves with any %d/%d"
          % (sum(final_counts) / n, sum(1 for c in final_counts if c), n))
    print("  legal river cells (plain fill, no claimed neighbour): mean %.1f of 400, min %d, max %d"
          % (sum(legal_counts) / n, min(legal_counts or [0]), max(legal_counts or [0])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
