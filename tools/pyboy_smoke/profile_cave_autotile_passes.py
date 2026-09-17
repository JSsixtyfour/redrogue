"""Break PCAutotilePass down into its four sweeps.

Phase 6 follow-up measurement, taken as a REPORT, not as a prelude to editing
anything. Once PCAutotileRiverEdges was scoped to the river's bounding box,
`profile_cave_phases.py` put PCAutotilePass at 37.57 frames - 70% of cave
finalize and now the only phase that matters. Anyone who picks that up next
needs to know which of its four sweeps the time is actually in, and nobody has
ever measured that; the 2026-06-26 performance plan only ever treated the
routine as one lump.

The four sweeps, in order, each a full 400-cell walk:

  Pass A    peninsula resolution (fill with 3+ floor-like neighbours -> floor)
  cleanup   turn Pass A's PC_BLOCK_PENDING_FLOOR sentinels into real floor
  Pass B    edge/corner classification, plus PCRecheckNeighbors/PCVerifyCorner
  Pass C    cosmetic edges around rocks (wProcCaveIncludeRocks set)

Each sweep's Y-loop label is hooked, and because those labels are re-entered
once per row, only the FIRST hit inside a given finalize is kept - that is the
sweep's start. A sweep's cost is then the gap to the next sweep's start, and
Pass C's is the gap to PCDecorateLast, the phase that follows the whole
routine.

Usage:
    python3 tools/pyboy_smoke/profile_cave_autotile_passes.py [--layouts N]

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

CYCLES_PER_FRAME = 70224
RNG_STATE_BYTES = 10

PC_SIZE = 20
PC_STRIDE = 26
PC_BASE = 81

# (hook label, human name). In execution order; the last one is the terminator
# that closes Pass C rather than a sweep of its own.
MARKS = (
    ("PCAutotilePass.aYLoop", "Pass A  (peninsula)"),
    ("PCAutotilePass.cleanYLoop", "cleanup (sentinels)"),
    ("PCAutotilePass.yLoop", "Pass B  (edges/corners)"),
    ("PCAutotilePass.passCStart", "Pass C  (rock edges)"),
    ("PCDecorateLast", "-- end of PCAutotilePass --"),
)


def grid_bytes(harness: RedRogueHarness) -> bytes:
    origin = harness.address("wOverworldMap") + PC_BASE
    return bytes(
        harness.pyboy.memory[origin + y * PC_STRIDE + x]
        for y in range(PC_SIZE)
        for x in range(PC_SIZE)
    )


def profile_one(map_id: int, seed: int) -> tuple[dict[str, int], dict[str, int]]:
    """Returns ({sweep: cycles}, {sweep: cells it changed})."""
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    first: dict[str, int] = {}
    snaps: dict[str, bytes] = {}
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)

        def note(label):
            def callback(_context) -> None:
                # Row labels fire 20x per sweep; only the first is the start.
                # PCPreloadCave does not run PCAutotilePass, so there is no
                # earlier finalize-unrelated hit to filter out here.
                if label not in first:
                    first[label] = harness.cycle_count()
                    snaps[label] = grid_bytes(harness)

            return callback

        for label, _ in MARKS:
            harness.register_hook(label, note(label))
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
    finally:
        try:
            harness.close()
        except Exception:
            pass

    costs: dict[str, int] = {}
    changed: dict[str, int] = {}
    for (label, name), (next_label, _) in zip(MARKS, MARKS[1:]):
        if label in first and next_label in first:
            costs[name] = first[next_label] - first[label]
            before, after = snaps[label], snaps[next_label]
            changed[name] = sum(1 for x, y in zip(before, after) if x != y)
    return costs, changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=32)
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    samples: dict[str, list[int]] = {}
    edits: dict[str, list[int]] = {}
    totals: list[int] = []
    errors = 0
    started = time.time()

    for seed in range(args.layouts):
        try:
            costs, changed = profile_one(map_id, seed)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue
        if not costs:
            errors += 1
            continue
        for name, cost in costs.items():
            samples.setdefault(name, []).append(cost)
        for name, count in changed.items():
            edits.setdefault(name, []).append(count)
        totals.append(sum(costs.values()))

    elapsed = time.time() - started
    print()
    print("=== PCAutotilePass sweep breakdown ===")
    print("%d layouts, %d harness errors, %.0fs wall" % (args.layouts, errors, elapsed))
    print()
    if not totals:
        print("no samples")
        return 0

    mean_total = statistics.mean(totals)
    print("sweep                   mean frames   %% of routine   cells changed   frames/cell")
    for _, name in MARKS[:-1]:
        values = samples.get(name) or []
        if not values:
            continue
        mean = statistics.mean(values)
        cells = statistics.mean(edits.get(name) or [0])
        print(
            "%-22s %13.2f %14.1f %15.1f %13.3f"
            % (name, mean / CYCLES_PER_FRAME, 100.0 * mean / mean_total, cells,
               (mean / CYCLES_PER_FRAME) / max(cells, 1e-9))
        )
    print()
    print("PCAutotilePass total: mean %.2f frames (min %.2f, max %.2f)"
          % (mean_total / CYCLES_PER_FRAME,
             min(totals) / CYCLES_PER_FRAME,
             max(totals) / CYCLES_PER_FRAME))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
