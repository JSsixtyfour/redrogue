#!/usr/bin/env python3
"""Measure Procedural Facility generation cost in CPU cycles.

Answers the reported generation-lag question: how long does one full
`PFacFinalize` first-visit generation actually take, and what drives the spread?

MEASUREMENT GRANULARITY. `harness.wait_until` ticks WHOLE FRAMES and tests its
predicate once per frame, so a routine's completion is only ever observed at a
frame boundary. Every cycle figure below is therefore an upper bound that
overshoots the truth by less than one frame (70224 cycles). That is fine at this
scale - generation costs tens of frames - but it means these numbers must not be
used to compare two changes that differ by less than a frame. For that, hook a
label inside the routine instead.

Frames here are emulated CPU time, not rendered frames: `PFacFinalize` runs
inside `LoadMapData` with the LCD off. `ProcGenerationBeginDoubleSpeed` wraps
the real dispatch (not this harness call), so divide the 1x frame count by two
for what a player actually waits through.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/measure_facility_generation.py [--seeds N]
"""

from __future__ import annotations

import argparse
import io
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

CYCLES_PER_FRAME = 70224
CALL_LIMIT = 4000  # frames, not cycles - wait_until counts frames. The smoke
                   # suite's 120000 is a very loose ceiling; this one is tight
                   # enough to fail fast if generation ever runs away.

# The same deterministic states the corpus test uses, so a measurement can be
# lined up against a specific layout when one of them is the slow case.
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

    # PFacFillUntouched runs once at the top of PFacFinalize and then once per
    # layout attempt inside PFacGenerateFacility's retry loop, so counting it
    # separates "generation is expensive" from "generation is RETRYING", which
    # are very different problems with very different fixes.
    fills = {"count": 0}

    def count_fill(_context) -> None:
        fills["count"] += 1

    harness.register_hook("PFacFillUntouched", count_fill)

    samples: list[tuple[tuple[int, ...], int, int]] = []
    for index, seed in enumerate(SEEDS[: args.seeds]):
        harness.load_state(baseline)
        harness.write_sram_bytes("sProcFacilityExitEdge", [index % 3])
        harness.seed_rng(seed)
        fills["count"] = 0
        before = harness.cycle_count()
        harness.call_routine("PFacFinalize", limit=CALL_LIMIT)
        cost = harness.cycle_count() - before
        samples.append((seed, cost, max(fills["count"] - 1, 0)))

    costs = [cost for _, cost, _ in samples]
    attempts = [tries for _, _, tries in samples]
    print("seed              frames@1x  frames@2x  layout attempts")
    for seed, cost, tries in samples:
        label = " ".join(f"{byte:02X}" for byte in seed)
        print(
            f"{label}   {cost / CYCLES_PER_FRAME:9.0f}"
            f"  {cost / (CYCLES_PER_FRAME * 2):9.1f}  {tries:15d}"
        )
    print()
    print(f"samples        {len(costs)}")
    print(f"frames@2x min  {min(costs) / (CYCLES_PER_FRAME * 2):.1f}")
    print(f"frames@2x med  {statistics.median(costs) / (CYCLES_PER_FRAME * 2):.1f}")
    print(f"frames@2x max  {max(costs) / (CYCLES_PER_FRAME * 2):.1f}"
          f"  ({max(costs) / (CYCLES_PER_FRAME * 2) / 60:.1f}s of wall time)")
    print(f"attempts       min {min(attempts)}  med "
          f"{int(statistics.median(attempts))}  max {max(attempts)}")
    if max(attempts) > 1:
        per_attempt = [
            cost / max(tries, 1) for _, cost, tries in samples
        ]
        print(
            "cost per attempt (frames@2x): min "
            f"{min(per_attempt) / (CYCLES_PER_FRAME * 2):.1f}  max "
            f"{max(per_attempt) / (CYCLES_PER_FRAME * 2):.1f}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
