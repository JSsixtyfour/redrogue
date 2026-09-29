"""Multi-hit moves print the effectiveness text once, on the first hit (ShinRed)."""

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants


ROOT = Path(__file__).resolve().parents[2]


class MultiHitEffectivenessTextTest(unittest.TestCase):
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

    def run_double_kick(self, player: str, enemy: str, attacker_turn: int) -> tuple[int, int, int]:
        """Returns (hits, DisplayEffectiveness entries, texts printed) for the
        attacker's Double Kick. Fighting into a Normal-type Snorlax is x2."""
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            h.inject_fight2_spec(
                [self.mon(*player.split())],
                [self.mon(*enemy.split())],
                trainer_class=self.trainers["COOLTRAINER_M"],
                ai_tier=0,
            )
            h.boot_fight2(seed=1)
            counts = {"entries": 0, "printed": 0}

            def on_turn(key: str):
                def callback(_context) -> None:
                    if h.read8("hWhoseTurn") == attacker_turn:
                        counts[key] += 1
                return callback

            h.register_hook("DisplayEffectiveness", on_turn("entries"))
            h.register_hook("DisplayEffectiveness.done", on_turn("printed"))
            apply = "ApplyAttackToEnemyPokemon" if attacker_turn == 0 else "ApplyAttackToPlayerPokemon"
            done = "ExecutePlayerMoveDone" if attacker_turn == 0 else "ExecuteEnemyMoveDone"
            hits = h.hook_flag(apply)
            finished = h.hook_flag(done)
            h.hook_flag(
                "DisplayBattleMenu",
                action=lambda: h.write8("wBattleAndStartSavedMenuItem", 0),
            )
            h.hook_flag(
                "MoveSelectionMenu",
                action=lambda: h.write8("wPlayerMoveListIndex", 0),
            )
            for _ in range(900):
                h.tap("a", 1)
                h.tick(8)
                if hits["count"] >= 2 and finished["count"] >= 1:
                    break
            else:
                self.fail(f"Double Kick never finished: {h.diagnostic_state()}")
            return hits["count"], counts["entries"], counts["printed"]
        finally:
            h.close()

    def test_player_multihit_prints_effectiveness_once(self) -> None:
        hits, entries, printed = self.run_double_kick("TAUROS DOUBLE_KICK", "SNORLAX SPLASH", 0)
        self.assertEqual(hits, 2)
        self.assertEqual(entries, 2)  # reached on both hits; the gate is what stops the second
        self.assertEqual(printed, 1)

    def test_enemy_multihit_prints_effectiveness_once(self) -> None:
        hits, entries, printed = self.run_double_kick("SNORLAX SPLASH", "TAUROS DOUBLE_KICK", 1)
        self.assertEqual(hits, 2)
        self.assertEqual(entries, 2)
        self.assertEqual(printed, 1)


if __name__ == "__main__":
    unittest.main()
