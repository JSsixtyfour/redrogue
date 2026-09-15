#!/usr/bin/env python3
"""Attribute Procedural Facility generation cost to individual pipeline phases.

`measure_facility_generation.py` answers "how long does generation take and how
many layout attempts did it need". This answers the next question: WHERE inside
one attempt the time goes, and which phases a REJECTED attempt pays for before
the rejection is discovered.

Method: hook every phase entry label and read PyBoy's cycle counter there. A
phase's cost is the delta to the next hook, so this is exact per-call cycle
accounting, not the frame-granular upper bound `measure_facility_generation.py`
is limited to. Hooks fire on a PC match and consume no emulated cycles.

`PFacCarveCorridors` is called twice per attempt; both firings are traced
separately so the second (socket reopen) pass can be costed on its own.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/profile_facility_phases.py [--seeds N]
"""

from __future__ import annotations

import argparse
import io
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

CYCLES_PER_FRAME = 70224
CALL_LIMIT = 4000  # frames

# In pipeline order. The retry loop spans PFacFillUntouched through
# PFacValidateGeneratedCorners; everything after runs exactly once.
LOOP_PHASES = (
    "PFacFillUntouched",
    "PFacInitRoomRecords",
    "PFacPlaceEntryRoom",
    "PFacPlaceExitRoom",
    "PFacPlaceMiddleRooms",
    "PFacAssignExitParent",
    "PFacStampRoomFloors",
    "PFacCarveCorridors",
    "PFacSelectPremadeMiddleRooms",
    "PFacEncloseRooms",
    "PFacValidateGeneratedCorners",
)
TAIL_PHASES = (
    "PFacCarveEdgeOpenings",
    "PFacBuildCorridorWalls",
    "PFacApplyDoorJambs",
    "PFacFinalizeBlocks",
    "PFacRemoveIsolatedGeneratedCorners",
    "PFacNormalizeReversedCorners",
    "PFacPlaceLargeDecor",
    "PFacPlaceItems",
    "PFacDecorateExploreRooms",
    "PFacPlaceFakeBalls",
)

SEEDS = (
    (0x01, 0x23, 0x45, 0x67),
    (0x89, 0xAB, 0xCD, 0xEF),
    (0x13, 0x37, 0xC0, 0xDE),
    (0xDE, 0xAD, 0xBE, 0xEF),
    (0x55, 0xAA, 0x5A, 0xA5),
    (0xFE, 0xED, 0xFA, 0xCE),
    (0x10, 0x20, 0x30, 0x40),
    (0x36, 0x22, 0x22, 0xCA),
    (0x22, 0xBE, 0x26, 0x9E),
    (0x7F, 0x01, 0x80, 0xC3),
    (0x00, 0xFF, 0x0F, 0xF0),
    (0xA5, 0x5A, 0xC3, 0x3C),
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=len(SEEDS))
    args = parser.parse_args()

    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    harness.boot_to_lobby()
    harness.call_routine("PFacPreload", limit=60000)
    baseline = io.BytesIO()
    harness.save_state(baseline)

    trace: list[tuple[str, int]] = []

    def make_hook(label: str):
        def hook(_context) -> None:
            trace.append((label, harness.cycle_count()))
        return hook

    for label in LOOP_PHASES + TAIL_PHASES:
        harness.register_hook(label, make_hook(label))

    # Cost of a phase = cycles until the NEXT traced label. The final tail phase
    # has no successor, so it is charged the remainder of the measured window.
    totals: dict[str, int] = defaultdict(int)
    calls: dict[str, int] = defaultdict(int)
    rejected_cost = 0
    accepted_cost = 0
    attempts_total = 0

    for index, seed in enumerate(SEEDS[: args.seeds]):
        harness.load_state(baseline)
        harness.write_sram_bytes("sProcFacilityExitEdge", [index % 3])
        harness.write8("hRandomAdd", seed[0])
        harness.write8("hRandomSub", seed[1])
        harness.write8("hRandomLast", seed[2])
        harness.write8("hRandomLast", seed[3], offset=1)
        trace.clear()
        start = harness.cycle_count()
        harness.call_routine("PFacFinalize", limit=CALL_LIMIT)
        end = harness.cycle_count()

        # PFacFillUntouched also runs once at the top of PFacFinalize, outside
        # the retry loop, so the first firing is not a layout attempt.
        fills = sum(1 for label, _ in trace if label == "PFacFillUntouched")
        attempts = max(fills - 1, 0)
        attempts_total += attempts

        for position, (label, cycles) in enumerate(trace):
            following = trace[position + 1][1] if position + 1 < len(trace) else end
            totals[label] += following - cycles
            calls[label] += 1

        # Split the window at the last PFacValidateGeneratedCorners: everything
        # before it that was not the winning attempt is pure retry waste.
        last_validate = max(
            (position for position, (label, _) in enumerate(trace)
             if label == "PFacValidateGeneratedCorners"),
            default=None,
        )
        if last_validate is not None:
            accepted_start = None
            for position in range(last_validate, -1, -1):
                if trace[position][0] == "PFacFillUntouched":
                    accepted_start = trace[position][1]
                    break
            if accepted_start is not None:
                rejected_cost += accepted_start - start
                accepted_cost += end - accepted_start

    window = sum(totals.values())
    print(f"seeds {args.seeds}   layout attempts {attempts_total}\n")
    print("phase                               calls    total f@2x   per-call f@2x   share")
    for label in LOOP_PHASES + TAIL_PHASES:
        total = totals[label]
        count = calls[label]
        if count == 0:
            continue
        print(
            f"{label:34s} {count:6d} {total / (CYCLES_PER_FRAME * 2):11.1f}"
            f" {total / count / (CYCLES_PER_FRAME * 2):15.2f}"
            f" {total / window:7.1%}"
        )
    print()
    span = rejected_cost + accepted_cost
    print(f"discarded retry work   {rejected_cost / (CYCLES_PER_FRAME * 2):8.1f} f@2x"
          f"  {rejected_cost / span:6.1%}")
    print(f"winning attempt + tail {accepted_cost / (CYCLES_PER_FRAME * 2):8.1f} f@2x"
          f"  {accepted_cost / span:6.1%}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
