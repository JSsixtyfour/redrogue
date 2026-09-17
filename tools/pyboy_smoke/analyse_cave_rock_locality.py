"""Size the candidate set for PCAutotilePass's Pass C (cosmetic rock edges).

Phase 6 follow-up. `profile_cave_autotile_passes.py` measured Pass C at 10.91
frames - 29% of `PCAutotilePass` and 20% of the whole cave finalize - to change
7.1 cells, nine times worse per cell than Pass B. It is the same wasted-sweep
shape Phase 6 just fixed for the river, and this script decides which mechanism
fits, exactly as `analyse_cave_river_locality.py` did there.

The reason it cannot simply copy the river's answer: the river is a connected
walk, so its bounding box is tight. Rocks are placed independently at stray
corners scattered across the map, so a box around all of them could easily be
most of the grid. That is a claim, and this measures it instead of assuming it.

Reported per cave, as cell counts out of 400:

  rocks          PCRockTable blocks on the grid when Pass C starts
  cheb<=1        the 3x3 neighbourhood of the rocks (what Pass C can convert)
  bbox+2         bounding box of all rocks grown by 2, clipped - what a
                 river-style box would sweep
  converted      cells Pass C actually changed
  max-dist       furthest converted cell from any rock, Chebyshev

`converted` and `max-dist` together are the locality contract: Pass C has no
cascade (a PC_BLOCK_PENDING_FLOOR result is deliberately discarded rather than
written, see its header), so unlike the river's Pass A'/B' pair nothing it does
can feed a later classification. Its reach should therefore be 1, not 2.

Sampled by hooking `PCAutotilePass.passCStart` (Pass C's row loop, first hit only =
its start) and `PCDecorateLast` (the phase after `PCAutotilePass` returns).

Usage:
    python3 tools/pyboy_smoke/analyse_cave_rock_locality.py [--layouts N]

Always exits 0: this is a measurement, not a contract.
"""

from __future__ import annotations

import argparse
import random
import statistics
import sys
import time
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

PC_SIZE = 20
PC_STRIDE = 26
PC_BASE = 81
RNG_STATE_BYTES = 10

# PCRockTable, custom_functions/procedural_cave_gen.asm. None of these is an
# autotile output (those are 1/20/21/22/24/25/26/28/29/30/36), a decoration
# (60/61/117), floor decor (12-19) or water (118), so counting them on the grid
# identifies rocks unambiguously.
ROCK_IDS = frozenset((2, 77, 78, 79, 81, 82, 83))


def read_grid(harness: RedRogueHarness) -> list[list[int]]:
    origin = harness.address("wOverworldMap") + PC_BASE
    return [
        [harness.pyboy.memory[origin + y * PC_STRIDE + x] for x in range(PC_SIZE)]
        for y in range(PC_SIZE)
    ]


def sample(map_id: int, seed: int):
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    first: dict[str, list[list[int]]] = {}
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)

        def note(label):
            def callback(_context) -> None:
                if label not in first:      # cYLoop fires once per row
                    first[label] = read_grid(harness)

            return callback

        for label in ("PCAutotilePass.passCStart", "PCDecorateLast"):
            harness.register_hook(label, note(label))
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
    finally:
        try:
            harness.close()
        except Exception:
            pass
    return first.get("PCAutotilePass.passCStart"), first.get("PCDecorateLast")


