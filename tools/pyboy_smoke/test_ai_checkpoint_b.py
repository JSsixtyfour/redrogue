"""Runtime regression fixtures for AI review checkpoint B contracts."""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class AICheckpointBTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.effects = parse_rgbds_constants(ROOT / "constants/move_effect_constants.asm")
        self.battle = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")
        self.types = parse_rgbds_constants(ROOT / "constants/type_constants.asm")
        self.ram = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")
        self.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        self.pokemon_data = parse_rgbds_constants(
            ROOT / "constants/pokemon_data_constants.asm"
        )
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

        def mon(name, moves):
            return {
                "species": self.species[name],
                "level": 50,
                "moves": [self.moves[move] for move in moves],
            }

        self.h.inject_fight2_spec(
            [mon("SNORLAX", ["SPLASH"])],
            [mon("TAUROS", ["TACKLE"])],
            trainer_class=trainers["COOLTRAINER_M"],
            ai_tier=2,
        )
        self.h.boot_fight2(seed=1)

    def tearDown(self):
        self.h.close()

    def word(self, label, value):
        self.h.write8(label, value >> 8)
        self.h.write8(label, value & 255, offset=1)

    def load_enemy_move(self, name):
        h = self.h
        bank, address = h.symbols.get("Moves")
        offset = bank * 0x4000 + address - 0x4000 + (self.moves[name] - 1) * 6
        data = (ROOT / "pokeblue_debug.gbc").read_bytes()[offset:offset + 6]
        for index, value in enumerate(data):
            h.write8("wEnemyMoveNum", value, offset=index)

    def estimate(self, name, crit=False):
        h = self.h
        h.park_before_hijack()
        self.load_enemy_move(name)
        h.call_routine("AIEstimateDamage", limit=120)
        if crit:
            h.park_before_hijack()
            h.call_routine("AIScaleDamageForCrit", limit=120)
        return int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big")

    def test_crit_expectation_cannot_invent_an_ordinary_hit_ko(self):
        h = self.h
        raw = self.estimate("TACKLE")
        weighted = self.estimate("TACKLE", crit=True)
        self.assertGreater(weighted, raw)

        # Put the target immediately above the maximum ordinary hit but below
        # the crit-weighted ranking value. Before R5 this received AI_KILL.
        hp = raw + 1
        self.assertLessEqual(hp, weighted)
        self.word("wBattleMonHP", hp)
        h.write8("wEnemyMonMoves", self.moves["TACKLE"])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)

        h.park_before_hijack()
        h.call_routine("AILayerDamage", limit=240)

        # Expected-value ranking still sees a strong hit and the best-damage
        # nudge, but the raw noncritical bound cannot earn the five-point kill.
        self.assertEqual(h.read8("wBuffer"), 17)
    def single_move_damage_score(self, move, player_hp):
        """AI_DAMAGE's score for a lone move against a given player HP.

        From 20: 10 = reliable kill that acts first (AI_KILL_FIRST 9 + best
        nudge 1; Tauros outspeeds Snorlax), 17 = unreliable kill or a strong
        hit (AI_STRONG 2 + best nudge 1).
        """
        h = self.h
        self.word("wBattleMonHP", player_hp)
        h.write8("wEnemyMonMoves", self.moves[move])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.park_before_hijack()
        h.call_routine("AILayerDamage", limit=240)
        return h.read8("wBuffer")

    def test_kill_needing_a_high_roll_is_not_reliable(self):
        # Review F4 (2026-09-29): only the maximum roll reaches here.
        raw = self.estimate("TACKLE")
        self.assertEqual(self.single_move_damage_score("TACKLE", raw), 17)

    def test_minimum_roll_kill_is_reliable(self):
        raw = self.estimate("TACKLE")
        self.assertEqual(self.single_move_damage_score("TACKLE", raw * 217 // 255), 10)

    def test_multihit_kill_needing_three_hits_is_not_reliable(self):
        # Review F2 (2026-09-29): 2 hits cannot reach, 5 can - a 1-in-8 kill
        # used to score as a sure one (10).
        raw = self.estimate("SPIKE_CANNON")
        self.assertEqual(self.single_move_damage_score("SPIKE_CANNON", 3 * raw), 17)

    def test_multihit_kill_within_two_minimum_hits_is_reliable(self):
        raw = self.estimate("SPIKE_CANNON")
        guaranteed = 2 * (raw * 217 // 255)
        self.assertEqual(self.single_move_damage_score("SPIKE_CANNON", guaranteed), 10)

    def smart_scores_by_speed(self, move, boards, extra=None):
        """AI_SMART score (from 20, before cross-cutting rules) of a lone move
        for each (our Speed, player Speed) board. Unmodified Speed matches the
        live value and both Speed stages are neutral, so stage predictions
        (Speed control) start from the same numbers the board shows."""
        h = self.h
        scores = []
        h.hook_flag("AISmartCrossCutting", action=lambda: scores.append(h.read8("wBuffer")))
        for ours, theirs in boards:
            h.park_before_hijack()
            self.word("wEnemyMonSpeed", ours)
            self.word("wBattleMonSpeed", theirs)
            self.word("wEnemyMonUnmodifiedSpeed", ours)
            self.word("wPlayerMonUnmodifiedSpeed", theirs)
            h.write8("wEnemyMonSpeedMod", 7)
            h.write8("wPlayerMonSpeedMod", 7)
            h.write8("wEnemyMonStatus", 0)
            for label, value in (extra or {}).items():
                if isinstance(value, tuple):
                    self.word(label, value[0])
                else:
                    h.write8(label, value)
            h.write8("wBattleMonStatus", 0)
            h.write8("wPlayerBattleStatus1", 0)
            h.write8("wPlayerBattleStatus2", 0)
            h.write8("wAILastMoveNum", 0)
            h.write8("wAISameMoveCount", 0)
            h.write8("wEnemyMonMoves", self.moves[move])
            for slot in range(1, 4):
                h.write8("wEnemyMonMoves", 0, offset=slot)
            h.write8("wBuffer", 20)
            h.call_routine("AILayerSmart", limit=240)
        return scores

    def test_thunder_wave_that_flips_turn_order_is_strongly_preferred(self):
        # Phase 7 (2026-09-29): paralysis quarters Speed for the rest of the
        # matchup, so flipping who acts first gets AI_VERY_STRONG (20 -> 17).
        scores = self.smart_scores_by_speed("THUNDER_WAVE", [
            (100, 200),  # player ahead, 200/4 = 50 < 100: flips
            (100, 500),  # player ahead, 500/4 = 125: still ahead, no flip
            (100, 90),   # we are already faster: nothing to flip
            (100, 100),  # a tie is a coin flip, not "ahead": no flip
        ])
        self.assertEqual(scores, [17, 20, 20, 20])

    def test_paralysis_rider_that_flips_turn_order_gains_a_point(self):
        # Thunderbolt's 10% rider is AI_NUDGE (19); a flip makes it 18. (Not
        # Body Slam: the player here is Snorlax, and a Normal rider cannot
        # affect a Normal target - AISmartParaSideBlocked, the Gen 1 rule.)
        scores = self.smart_scores_by_speed("THUNDERBOLT", [(100, 200), (100, 90)])
        self.assertEqual(scores, [18, 19])

    # --- AI_BACKLOG.md B7: the player also holding Quick Attack --------------
    # AI_DAMAGE from 20 on a reliable kill: 10 = acts first (AI_KILL_FIRST 9 +
    # best nudge 1), 14 = does not (AI_KILL 5 + 1). Tauros outspeeds Snorlax.
    def kill_score_vs_player_quick_attack(self, move, revealed, *, slower=False):
        h = self.h
        raw = self.estimate(move)
        h.write8("wBattleMonMoves", self.moves["QUICK_ATTACK"])
        h.reveal_player_moves(0, [0] if revealed else [], clear=True)
        if slower:
            self.word("wEnemyMonSpeed", 10)
            self.word("wBattleMonSpeed", 200)
        return self.single_move_damage_score(move, raw * 217 // 255)

    def test_ordinary_kill_is_not_first_against_a_known_quick_attack(self):
        self.assertEqual(self.kill_score_vs_player_quick_attack("TACKLE", True), 14)

    def test_an_unrevealed_quick_attack_does_not_count(self):
        # Only moves the AI has SEEN count; a type guess never does.
        self.assertEqual(self.kill_score_vs_player_quick_attack("TACKLE", False), 10)

    def test_mirror_quick_attack_falls_back_to_speed(self):
        # Both Quick Attack: the faster side goes first (MainInBattleLoop).
        self.assertEqual(self.kill_score_vs_player_quick_attack("QUICK_ATTACK", True), 10)

    def test_slower_quick_attack_loses_priority_to_a_known_mirror(self):
        self.assertEqual(
            self.kill_score_vs_player_quick_attack("QUICK_ATTACK", True, slower=True), 14)

    def test_quick_attack_is_first_when_the_player_has_none(self):
        self.assertEqual(
            self.kill_score_vs_player_quick_attack("QUICK_ATTACK", False, slower=True), 10)

    # --- AI_BACKLOG.md B2: Speed control by turn order ----------------------
    # From 20: 18 = AI_STRONG (flips order), 20 = no opinion, 21 = mild waste
    # (we already act first). -1 Speed is x66/100, +2 is x2 (StatModifierRatios).
    def test_string_shot_scored_by_turn_order(self):
        scores = self.smart_scores_by_speed("STRING_SHOT", [
            (100, 140),  # 140 * 66 / 100 = 92 < 100: flips
            (100, 160),  # 105: still ahead, no flip
            (100, 90),   # already faster: a wasted turn
        ])
        self.assertEqual(scores, [18, 20, 21])

    def test_speed_drop_prediction_includes_the_earned_speed_boost(self):
        # Codex follow-up R5: execution re-applies the earned x1.125 Speed boost
        # after the drop. Unmodified 125 -> -1 stage 82 -> +82/8 = 92 > our 90:
        # still ahead, no flip (20). Without the boost, 82 < 90 flips (18).
        boosted = self.smart_scores_by_speed("STRING_SHOT", [(90, 140)], extra={
            "wPlayerMonUnmodifiedSpeed": (125,), "wEarnedStatBoosts": 1 << 2})
        plain = self.smart_scores_by_speed("STRING_SHOT", [(90, 125)], extra={
            "wEarnedStatBoosts": 0})
        self.assertEqual((boosted[0], plain[-1]), (20, 18))

    def test_agility_scored_by_turn_order(self):
        scores = self.smart_scores_by_speed("AGILITY", [
            (100, 150),  # 100 * 2 = 200 > 150: flips
            (100, 250),  # 200 < 250: still behind
            (100, 90),   # already faster
        ])
        self.assertEqual(scores, [18, 20, 21])

    def test_speed_drop_rider_that_flips_gains_a_point(self):
        # Bubble's 33% Speed-drop rider: AI_NUDGE (19), +1 on a flip.
        scores = self.smart_scores_by_speed("BUBBLE", [(100, 140), (100, 90)])
        self.assertEqual(scores, [18, 19])

    # --- AI_BACKLOG.md B1: burn against physical threats ----------------------
    def test_burn_rider_gains_a_point_against_a_physical_attacker(self):
        # Snorlax (Attack > Special, a believed Normal STAB guess) is physical:
        # Ember's rider 19 -> 18. With Special above Attack it stays 19.
        physical = self.smart_scores_by_speed("EMBER", [(100, 90)])
        special = self.smart_scores_by_speed("EMBER", [(100, 90)], extra={
            "wBattleMonAttack": (50,), "wBattleMonSpecial": (200,)})
        # Each helper call adds its own hook, so the first list also records
        # the second run: compare each run's own (first/last) entry.
        self.assertEqual((physical[0], special[-1]), (18, 19))

    def test_ai_stat_ratio_copy_matches_the_engine_table(self):
        rom = (ROOT / "pokeblue_debug.gbc").read_bytes()

        def rom_bytes(label, length):
            bank, address = self.h.symbols.get(label)
            offset = address if bank == 0 else bank * 0x4000 + address - 0x4000
            return rom[offset:offset + length]

        self.assertEqual(rom_bytes("AIStatModifierRatios", 26),
                         rom_bytes("StatModifierRatios", 26))

    def substitute_rank(self, move, sub_hp):
        """The ranking value AI_DAMAGE gives a lone move behind a Substitute."""
        h = self.h
        h.write8("wPlayerBattleStatus2", 1 << self.battle["HAS_SUBSTITUTE_UP"])
        h.write8("wPlayerSubstituteHP", sub_hp)
        h.write8("wEnemyMonMoves", self.moves[move])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        h.write8("wBuffer", 20)
        ranked = []
        h.hook_flag("AILayerDamage.trackBest", action=lambda: ranked.append(
            int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big")))
        h.park_before_hijack()
        h.call_routine("AILayerDamage", limit=240)
        return ranked[-1]

    def test_multihit_shield_progress_counts_every_hit(self):
        # Codex follow-up R3: a 200-HP shield outlasts all five Fury Attack
        # hits, so the rank is pure shield progress: ~3 hits on average at 85%
        # accuracy. It used to be credited ONE hit.
        one_hit = self.estimate("FURY_ATTACK")
        self.assertLess(5 * one_hit, 200)
        self.assertGreater(self.substitute_rank("FURY_ATTACK", 200), 2 * one_hit)

    def test_crit_weighting_cannot_inflate_capped_shield_progress(self):
        # A 10-HP shield caps a breaking Tackle's shield part at 11, and the
        # breaking hit never spills to the owner, so 11 is the whole value before
        # accuracy; AIScaleDamageByAccuracy's x255/256 floors it to 10. Crit
        # weighting used to be applied on top of the cap (12 before accuracy).
        self.assertGreater(self.estimate("TACKLE"), 10)
        self.assertEqual(self.substitute_rank("TACKLE", 10), 11 * 255 // 256)

    def test_substitute_breaker_outranks_a_hit_the_shield_absorbs(self):
        # Review F3 (2026-09-29): behind a Substitute every single hit used to
        # rank at 0 owner damage, so Tackle and Body Slam tied at 20. Now the
        # move that breaks the shield gets the best-damage nudge.
        h = self.h
        tackle = self.estimate("TACKLE")
        slam = self.estimate("BODY_SLAM")
        self.assertLess(tackle + 1, slam)
        sub_hp = (tackle + slam) // 2  # Tackle cannot break it, Body Slam can
        h.write8("wPlayerBattleStatus2", 1 << self.battle["HAS_SUBSTITUTE_UP"])
        h.write8("wPlayerSubstituteHP", sub_hp)
        h.write8("wEnemyMonMoves", self.moves["TACKLE"])
        h.write8("wEnemyMonMoves", self.moves["BODY_SLAM"], offset=1)
        for slot in range(2, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.park_before_hijack()
        h.call_routine("AILayerDamage", limit=240)
        tackle_score, slam_score = h.read8("wBuffer"), h.read8("wBuffer", 1)
        self.assertLess(slam_score, tackle_score, (tackle, slam, sub_hp))

    def lone_smart_score(self, move, *, enemy_hp=None, substitute=False):
        """AI_SMART's score for a lone move (from 20), read before the
        cross-cutting rules."""
        h = self.h
        scores = []
        h.hook_flag("AISmartCrossCutting", action=lambda: scores.append(h.read8("wBuffer")))
        h.park_before_hijack()
        if enemy_hp is not None:
            self.word("wEnemyMonHP", enemy_hp)
        h.write8("wPlayerBattleStatus2",
                 (1 << self.battle["HAS_SUBSTITUTE_UP"]) if substitute else 0)
        h.write8("wPlayerSubstituteHP", 30 if substitute else 0)
        h.write8("wAILastMoveNum", 0)
        h.write8("wAISameMoveCount", 0)
        h.write8("wEnemyMonMoves", self.moves[move])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        h.write8("wBuffer", 20)
        h.call_routine("AILayerSmart", limit=240)
        return scores[-1]

    def test_low_hp_explosion_into_a_substitute_is_heavily_discouraged(self):
        # Codex follow-up L2: below a quarter HP, Explosion is normally a fine
        # trade (18), but into a Substitute the user faints for nothing (30).
        self.assertEqual(self.lone_smart_score("EXPLOSION", enemy_hp=5), 18)

    def test_explosion_into_a_substitute_whatever_our_hp(self):
        self.assertEqual(self.lone_smart_score("EXPLOSION", enemy_hp=5, substitute=True), 30)

    def test_recoil_of_at_least_one_kills_a_one_hp_user(self):
        # A level-2 Tauros' Take Down deals under 4, so damage/4 rounds to 0,
        # but RecoilEffect_ deals at least 1: at 1 HP that is self-KO (AI_HEAVY,
        # 30), not the mild "survivable recoil" nudge (21).
        h = self.h
        h.write8("wEnemyMonLevel", 2)
        self.word("wBattleMonDefense", 999)
        self.assertLess(self.estimate("TAKE_DOWN"), 4)
        self.assertEqual(self.lone_smart_score("TAKE_DOWN", enemy_hp=1), 30)

    def test_fresh_mon_does_not_inherit_the_previous_mons_move_history(self):
        # Codex follow-up L1: after a send-out the tracker is marked fresh; the
        # first decision clears streak, last move and last power instead of
        # recording the previous mon's selection.
        h = self.h
        h.park_before_hijack()
        h.write8("wAILastMoveNum", self.ai["AI_LAST_MOVE_FRESH_MON"])
        h.write8("wAISameMoveCount", 5)
        h.write8("wAILastMovePower", 0)
        h.write8("wEnemySelectedMove", self.moves["GROWL"])
        h.call_routine("AITrackLastMove", limit=120)
        self.assertEqual([h.read8("wAILastMoveNum"), h.read8("wAISameMoveCount"),
                          h.read8("wAILastMovePower")], [0, 0, 0])

    def test_player_psywave_threat_uses_its_maximum_roll(self):
        # Codex follow-up R6: a level-100 Psywave rolls up to 149, but the
        # estimator's 3/4-level expectation (75) read as "cannot KO" at 100 HP.
        h = self.h
        h.write8("wBattleMonLevel", 100)
        h.write8("wBattleMonMoves", self.moves["PSYWAVE"])
        h.reveal_player_moves(0, [0], clear=True)
        results = []
        for enemy_hp in (100, 149, 150):
            h.park_before_hijack()
            self.word("wEnemyMonHP", enemy_hp)
            h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_EMPTY"])
            h.call_routine("AIPlayerWouldKO", limit=240)
            results.append(h.read8("wAIPlayerKOCache"))
        yes, no = self.ai["AI_KO_CACHE_YES"], self.ai["AI_KO_CACHE_NO"]
        self.assertEqual(results, [yes, yes, no])

    # --- AIPlayerWouldKO one-decision cache (AI review option 3) ------------
    def test_ko_cache_hit_skips_the_scan_and_empty_recomputes(self):
        h = self.h
        scans = h.hook_flag("_AIScanPlayerMovesForKO")
        for state, expected_scans in ((self.ai["AI_KO_CACHE_NO"], 0),
                                      (self.ai["AI_KO_CACHE_EMPTY"], 1)):
            with self.subTest(state=state):
                before = scans["count"]
                h.park_before_hijack()
                h.write8("wAIPlayerKOCache", state)
                h.call_routine("AIPlayerWouldKO", limit=240)
                self.assertEqual(scans["count"] - before, expected_scans)
        self.assertIn(h.read8("wAIPlayerKOCache"),
                      (self.ai["AI_KO_CACHE_NO"], self.ai["AI_KO_CACHE_YES"]))

    def test_ko_cache_is_cleared_when_move_selection_starts(self):
        # T0 runs no layer that asks AIPlayerWouldKO, so the entry clear is
        # all that can change the byte.
        h = self.h
        h.write8("wAITier", 1)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_YES"])
        h.park_before_hijack()
        h.call_routine("AIEnemyTrainerChooseMoves", limit=600)
        self.assertEqual(h.read8("wAIPlayerKOCache"), self.ai["AI_KO_CACHE_EMPTY"])

    def test_ko_cache_is_cleared_when_trainer_ai_starts(self):
        # T1 TrainerAI never asks AIPlayerWouldKO (AIIncreaseStat's check is
        # T2+), so the entry clear is all that can change the byte.
        h = self.h
        h.write8("wAITier", 2)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_YES"])
        h.park_before_hijack()
        h.call_routine("TrainerAI", limit=600)
        self.assertEqual(h.read8("wAIPlayerKOCache"), self.ai["AI_KO_CACHE_EMPTY"])

    def test_damage_layer_caps_high_crit_ranking_at_remaining_owner_hp(self):
        h = self.h
        raw = self.estimate("SLASH")
        hp = max(1, raw // 2)
        self.word("wBattleMonHP", hp)
        h.write8("wEnemyMonMoves", self.moves["SLASH"])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        # Capture the ranking value where it is used: the .kill path re-estimates
        # guaranteed damage afterwards (review F2/F4), overwriting it.
        ranked_values = []
        h.hook_flag("AILayerDamage.trackBest", action=lambda: ranked_values.append(
            int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big")))
        h.park_before_hijack()
        h.call_routine("AILayerDamage", limit=240)
        self.assertEqual(len(ranked_values), 1)
        self.assertLessEqual(ranked_values[0], hp)
    def smart_recoil_score(self, substitute_hp=None):
        h = self.h
        raw = self.estimate("TAKE_DOWN")
        self.assertGreaterEqual(raw // 4, 1)
        self.word("wEnemyMonHP", 1)
        self.word("wBattleMonHP", 1)
        h.write8("wPlayerBattleStatus2", 0)
        if substitute_hp is not None:
            h.write8(
                "wPlayerBattleStatus2", 1 << self.battle["HAS_SUBSTITUTE_UP"]
            )
            h.write8("wPlayerSubstituteHP", substitute_hp)
        h.write8("wEnemyMonMoves", self.moves["TAKE_DOWN"])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        h.write8("wBuffer", 20)
        h.park_before_hijack()
        h.call_routine("AILayerSmart", limit=240)
        return h.read8("wBuffer"), raw

    def test_recoil_trade_does_not_treat_substitute_break_as_owner_ko(self):
        mutual_ko_score, raw = self.smart_recoil_score()
        substitute_score, _ = self.smart_recoil_score(min(raw, 255))
        self.assertEqual(mutual_ko_score, 20)
        self.assertEqual(substitute_score, 30)

    def test_multihit_recoil_into_substitute_is_not_an_owner_ko(self):
        h = self.h
        variable = self.effects["TWO_TO_FIVE_ATTACKS_EFFECT"]

        # Recoil and multi-hit use separate effect IDs in move data. Inject the
        # multi-hit effect at the recoil handler boundary to exercise the
        # combined owner-delivery case without changing ROM data.
        h.park_before_hijack()
        self.load_enemy_move("TAKE_DOWN")
        h.write8("wEnemyMoveEffect", variable)
        h.write8("wEnemyMovePower", 20)
        h.call_routine("AIEstimateDamage", limit=120)
        one_hit = int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big")
        self.assertGreater(one_hit // 4, 0)
        self.assertLessEqual(one_hit * 5, 255)

        h.park_before_hijack()
        self.word("wEnemyMonHP", 1)
        self.word("wBattleMonHP", 1)
        h.write8("wPlayerBattleStatus2", 1 << self.battle["HAS_SUBSTITUTE_UP"])
        # $ff is the estimator's "no Substitute" sentinel; $fe is the largest
        # real shield HP and still exceeds the bounded five-hit total above.
        h.write8("wPlayerSubstituteHP", 254)
        h.write8("wEnemyMonMoves", self.moves["TAKE_DOWN"])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)

        recoil_handler = h.hook_flag(
            "AISmart_RecoilEffect",
            action=lambda: (
                h.write8("wEnemyMoveEffect", variable),
                h.write8("wEnemyMovePower", 20),
            ),
        )
        h.call_routine("AILayerSmart", limit=240)

        self.assertEqual(recoil_handler["count"], 1)
        self.assertEqual(
            int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big"),
            0,
        )
        self.assertEqual(h.read8("wBuffer"), 30)

    def select_plan(
        self,
        moves,
        player_types,
        enemy_speed=200,
        player_speed=100,
        bridge_effect=None,
        whose_turn=1,
    ):
        h = self.h
        h.park_before_hijack()
        for slot in range(4):
            move = self.moves[moves[slot]] if slot < len(moves) else 0
            h.write8("wEnemyMonMoves", move, offset=slot)
        h.call_routine("AIClassifyMoveset", limit=240)

        # Install the board after classification so the parked battle loop cannot
        # refresh live types, status, or selected effects between setup and fit.
        h.write8("wBattleMonType1", player_types[0])
        h.write8("wBattleMonType2", player_types[1])
        self.word("wEnemyMonSpeed", enemy_speed)
        self.word("wBattleMonSpeed", player_speed)
        for label in (
            "wBattleMonStatus",
            "wPlayerBattleStatus1",
            "wPlayerBattleStatus2",
            "wPlayerBattleStatus3",
            "wEnemyBattleStatus1",
            "wEnemyBattleStatus2",
            "wEnemyBattleStatus3",
            "wEnemyDisabledMove",
            "wAIPlan",
            "wAIPlanStep",
        ):
            h.write8(label, 0)
        h.write8("hWhoseTurn", whose_turn)
        h.write8("wLinkState", 0)
        h.write8("wPlayerMonNumber", 0)
        for offset in range(4):
            h.write8("wBridgeSelectedEffects", 0, offset=offset)
        if bridge_effect is not None:
            h.write8("wBridgeSelectedEffects", 1)
            h.write8("wBridgeSelectedEffects", bridge_effect, offset=1)
        h.call_routine("AIPlanSelect", limit=480)
        return h.read8("wAIPlan")

    def test_d_sleep_payoff_outranks_nonessential_setup_when_slower(self):
        selected = self.select_plan(
            ["HYPNOSIS", "AMNESIA", "RECOVER"],
            (self.types["NORMAL"], self.types["NORMAL"]),
            enemy_speed=50,
            player_speed=100,
        )
        self.assertEqual(selected, self.ai["AI_PLAN_SLEEP_LEAD"])

    def test_r7_sleep_legality_ignores_normal_ghost_damage_immunity(self):
        selected = self.select_plan(
            ["SING"],
            (self.types["GHOST"], self.types["GHOST"]),
        )
        self.assertEqual(selected, self.ai["AI_PLAN_SLEEP_LEAD"])

    def test_r7_paralysis_ground_immunity_is_electric_only(self):
        ground = (self.types["WATER"], self.types["GROUND"])
        self.assertEqual(
            self.select_plan(["THUNDER_WAVE", "RECOVER"], ground),
            self.ai["AI_PLAN_BRUISER"],
        )
        for move in ("STUN_SPORE", "GLARE"):
            with self.subTest(move=move):
                self.assertEqual(
                    self.select_plan([move, "RECOVER"], ground),
                    self.ai["AI_PLAN_CHANSEY_STALL"],
                )

    def test_r7_later_legal_trap_is_not_hidden_by_immune_first_match(self):
        selected = self.select_plan(
            ["WRAP", "CLAMP"],
            (self.types["GHOST"], self.types["GHOST"]),
        )
        self.assertEqual(selected, self.ai["AI_PLAN_WRAP_LOCK"])

    def test_r7_bridge_status_immunities_block_only_their_real_categories(self):
        full = self.pokemon_data["BRIDGE_SELECTED_EFFECT_STATUS_IMMUNITY"]
        poison = self.pokemon_data["BRIDGE_SELECTED_EFFECT_POISON_IMMUNITY"]
        ghost = (self.types["GHOST"], self.types["GHOST"])
        self.assertEqual(
            self.select_plan(["SING"], ghost, bridge_effect=full),
            self.ai["AI_PLAN_BRUISER"],
        )
        self.assertEqual(
            self.select_plan(["TOXIC", "RECOVER"], ghost, bridge_effect=poison),
            self.ai["AI_PLAN_BRUISER"],
        )
        self.assertEqual(
            self.select_plan(["SING"], ghost, bridge_effect=poison),
            self.ai["AI_PLAN_SLEEP_LEAD"],
        )

    def test_r7_bridge_immunities_hold_whoever_moved_last(self):
        # The AI plans with hWhoseTurn left over from the last move executed, and
        # measured in FIGHT 2 it is 0 for 30 of 35 predicate calls. The status
        # predicates used to pass that straight to BridgePlayerTargetBlocksStatus,
        # which treats 0 as "the player is attacking" and allows everything, so an
        # immune player looked sleepable. The test above pins hWhoseTurn to 1 and
        # could not see it.
        full = self.pokemon_data["BRIDGE_SELECTED_EFFECT_STATUS_IMMUNITY"]
        poison = self.pokemon_data["BRIDGE_SELECTED_EFFECT_POISON_IMMUNITY"]
        ghost = (self.types["GHOST"], self.types["GHOST"])
        for whose_turn in (0, 1):
            with self.subTest(whose_turn=whose_turn):
                self.assertEqual(
                    self.select_plan(["SING"], ghost, bridge_effect=full,
                                     whose_turn=whose_turn),
                    self.ai["AI_PLAN_BRUISER"],
                )
                self.assertEqual(
                    self.select_plan(["TOXIC", "RECOVER"], ghost, bridge_effect=poison,
                                     whose_turn=whose_turn),
                    self.ai["AI_PLAN_BRUISER"],
                )
                self.assertEqual(
                    self.h.read8("hWhoseTurn"), whose_turn,
                    "AIPlanSelect must leave hWhoseTurn as it found it",
                )

    def delivered(self, routine, effect, damage, substitute_hp=None, witch=False, owner_hp=None):
        h = self.h
        h.park_before_hijack()
        player_attacks = "Player" in routine
        h.write8("wPlayerMoveEffect" if player_attacks else "wEnemyMoveEffect", effect)
        h.write8("wAIDamageEstimate", damage >> 8)
        h.write8("wAIDamageEstimate", damage & 255, offset=1)
        h.write8("wPlayerBattleStatus2", 0)
        h.write8("wEnemyBattleStatus2", 0)
        h.write8("wWitchPrizesEarned", 0, offset=1)
        if owner_hp is not None:
            self.word("wEnemyMonHP" if player_attacks else "wBattleMonHP", owner_hp)
        if witch:
            bit = self.ram["PRIZE_MULTISTRIKE"] - 9
            h.write8("wWitchPrizesEarned", 1 << bit, offset=1)
        if substitute_hp is not None:
            status = "wEnemyBattleStatus2" if player_attacks else "wPlayerBattleStatus2"
            sub_hp = "wEnemySubstituteHP" if player_attacks else "wPlayerSubstituteHP"
            h.write8(status, 1 << self.battle["HAS_SUBSTITUTE_UP"])
            h.write8(sub_hp, substitute_hp)
        h.call_routine(routine, limit=240)
        return int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big")

    def test_single_and_fixed_two_hit_substitute_delivery_both_directions(self):
        fixed = self.effects["ATTACK_TWICE_EFFECT"]
        plain = self.effects["NO_ADDITIONAL_EFFECT"]
        for prefix in ("Enemy", "Player"):
            possible = f"AIAdjust{prefix}DamageForPossibleDelivery"
            with self.subTest(direction=prefix, case="single-no-sub"):
                self.assertEqual(self.delivered(possible, plain, 20), 20)
            with self.subTest(direction=prefix, case="single-break-no-spill"):
                self.assertEqual(self.delivered(possible, plain, 20, 10), 0)
            with self.subTest(direction=prefix, case="fixed-break-then-owner"):
                self.assertEqual(self.delivered(possible, fixed, 20, 10), 20)
            with self.subTest(direction=prefix, case="fixed-equality-then-break"):
                self.assertEqual(self.delivered(possible, fixed, 20, 20), 0)

    def test_standard_variable_hits_use_maximum_for_possible_and_distribution_for_expected(self):
        variable = self.effects["TWO_TO_FIVE_ATTACKS_EFFECT"]
        self.assertEqual(
            self.delivered("AIAdjustEnemyDamageForPossibleDelivery", variable, 20), 100
        )
        self.assertEqual(
            self.delivered("AIAdjustEnemyDamageForExpectedDelivery", variable, 20), 60
        )
        # A 30-HP shield consumes two hits: at counts 2/3/4/5 the owner receives
        # 0/1/2/3 hits, whose weighted expectation is exactly one hit.
        self.assertEqual(
            self.delivered("AIAdjustEnemyDamageForPossibleDelivery", variable, 20, 30), 60
        )
        self.assertEqual(
            self.delivered("AIAdjustEnemyDamageForExpectedDelivery", variable, 20, 30), 20
        )

    def test_effect_1e_shares_the_variable_hit_contract(self):
        effect = self.effects["EFFECT_1E"]
        self.assertEqual(
            self.delivered("AIAdjustEnemyDamageForPossibleDelivery", effect, 17), 85
        )
        self.assertEqual(
            self.delivered("AIAdjustEnemyDamageForExpectedDelivery", effect, 17), 51
        )

    def test_delivery_zero_and_worst_case_arithmetic(self):
        variable = self.effects["TWO_TO_FIVE_ATTACKS_EFFECT"]
        self.assertEqual(
            self.delivered("AIAdjustEnemyDamageForPossibleDelivery", variable, 0, 0),
            0,
        )
        self.assertEqual(
            self.delivered("AIAdjustEnemyDamageForPossibleDelivery", variable, 999),
            4995,
        )
        self.assertEqual(
            self.delivered(
                "AIAdjustEnemyDamageForExpectedDelivery", variable, 999, owner_hp=999
            ),
            999,
        )
        self.assertEqual(
            self.delivered(
                "AIAdjustEnemyDamageForExpectedDelivery", variable, 100, owner_hp=150
            ),
            150,
        )

    def test_witch_multistrike_is_player_only_and_uses_four_five_expectation(self):
        variable = self.effects["TWO_TO_FIVE_ATTACKS_EFFECT"]
        self.assertEqual(
            self.delivered(
                "AIAdjustPlayerDamageForExpectedDelivery", variable, 20, witch=True
            ),
            90,
        )
        self.assertEqual(
            self.delivered(
                "AIAdjustPlayerDamageForPossibleDelivery", variable, 20, witch=True
            ),
            100,
        )
        self.assertEqual(
            self.delivered(
                "AIAdjustEnemyDamageForExpectedDelivery", variable, 20, witch=True
            ),
            60,
        )


if __name__ == "__main__":
    unittest.main()
