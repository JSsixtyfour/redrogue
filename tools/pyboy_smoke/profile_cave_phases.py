"""Profile Procedural Cave generation, phase by phase, in CPU cycles.

Phase 6 measurement. The only per-routine breakdown on record for the cave is
the 2026-06-26 one in `Red Rogue Files/procedural-cave-performance-plan.md`,
and that file says of itself that the table is stale: `PCAutotileRiverEdges`
and the drop-in overlap checks were added AFTER it was taken, and Phase 5a then
rewrote the river so it actually carves (0.00 -> 10.03 blocks per cave, which
is the input `PCAutotileRiverEdges` reacts to). So the one number Phase 6 is
supposed to act on - what the second 400-cell sweep actually costs - has never
been measured on a build where the river does anything.

HOW THE ATTRIBUTION WORKS. `PCFinalizeCave` calls its phases back to back:

    PCAutotilePass -> PCDecorateLast -> PCCarveRiver -> PCAutotileRiverEdges
    -> PCPlaceExitLadder -> ... -> PCPlaceWildAreaItems -> PCPlaceBoss
    -> PCSprinkleFloorDecor -> PCPlaceDropIn

so an execution hook on each entry point turns the gap between two consecutive
hits into the cost of the phase that owns the earlier hit, plus the handful of
`ld`s between the two `call`s. No exit hooks needed, and no frame quantisation:
`cycle_count()` is read inside the hook itself, so unlike
`measure_facility_generation.py` (which brackets a whole `call_routine` and is
therefore accurate only to one 70224-cycle frame) this resolves differences far
smaller than a frame. That matters here - the whole river pass may well BE a
sub-frame cost, and the point of the exercise is to find out before spending
SRAM on it.

The last phase, `PCPlaceDropIn`, has no successor hook, so it is not attributed
and its cost lands in neither column; everything this plan is about happens
earlier.

Hooks fire during preload too (`PCPreloadCave` runs `PCCarveOne` and friends
against the SRAM staging buffer), so the stream is cut at the `PCFinalizeCave`
hit and only hits after it are attributed.

One fresh harness per layout, and the RNG table scrambled per layout, for the
reason `audit_cave_water_visibility.py` documents: `boot_to_lobby` is not
reentrant and is otherwise deterministic, so N boots would otherwise profile
the same cave N times.

Usage:
    python3 tools/pyboy_smoke/profile_cave_phases.py [--layouts N] [--label TEXT]

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
PC_BLOCK_WATER = 118

# In call order. The final entry closes the window for the one before it.
PHASES = (
    "PCFinalizeCave",
    "PCAutotilePass",
    "PCDecorateLast",
    "PCCarveRiver",
    "PCAutotileRiverEdges",
    "PCPlaceExitLadder",
    "PCPlaceWildAreaItems",
    "PCPlaceBoss",
    "PCSprinkleFloorDecor",
    "PCPlaceDropIn",
)


def water_count(harness: RedRogueHarness) -> int:
    origin = harness.address("wOverworldMap") + PC_BASE
    return sum(
        1
        for y in range(PC_SIZE)
        for x in range(PC_SIZE)
        if harness.pyboy.memory[origin + y * PC_STRIDE + x] == PC_BLOCK_WATER
    )


def profile_one(map_id: int, seed: int) -> tuple[dict[str, int], int]:
    """Returns ({phase: cycles}, river blocks carved this layout)."""
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    stream: list[tuple[str, int]] = []
    river = {"blocks": 0}
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)

        def note(label):
            def callback(_context) -> None:
                stream.append((label, harness.cycle_count()))

            return callback

        for label in PHASES:
            harness.register_hook(label, note(label))

        # Sampled at PCPlaceExitLadder's entry: the river has been carved and
        # autotiled, and PCPlaceDropIn's pool stamp (also block 118) has not
        # run yet, so this counts river water only. Same discipline as
        # audit_cave_water_visibility.py, one phase later.
        harness.register_hook(
            "PCPlaceExitLadder",
            lambda _ctx: river.__setitem__("blocks", water_count(harness)),
        )

        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
    finally:
        try:
            harness.close()
        except Exception:
            pass

    # Cut everything before finalize: preload drives the same helpers.
    for index, (label, _) in enumerate(stream):
        if label == "PCFinalizeCave":
            stream = stream[index:]
            break
    else:
        return {}, river["blocks"]

    costs: dict[str, int] = {}
    for (label, start), (_, end) in zip(stream, stream[1:]):
        # First hit of each phase only. A phase that somehow fires twice inside
        # one finalize would otherwise be summed silently.
        if label not in costs:
            costs[label] = end - start
    return costs, river["blocks"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=16)
    parser.add_argument("--label", default="baseline")
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    samples: dict[str, list[int]] = {phase: [] for phase in PHASES[:-1]}
    rivers: list[int] = []
    totals: list[int] = []
    errors = 0
    started = time.time()

    for seed in range(args.layouts):
        try:
            costs, river = profile_one(map_id, seed)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue
        if not costs:
            errors += 1
            print("  seed %d: no PCFinalizeCave hit" % seed)
            continue
        for phase, cost in costs.items():
            samples.setdefault(phase, []).append(cost)
        rivers.append(river)
        totals.append(sum(costs.values()))

    elapsed = time.time() - started
    print()
    print("=== cave generation phase profile: %s ===" % args.label)
    print("%d layouts, %d harness errors, %.0fs wall" % (args.layouts, errors, elapsed))
    print()
    if not totals:
        print("no samples")
        return 0

    mean_total = statistics.mean(totals)
    print("phase                    mean cyc   mean frames   %% of profiled   max frames")
    for phase in PHASES[:-1]:
        values = samples.get(phase) or []
        if not values:
            continue
        mean = statistics.mean(values)
        print(
            "%-22s %10.0f %13.2f %15.1f %12.2f"
            % (
                phase,
                mean,
                mean / CYCLES_PER_FRAME,
                100.0 * mean / mean_total,
                max(values) / CYCLES_PER_FRAME,
            )
        )
    print()
    print("profiled span (PCFinalizeCave entry -> PCPlaceDropIn entry)")
    print("  mean %.2f frames, min %.2f, max %.2f"
          % (mean_total / CYCLES_PER_FRAME,
             min(totals) / CYCLES_PER_FRAME,
             max(totals) / CYCLES_PER_FRAME))
    print("  NOTE: generation runs at double speed, so a player waits half this.")
    print()
    print("river blocks carved (sampled at PCPlaceExitLadder, pool stamp excluded)")
    print("  mean %.2f, min %d, max %d, caves with water %d/%d"
          % (statistics.mean(rivers), min(rivers), max(rivers),
             sum(1 for r in rivers if r), len(rivers)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
