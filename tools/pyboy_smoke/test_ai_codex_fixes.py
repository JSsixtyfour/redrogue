"""Codex follow-up fixes F1, F3-F5, F7, F8 (2026-10-21). F2 lives in test_ai_pp_economy.py.

Each test was written to fail on the pre-fix ROM; the shipped behaviour it
catches is named in the test's comment. Spec: AI_REVIEW_2026-10-21_CODEX_FIXES_SPEC.md.
"""
from __future__ import annotations

import unittest

from test_ai_heuristic_gaps import _AIGapsBase, _MoveLayerGapsBase


class SmartLoopBoundTest(_MoveLayerGapsBase):
    """F1: AISmartCrossCutting leaves the move id in b, which AILayerSmart's
    `dec b / ret z` counter then mistook for the slot counter."""

    def smart_visits(self, moves):
        h = self.h
        visits = h.hook_flag("AISmartCrossCutting")
        self.prime_clean()
        self.load_moveset(moves)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.call_routine("AILayerSmart", limit=2400)
        return visits["count"]

    def test_full_moveset_visits_exactly_four_slots(self):
        # shipped: 7 (walked on into the DVs, level and max HP)
        self.assertEqual(self.smart_visits(["TACKLE", "GROWL", "BITE", "SURF"]), 4)

    def test_pound_does_not_truncate_the_loop(self):
        # shipped: 1 (Pound is move id 1, so the next `dec b` returned)
        self.assertEqual(self.smart_visits(["POUND", "GROWL", "BITE", "SURF"]), 4)

    def test_slot_after_pound_is_scored(self):
        # shipped: Hypnosis (75% accurate) stays at baseline because it is never visited
        h = self.h
        self.prime_clean()
        self.load_moveset(["POUND", "HYPNOSIS"])
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.call_routine("AILayerSmart", limit=2400)
        self.assertNotEqual(h.read8("wBuffer", 1), 20)


class PhysicalOwnershipTest(_MoveLayerGapsBase):
    """F3: the setup gate counts only live attacks that scale with Attack."""

    def owns_physical(self, moves, pp=None, disabled_slot=None):
        h = self.h
        self.prime_clean()
        self.load_moveset(moves)
        for slot, value in (pp or {}).items():
            h.write8("wEnemyMonPP", value, offset=slot)
        if disabled_slot is not None:
            h.write8("wEnemyDisabledMove", ((disabled_slot + 1) << 4) | 1)
        h.call_routine("AIOwnsPhysicalMove", limit=1200)
        return h.read8("wBuffer", self.ai["AI_BUF_PHYSICAL"])

    def test_control_live_physical_attack(self):
        self.assertEqual(self.owns_physical(["TACKLE", "SWORDS_DANCE"]), 1)

    def test_fixed_damage_only_is_not_physical(self):
        # shipped: 1 (Seismic Toss has power 1, which `and a` accepted)
        self.assertEqual(self.owns_physical(["SEISMIC_TOSS", "SWORDS_DANCE"]), 0)

    def test_exhausted_attack_is_not_physical(self):
        # shipped: 1
        self.assertEqual(self.owns_physical(["TACKLE", "SWORDS_DANCE"], pp={0: 0}), 0)

    def test_disabled_attack_is_not_physical(self):
        # shipped: 1
        self.assertEqual(self.owns_physical(["TACKLE", "SWORDS_DANCE"], disabled_slot=0), 0)

    def test_dead_first_slot_does_not_hide_a_live_one(self):
        self.assertEqual(self.owns_physical(["TACKLE", "BODY_SLAM"], pp={0: 0}), 1)


