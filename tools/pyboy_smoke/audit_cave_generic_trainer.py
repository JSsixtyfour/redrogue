#!/usr/bin/env python3
"""Audit: the cave's generic route trainer (GENERIC_TRAINER_ALL_AREAS_SPEC.md).

For each seeded cave (one fresh boot, real preload and warp-in, no stage event),
with his roll forced to a row on floor 1, this checks that he is placed by
test_cave_generic_trainer's assert_placed (a candidate dead end, or, when every
candidate is taken, the fallback dead end clear of the pair, objects and warps;
talkable from a tile the player reaches). Any absence fails (2026-11-20: the
fallback scan made him always present; before it, 14 of 120 caves with Jessie &
James armed had none).

Usage:
    python3 tools/pyboy_smoke/audit_cave_generic_trainer.py [--seeds 120]
"""

from __future__ import annotations

import argparse
import unittest
from collections import Counter

import test_cave_generic_trainer as t

MAX_ABSENT = 0.0


class Audit(t.CaveGenericTrainerTest):
    def runTest(self) -> None:  # unittest needs one
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=120)
    parser.add_argument("--start", type=int, default=1)
    parser.add_argument("--event", default="", help="arm a stage event, e.g. STAGE_EVENT_JESSIE_JAMES "
                        "(the hideout is then taken, so only the second candidate counts)")
    args = parser.parse_args()
    audit = Audit()
    audit.setUp()
    event = audit.ram[args.event] if args.event else 0
    problems, reasons = 0, Counter()
    try:
        h = audit.h
        for seed in range(args.start, args.start + args.seeds):
            audit.enter(1, seed, event)
            try:
                if audit.picture(t.SLOT):
                    audit.assert_placed(0, f"seed {seed}")
                    ax, ay = h.read_sram_bytes("sStageEventHideoutAltX", 2, bank=0)
                    hx, hy = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
                    tx, ty = audit.pos(t.SLOT)
                    which = ("second candidate" if (tx // 2, ty // 2) == (ax, ay)
                             else "hideout's dead end" if (tx // 2, ty // 2) == (hx, hy) else "fallback")
                    reasons[f"placed: {which}"] += 1
                    continue
                ax, ay = h.read_sram_bytes("sStageEventHideoutAltX", 2, bank=0)
                ey, ex = h.read8("wWarpEntries", offset=4) // 2, h.read8("wWarpEntries", offset=5) // 2
                balls = {(x // 2, y // 2) for x, y in (audit.pos(s) for s in range(2, 6))}
                hx, hy = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
                why = ("exit" if (ax, ay) == (ex, ey) else "ball" if (ax, ay) in balls
                       else "hideout took it" if (ax, ay) == (hx, hy) else "other")
                reasons[f"absent: {why}"] += 1
                audit.assertEqual(audit.cell(), t.CELL_NONE)
            except AssertionError as error:
                problems += 1
                print(f"seed {seed}: {error}")
    finally:
        audit.tearDown()
    absent = sum(n for k, n in reasons.items() if k.startswith("absent"))
    rate = absent / args.seeds
    print(f"caves {args.seeds}, {dict(reasons)}, absent {rate:.1%} (max {MAX_ABSENT:.0%}), problems {problems}")
    return 1 if problems or rate > MAX_ABSENT else 0


if __name__ == "__main__":
    raise SystemExit(main())
