#!/usr/bin/env python3
"""Audit: the Cemetery's generic route trainer on every floor
(GENERIC_TRAINER_ALL_AREAS_SPEC.md).

Each Cemetery is a deep one (six stops: 1, 2, 3, 2b, 3b, 4), walked down by the
live stairs (test_cemetery_deep_floor's `stair`). Before each stop's load his
floor ordinal is set to that stop and his row to 1, and the resurrector's
ordinal too (the worst case: the two must keep apart), so every stop must show
him. Since his cell is re-derived on each load, this samples six cells per
Cemetery. A stop is checked by test_cemetery_generic_trainer's assert_placed:
ground, not the ball or a stair, and clear of the Channeler, the resurrector
and both stairs' arrival blocks (by one block when the strict pass placed him,
off their blocks on the loose and open-ground passes). Reports which pass placed
him; any absence fails.

Usage:
    python3 tools/pyboy_smoke/audit_cemetery_generic_trainer.py [--cemeteries 60]
"""

from __future__ import annotations

import argparse
import io
from collections import Counter

import test_cemetery_deep_floor as deep
import test_cemetery_generic_trainer as gen
from harness import RedRogueHarness

MAX_ABSENT = 0.0
NAMES = ["1", "2", "3", "2b", "3b", "4"]


class Placement(gen.CemeteryGenericTrainerTest):
    def runTest(self) -> None:  # unittest needs one
        pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cemeteries", type=int, default=60)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--resurrector-elsewhere", action="store_true",
                        help="leave the resurrector's own roll alone")
    args = parser.parse_args()

    h = RedRogueHarness(deep.ROOT, deep.ARTIFACTS)
    h.allow_deep_cemetery_floor = True
    walk = deep.CemeteryDeepFloorTest("test_the_chain_down_and_back")
    walk.h = h
    check = Placement()
    check.h = h
    check.maps = None
    from source_constants import parse_rgbds_constants
    check.sprites = parse_rgbds_constants(gen.ROOT / "constants/sprite_constants.asm")
    check.trainers = gen.trainer_ids()
    check.track_passes()

    def aim(ordinal: int) -> None:
        h.write_sram_bytes("sWildGenericRow", [1], bank=0)
        h.write_sram_bytes("sWildGenericFloor", [ordinal], bank=0)
        if not args.resurrector_elsewhere:
            base = h.read_sram_bytes("sProcCaveStagingBuffer", 6, bank=0)
            base[5] = ordinal                    # CEM_DEEP_RES_ORD
            h.write_sram_bytes("sProcCaveStagingBuffer", base, bank=0)

    problems, placed, absent, passes = 0, Counter(), Counter(), Counter()
    try:
        h.boot_to_lobby(battle_count=41, encounter_kind=4)
        h.write8("wStageEvent", 0)
        lobby = io.BytesIO()
        h.save_state(lobby)
        for n in range(args.start, args.start + args.cemeteries):
            h.load_state(lobby)
            h.seed_rng((n & 255, (n >> 8) ^ 0x5A, n * 7 & 255, 1))

            def first(_context) -> None:
                h.pyboy.register_file.A = 1

            def floor0(_context) -> None:
                h.pyboy.register_file.A = 0

            hooks = [("CemGenericRoll.store", first), ("CemGenericRoll.floor", floor0)]
            if not args.resurrector_elsewhere:
                hooks.append(("CemResurrectorRoll.store", floor0))
            for label, fn in hooks:
                h.register_hook(label, fn)
            try:
                h.preload_and_enter_wild_area(deep.CEM[1], "cemetery")
            finally:
                for label, fn in hooks:
                    h.unregister_hook(label, fn)
            h.wait_until(lambda: h.read8("hJoyIgnore") == 0, "settled", 900)
            h.tick(60)
            h.write8("wProcCemWildBudget", 0)
            for stop in range(6):
                if stop:
                    aim(stop)
                    try:
                        walk.stair(1, f"cemetery {n}: stop {stop}")
                    except AssertionError as error:
                        problems += 1
                        print(f"cemetery {n}: stair to {NAMES[stop]}: {error}")
                        break
                label = f"cemetery {n} floor {NAMES[stop]}"
                try:
                    if check.picture(gen.SLOT):
                        check.assert_placed(0, label)
                        placed[NAMES[stop]] += 1
                        passes[check.place_pass] += 1
                    else:
                        absent[NAMES[stop]] += 1
                        print(f"{label}: absent")
                except AssertionError as error:
                    problems += 1
                    print(f"{label}: {error}")
    finally:
        h.close()
    total = sum(placed.values()) + sum(absent.values())
    rate = sum(absent.values()) / total if total else 1.0
    print(f"placing pass (1 strict, 2 loose, 3 open ground): {dict(passes)}")
    print(f"cemeteries {args.cemeteries}, stops {total}, placed {dict(placed)}, absent {dict(absent)}, "
          f"absent {rate:.1%} (max {MAX_ABSENT:.0%}), problems {problems}")
    return 1 if problems or rate > MAX_ABSENT or not total else 0


if __name__ == "__main__":
    raise SystemExit(main())
