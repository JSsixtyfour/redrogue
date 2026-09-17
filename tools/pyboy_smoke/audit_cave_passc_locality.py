"""Is every Pass C conversion next to a rock or a Pass B escalation?

This is the contract behind scoping `PCAutotilePass`'s Pass C to a tracked
position list, and it is deliberately written BEFORE that scoping exists, so it
can falsify the design instead of rubber-stamping it afterwards.

THE CLAIM. Pass C re-sweeps the whole 400-cell grid with `wProcCaveIncludeRocks`
set. Measured over 64 caves, 463 of its 470 conversions sit one cell from a
`PCRockTable` boulder - that is its advertised job. The other 7 do not: they are
straight edges (24/26/29) upgraded to real corners (28/30) because floor
appeared beside them AFTER Pass B had already classified them. Pass C is
quietly doing a second, undocumented job - repairing Pass B's own
order-dependent output.

That second job has exactly one source: `PCRecheckNeighbors`, which Pass B calls
at each cell it escalates to floor mid-sweep (measured: mean 1.1, max 4 per
cave). So the claim is:

    every Pass C conversion is within Chebyshev 1 of a rock OR of an
    escalated cell

If that holds, sweeping the 3x3 around each tracked position is output-identical
and Pass C can drop from 400 cells to ~45. If even one conversion falls outside
both neighbourhoods, it does not hold and the scoping would silently lose a
tile - which is the failure this exists to catch.

Chebyshev 1 and not 2, unlike the river's pass: Pass C cannot cascade. It writes
only edge and corner IDs, and `PCIsFloorLike` does not count those as
floor-like, so no conversion it makes can change another cell's classification.
That also makes it order-independent and idempotent, which is what lets a
neighbourhood walk visit a cell twice without changing the result.

Sampled by hooking `PCRecheckNeighbors` (escalation sites, read from
wProcCaveCurX/Y), `PCAutotilePass.passCStart` (a label placed there for exactly this) and
`PCDecorateLast` (the phase after `PCAutotilePass` returns).

Usage:
    python3 tools/pyboy_smoke/audit_cave_passc_locality.py [--layouts N]

Exits 1 if any conversion falls outside both neighbourhoods. This is a
contract, not a measurement.
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

# wBuffer offsets, custom_functions/procedural_cave_gen.asm
WPROC_CUR_X = 8
WPROC_CUR_Y = 9

ROCK_IDS = frozenset((2, 77, 78, 79, 81, 82, 83))


def read_grid(harness: RedRogueHarness) -> list[list[int]]:
    origin = harness.address("wOverworldMap") + PC_BASE
    return [
        [harness.pyboy.memory[origin + y * PC_STRIDE + x] for x in range(PC_SIZE)]
        for y in range(PC_SIZE)
    ]


def sample(map_id: int, seed: int):
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    escalations: list[tuple[int, int]] = []
    snaps: dict[str, list[list[int]]] = {}
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)
        buffer = harness.address("wBuffer")

        def on_escalate(_context) -> None:
            escalations.append(
                (
                    harness.pyboy.memory[buffer + WPROC_CUR_X],
                    harness.pyboy.memory[buffer + WPROC_CUR_Y],
                )
            )

        def snap(label):
            def callback(_context) -> None:
                if label not in snaps:   # cYLoop fires once per row
                    snaps[label] = read_grid(harness)

            return callback

        harness.register_hook("PCRecheckNeighbors", on_escalate)
        harness.register_hook("PCAutotilePass.passCStart", snap("start"))
        harness.register_hook("PCDecorateLast", snap("end"))
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
    finally:
        try:
            harness.close()
        except Exception:
            pass
    return snaps.get("start"), snaps.get("end"), escalations


def near(cell, anchors) -> bool:
    x, y = cell
    return any(max(abs(x - ax), abs(y - ay)) <= 1 for ax, ay in anchors)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=64)
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    by_rock = 0
    by_escalation = 0
    orphans: list[str] = []
    conversions = 0
    caves = 0
    errors = 0
    entries: list[int] = []
    started = time.time()

    for seed in range(args.layouts):
        try:
            start, end, escalations = sample(map_id, seed)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue
        if start is None or end is None:
            errors += 1
            print("  seed %d: hooks did not both fire" % seed)
            continue
        caves += 1

        rocks = [
            (x, y)
            for y in range(PC_SIZE)
            for x in range(PC_SIZE)
            if start[y][x] in ROCK_IDS
        ]
        entries.append(len(rocks) + len(escalations))

        for y in range(PC_SIZE):
            for x in range(PC_SIZE):
                if start[y][x] == end[y][x]:
                    continue
                conversions += 1
                if near((x, y), rocks):
                    by_rock += 1
                elif near((x, y), escalations):
                    by_escalation += 1
                else:
                    orphans.append(
                        "  seed %d: (%d,%d) %d -> %d, %d rocks, %d escalations"
                        % (seed, x, y, start[y][x], end[y][x],
                           len(rocks), len(escalations))
                    )

    elapsed = time.time() - started
    print()
    print("=== Pass C conversion locality ===")
    print("%d caves, %d harness errors, %.0fs wall" % (caves, errors, elapsed))
    print("%d conversions total" % conversions)
    print("  next to a rock:           %d (%.1f%%)"
          % (by_rock, 100.0 * by_rock / max(conversions, 1)))
    print("  next to an escalation:    %d (%.1f%%)"
          % (by_escalation, 100.0 * by_escalation / max(conversions, 1)))
    print("  next to NEITHER:          %d" % len(orphans))
    print()
    if entries:
        print("tracked entries per cave (rocks + escalations):")
        print("  mean %.1f  max %d  histogram %s"
              % (statistics.mean(entries), max(entries),
                 dict(sorted(Counter(entries).items()))))
        print()
    # A contract that passes when it measured nothing is worse than no contract:
    # it reports success for a broken harness, a renamed hook, or a stale .sym.
    # This exact failure happened during Phase 6's follow-up - every seed threw
    # KeyError on a renamed label and the script still printed CONTRACT HOLDS.
    # Sample size is checked BEFORE the verdict, never folded into a
    # max(1, denominator).
    if caves == 0 or conversions == 0:
        print("CONTRACT INCONCLUSIVE: %d caves and %d conversions sampled."
              % (caves, conversions))
        print("Nothing was measured, so nothing is proven. Check that the hook")
        print("labels still exist in the .sym and that the ROM is freshly built.")
        return 1

    if orphans:
        print("CONTRACT FAILED: %d conversion(s) outside both neighbourhoods."
              % len(orphans))
        print("Scoping Pass C to a tracked position list WOULD LOSE THESE.")
        for line in orphans[:40]:
            print(line)
        if len(orphans) > 40:
            print("  ... and %d more" % (len(orphans) - 40))
        return 1
    print("CONTRACT HOLDS: every Pass C conversion is within Chebyshev 1 of a")
    print("rock or an escalated cell. Sweeping the 3x3 around each tracked")
    print("position is output-identical.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
