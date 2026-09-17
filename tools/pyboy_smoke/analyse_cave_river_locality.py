"""How much of PCAutotileRiverEdges' 400-cell sweep can change anything?

Phase 6 sizing measurement, taken BEFORE choosing a mechanism, because the
plan's proposed fix (track every water position in a new SRAM scratch block)
and the obvious cheap alternative (track the river's bounding box in four
already-dead `wBuffer` bytes) differ enormously in cost and risk, and which one
is worth doing depends entirely on numbers nobody has taken.

THE ARGUMENT THIS CHECKS. `PCAutotilePass` has already classified the whole
grid by the time the river runs. `PCAutotileRiverEdges` re-sweeps it with
`wProcCaveIncludeWater` set, so a still-plain-fill cell is reclassified with
water counted as floor-like. A fill cell with no water in the neighbourhood
`PCClassifyCell` examines therefore classifies EXACTLY as it did a moment ago,
which is "leave it alone" - it is still fill precisely because the earlier pass
declined to convert it. Visiting it is provably wasted work.

So the candidate set is the cells near water, and the question is only how near
and how many:

  * Pass B' candidates reach TWO cells from water, not one. Pass A' can mint a
    new floor cell adjacent to water, and Pass B' then classifies that new
    cell's own neighbours, which sit one further out.
  * `PCClassifyCell` reads diagonals (for corners), so "near" is Chebyshev,
    not Manhattan.

Reported per cave, all as cell counts out of 400:

  water            river blocks carved
  cheb<=1          the 3x3 neighbourhood of the river (Pass A' candidates)
  cheb<=2          the 5x5 neighbourhood (Pass B' candidates, the set a
                   position-tracked implementation would have to visit)
  bbox+2           the river's bounding box grown by 2, clipped to the grid -
                   what the four-byte bounding-box implementation would sweep
  fill-in-bbox+2   of those, how many still read as plain fill, i.e. how many
                   would survive the `cp 25` and reach PCClassifyCell

`bbox+2` is necessarily >= `cheb<=2`; the gap between them is exactly what the
expensive mechanism buys over the cheap one.

Sampled at `PCPlaceExitLadder`'s entry: the river has been carved and
autotiled and `PCPlaceDropIn`'s pool stamp (also block 118) has not run, so
the water counted here is river water only. Same discipline as
`audit_cave_water_visibility.py`, one phase later.

Usage:
    python3 tools/pyboy_smoke/analyse_cave_river_locality.py [--layouts N]

Always exits 0: this is a measurement, not a contract.
"""

from __future__ import annotations

import argparse
import random
import statistics
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
PC_BLOCK_FILL = 25
PC_BLOCK_WATER = 118
RNG_STATE_BYTES = 10


def read_grid(harness: RedRogueHarness) -> list[list[int]]:
    origin = harness.address("wOverworldMap") + PC_BASE
    return [
        [harness.pyboy.memory[origin + y * PC_STRIDE + x] for x in range(PC_SIZE)]
        for y in range(PC_SIZE)
    ]


def sample(map_id: int, seed: int) -> list[list[int]] | None:
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    grabbed: list[list[list[int]]] = []
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)
        harness.register_hook(
            "PCPlaceExitLadder", lambda _ctx: grabbed.append(read_grid(harness))
        )
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
    finally:
        try:
            harness.close()
        except Exception:
            pass
    return grabbed[0] if grabbed else None


def neighbourhood(water: list[tuple[int, int]], radius: int) -> set[tuple[int, int]]:
    out: set[tuple[int, int]] = set()
    for wx, wy in water:
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                x, y = wx + dx, wy + dy
                if 0 <= x < PC_SIZE and 0 <= y < PC_SIZE:
                    out.add((x, y))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=32)
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    rows: list[tuple[int, int, int, int, int]] = []
    errors = 0
    started = time.time()

    for seed in range(args.layouts):
        try:
            grid = sample(map_id, seed)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue
        if grid is None:
            errors += 1
            continue

        water = [
            (x, y)
            for y in range(PC_SIZE)
            for x in range(PC_SIZE)
            if grid[y][x] == PC_BLOCK_WATER
        ]
        if not water:
            rows.append((0, 0, 0, 0, 0))
            continue

        near1 = len(neighbourhood(water, 1))
        near2 = neighbourhood(water, 2)
        xs = [x for x, _ in water]
        ys = [y for _, y in water]
        x0, x1 = max(0, min(xs) - 2), min(PC_SIZE - 1, max(xs) + 2)
        y0, y1 = max(0, min(ys) - 2), min(PC_SIZE - 1, max(ys) + 2)
        box = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
        fill_in_box = sum(1 for x, y in box if grid[y][x] == PC_BLOCK_FILL)
        rows.append((len(water), near1, len(near2), len(box), fill_in_box))

    elapsed = time.time() - started
    print()
    print("=== cave river locality (out of %d cells) ===" % (PC_SIZE * PC_SIZE))
    print("%d layouts, %d harness errors, %.0fs wall" % (args.layouts, errors, elapsed))
    print()
    if not rows:
        print("no samples")
        return 0

    names = ("water", "cheb<=1", "cheb<=2", "bbox+2", "fill-in-bbox+2")
    print("%-16s %8s %8s %8s %8s" % ("metric", "mean", "median", "min", "max"))
    for index, name in enumerate(names):
        values = [row[index] for row in rows]
        print(
            "%-16s %8.1f %8.1f %8d %8d"
            % (name, statistics.mean(values), statistics.median(values), min(values), max(values))
        )

    mean_near2 = statistics.mean([row[2] for row in rows])
    mean_box = statistics.mean([row[3] for row in rows])
    total = PC_SIZE * PC_SIZE
    print()
    print("sweep reduction vs the current full-grid pass")
    print("  position-tracked (cheb<=2): %.1f -> %.1fx less work" % (mean_near2, total / max(mean_near2, 1)))
    print("  bounding box (bbox+2):      %.1f -> %.1fx less work" % (mean_box, total / max(mean_box, 1)))
    worst_box = max(row[3] for row in rows)
    print("  bounding box worst case:    %d cells (%.0f%% of the full grid)"
          % (worst_box, 100.0 * worst_box / total))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
