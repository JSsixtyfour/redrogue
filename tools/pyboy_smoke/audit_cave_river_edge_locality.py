"""Does PCAutotileRiverEdges ever convert a cell that is not near water?

This is the correctness premise behind every cheap version of that pass, and it
is the one thing that must NOT be taken on reasoning. The argument is that
`PCAutotilePass` has already classified the whole grid, so a still-plain-fill
cell with no water in the neighbourhood `PCClassifyCell` examines must
reclassify to exactly what it already is - leave it alone - and visiting it is
provably wasted work. If that is true, restricting the sweep to the cells near
the river is output-identical and the saving is free. If there is even one
conversion far from water, it is not, and the whole optimisation is wrong.

`PCDecorateLast` is the reason this cannot be settled by reading the source: it
runs BETWEEN `PCAutotilePass` and the river and rewrites fill cells, so the grid
the river pass sees is not the one the main pass classified. Whether any of that
can change a distant cell's classification is exactly the question.

METHOD. Snapshot the whole 20x20 block grid at `PCAutotileRiverEdges` entry and
again at `PCPlaceExitLadder` entry (the very next phase, so nothing else runs in
between), and diff them. Every differing cell is a conversion this pass made.
Report each one's Chebyshev distance to the nearest water block. Distance 0-2 is
expected and fine; anything at 3 or more falsifies the premise, and the script
prints the offending cells rather than just a count so the case can be looked at
directly.

Water is read from the entry snapshot, which is after `PCCarveRiver` and before
`PCPlaceDropIn`'s pool stamp, so it is river water only.

Usage:
    python3 tools/pyboy_smoke/audit_cave_river_edge_locality.py [--layouts N]

Exits 1 if any conversion lands at distance >= 3, because unlike its sibling
measurement scripts this one IS a contract: it is the premise the Phase 6
optimisation rests on.
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

PC_SIZE = 20
PC_STRIDE = 26
PC_BASE = 81
PC_BLOCK_WATER = 118
RNG_STATE_BYTES = 10

# Pass A' can mint a floor cell one out from water, and Pass B' then classifies
# that new cell's own neighbours, one further out again. So 2 is the largest
# distance the mechanism can legitimately reach.
MAX_LEGAL_DISTANCE = 2


def read_grid(harness: RedRogueHarness) -> list[list[int]]:
    origin = harness.address("wOverworldMap") + PC_BASE
    return [
        [harness.pyboy.memory[origin + y * PC_STRIDE + x] for x in range(PC_SIZE)]
        for y in range(PC_SIZE)
    ]


def sample(map_id: int, seed: int):
    """Returns (grid at river-pass entry, grid at river-pass exit)."""
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    before: list[list[list[int]]] = []
    after: list[list[list[int]]] = []
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)
        harness.register_hook(
            "PCAutotileRiverEdges", lambda _ctx: before.append(read_grid(harness))
        )
        harness.register_hook(
            "PCPlaceExitLadder", lambda _ctx: after.append(read_grid(harness))
        )
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
    finally:
        try:
            harness.close()
        except Exception:
            pass
    # Since 2026-09-16 the river is rolled at 50%, so PCAutotileRiverEdges
    # genuinely does not run in about half of caves and its entry hook never
    # fires. That is a clean skip, NOT a harness failure - the caller tells the
    # two apart by whether the PCPlaceExitLadder snapshot arrived, since that
    # phase runs unconditionally. Reporting no-river caves as errors would both
    # look like a broken harness and halve the sample without saying so.
    return (before[0] if before else None), (after[0] if after else None)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=64)
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    distances: Counter[int] = Counter()
    violations: list[str] = []
    conversions = 0
    errors = 0
    caves = 0
    no_river = 0
    started = time.time()

    for seed in range(args.layouts):
        try:
            before, after = sample(map_id, seed)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue
        if after is None:
            errors += 1
            print("  seed %d: PCPlaceExitLadder never ran - harness failure" % seed)
            continue
        if before is None:
            no_river += 1          # river rolled off this cave; nothing to audit
            continue
        caves += 1

        water = [
            (x, y)
            for y in range(PC_SIZE)
            for x in range(PC_SIZE)
            if before[y][x] == PC_BLOCK_WATER
        ]
        for y in range(PC_SIZE):
            for x in range(PC_SIZE):
                if before[y][x] == after[y][x]:
                    continue
                conversions += 1
                if not water:
                    distance = 99
                else:
                    distance = min(
                        max(abs(x - wx), abs(y - wy)) for wx, wy in water
                    )
                distances[distance] += 1
                if distance > MAX_LEGAL_DISTANCE:
                    violations.append(
                        "  seed %d: (%d,%d) %d -> %d at distance %d from water"
                        % (seed, x, y, before[y][x], after[y][x], distance)
                    )

    elapsed = time.time() - started
    print()
    print("=== PCAutotileRiverEdges conversion locality ===")
    print("%d caves with a river audited, %d rolled no river, %d harness errors, %.0fs wall"
          % (caves, no_river, errors, elapsed))
    print("%d cells converted in total (%.1f per cave)"
          % (conversions, conversions / max(caves, 1)))
    print()
    print("Chebyshev distance from the converted cell to the nearest water block:")
    for distance in sorted(distances):
        print("  %2d: %5d (%5.1f%%)"
              % (distance, distances[distance], 100.0 * distances[distance] / max(conversions, 1)))
    print()
    # Same guard as audit_cave_passc_locality.py, added for the same reason: a
    # contract that passes on zero samples reports success for a broken harness
    # or a renamed hook. Checked before the verdict, never hidden in a
    # max(1, denominator).
    if caves == 0 or conversions == 0:
        print("PREMISE INCONCLUSIVE: %d caves and %d conversions sampled."
              % (caves, conversions))
        print("Nothing was measured, so nothing is proven. Check that the hook")
        print("labels still exist in the .sym and that the ROM is freshly built.")
        return 1

    if violations:
        print("PREMISE FALSIFIED: %d conversion(s) beyond distance %d"
              % (len(violations), MAX_LEGAL_DISTANCE))
        for line in violations[:40]:
            print(line)
        if len(violations) > 40:
            print("  ... and %d more" % (len(violations) - 40))
        return 1
    print("PREMISE HOLDS: every conversion is within distance %d of water."
          % MAX_LEGAL_DISTANCE)
    print("Restricting the sweep to that neighbourhood is output-identical.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
