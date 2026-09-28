"""Witch Turn Limit drain animates the PLAYER's HP bar, whoever moved last.

HandleTurnLimitDrain runs after both moves and only ever drains the player's
mon. Its inlined HP-bar update used to pick the bar from hWhoseTurn, which is
whoever moved LAST: on the player-moves-first path that is the enemy, and the
enemy's bar was animated with the player's HP (measured 2026-09-28: 3 of 3
drains). The fixture makes the player faster so that path is the one taken, and
asserts it was actually taken, so the test cannot pass by missing it.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class WitchTurnLimitBarTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")

    def tearDown(self):
        self.h.close()

    def test_drain_animates_player_bar_when_enemy_moved_last(self):
        h = self.h
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        ram = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

        drains = []

        def drain_fired():
            drains.append({"whose": h.read8("hWhoseTurn"), "bar": None})

        def bar_updated():
            if drains and drains[-1]["bar"] is None:
                drains[-1]["bar"] = h.read8("wHPBarType")

        h.hook_flag("HandleTurnLimitDrain.nonZeroDamage", drain_fired)
        h.hook_flag("UpdateHPBar2", bar_updated)
        # Player faster than the enemy: the enemy moves last every turn.
        h.inject_fight2_spec(
            [{"species": species["GENGAR"], "level": 50, "moves": [moves["NIGHT_SHADE"]]}],
            [{"species": species["SNORLAX"], "level": 50, "moves": [moves["SPLASH"]]}],
            trainer_class=trainers["COOLTRAINER_M"],
            ai_tier=0,
        )
        h.boot_fight2(seed=1)
        flags = h.read8("wRogueFlagsBitfield")
        h.write8("wRogueFlagsBitfield", flags | (1 << ram["BIT_WITCH_ACCEPTED"]))
        h.write8("wWitchChallenge", ram["CHALLENGE_TURN_LIMIT"])
        h.write8("wBattleTurnLimit", 1)
        h.write8("wBattleTurnCount", 0)
        for _ in range(300):
            h.tap("a", 1)
            h.tick(8)
            if len(drains) >= 2 or h.read8("hIsInBattle") == 0:
                break

        self.assertGreaterEqual(len(drains), 2, "the Turn Limit drain never fired")
        self.assertTrue(any(d["whose"] == 1 for d in drains),
                        f"no drain ran with the enemy having moved last: {drains}")
        for d in drains:
            with self.subTest(drain=d):
                self.assertEqual(d["bar"], 1, "wHPBarType must be the player bar")


if __name__ == "__main__":
    unittest.main()
