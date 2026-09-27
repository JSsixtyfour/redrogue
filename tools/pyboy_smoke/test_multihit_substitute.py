"""Multi-hit moves continue after breaking a Substitute."""

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants


ROOT = Path(__file__).resolve().parents[2]
HAS_SUBSTITUTE_UP = 1 << 4


class MultiHitSubstituteTest(unittest.TestCase):
    def setUp(self) -> None:
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

    def mon(self, species: str, move: str) -> dict[str, object]:
        return {
            "species": self.species[species],
            "level": 50,
            "moves": [self.moves[move]],
        }

    def run_until(self, harness: RedRogueHarness, predicate) -> None:
        for _ in range(900):
            harness.tap("a", 1)
            harness.tick(8)
            if predicate():
                return
        self.fail(f"battle did not reach expected multi-hit result: {harness.diagnostic_state()}")

    @staticmethod
    def set_word(harness: RedRogueHarness, label: str, value: int) -> None:
        harness.write8(label, value >> 8)
        harness.write8(label, value, offset=1)

    def test_player_second_hit_reaches_owner_after_first_breaks_substitute(self) -> None:
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            h.inject_fight2_spec(
                [self.mon("TAUROS", "DOUBLE_KICK")],
                [self.mon("SNORLAX", "SPLASH")],
                trainer_class=self.trainers["COOLTRAINER_M"],
                ai_tier=0,
            )
            h.boot_fight2(seed=1)
            primed = {"done": False}

            def prime(_context) -> None:
                if primed["done"]:
                    return
                primed["done"] = True
                h.write8(
                    "wEnemyBattleStatus2",
                    h.read8("wEnemyBattleStatus2") | HAS_SUBSTITUTE_UP,
                )
                h.write8("wEnemySubstituteHP", 1)
                self.set_word(h, "wEnemyMonHP", 1)

            h.register_hook("ExecutePlayerMove", prime)
            hits = h.hook_flag("ApplyAttackToEnemyPokemon")
            h.hook_flag(
                "DisplayBattleMenu",
                action=lambda: h.write8("wBattleAndStartSavedMenuItem", 0),
            )
            h.hook_flag(
                "MoveSelectionMenu",
                action=lambda: h.write8("wPlayerMoveListIndex", 0),
            )
            self.run_until(h, lambda: hits["count"] >= 2)
            self.assertGreaterEqual(hits["count"], 2)
            self.assertEqual(h.read_bytes("wEnemyMonHP", 2), [0, 0])
            self.assertFalse(h.read8("wEnemyBattleStatus2") & HAS_SUBSTITUTE_UP)
        finally:
            h.close()

    def test_enemy_second_hit_reaches_owner_after_first_breaks_substitute(self) -> None:
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            h.inject_fight2_spec(
                [self.mon("SNORLAX", "SPLASH")],
                [self.mon("TAUROS", "DOUBLE_KICK")],
                trainer_class=self.trainers["COOLTRAINER_M"],
                ai_tier=0,
            )
            h.boot_fight2(seed=1)
            primed = {"done": False}

            def prime(_context) -> None:
                if primed["done"]:
                    return
                primed["done"] = True
                h.write8(
                    "wPlayerBattleStatus2",
                    h.read8("wPlayerBattleStatus2") | HAS_SUBSTITUTE_UP,
                )
                h.write8("wPlayerSubstituteHP", 1)
                self.set_word(h, "wBattleMonHP", 1)

            h.register_hook("ExecuteEnemyMove", prime)
            hits = h.hook_flag("ApplyAttackToPlayerPokemon")
            h.hook_flag(
                "DisplayBattleMenu",
                action=lambda: h.write8("wBattleAndStartSavedMenuItem", 0),
            )
            h.hook_flag(
                "MoveSelectionMenu",
                action=lambda: h.write8("wPlayerMoveListIndex", 0),
            )
            self.run_until(h, lambda: hits["count"] >= 2)
            self.assertGreaterEqual(hits["count"], 2)
            self.assertEqual(h.read_bytes("wBattleMonHP", 2), [0, 0])
            self.assertFalse(h.read8("wPlayerBattleStatus2") & HAS_SUBSTITUTE_UP)
        finally:
            h.close()


if __name__ == "__main__":
    unittest.main()