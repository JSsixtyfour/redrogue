"""Audit: is RollElite4AndChampion's room order actually uniform?

Reported 2026-09-23: "Karen seems to be the final Elite Four member a lot".
RollElite4 (custom_functions/final_sequence.asm) is rejection sampling over a
used-slot mask and reads as uniform in source, so this measures it on the real
ROM instead of arguing from the code.

Johto on (BIT_DEBUG2_MODE), empty gym lineup, so Koga_E4 is eligible and the
pool is all seven members. Expected: every member lands in every position about
4/7 * 1/4 = 1/7 of the time (~14%).

call_routine corrupts the machine after roughly ten invocations per boot
(project_call_routine_harness_limits), so each boot rolls ROLLS_PER_BOOT times
and the seed varies across boots. test_elite_four_roll.py uses seed=1 for every
boot, which is fine for a correctness test and useless for a distribution.

Not part of make smoke. Usage:
    python3 tools/pyboy_smoke/audit_e4_roll_distribution.py [--boots N]
"""
from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import (  # noqa: E402
    parse_rgbds_constants,
    parse_trainer_class_indexes,
)

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
ROLLS_PER_BOOT = 6
NUM_E4 = 4


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--boots", type=int, default=40)
    args = parser.parse_args()

    classes = parse_trainer_class_indexes(REPO_ROOT / "constants" / "trainer_constants.asm")
    by_id = {v: k for k, v in classes.items()}
    ram = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")
    debug2_bit = ram["BIT_DEBUG2_MODE"]

    position = [Counter() for _ in range(NUM_E4)]
    champion = Counter()
    rolls = 0
    for boot in range(args.boots):
        seed = boot % 99 + 1
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_fight2(seed=seed)
            h.write8("wStatusFlags6", h.read8("wStatusFlags6") | (1 << debug2_bit))
            for i in range(8):
                h.write8("wRunGymLineup", 0, offset=i)
            for _ in range(ROLLS_PER_BOOT):
                h.park_before_hijack()
                h.call_routine("RollElite4AndChampion")
                members = h.read_bytes("wRunElite4", NUM_E4)
                for pos, cls in enumerate(members):
                    position[pos][by_id.get(cls, f"?{cls}")] += 1
                champion[by_id.get(h.read8("wRunChampion"), "?")] += 1
                rolls += 1
        finally:
            h.close()
        print(f"boot {boot + 1}/{args.boots} (seed {seed}) done", file=sys.stderr)

    names = sorted({n for c in position for n in c})
    print(f"\n{rolls} rolls, expected ~{100 / 7:.1f}% per cell\n")
    print(f"{'member':<10}" + "".join(f"{'pos' + str(p):>9}" for p in range(NUM_E4)) + f"{'drawn':>9}")
    for n in names:
        cells = "".join(f"{100 * position[p][n] / rolls:>8.1f}%" for p in range(NUM_E4))
        drawn = sum(position[p][n] for p in range(NUM_E4))
        print(f"{n:<10}{cells}{100 * drawn / rolls:>8.1f}%")
    print("\nchampion:", dict(champion))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