def neighbourhood(cells, radius: int) -> set:
    out = set()
    for cx, cy in cells:
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                x, y = cx + dx, cy + dy
                if 0 <= x < PC_SIZE and 0 <= y < PC_SIZE:
                    out.add((x, y))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=32)
    parser.add_argument(
        "--explain",
        action="store_true",
        help="dump the full neighbourhood of every conversion that lands more "
             "than one cell from a rock - the cases that decide whether Pass C "
             "can be scoped to rocks at all",
    )
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    rows = []
    id_hist: Counter[int] = Counter()
    dist_hist: Counter[int] = Counter()
    errors = 0
    started = time.time()

    for seed in range(args.layouts):
        try:
            before, after = sample(map_id, seed)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue
        if before is None or after is None:
            errors += 1
            print("  seed %d: hooks did not both fire" % seed)
            continue

        rocks = [
            (x, y)
            for y in range(PC_SIZE)
            for x in range(PC_SIZE)
            if before[y][x] in ROCK_IDS
        ]
        for x, y in rocks:
            id_hist[before[y][x]] += 1

        converted = [
            (x, y)
            for y in range(PC_SIZE)
            for x in range(PC_SIZE)
            if before[y][x] != after[y][x]
        ]
        if rocks:
            dists = [
                min(max(abs(x - rx), abs(y - ry)) for rx, ry in rocks)
                for x, y in converted
            ]
        else:
            dists = [99] * len(converted)
        for d in dists:
            dist_hist[d] += 1

        if args.explain:
            for (x, y), d in zip(converted, dists):
                if d <= 1:
                    continue
                print()
                print("  seed %d: (%d,%d) %d -> %d, %d cells from the nearest rock"
                      % (seed, x, y, before[y][x], after[y][x], d))
                print("    3x3 before (X = off grid):")
                for ny in range(y - 1, y + 2):
                    cells = []
                    for nx in range(x - 1, x + 2):
                        if 0 <= nx < PC_SIZE and 0 <= ny < PC_SIZE:
                            cells.append("%3d" % before[ny][nx])
                        else:
                            cells.append("  X")
                    print("      " + " ".join(cells))
                orth = [
                    before[ny][nx]
                    for nx, ny in ((x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y))
                    if 0 <= nx < PC_SIZE and 0 <= ny < PC_SIZE
                ]
                print("    orthogonal neighbours: %s  (1 = real floor, 36 = entrance)" % orth)
                print("    touches real floor: %s" % any(v in (1, 36) for v in orth))

        near1 = len(neighbourhood(rocks, 1)) if rocks else 0
        if rocks:
            xs = [x for x, _ in rocks]
            ys = [y for _, y in rocks]
            x0, x1 = max(0, min(xs) - 2), min(PC_SIZE - 1, max(xs) + 2)
            y0, y1 = max(0, min(ys) - 2), min(PC_SIZE - 1, max(ys) + 2)
            box = (x1 - x0 + 1) * (y1 - y0 + 1)
        else:
            box = 0
        rows.append((len(rocks), near1, box, len(converted), max(dists) if dists else 0))

    elapsed = time.time() - started
    print()
    print("=== cave rock locality (out of %d cells) ===" % (PC_SIZE * PC_SIZE))
    print("%d layouts, %d harness errors, %.0fs wall" % (args.layouts, errors, elapsed))
    print()
    if not rows:
        print("no samples")
        return 0

    names = ("rocks", "cheb<=1", "bbox+2", "converted", "max-dist")
    print("%-12s %8s %8s %8s %8s" % ("metric", "mean", "median", "min", "max"))
    for index, name in enumerate(names):
        values = [row[index] for row in rows]
        print("%-12s %8.1f %8.1f %8d %8d"
              % (name, statistics.mean(values), statistics.median(values),
                 min(values), max(values)))

    print()
    print("rock IDs seen:", dict(sorted(id_hist.items())))
    print("converted-cell distance to nearest rock:", dict(sorted(dist_hist.items())))

    total = PC_SIZE * PC_SIZE
    mean_near1 = statistics.mean([row[1] for row in rows])
    mean_box = statistics.mean([row[2] for row in rows])
    worst_box = max(row[2] for row in rows)
    print()
    print("sweep reduction vs the current full-grid Pass C")
    print("  position list (cheb<=1): %.1f cells -> %.1fx less work"
          % (mean_near1, total / max(mean_near1, 1)))
    print("  bounding box (bbox+2):   %.1f cells -> %.1fx less work"
          % (mean_box, total / max(mean_box, 1)))
    print("  bounding box worst case: %d cells (%.0f%% of the full grid)"
          % (worst_box, 100.0 * worst_box / total))
    print()
    print("a position list needs room for the worst-case rock count: %d"
          % max(row[0] for row in rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
