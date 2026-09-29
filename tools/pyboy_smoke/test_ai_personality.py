"""Focused runtime contracts for the checkpoint E personality framework."""
from io import BytesIO
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import (
    parse_rgbds_constants,
    parse_trainer_class_indexes,
    parse_trainer_constants,
)

ROOT = Path(__file__).resolve().parents[2]


class AIPersonalityTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.trainer_classes = parse_trainer_class_indexes(
            ROOT / "constants/trainer_constants.asm"
        )
        self.types = parse_rgbds_constants(ROOT / "constants/type_constants.asm")
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
        self.battle_state = BytesIO()
        self.h.save_state(self.battle_state)

    def tearDown(self):
        self.h.close()

    def prime(self, move_names=("TACKLE", "GROWL", "NIGHT_SHADE", "TAIL_WHIP")):
        for slot in range(4):
            move = move_names[slot] if slot < len(move_names) else None
            self.h.write8(
                "wEnemyMonMoves", self.moves[move] if move else 0, offset=slot
            )
            self.h.write8("wBuffer", self.ai["AI_SCORE_BASE"], offset=slot)

    def dispatch(self, records, move_names, trainer_class, *, trainer_no=1, tier=0, disabled_slot=None, player_types=None, player_hp=None):
        """Run the production chooser from the same parked FIGHT 2 state."""
        h = self.h
        h.load_state(self.battle_state)
        for slot in range(4):
            name = move_names[slot] if slot < len(move_names) else None
            h.write8("wEnemyMonMoves", self.moves[name] if name else 0, offset=slot)
        h.write8("wTrainerClass", trainer_class)
        h.write8("wTrainerNo", trainer_no)
        h.write8("wAITier", tier + 1)
        h.write8("wAILayer2Encouragement", 0)
        h.write8("wEnemyDisabledMove", 0)
        h.write8("wBattleMonStatus", 0)
        if disabled_slot is not None:
            h.write8("wEnemyDisabledMove", ((disabled_slot + 1) << 4) | 1)
        if player_types is not None:
            h.write8("wBattleMonType1", player_types[0])
            h.write8("wBattleMonType2", player_types[1])
        if player_hp is not None:
            h.write8("wBattleMonHP", player_hp >> 8)
            h.write8("wBattleMonHP", player_hp & 0xFF, offset=1)
        h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
        scored = records[-1]
        return {
            "scores": scored["scores"],
            "eligible_slots": scored["eligible_slots"],
            "candidates": [move for move in h.read_bytes("wBuffer", 4) if move],
        }

    def scores(self):
        return list(self.h.read_bytes("wBuffer", 4))

    def call(self, routine):
        # boot_fight2 already parks safely; do not tick after priming test state.
        self.h.call_routine(routine, limit=240)

    def test_neutral_live_table_preserves_scores(self):
        self.prime()
        self.h.write8("wTrainerClass", self.trainer_classes["COOLTRAINER_M"])
        self.call("AIRunPersonality")
        self.assertEqual(self.scores(), [self.ai["AI_SCORE_BASE"]] * 4)

    def test_blackbelt_live_resolver_nudges_damaging_and_fixed_damage_moves(self):
        self.prime()
        self.h.write8("wBuffer", self.ai["AI_SCORE_DISABLED"], offset=0)
        self.h.write8("wTrainerClass", self.trainer_classes["BLACKBELT"])
        self.call("AIRunPersonality")
        self.assertEqual(
            self.scores(),
            [
                self.ai["AI_SCORE_DISABLED"],
                self.ai["AI_SCORE_BASE"],
                self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
                self.ai["AI_SCORE_BASE"],
            ],
        )

    def test_blackbelt_offense_classifies_bide_as_damage(self):
        self.prime(("NIGHT_SHADE", "BIDE", "GROWL"))
        self.h.write8("wTrainerClass", self.trainer_classes["BLACKBELT"])
        self.call("AIRunPersonality")
        self.assertEqual(
            self.scores(),
            [
                self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
                self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
                self.ai["AI_SCORE_BASE"],
                self.ai["AI_SCORE_BASE"],
            ],
        )

    def test_blackbelt_profile_leaves_empty_move_slots_untouched(self):
        self.prime(("TACKLE",))
        self.h.write8("wTrainerClass", self.trainer_classes["BLACKBELT"])
        self.call("AIRunPersonality")
        self.assertEqual(
            self.scores(),
            [
                self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
                self.ai["AI_SCORE_BASE"],
                self.ai["AI_SCORE_BASE"],
                self.ai["AI_SCORE_BASE"],
            ],
        )

    def test_final_ai_remains_neutral(self):
        self.prime()
        self.h.write8("wTrainerClass", self.trainer_classes["FINAL_AI"])
        self.call("AIRunPersonality")
        self.assertEqual(self.scores(), [self.ai["AI_SCORE_BASE"]] * 4)

    def test_individual_override_precedes_class_default_and_none_is_explicit(self):
        h = self.h
        blackbelt = self.trainer_classes["BLACKBELT"]

        def probe(trainer_no, profile):
            h.park_before_hijack()
            h.write8("wBuffer", blackbelt)
            h.write8("wBuffer", trainer_no, offset=1)
            h.write8("wBuffer", blackbelt, offset=2)
            h.write8("wBuffer", 1, offset=3)
            h.write8("wBuffer", profile, offset=4)
            h.write8("wBuffer", 0xFF, offset=5)
            h.call_routine("AISoftPersonalityTestResolveTrainerOverride", limit=120)
            return h.read_bytes("wBuffer", 2)

        self.assertEqual(probe(1, self.ai["AI_PERSONALITY_CONTROL"]),
                         [self.ai["AI_PERSONALITY_CONTROL"], 1])
        self.assertEqual(probe(1, self.ai["AI_PERSONALITY_NONE"]),
                         [self.ai["AI_PERSONALITY_NONE"], 1])
        self.assertEqual(probe(2, self.ai["AI_PERSONALITY_CONTROL"]),
                         [self.ai["AI_PERSONALITY_NONE"], 0])

    def test_nonmatching_blackbelt_trainer_uses_class_offense_default(self):
        self.prime(("TACKLE", "GROWL"))
        self.h.write8("wTrainerClass", self.trainer_classes["BLACKBELT"])
        self.h.write8("wTrainerNo", 2)
        self.call("AIRunPersonality")
        self.assertEqual(self.scores()[:2], [
            self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
            self.ai["AI_SCORE_BASE"],
        ])

    def test_blackbelt_reliable_ko_stays_selected_in_full_dispatch(self):
        records = self.h.hook_ai_scores()
        neutral = self.dispatch(records, ("TACKLE", "GROWL"),
                                self.trainer_classes["COOLTRAINER_M"],
                                tier=2, player_hp=1)
        blackbelt = self.dispatch(records, ("TACKLE", "GROWL"),
                                  self.trainer_classes["BLACKBELT"],
                                  tier=2, player_hp=1)
        self.assertEqual(neutral["candidates"], [self.moves["TACKLE"]])
        self.assertEqual(blackbelt["candidates"], [self.moves["TACKLE"]])
        self.assertEqual(blackbelt["eligible_slots"], [0])
        self.assertLess(blackbelt["scores"][0], neutral["scores"][0])

    def test_blackbelt_does_not_resurrect_immune_or_redundant_damage(self):
        records = self.h.hook_ai_scores()
        cases = (
            ("immune normal move", ("TACKLE", "EMBER"), 1,
             (self.types["GHOST"], self.types["GHOST"])),
            ("redundant Dream Eater", ("DREAM_EATER", "TACKLE"), 0, None),
        )
        for label, moves, tier, player_types in cases:
            with self.subTest(case=label):
                neutral = self.dispatch(records, moves,
                                        self.trainer_classes["COOLTRAINER_M"],
                                        tier=tier, player_types=player_types)
                blackbelt = self.dispatch(records, moves,
                                          self.trainer_classes["BLACKBELT"],
                                          tier=tier, player_types=player_types)
                self.assertEqual(neutral["eligible_slots"], [1])
                self.assertEqual(blackbelt["eligible_slots"], [1])
                self.assertEqual(blackbelt["candidates"], [self.moves[moves[1]]])

    def test_blackbelt_keeps_disabled_damaging_move_excluded(self):
        records = self.h.hook_ai_scores()
        blackbelt = self.dispatch(records, ("TACKLE", "EMBER"),
                                  self.trainer_classes["BLACKBELT"],
                                  disabled_slot=0)
        self.assertEqual(blackbelt["scores"][0], self.ai["AI_SCORE_DISABLED"])
        self.assertEqual(blackbelt["candidates"], [self.moves["EMBER"]])
        self.assertEqual(blackbelt["eligible_slots"], [1])

    def test_blackbelt_does_not_overturn_stronger_setup_score(self):
        records = self.h.hook_ai_scores()
        neutral = self.dispatch(records, ("TACKLE", "SWORDS_DANCE"),
                                self.trainer_classes["COOLTRAINER_M"], tier=1)
        blackbelt = self.dispatch(records, ("TACKLE", "SWORDS_DANCE"),
                                  self.trainer_classes["BLACKBELT"], tier=1)
        self.assertEqual(neutral["candidates"], [self.moves["SWORDS_DANCE"]])
        self.assertEqual(blackbelt["candidates"], [self.moves["SWORDS_DANCE"]])
        self.assertLess(blackbelt["scores"][1], blackbelt["scores"][0])


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


    def test_full_dispatch_changes_blackbelt_candidates_and_records_profile_cycles(self):
        h = self.h
        decisions = h.hook_ai_scores()
        personality_timing = h.hook_ai_personality_timing()
        baseline = BytesIO()
        h.save_state(baseline)

        def dispatch(trainer_class):
            h.load_state(baseline)
            h.write8("wEnemyMonMoves", self.moves["TACKLE"], offset=0)
            h.write8("wEnemyMonMoves", self.moves["GROWL"], offset=1)
            h.write8("wEnemyMonMoves", 0, offset=2)
            h.write8("wEnemyMonMoves", 0, offset=3)
            h.write8("wTrainerClass", trainer_class)
            h.write8("wAITier", 1)  # tier 0: isolates the personality nudge
            h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
            return list(h.read_bytes("wBuffer", 4))

        neutral_candidates = dispatch(self.trainer_classes["COOLTRAINER_M"])
        profile_candidates = dispatch(self.trainer_classes["BLACKBELT"])

        self.assertEqual(
            neutral_candidates[:2], [self.moves["TACKLE"], self.moves["GROWL"]]
        )
        self.assertEqual(profile_candidates[:2], [self.moves["TACKLE"], 0])
        self.assertEqual(neutral_candidates[2:], [0, 0])
        self.assertEqual(profile_candidates[2:], [0, 0])
        self.assertEqual(len(decisions), 2)
        self.assertEqual(decisions[0]["eligible_slots"], [0, 1])
        self.assertEqual(decisions[1]["eligible_slots"], [0])
        self.assertEqual(len(personality_timing), 2)
        self.assertEqual(
            [record["trainer_class"] for record in personality_timing],
            [
                self.trainer_classes["COOLTRAINER_M"],
                self.trainer_classes["BLACKBELT"],
            ],
        )
        self.assertGreater(personality_timing[0]["cycles"], 0)
        self.assertGreater(personality_timing[1]["cycles"], 0)


if __name__ == "__main__":
    unittest.main()