#!/usr/bin/env python3
"""Audit: the Facility's generic route trainer (GENERIC_TRAINER_ALL_AREAS_SPEC.md).

For each seeded Facility (one boot, real preload and warp-in), with his roll
forced to a row on floor 1, this checks that he is either placed by
test_facility_generic_trainer's assert_placed (a room's plain-floor block, clear
of every object and more than two blocks from the hideout) or absent with the
"no trainer" cell. It reports the absence rate and fails above MAX_ABSENT.

Usage:
    python3 tools/pyboy_smoke/audit_facility_generic_trainer.py [--seeds 200] [--event STAGE_EVENT_JESSIE_JAMES]
"""

from __future__ import annotations

import argparse
from collections import Counter

import test_facility_generic_trainer as t
from source_constants import parse_rgbds_constants

MAX_ABSENT = 0.0


class Audit(t.FacilityGenericTrainerTest):
    def runTest(self) -> None:  # unittest needs one
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=200)
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--event", default="", help="arm a stage event, e.g. STAGE_EVENT_JESSIE_JAMES")
    args = parser.parse_args()
    ram = parse_rgbds_constants(t.ROOT / "constants/ram_constants.asm")
    event = ram[args.event] if args.event else 0
    audit = Audit()
    audit.setUp()
    problems, reasons = 0, Counter()
    try:
        for seed in range(args.start, args.start + args.seeds):
            audit.enter(1, seed, event)
            try:
                if audit.picture(t.SLOT):
                    audit.assert_placed(0, f"seed {seed}")
                    reasons["placed"] += 1
                else:
                    audit.assertEqual(audit.cell(), t.CELL_NONE, f"seed {seed}: absent, cell not 'none'")
                    reasons["absent"] += 1
                    print(f"seed {seed}: absent")
            except AssertionError as error:
                problems += 1
                print(f"seed {seed}: {error}")
    finally:
        audit.tearDown()
    rate = reasons["absent"] / args.seeds
    print(f"facilities {args.seeds}, event {args.event or 'none'}, {dict(reasons)}, "
          f"absent {rate:.1%} (max {MAX_ABSENT:.0%}), problems {problems}")
    return 1 if problems or rate > MAX_ABSENT else 0


if __name__ == "__main__":
    raise SystemExit(main())
