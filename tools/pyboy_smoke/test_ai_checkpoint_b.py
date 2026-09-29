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
