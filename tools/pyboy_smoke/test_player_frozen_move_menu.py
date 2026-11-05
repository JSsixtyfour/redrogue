"""A frozen mon picks a move; a sleeping one does not.

A frozen mon used to skip the move menu. In a battle's first turn that left the selected move 0, and
when an enemy's Fire move thawed the mon, its turn ran with move 0: GetCurrentMove read before the
move table, as code, and the battle crashed. Shin Pokemon Red selects a move while frozen, so the
same is done here. Sleep is deliberately unchanged.

Real battles through FIGHT 2. Every assertion counts a hooked branch, not the battle's outcome.
"""
from __future__ import annotations

import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
FRZ_BIT = 5
SLEEP_TURNS = 3
PP = 15


class PlayerFrozenMoveMenuTest(unittest.TestCase):
    def battle(self, enemy_species: str, enemy_move: str, status: int) -> tuple[RedRogueHarness, dict]:
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.inject_fight2_spec(
            [{"species": species["SNORLAX"], "level": 50, "moves": [moves["BODY_SLAM"]]}],
            [{"species": species[enemy_species], "level": 50, "moves": [moves[enemy_move]]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=0)
        seen = {name: h.hook_flag(label) for name, label in (
            ("menu", "MoveSelectionMenu"), ("frozen", "CheckPlayerStatusConditions.FrozenCheck"),
            ("acted", "PlayerCanExecuteMove"), ("enemy", "ExecuteEnemyMove"),
            ("loop", "MainInBattleLoop.mainLoopPlayerAlive"))}
        h.boot_fight2(seed=1)
        h.write8("wBattleMonStatus", status)
        h.write8("wBattleMonPP", PP)
        seen["moves"] = moves
        return h, seen

    def play_one_turn(self, h, seen) -> None:
        """Until the battle loop comes round again, which is when both sides have had their turn."""
        start = seen["loop"]["count"]
        for _ in range(240):
            h.tap("a", 1)
            h.tick(8)
            if seen["loop"]["count"] > start:
                break
        self.assertGreater(seen["loop"]["count"], start, "the turn never finished")
        self.assertGreater(seen["enemy"]["count"], 0, "the enemy never moved")

    def test_staying_frozen_picks_a_move_and_spends_nothing(self) -> None:
        h, seen = self.battle("GENGAR", "NIGHT_SHADE", 1 << FRZ_BIT)
        self.play_one_turn(h, seen)
        self.assertGreater(seen["menu"]["count"], 0, "a frozen mon skipped the move menu")
        self.assertGreater(seen["frozen"]["count"], 0)
        self.assertEqual(seen["acted"]["count"], 0, "a frozen mon acted")
        self.assertEqual(h.read8("wBattleMonPP") & 0x3F, PP)
        self.assertEqual(h.read8("wBattleMonStatus"), 1 << FRZ_BIT)

    def test_thawed_before_its_turn_uses_the_chosen_move(self) -> None:
        h, seen = self.battle("JOLTEON", "FLAMETHROWER", 1 << FRZ_BIT)
        self.play_one_turn(h, seen)
        self.assertEqual(h.read8("wBattleMonStatus") & 1 << FRZ_BIT, 0, "the Fire move never thawed it")
        self.assertGreater(seen["acted"]["count"], 0, "the thawed mon lost its turn")
        self.assertEqual(h.read8("wPlayerSelectedMove"), seen["moves"]["BODY_SLAM"])
        self.assertEqual(h.read8("wBattleMonPP") & 0x3F, PP - 1)

    def test_sleep_still_skips_the_move_menu(self) -> None:
        h, seen = self.battle("GENGAR", "NIGHT_SHADE", SLEEP_TURNS)
        self.play_one_turn(h, seen)
        self.assertEqual(seen["menu"]["count"], 0, "a sleeping mon opened the move menu")
        self.assertEqual(seen["acted"]["count"], 0, "a sleeping mon acted")
        self.assertEqual(h.read8("wBattleMonPP") & 0x3F, PP)


if __name__ == "__main__":
    unittest.main()
