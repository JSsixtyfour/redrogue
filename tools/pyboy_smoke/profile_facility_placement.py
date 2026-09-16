#!/usr/bin/env python3
"""Break PFacPlaceMiddleRooms, the largest remaining phase, into its internals.

After R6 removed most layout retries, PFacPlaceMiddleRooms is ~41% of all
Facility generation cost. This attributes that 41% to the routines inside one
candidate roll, so a proposal to change the RNG can be costed against a
measurement instead of an instruction count.

Method is the same as profile_facility_phases.py: hook each routine's entry
label and read PyBoy's cycle counter, charging each hook the delta to the next
one. Nested calls mean a routine is charged only until its first hooked callee,
so read these as "cost attributable at this point in the sequence", not as
exclusive self time. Rangerandom and Random are deliberately NOT hooked - they
are called from the whole ROM and hooking them stalls the harness - so RNG cost
shows up inside the routines that draw.

PFacRollRoomDim is called twice in a row per roll, so the delta between the two
firings is one clean, complete measurement of it.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/profile_facility_placement.py [--seeds N]
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

TRACKED = (
    "PFacRollCandidate",
    "PFacPickParent",
    "PFacRollRoomDim",
    "PFacRoomCenter",
    "PFacCandInBounds",
    "PFacCandOverlaps",
    "PFacStoreRoom",
    "PFacForceItemRoom",
)

SEEDS = (
    (0x01, 0x23, 0x45, 0x67), (0x89, 0xAB, 0xCD, 0xEF),
    (0x13, 0x37, 0xC0, 0xDE), (0xDE, 0xAD, 0xBE, 0xEF),
    (0x55, 0xAA, 0x5A, 0xA5), (0xFE, 0xED, 0xFA, 0xCE),
    (0x10, 0x20, 0x30, 0x40), (0x36, 0x22, 0x22, 0xCA),
    (0x22, 0xBE, 0x26, 0x9E), (0x7F, 0x01, 0x80, 0xC3),
    (0x00, 0xFF, 0x0F, 0xF0), (0xA5, 0x5A, 0xC3, 0x3C),
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

    inside = {"flag": False}
    trace: list[tuple[str, int]] = []
    windows: list[tuple[int, int]] = []

    def enter(_context) -> None:
        inside["flag"] = True
        trace.append(("<phase>", harness.cycle_count()))

    def leave(_context) -> None:
        if inside["flag"]:
            inside["flag"] = False
            trace.append(("<end>", harness.cycle_count()))

    harness.register_hook("PFacPlaceMiddleRooms", enter)
    harness.register_hook("PFacAssignExitParent", leave)

    def make_hook(label: str):
        def hook(_context) -> None:
            if inside["flag"]:
                trace.append((label, harness.cycle_count()))
        return hook

    for label in TRACKED:
        harness.register_hook(label, make_hook(label))

    for index, seed in enumerate(SEEDS[: args.seeds]):
        harness.load_state(baseline)
        harness.write_sram_bytes("sProcFacilityExitEdge", [index % 3])
        harness.seed_rng(seed)
        harness.call_routine("PFacFinalize", limit=4000)

    totals: dict[str, int] = defaultdict(int)
    calls: dict[str, int] = defaultdict(int)
    for position in range(len(trace) - 1):
        label, cycles = trace[position]
        following = trace[position + 1][1]
        if label in ("<end>",):
            continue
        totals[label] += following - cycles
        calls[label] += 1

    phase = sum(totals.values())
    rolls = calls["PFacRollCandidate"]
    print(f"placement windows {calls['<phase>']}   candidate rolls {rolls}")
    print(f"phase total {phase / (CYCLES_PER_FRAME * 2):.1f} f@2x"
          f"   per roll {phase / max(rolls, 1):.0f} cycles\n")
    print("routine                    calls   total f@2x   per call cyc    share")
    for label in ("<phase>",) + TRACKED:
        if not calls[label]:
            continue
        print(
            f"{label:24s} {calls[label]:7d} {totals[label] / (CYCLES_PER_FRAME * 2):11.1f}"
            f" {totals[label] / calls[label]:14.0f} {totals[label] / phase:8.1%}"
        )
    dim = totals["PFacRollRoomDim"]
    print(f"\nPFacRollRoomDim is {dim / phase:.1%} of placement.")
    print("It spends two Rangerandom(c=7) draws to produce min(r1,r2)+1;"
          " a single-draw form")
    print(f"would remove roughly half of that, i.e. ~{dim / 2 / phase:.1%}"
          " of placement.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
