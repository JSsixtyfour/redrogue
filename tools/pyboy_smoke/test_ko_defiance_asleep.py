"""KO DEFIANCE reviving a sleeping mon must not let it act on a move it never chose.

A sleeping mon skips move selection, so its selected move is whatever was there before: the
fainted mon's, or 0 on a battle's first turn. KO DEFIANCE clears the sleep, and when the
enemy moved first the revived mon still had its turn to come: it used a teammate's Rock Throw
(autoplay seed 4007, 2026-11-24), and on turn 1 it read move 0, before the Moves table.
A mon locked into a move keeps it, as after Haze.
"""
from __future__ import annotations

import unittest
from pathlib import Path

import autoplay
from autoplay_checks import GameChecks
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants
from test_autoplay_battle_checks import Agent

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
THRASHING_ABOUT, CANNOT_MOVE = 1, 0xFF


class KODefianceAsleepTest(unittest.TestCase):
    def play(self, *, status: int, first_turn: bool = True, lock: bool = False,
             lead: str = "SNORLAX") -> dict:
        """A last mon at 1 HP with `status` set at the top of a turn, against a faster attacker."""
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.inject_fight2_spec(
            [{"species": species[lead], "level": 100, "moves": [moves["SPLASH"]]}],
            [{"species": species["JOLTEON"], "level": 60, "moves": [moves["SWIFT"]]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=0)
        checks = GameChecks(Agent(h), ROOT)
        seen = {"turn": 0, "revived": 0, "acts_after": None, "selected": None, "hp_bar": None, "moves": moves}
        when = 1 if first_turn else 3

        def turn(_context) -> None:
            seen["turn"] += 1
            h.write8("wStatusFlags7", h.read8("wStatusFlags7") & ~1)  # not a test battle
            if seen["turn"] == 1:
                autoplay.grant_kit(h, [["KO_DEFIANCE", 0, True]])
                h.write8("wKODefianceUsages", 1)
            if seen["turn"] == when:
                h.write8("wBattleMonStatus", status)
                h.write8("wBattleMonHP", 0)
                h.write8("wBattleMonHP", 1, 1)
                if lock:
                    h.write8("wPlayerBattleStatus1", 1 << THRASHING_ABOUT)
                    h.write8("wPlayerNumAttacksLeft", 2)
                    h.write8("wPlayerSelectedMove", moves["THRASH"])

        def revived(_context) -> None:
            seen["revived"] += 1
            seen["hp"] = h.read8("wBattleMonHP") << 8 | h.read8("wBattleMonHP", 1)
            seen["max_hp"] = h.read8("wBattleMonMaxHP") << 8 | h.read8("wBattleMonMaxHP", 1)
            seen["status"] = h.read8("wBattleMonStatus")

        h.register_hook("MainInBattleLoop", turn)
        def bar(_context) -> None:  # the first player-bar fill after the revival
            if seen["revived"] and "bar" not in seen and h.read8("wHPBarType") == 1:
                seen["bar"] = h.read8("wHPBarNewHP") | h.read8("wHPBarNewHP", 1) << 8

        h.register_hook("UpdateHPBar2", bar)
        h.register_hook("ExecutePlayerMove", lambda _c: seen.update(
            selected=h.read8("wPlayerSelectedMove")) if seen["revived"] and seen["selected"] is None else None)
        h.register_hook("KODefianceRevive.revived", revived)
        h.boot_fight2(seed=1)
        for _ in range(900):
            if seen["turn"] >= when + 2 or checks.crash:
                break
            h.tap("a", 1)
            h.tick(8)
        seen["anomalies"] = [a for a in checks.anomalies if a["check"] not in ("party", "enemy_party")]
        seen["crash"] = checks.crash
        self.assertFalse(h.hook_errors, h.hook_errors)
        self.assertTrue(seen["revived"], f"KO DEFIANCE never ran: {seen}")
        return seen

    def test_a_mon_revived_asleep_does_not_act_on_a_stale_move(self) -> None:
        for first_turn in (True, False):
            with self.subTest(first_turn=first_turn):
                seen = self.play(status=3, first_turn=first_turn)
                self.assertEqual(seen["anomalies"], [])
                self.assertIsNone(seen["crash"])
                self.assertEqual(seen["selected"], CANNOT_MOVE, seen)
                self.assertGreaterEqual(seen["turn"], 3 if first_turn else 5, "the battle did not go on")

    def test_a_mon_revived_awake_keeps_its_chosen_move(self) -> None:
        seen = self.play(status=0, first_turn=False)
        self.assertEqual(seen["selected"], seen["moves"]["SPLASH"], seen)
        self.assertEqual(seen["anomalies"], [])

    def test_a_locked_mon_keeps_its_move(self) -> None:
        seen = self.play(status=3, first_turn=False, lock=True)
        self.assertEqual(seen["selected"], seen["moves"]["THRASH"], seen)

    def test_the_revived_hp_is_half_and_the_bar_fills_to_it(self) -> None:
        seen = self.play(status=3, lead="CHANSEY")
        self.assertEqual(seen["hp"], seen["max_hp"] // 2)
        self.assertGreater(seen["hp"], 255, "fixture: a level 100 Chansey is here for the high byte")
        self.assertEqual(seen["bar"], seen["hp"], "the HP bar lost the revival HP's high byte")


if __name__ == "__main__":
    unittest.main()
