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
        self.battle_bits = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")

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

    def dispatch(
        self, records, move_names, trainer_class, *, trainer_no=1, tier=0,
        disabled_slot=None, player_types=None, player_hp=None, player_status=0,
        enemy_hp=None, rng_seed=None, cached_profile=None,
    ):
        """Run the production chooser from the same parked FIGHT 2 state."""
        h = self.h
        h.load_state(self.battle_state)
        for slot in range(4):
            name = move_names[slot] if slot < len(move_names) else None
            h.write8("wEnemyMonMoves", self.moves[name] if name else 0, offset=slot)
        h.write8("wTrainerClass", trainer_class)
        h.write8("wTrainerNo", trainer_no)
        h.write8("wAIRandomPersonality", 0)
        if cached_profile is not None:
            h.write8("wAIRandomPersonality", cached_profile + 1)
        h.write8("wAITier", tier + 1)
        h.write8("wAILayer2Encouragement", 0)
        h.write8("wEnemyDisabledMove", 0)
        h.write8("wBattleMonStatus", player_status)
        if disabled_slot is not None:
            h.write8("wEnemyDisabledMove", ((disabled_slot + 1) << 4) | 1)
        if player_types is not None:
            h.write8("wBattleMonType1", player_types[0])
            h.write8("wBattleMonType2", player_types[1])
        if player_hp is not None:
            h.write8("wBattleMonHP", player_hp >> 8)
            h.write8("wBattleMonHP", player_hp & 0xFF, offset=1)
        if enemy_hp is not None:
            current_hp, max_hp = enemy_hp
            h.write8("wEnemyMonHP", current_hp >> 8)
            h.write8("wEnemyMonHP", current_hp & 0xFF, offset=1)
            h.write8("wEnemyMonMaxHP", max_hp >> 8)
            h.write8("wEnemyMonMaxHP", max_hp & 0xFF, offset=1)
        if rng_seed is not None:
            h.seed_rng(rng_seed)
        h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
        scored = records[-1]
        return {
            "scores": scored["scores"],
            "eligible_slots": scored["eligible_slots"],
            "candidates": [move for move in h.read_bytes("wBuffer", 4) if move],
        }

    def dispatch_profile(self, records, move_names, trainer_class, profile, **kwargs):
        """Dispatch with a fixed profile cache for deterministic AI fixtures."""
        return self.dispatch(
            records, move_names, trainer_class, trainer_no=2,
            cached_profile=profile, **kwargs,
        )

    def scores(self):
        return list(self.h.read_bytes("wBuffer", 4))


    def call_counting_random(self, routine):
        """Count generator calls while the injected routine executes."""
        bank, address = self.h.symbols.get("Random")
        calls = {"value": 0}

        def count(_context):
            calls["value"] += 1

        self.h.pyboy.hook_register(bank, address, count, None)
        try:
            self.h.call_routine(routine, limit=1200)
        finally:
            self.h.pyboy.hook_deregister(bank, address)
        return calls["value"]

    def prime_cached_personality(self, move_names, trainer_class, trainer_no, profile):
        """Inject the staged battle cache to exercise a retained soft style."""
        self.prime(move_names)
        self.h.write8("wTrainerClass", trainer_class)
        self.h.write8("wTrainerNo", trainer_no)
        self.h.write8("wAIRandomPersonality", profile + 1)
        self.h.write8("wLinkState", 0)

    def call(self, routine):
        # boot_fight2 already parks safely; do not tick after priming test state.
        self.h.call_routine(routine, limit=240)

    def test_blackbelt_karate_master_exact_override_is_neutral(self):
        self.prime()
        self.h.write8("wTrainerClass", self.trainer_classes["BLACKBELT"])
        self.h.write8("wTrainerNo", 1)
        self.h.write8("wAIRandomPersonality", 0)
        self.h.seed_rng((17, 29, 43, 71))
        random_calls = self.call_counting_random("AIRunPersonality")
        self.assertEqual(self.scores(), [self.ai["AI_SCORE_BASE"]] * 4)
        self.assertEqual(self.h.read8("wAIRandomPersonality"), 0)
        self.assertEqual(random_calls, 1)  # VBlank only, no personality roll
    def test_blackbelt_live_resolver_nudges_damaging_and_fixed_damage_moves(self):
        self.prime_cached_personality(
            ("TACKLE", "GROWL", "NIGHT_SHADE", "TAIL_WHIP"),
            self.trainer_classes["BLACKBELT"], 2,
            self.ai["AI_PERSONALITY_OFFENSE"],
        )
        self.h.write8("wBuffer", self.ai["AI_SCORE_DISABLED"], offset=0)
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
        self.prime_cached_personality(
            ("NIGHT_SHADE", "BIDE", "GROWL"),
            self.trainer_classes["BLACKBELT"], 2,
            self.ai["AI_PERSONALITY_OFFENSE"],
        )
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
        self.prime_cached_personality(
            ("TACKLE",), self.trainer_classes["BLACKBELT"], 2,
            self.ai["AI_PERSONALITY_OFFENSE"],
        )
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

    def test_ordinary_random_assignment_is_disabled_but_cached_styles_remain(self):
        h = self.h
        self.assertEqual(self.ai["AI_RANDOM_PERSONALITIES_ENABLED"], 0)
        for trainer_name in ("YOUNGSTER", "BLACKBELT", "PSYCHIC_TR"):
            with self.subTest(trainer_class=trainer_name):
                h.write8("wTrainerClass", self.trainer_classes[trainer_name])
                h.write8("wTrainerNo", 2)
                h.write8("wAIRandomPersonality", 0)
                h.write8("wLinkState", 0)
                random_calls = self.call_counting_random("AISoftPersonalityTestResolve")
                self.assertEqual(h.read8("wBuffer"), self.ai["AI_PERSONALITY_NONE"])
                self.assertEqual(h.read8("wAIRandomPersonality"), 0)
                self.assertEqual(random_calls, 1)  # ambient VBlank draw only

        for profile in (
            self.ai["AI_PERSONALITY_OFFENSE"],
            self.ai["AI_PERSONALITY_CONTROL"],
            self.ai["AI_PERSONALITY_DEFENSIVE"],
        ):
            h.write8("wTrainerClass", self.trainer_classes["BLACKBELT"])
            h.write8("wTrainerNo", 2)
            h.write8("wAIRandomPersonality", profile + 1)
            h.call_routine("AISoftPersonalityTestResolve", limit=1200)
            self.assertEqual(h.read8("wBuffer"), profile)
    def test_special_classes_remain_neutral_without_random_assignment(self):
        h = self.h
        excluded = (
            "GAMBLER", "NURSE_JOY", "OFFICER_JENNY", "RIVAL1", "RIVAL2",
            "RIVAL3", "PROF_OAK", "GIOVANNI", "BRUNO", "BROCK", "MISTY",
            "LT_SURGE", "ERIKA", "KOGA", "BLAINE", "SABRINA", "LORELEI",
            "AGATHA", "LANCE", "RIVAL_MINIBOSS", "GIOVANNI_MINIBOSS",
            "JESSIE_JAMES", "FALKNER", "BUGSY", "WHITNEY", "MORTY", "CHUCK",
            "JASMINE", "PRYCE", "CLAIR", "JANINE", "WILL", "KAREN", "KOGA_E4",
            "FINAL_AI", "KARATE_MINIBOSS",
        )
        rng_seed = (23, 51, 79, 107)
        for name in excluded:
            with self.subTest(trainer_class=name):
                h.write8("wTrainerClass", self.trainer_classes[name])
                h.write8("wTrainerNo", 1)
                h.write8("wAIRandomPersonality", 0)
                h.write8("wLinkState", 0)
                h.seed_rng(rng_seed)
                random_calls = self.call_counting_random("AISoftPersonalityTestResolve")
                self.assertEqual(h.read8("wBuffer"), self.ai["AI_PERSONALITY_NONE"])
                self.assertEqual(h.read8("wAIRandomPersonality"), 0)
                self.assertEqual(random_calls, 1)  # ambient VBlank draw only


    def test_blackbelt_reliable_ko_stays_selected_in_full_dispatch(self):
        records = self.h.hook_ai_scores()
        neutral = self.dispatch(records, ("TACKLE", "GROWL"),
                                self.trainer_classes["BLACKBELT"],
                                trainer_no=1, tier=2, player_hp=1)
        blackbelt = self.dispatch_profile(
            records, ("TACKLE", "GROWL"), self.trainer_classes["BLACKBELT"],
            self.ai["AI_PERSONALITY_OFFENSE"], tier=2, player_hp=1,
        )
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
                                        self.trainer_classes["BLACKBELT"],
                                        tier=tier, player_types=player_types)
                blackbelt = self.dispatch_profile(
                    records, moves, self.trainer_classes["BLACKBELT"],
                    self.ai["AI_PERSONALITY_OFFENSE"],
                    tier=tier, player_types=player_types,
                )
                self.assertEqual(neutral["eligible_slots"], [1])
                self.assertEqual(blackbelt["eligible_slots"], [1])
                self.assertEqual(blackbelt["candidates"], [self.moves[moves[1]]])

    def test_blackbelt_keeps_disabled_damaging_move_excluded(self):
        records = self.h.hook_ai_scores()
        blackbelt = self.dispatch_profile(
            records, ("TACKLE", "EMBER"), self.trainer_classes["BLACKBELT"],
            self.ai["AI_PERSONALITY_OFFENSE"], disabled_slot=0,
        )
        self.assertEqual(blackbelt["scores"][0], self.ai["AI_SCORE_DISABLED"])
        self.assertEqual(blackbelt["candidates"], [self.moves["EMBER"]])
        self.assertEqual(blackbelt["eligible_slots"], [1])

    def test_blackbelt_does_not_overturn_stronger_setup_score(self):
        records = self.h.hook_ai_scores()
        neutral = self.dispatch(records, ("TACKLE", "SWORDS_DANCE"),
                                self.trainer_classes["BLACKBELT"], tier=1)
        blackbelt = self.dispatch_profile(
            records, ("TACKLE", "SWORDS_DANCE"),
            self.trainer_classes["BLACKBELT"], self.ai["AI_PERSONALITY_OFFENSE"],
            tier=1,
        )
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

        def dispatch(trainer_no, cached_profile=None):
            h.load_state(baseline)
            h.write8("wEnemyMonMoves", self.moves["TACKLE"], offset=0)
            h.write8("wEnemyMonMoves", self.moves["GROWL"], offset=1)
            h.write8("wEnemyMonMoves", 0, offset=2)
            h.write8("wEnemyMonMoves", 0, offset=3)
            h.write8("wTrainerClass", self.trainer_classes["BLACKBELT"])
            h.write8("wTrainerNo", trainer_no)
            h.write8("wAIRandomPersonality", 0)
            if cached_profile is not None:
                h.write8("wAIRandomPersonality", cached_profile + 1)
            h.write8("wAITier", 1)  # tier 0: isolates the personality nudge
            h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
            return list(h.read_bytes("wBuffer", 4))

        neutral_candidates = dispatch(1)
        profile_candidates = dispatch(2, self.ai["AI_PERSONALITY_OFFENSE"])

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
                self.trainer_classes["BLACKBELT"],
                self.trainer_classes["BLACKBELT"],
            ],
        )
        self.assertGreater(personality_timing[0]["cycles"], 0)
        self.assertGreater(personality_timing[1]["cycles"], 0)


    def test_hiker_defensive_profile_uses_state_and_score_guards(self):
        h = self.h
        hiker = self.trainer_classes["HIKER"]

        def run(moves, current_hp, max_hp=600, *, status2=0, status3=0,
                scores=None, defense_at_cap=False):
            h.load_state(self.battle_state)
            self.prime(moves)
            h.write8("wTrainerClass", hiker)
            h.write8("wTrainerNo", 1)
            h.write8("wEnemyMonHP", current_hp >> 8)
            h.write8("wEnemyMonHP", current_hp & 0xFF, offset=1)
            h.write8("wEnemyMonMaxHP", max_hp >> 8)
            h.write8("wEnemyMonMaxHP", max_hp & 0xFF, offset=1)
            h.write8("wEnemyBattleStatus2", status2)
            h.write8("wEnemyBattleStatus3", status3)
            if defense_at_cap:
                h.write8("wEnemyMonStatMods", 13, offset=1)
            if scores is not None:
                for slot, score in enumerate(scores):
                    h.write8("wBuffer", score, offset=slot)
            self.call("AIRunPersonality")
            return self.scores()

        base = self.ai["AI_SCORE_BASE"]
        nudge = self.ai["AI_NUDGE"]
        neutral = [base] * 4
        self.assertEqual(run(("RECOVER",), 200), [base - nudge, *neutral[1:]])
        self.assertEqual(run(("RECOVER",), 400), neutral)

        screens = (
            1 << self.battle_bits["HAS_LIGHT_SCREEN_UP"]
        ) | (
            1 << self.battle_bits["HAS_REFLECT_UP"]
        )
        self.assertEqual(
            run(("LIGHT_SCREEN", "REFLECT"), 600),
            [base - nudge, base - nudge, base, base],
        )
        self.assertEqual(run(("LIGHT_SCREEN", "REFLECT"), 400), neutral)
        self.assertEqual(
            run(("LIGHT_SCREEN", "REFLECT"), 600, status3=screens), neutral
        )

        self.assertEqual(run(("BARRIER",), 400), [base - nudge, *neutral[1:]])
        self.assertEqual(run(("BARRIER",), 200), neutral)
        self.assertEqual(run(("BARRIER",), 400, defense_at_cap=True), neutral)

        self.assertEqual(
            run(("SUBSTITUTE",), 400),
            [base - nudge, *neutral[1:]],
        )
        self.assertEqual(run(("SUBSTITUTE",), 75, max_hp=100), neutral)
        self.assertEqual(run(("SUBSTITUTE",), 200), neutral)
        self.assertEqual(
            run(
                ("SUBSTITUTE",), 400,
                status2=1 << self.battle_bits["HAS_SUBSTITUTE_UP"],
            ),
            neutral,
        )

        eligible = ("LIGHT_SCREEN", "REFLECT", "BARRIER", "SUBSTITUTE")
        self.assertEqual(
            run(eligible, 600, scores=[79, 80, 79, 80]),
            [79, 80, 79, 80],
        )
        self.assertEqual(
            run(("RECOVER",), 200, scores=[79, 80, 79, 80]),
            [79, 80, 79, 80],
        )

    def test_hiker_dispatch_nudges_defense_and_respects_tactical_scores(self):
        decisions = self.h.hook_ai_scores()
        timings = self.h.hook_ai_personality_timing()
        neutral = self.dispatch(
            decisions, ("TACKLE", "BARRIER"),
            self.trainer_classes["BLACKBELT"], tier=0,
            enemy_hp=(600, 600),
        )
        hiker = self.dispatch(
            decisions, ("TACKLE", "BARRIER"),
            self.trainer_classes["HIKER"], tier=0,
            enemy_hp=(600, 600),
        )
        self.assertEqual(neutral["eligible_slots"], [0, 1])
        self.assertEqual(hiker["candidates"], [self.moves["BARRIER"]])
        self.assertEqual(hiker["eligible_slots"], [1])
        self.assertEqual(len(timings), 2)
        self.assertEqual(
            [record["trainer_class"] for record in timings],
            [
                self.trainer_classes["BLACKBELT"],
                self.trainer_classes["HIKER"],
            ],
        )
        self.assertGreater(timings[1]["cycles"], 0)
        self.assertLess(timings[1]["cycles"], 70224)

        ko = self.dispatch(
            decisions, ("TACKLE", "RECOVER"),
            self.trainer_classes["HIKER"], tier=2, player_hp=1,
            enemy_hp=(200, 600),
        )
        self.assertEqual(ko["candidates"], [self.moves["TACKLE"]])
        self.assertEqual(ko["eligible_slots"], [0])

        neutral_plan = self.dispatch(
            decisions, ("BARRIER", "SWORDS_DANCE"),
            self.trainer_classes["BLACKBELT"], tier=1,
            enemy_hp=(600, 600),
        )
        hiker_plan = self.dispatch(
            decisions, ("BARRIER", "SWORDS_DANCE"),
            self.trainer_classes["HIKER"], tier=1,
            enemy_hp=(600, 600),
        )
        self.assertTrue(neutral_plan["candidates"])
        self.assertEqual(hiker_plan["candidates"], neutral_plan["candidates"])

    def test_psychic_profile_favors_disruption_not_setup_healing_or_empty_slots(self):
        self.prime_cached_personality(
            ("TACKLE", "HYPNOSIS", "CONFUSE_RAY", "SWORDS_DANCE"),
            self.trainer_classes["PSYCHIC_TR"], 2,
            self.ai["AI_PERSONALITY_CONTROL"],
        )
        self.call("AIRunPersonality")
        self.assertEqual(self.scores(), [
            self.ai["AI_SCORE_BASE"],
            self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
            self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
            self.ai["AI_SCORE_BASE"],
        ])

        self.prime_cached_personality(
            ("DISABLE", "LEECH_SEED", "BODY_SLAM", "RECOVER"),
            self.trainer_classes["PSYCHIC_TR"], 2,
            self.ai["AI_PERSONALITY_CONTROL"],
        )
        self.call("AIRunPersonality")
        self.assertEqual(self.scores(), [
            self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
            self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
            self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
            self.ai["AI_SCORE_BASE"],
        ])

        self.prime_cached_personality(
            ("HYPNOSIS",), self.trainer_classes["PSYCHIC_TR"], 2,
            self.ai["AI_PERSONALITY_CONTROL"],
        )
        self.call("AIRunPersonality")
        self.assertEqual(self.scores(), [
            self.ai["AI_SCORE_BASE"] - self.ai["AI_NUDGE"],
            self.ai["AI_SCORE_BASE"],
            self.ai["AI_SCORE_BASE"],
            self.ai["AI_SCORE_BASE"],
        ])

    def test_psychic_full_dispatch_selects_hypnosis_and_records_profile_timing(self):
        decisions = self.h.hook_ai_scores()
        timings = self.h.hook_ai_personality_timing()
        neutral = self.dispatch(
            decisions, ("TACKLE", "HYPNOSIS"),
            self.trainer_classes["BLACKBELT"], tier=0,
        )
        psychic = self.dispatch_profile(
            decisions, ("TACKLE", "HYPNOSIS"),
            self.trainer_classes["PSYCHIC_TR"],
            self.ai["AI_PERSONALITY_CONTROL"], tier=0,
        )
        self.assertEqual(neutral["eligible_slots"], [0, 1])
        self.assertEqual(psychic["eligible_slots"], [1])
        self.assertEqual(psychic["candidates"], [self.moves["HYPNOSIS"]])
        self.assertEqual([record["trainer_class"] for record in timings], [
            self.trainer_classes["BLACKBELT"],
            self.trainer_classes["PSYCHIC_TR"],
        ])
        self.assertGreater(timings[0]["cycles"], 0)
        self.assertGreater(timings[1]["cycles"], timings[0]["cycles"])
        self.assertLess(timings[1]["cycles"], 70224)  # under one DMG frame

    def test_psychic_control_does_not_overturn_a_reliable_ko(self):
        decisions = self.h.hook_ai_scores()
        neutral = self.dispatch(
            decisions, ("TACKLE", "HYPNOSIS"),
            self.trainer_classes["BLACKBELT"], tier=2, player_hp=1,
        )
        psychic = self.dispatch_profile(
            decisions, ("TACKLE", "HYPNOSIS"),
            self.trainer_classes["PSYCHIC_TR"],
            self.ai["AI_PERSONALITY_CONTROL"], tier=2, player_hp=1,
        )
        self.assertEqual(neutral["candidates"], [self.moves["TACKLE"]])
        self.assertEqual(psychic["candidates"], [self.moves["TACKLE"]])
        self.assertEqual(psychic["eligible_slots"], [0])

    def test_psychic_control_respects_status_redundancy_immunity_and_disabled_moves(self):
        decisions = self.h.hook_ai_scores()
        cases = (
            ("sleep already present", ("TACKLE", "HYPNOSIS"), 0, None, 1, None),
            ("paralysis immunity", ("TACKLE", "THUNDER_WAVE"), 0,
             (self.types["GROUND"], self.types["GROUND"]), 0, None),
            ("disabled hypnosis", ("TACKLE", "HYPNOSIS"), 0, None, 0, 1),
        )
        for label, moves, tier, player_types, player_status, disabled_slot in cases:
            with self.subTest(case=label):
                psychic = self.dispatch_profile(
                    decisions, moves, self.trainer_classes["PSYCHIC_TR"],
                    self.ai["AI_PERSONALITY_CONTROL"],
                    tier=tier, player_types=player_types,
                    player_status=player_status, disabled_slot=disabled_slot,
                )
                self.assertEqual(psychic["candidates"], [self.moves[moves[0]]])
                self.assertEqual(psychic["eligible_slots"], [0])
                if disabled_slot is not None:
                    self.assertEqual(psychic["scores"][disabled_slot],
                                     self.ai["AI_SCORE_DISABLED"])

    def test_psychic_control_preserves_stronger_setup_choice(self):
        decisions = self.h.hook_ai_scores()
        neutral = self.dispatch(
            decisions, ("TACKLE", "SWORDS_DANCE"),
            self.trainer_classes["BLACKBELT"], tier=1,
        )
        psychic = self.dispatch_profile(
            decisions, ("TACKLE", "SWORDS_DANCE"),
            self.trainer_classes["PSYCHIC_TR"],
            self.ai["AI_PERSONALITY_CONTROL"], tier=1,
        )
        self.assertEqual(neutral["candidates"], [self.moves["SWORDS_DANCE"]])
        self.assertEqual(psychic["candidates"], [self.moves["SWORDS_DANCE"]])
        self.assertEqual(neutral["scores"], psychic["scores"])

if __name__ == "__main__":
    unittest.main()