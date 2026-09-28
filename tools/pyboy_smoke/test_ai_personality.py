"""Focused runtime contracts for the checkpoint E personality framework."""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class AIPersonalityTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")

        def mon(name, moves):
            return {
                "species": species[name],
                "level": 50,
                "moves": [self.moves[move] for move in moves],
            }

        self.h.inject_fight2_spec(
            [mon("SNORLAX", ["SPLASH"])],
            [mon("TAUROS", ["TACKLE", "GROWL", "NIGHT_SHADE", "TAIL_WHIP"])],
            trainer_class=self.trainers["COOLTRAINER_M"],
            ai_tier=2,
        )
        self.h.boot_fight2(seed=1)

    def tearDown(self):
        self.h.close()

    def prime(self):
        move_names = ("TACKLE", "GROWL", "NIGHT_SHADE", "TAIL_WHIP")
        for slot, move in enumerate(move_names):
            self.h.write8("wEnemyMonMoves", self.moves[move], offset=slot)
            self.h.write8("wBuffer", self.ai["AI_SCORE_BASE"], offset=slot)

    def scores(self):
        return list(self.h.read_bytes("wBuffer", 4))

    def call(self, routine):
        self.h.park_before_hijack()
        self.h.call_routine(routine, limit=240)

    def test_neutral_live_table_preserves_scores(self):
        self.prime()
        self.h.write8("wTrainerClass", self.trainers["COOLTRAINER_M"])
        self.call("AIRunPersonality")
        self.assertEqual(self.scores(), [self.ai["AI_SCORE_BASE"]] * 4)

    def test_offense_profile_nudges_only_damaging_moves(self):
        self.prime()
        self.h.write8("wBuffer", self.ai["AI_SCORE_DISABLED"], offset=0)
        self.call("AISoftPersonalityOffense")
        self.assertEqual(
            self.scores(),
            [
                self.ai["AI_SCORE_DISABLED"],
                self.ai["AI_SCORE_BASE"],
                self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
                self.ai["AI_SCORE_BASE"],
            ],
        )

    def test_control_profile_nudges_only_status_moves(self):
        self.prime()
        self.call("AISoftPersonalityControl")
        self.assertEqual(
            self.scores(),
            [
                self.ai["AI_SCORE_BASE"],
                self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
                self.ai["AI_SCORE_BASE"],
                self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
            ],
        )


if __name__ == "__main__":
    unittest.main()