class RiskyChargeDeliveryTest(_AIGapsBase):
    """F4: a charge move delivers nothing this turn, so it is no guaranteed win."""

    def reaches_no_guaranteed_win(self, moves):
        h = self.h
        self.boot([self.mon("RATTATA", ["TACKLE"], level=60)],
                  [self.mon("TAUROS", moves)], tier=2)
        h.reveal_player_moves(0, [0], clear=True)
        h.park_before_hijack()
        self.word("wEnemyMonHP", 1)
        self.word("wEnemyMonMaxHP", 200)
        self.word("wBattleMonHP", 1)
        self.word("wBattleMonMaxHP", 200)
        self.word("wEnemyMonSpeed", 200)
        self.word("wBattleMonSpeed", 100)
        for slot in range(4):
            h.write8("wEnemyMonMoves", self.moves[moves[slot]] if slot < len(moves) else 0,
                     offset=slot)
            h.write8("wEnemyMonPP", 15, offset=slot)
            h.write8("wBuffer", 20, offset=slot)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_EMPTY"])
        reached = h.hook_flag("AILayerRisky.noGuaranteedWin")
        h.call_routine("AILayerRisky", limit=480)
        return reached["count"]

    def test_control_immediate_reliable_ko_silences_risky(self):
        self.assertEqual(self.reaches_no_guaranteed_win(["KARATE_CHOP", "GROWL"]), 0)

    def test_charge_move_does_not_silence_risky(self):
        # shipped: 0 (Solar Beam's eventual KO counted as a win this turn)
        self.assertEqual(self.reaches_no_guaranteed_win(["SOLARBEAM", "GROWL"]), 1)

    def test_fly_does_not_silence_risky(self):
        self.assertEqual(self.reaches_no_guaranteed_win(["FLY", "GROWL"]), 1)


class ScreenNoDamagingMoveTest(_MoveLayerGapsBase):
    """F5: a player who shows only fixed-damage moves gives no screen a reason."""

    def screen_score(self, move, player_move):
        self.h.reveal_player_moves(0, [0], clear=True)
        return self.smart_score(move, {"wBattleMonMoves": self.moves[player_move],
                                       "wEnemyMonHP": (200,)})

    def test_light_screen_against_fixed_damage_only_is_unchanged(self):
        # shipped: 19 (read as a special threat)
        self.assertEqual(self.screen_score("LIGHT_SCREEN", "SEISMIC_TOSS"), 20)

    def test_reflect_against_fixed_damage_only_is_unchanged(self):
        # shipped: 22 (wrong category)
        self.assertEqual(self.screen_score("REFLECT", "SEISMIC_TOSS"), 20)

    def test_controls_physical_and_special_still_match(self):
        self.assertEqual(self.screen_score("REFLECT", "BODY_SLAM"), 19)
        self.assertEqual(self.screen_score("LIGHT_SCREEN", "PSYCHIC_M"), 19)


class TypesAlternativeLiveTest(_MoveLayerGapsBase):
    """F7: AI_TYPES does not call a dead move a better alternative."""

    def resisted_score(self, tackle_pp):
        h = self.h
        self.prime_clean()
        h.write8("wBattleMonType1", self.types["WATER"])
        h.write8("wBattleMonType2", self.types["WATER"])
        self.load_moveset(["WATER_GUN", "TACKLE"])
        h.write8("wEnemyMonPP", tackle_pp, offset=1)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.call_routine("AIMoveChoiceModification3", limit=240)
        return h.read8("wBuffer")

    def test_control_live_alternative_discourages_the_resisted_move(self):
        self.assertEqual(self.resisted_score(15), 21)

    def test_exhausted_alternative_leaves_the_resisted_move_alone(self):
        # shipped: 21
        self.assertEqual(self.resisted_score(0), 20)


class AnyScoreBelowBaselineTest(_MoveLayerGapsBase):
    """F8: a dead slot's low score is not a real preference."""

    def below_baseline(self, scores, dead_slot=None):
        h = self.h
        self.prime_clean()
        self.load_moveset(["TACKLE", "GROWL", "BITE", "SURF"])
        if dead_slot is not None:
            h.write8("wEnemyMonPP", 0, offset=dead_slot)
        for slot, value in enumerate(scores):
            h.write8("wBuffer", value, offset=slot)
        yes = h.hook_flag("AIAnyScoreBelowBaseline.yes")
        h.call_routine("AIAnyScoreBelowBaseline", limit=240)
        return yes["count"]

    def test_control_live_low_score_counts(self):
        self.assertEqual(self.below_baseline([20, 20, 15, 20]), 1)

    def test_dead_slot_low_score_is_ignored(self):
        # shipped: 1
        self.assertEqual(self.below_baseline([20, 20, 15, 20], dead_slot=2), 0)

    def test_all_baseline_is_no(self):
        self.assertEqual(self.below_baseline([20, 20, 20, 20]), 0)


if __name__ == "__main__":
    unittest.main()
