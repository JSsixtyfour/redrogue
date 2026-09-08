from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class BridgeBattleEffectsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.harness.boot_to_lobby()

    def tearDown(self) -> None:
        self.harness.close()

    def selected_records(self) -> list[int]:
        start = self.harness.address("wBridgeSelectedEffects")
        return list(self.harness.pyboy.memory[start : start + 4])

    def damage(self) -> int:
        return (self.harness.read8("wDamage") << 8) | self.harness.read8(
            "wDamage", 1
        )

    def status_block_result(self, effect: int, status_kind: int) -> str:
        start = self.harness.address("wBridgeSelectedEffects")
        self.harness.pyboy.memory[start : start + 4] = [1, effect, 0, 0]
        self.harness.write8("wPlayerMonNumber", 0)
        self.harness.write8("hWhoseTurn", 1)
        self.harness.write8("wLinkState", 0)
        self.harness.pyboy.register_file.E = status_kind
        captured: list[str] = []
        hooks: list[tuple[int, int]] = []
        for outcome in ("blocked", "allowed"):
            bank, address = self.harness.symbols.get(
                f"BridgePlayerTargetBlocksStatus.{outcome}"
            )
            hooks.append((bank, address))

            def capture(_context, value=outcome) -> None:
                captured.append(value)

            self.harness.pyboy.hook_register(bank, address, capture, None)
        try:
            self.harness.call_routine("BridgePlayerTargetBlocksStatus", limit=100)
        finally:
            for bank, address in hooks:
                self.harness.pyboy.hook_deregister(bank, address)
        self.assertTrue(captured)
        return captured[0]

    def scaled_healing(self, routine: str, flags: int, amount: int) -> int:
        effects = self.harness.address("wBridgeGlobalEffects")
        self.harness.pyboy.memory[effects : effects + 3] = [0, flags, 0]
        self.harness.pyboy.register_file.D = amount >> 8
        self.harness.pyboy.register_file.E = amount & 0xFF
        captured: list[int] = []
        bank, address = self.harness.symbols.get("BridgeScaleHealingDE.done")

        def capture_amount(_context) -> None:
            captured.append(
                (self.harness.pyboy.register_file.D << 8)
                | self.harness.pyboy.register_file.E
            )

        self.harness.pyboy.hook_register(bank, address, capture_amount, None)
        try:
            self.harness.call_routine(routine, limit=100)
        finally:
            self.harness.pyboy.hook_deregister(bank, address)
        self.assertTrue(captured)
        return captured[-1]

    def prepare_type_expert_damage(self) -> None:
        effects = self.harness.address("wBridgeGlobalEffects")
        self.harness.pyboy.memory[effects : effects + 3] = [1 << 5, 0, 0]
        self.harness.pyboy.memory[
            self.harness.address("wDamage") : self.harness.address("wDamage") + 2
        ] = [0, 100]

    def test_type_expert_ignores_neutral_matchup(self) -> None:
        self.prepare_type_expert_damage()
        self.harness.pyboy.register_file.E = 20  # neutral in twentieths
        self.harness.call_routine("BridgeApplySuperEffectiveDamageBoost", limit=100)
        self.assertEqual(self.damage(), 100)

    def test_type_expert_boosts_super_effective_matchup(self) -> None:
        self.prepare_type_expert_damage()
        self.harness.pyboy.register_file.E = 40  # 2x effective in twentieths
        self.harness.call_routine("BridgeApplySuperEffectiveDamageBoost", limit=100)
        self.assertEqual(self.damage(), 120)

    def test_second_selected_effect_for_same_owner_is_refused(self) -> None:
        start = self.harness.address("wBridgeSelectedEffects")
        self.harness.pyboy.memory[start : start + 4] = [1, 1, 0, 0]
        self.harness.write8("wPartyCount", 1)
        self.harness.write8("hWhichPokemon", 0)

        self.harness.pyboy.register_file.E = 4  # flinch
        self.harness.call_routine("BridgeGrantSelectedEffect", limit=100)

        self.assertEqual(self.selected_records(), [1, 1, 0, 0])

    def test_selected_effect_grants_into_empty_registry(self) -> None:
        start = self.harness.address("wBridgeSelectedEffects")
        self.harness.pyboy.memory[start : start + 4] = [0, 0, 0, 0]
        self.harness.write8("wPartyCount", 1)
        self.harness.write8("hWhichPokemon", 0)
        self.harness.pyboy.register_file.E = 1  # critical rate

        self.harness.call_routine("BridgeGrantSelectedEffect", limit=100)

        self.assertEqual(self.selected_records(), [1, 1, 0, 0])

    def test_body_armor_publishes_its_calc_flag(self) -> None:
        start = self.harness.address("wBridgeSelectedEffects")
        self.harness.pyboy.memory[start : start + 4] = [1, 5, 0, 0]
        stats = self.harness.address("wPartyMon1Stats")
        self.harness.pyboy.register_file.D = stats >> 8
        self.harness.pyboy.register_file.E = stats & 0xFF

        self.harness.call_routine("PrepareFusionAndBridgeRayCalcStats")

        self.assertEqual(self.harness.read8("wBridgeCalcEffectFlags"), 1 << 5)

    def test_critical_damage_mastery_scales_a_critical_hit(self) -> None:
        effects = self.harness.address("wBridgeGlobalEffects")
        self.harness.pyboy.memory[effects : effects + 3] = [1, 0, 0]
        damage = self.harness.address("wDamage")
        self.harness.pyboy.memory[damage : damage + 2] = [0, 100]
        self.harness.write8("wCriticalHitOrOHKO", 1)

        self.harness.call_routine("BridgeApplyCriticalDamageBoost", limit=100)

        self.assertEqual(self.damage(), 120)

    def test_life_orb_scales_ordinary_damage(self) -> None:
        start = self.harness.address("wBridgeSelectedEffects")
        self.harness.pyboy.memory[start : start + 4] = [1, 7, 0, 0]
        self.harness.write8("wPlayerMonNumber", 0)
        self.harness.write8("hWhoseTurn", 0)
        self.harness.write8("wLinkState", 0)
        self.harness.write8("wCriticalHitOrOHKO", 0)
        self.harness.write8("wPlayerMovePower", 50)
        damage = self.harness.address("wDamage")
        self.harness.pyboy.memory[damage : damage + 2] = [0, 100]

        self.harness.call_routine("BridgeApplyLifeOrbDamageBoost", limit=100)

        self.assertEqual(self.damage(), 130)

    def test_life_orb_recoil_is_ten_percent_of_max_hp(self) -> None:
        start = self.harness.address("wBridgeSelectedEffects")
        self.harness.pyboy.memory[start : start + 4] = [1, 7, 0, 0]
        self.harness.write8("wPlayerMonNumber", 0)
        self.harness.write8("wLinkState", 0)
        self.harness.write8("hWhoseTurn", 0)
        self.harness.write8("wRogueFlagsBitfield", 0)
        self.harness.write8("wBridgeRepeatState", 1)
        self.harness.write8("wMoveMissed", 0)
        self.harness.write8("wDamage", 0)
        self.harness.write8("wDamage", 50, offset=1)
        self.harness.write8("wBattleMonHP", 0)
        self.harness.write8("wBattleMonHP", 100, offset=1)
        self.harness.write8("wBattleMonMaxHP", 0)
        self.harness.write8("wBattleMonMaxHP", 100, offset=1)
        captured: list[int] = []
        bank, address = self.harness.symbols.get("ApplyWitchSelfDamage")

        def capture_recoil(_context) -> None:
            captured.append(
                (self.harness.pyboy.register_file.B << 8)
                | self.harness.pyboy.register_file.C
            )

        self.harness.pyboy.hook_register(bank, address, capture_recoil, None)
        try:
            self.harness.probe_routine_until(
                "HandlePostPlayerMoveWitchEffects",
                lambda: bool(captured),
                limit=100,
            )
        finally:
            self.harness.pyboy.hook_deregister(bank, address)

        self.assertEqual(captured, [10])

    def test_selected_critical_training_adds_25_percentage_points(self) -> None:
        start = self.harness.address("wBridgeSelectedEffects")
        self.harness.pyboy.memory[start : start + 4] = [1, 1, 0, 0]
        self.harness.write8("wPlayerMonNumber", 0)
        self.harness.write8("hWhoseTurn", 0)
        self.harness.write8("wWitchPrizesEarned", 0)
        self.harness.pyboy.register_file.E = 100

        captured: dict[str, int] = {}
        bank, address = self.harness.symbols.get(
            "BridgeAdjustCriticalThreshold.storeCaptain"
        )

        def capture_threshold(_context) -> None:
            captured["threshold"] = self.harness.pyboy.register_file.A

        self.harness.pyboy.hook_register(bank, address, capture_threshold, None)
        try:
            self.harness.call_routine("BridgeAdjustCriticalThreshold", limit=100)
        finally:
            self.harness.pyboy.hook_deregister(bank, address)

        self.assertEqual(captured.get("threshold"), 164)

    def test_body_armor_permits_night_shade_class_moves(self) -> None:
        start = self.harness.address("wBridgeSelectedEffects")
        self.harness.pyboy.memory[start : start + 4] = [1, 5, 0, 0]
        self.harness.write8("wPlayerMonNumber", 0)
        self.harness.write8("wPlayerMovePower", 0)
        self.harness.write8("wPlayerMoveEffect", 0x29)  # SPECIAL_DAMAGE_EFFECT

        self.harness.call_routine("BridgeBodyArmorBlocksSelectedMove")

    def test_dulled_senses_suppresses_ordinary_recoil(self) -> None:
        effects = self.harness.address("wBridgeGlobalEffects")
        self.harness.pyboy.memory[effects : effects + 3] = [1 << 7, 0, 0]
        self.harness.write8("hWhoseTurn", 0)
        self.harness.write8("wPlayerMoveNum", 36)  # TAKE_DOWN
        self.harness.write8("wBattleMonHP", 0)
        self.harness.write8("wBattleMonHP", 100, offset=1)
        self.harness.write8("wDamage", 0)
        self.harness.write8("wDamage", 40, offset=1)

        self.harness.call_routine("RecoilEffect_", limit=100)

        self.assertEqual(self.harness.read8("wBattleMonHP"), 0)
        self.assertEqual(self.harness.read8("wBattleMonHP", 1), 100)

    def test_spiked_drink_scales_status_chance_relatively(self) -> None:
        effects = self.harness.address("wBridgeGlobalEffects")
        self.harness.pyboy.memory[effects : effects + 3] = [0, 1 << 1, 0]
        self.harness.write8("hWhoseTurn", 0)
        self.harness.pyboy.register_file.E = 50
        captured: dict[str, int] = {}
        bank, address = self.harness.symbols.get(
            "BridgeAdjustStatusChanceThreshold.done"
        )

        def capture_threshold(_context) -> None:
            captured["threshold"] = self.harness.pyboy.register_file.E

        self.harness.pyboy.hook_register(bank, address, capture_threshold, None)
        try:
            self.harness.call_routine(
                "BridgeAdjustStatusChanceThreshold",
                limit=100,
            )
        finally:
            self.harness.pyboy.hook_deregister(bank, address)

        self.assertEqual(captured.get("threshold"), 60)

    def test_deadly_venom_converts_player_poison_to_toxic(self) -> None:
        effects = self.harness.address("wBridgeGlobalEffects")
        self.harness.pyboy.memory[effects : effects + 3] = [0, 1 << 5, 0]
        self.harness.write8("hWhoseTurn", 0)
        self.harness.write8("wPlayerMoveNum", 77)  # POISON_POWDER
        self.harness.write8("wEnemyMonStatus", 0)
        self.harness.write8("wEnemyBattleStatus3", 0)
        self.harness.write8("wEnemyToxicCounter", 7)

        self.harness.call_routine("BridgeInflictPoisonStatus", limit=100)

        self.assertNotEqual(self.harness.read8("wEnemyMonStatus") & (1 << 3), 0)
        self.assertNotEqual(
            self.harness.read8("wEnemyBattleStatus3") & (1 << 0),
            0,
        )
        self.assertEqual(self.harness.read8("wEnemyToxicCounter"), 0)

    def test_poison_ward_blocks_poison(self) -> None:
        self.assertEqual(self.status_block_result(6, 0), "blocked")

    def test_poison_ward_allows_other_major_status(self) -> None:
        self.assertEqual(self.status_block_result(6, 1), "allowed")

    def test_full_immunity_blocks_other_major_status(self) -> None:
        self.assertEqual(self.status_block_result(8, 1), "blocked")

    def test_nurturing_care_scales_general_healing(self) -> None:
        self.assertEqual(
            self.scaled_healing("BridgeScaleGeneralHealingAmount", 1 << 4, 100),
            110,
        )

    def test_shadow_step_adds_party_evasion_stage(self) -> None:
        effects = self.harness.address("wBridgeGlobalEffects")
        self.harness.pyboy.memory[effects : effects + 3] = [0, 1 << 6, 0]
        start = self.harness.address("wBridgeSelectedEffects")
        self.harness.pyboy.memory[start : start + 4] = [0, 0, 0, 0]
        self.harness.write8("wLinkState", 0)
        self.harness.write8("wPlayerMonNumber", 0)
        self.harness.write8("wPlayerMonEvasionMod", 7)

        self.harness.call_routine("BridgeApplyShrinkRayEvasion", limit=100)

        self.assertEqual(self.harness.read8("wPlayerMonEvasionMod"), 8)

    def test_target_practice_adds_ten_accuracy_points(self) -> None:
        effects = self.harness.address("wBridgeGlobalEffects")
        self.harness.pyboy.memory[effects : effects + 3] = [0, 1 << 2, 0]
        self.harness.write8("hWhoseTurn", 0)
        self.harness.write8("wWitchPrizesEarned", 0)
        self.harness.pyboy.register_file.E = 200
        captured: list[int] = []
        bank, address = self.harness.symbols.get("BridgeAdjustAccuracyThreshold.done")

        def capture_threshold(_context) -> None:
            captured.append(self.harness.pyboy.register_file.E)

        self.harness.pyboy.hook_register(bank, address, capture_threshold, None)
        try:
            self.harness.call_routine("BridgeAdjustAccuracyThreshold", limit=100)
        finally:
            self.harness.pyboy.hook_deregister(bank, address)

        self.assertEqual(captured, [226])

    def test_verdant_drain_stacks_with_nurturing_care(self) -> None:
        self.assertEqual(
            self.scaled_healing(
                "BridgeScaleDrainHealingAmount",
                (1 << 7) | (1 << 4),
                100,
            ),
            143,
        )

    def test_repeat_matches_the_actual_move_and_party_slot(self) -> None:
        self.harness.write8("wLinkState", 0)
        self.harness.write8("wPlayerMoveEffect", 0)
        self.harness.write8("wPlayerSelectedMove", 33)
        self.harness.write8("wWitchPrevPlayerMove", 33)
        self.harness.write8("wWitchPrevPlayerSlot", 0)
        self.harness.write8("wPlayerMonNumber", 0)
        self.harness.write8("wBridgeRepeatState", 0)

        self.harness.call_routine("BridgePrepareRepeatAction", limit=100)

        self.assertEqual(self.harness.read8("wBridgeRepeatState"), 2)

    def test_repeat_records_a_disobedience_replacement_as_the_actual_move(self) -> None:
        self.harness.write8("wLinkState", 0)
        self.harness.write8("wPlayerMoveEffect", 0)
        self.harness.write8("wPlayerSelectedMove", 34)
        self.harness.write8("wWitchPrevPlayerMove", 33)
        self.harness.write8("wWitchPrevPlayerSlot", 0)
        self.harness.write8("wPlayerMonNumber", 0)

        self.harness.call_routine("BridgePrepareRepeatAction", limit=100)

        self.assertEqual(self.harness.read8("wBridgeRepeatState"), 1)
        self.assertEqual(self.harness.read8("wWitchPrevPlayerMove"), 34)

    def test_repeat_defers_metronome_until_its_generated_move(self) -> None:
        self.harness.write8("wLinkState", 0)
        self.harness.write8("wPlayerMoveEffect", 0x53)  # METRONOME_EFFECT
        self.harness.write8("wPlayerSelectedMove", 118)  # METRONOME
        self.harness.write8("wWitchPrevPlayerMove", 33)
        self.harness.write8("wBridgeRepeatState", 0)

        self.harness.call_routine("BridgePrepareRepeatAction", limit=100)

        self.assertEqual(self.harness.read8("wBridgeRepeatState"), 0)
        self.assertEqual(self.harness.read8("wWitchPrevPlayerMove"), 33)


class BridgeBattleSourceContractTest(unittest.TestCase):
    def test_repeat_does_not_clear_mirror_move_history(self) -> None:
        core = (REPO_ROOT / "engine" / "battle" / "core.asm").read_text()
        execute = core.split("ExecutePlayerMove:", 1)[1].split("ExecutePlayerMoveDone:", 1)[0]
        self.assertNotIn("ld [wPlayerUsedMove], a", execute.split("PlayerCanExecuteMove:", 1)[0])

    def test_repeat_hook_runs_after_disobedience_resolution(self) -> None:
        core = (REPO_ROOT / "engine" / "battle" / "core.asm").read_text()
        execute = core.split("ExecutePlayerMove:", 1)[1].split("DisplayUsedMoveText", 1)[0]
        self.assertLess(
            execute.index("call CheckForDisobedience"),
            execute.index("farcall BridgePrepareRepeatAction"),
        )

    def test_leech_seed_passes_healing_through_farcall_safe_registers(self) -> None:
        core = (REPO_ROOT / "engine" / "battle" / "core.asm").read_text()
        start = core.rindex("call HandlePoisonBurnLeechSeed_DecreaseOwnHP")
        seam = core[start : start + 300]
        self.assertIn("ld d, b", seam)
        self.assertIn("ld e, c", seam)
        self.assertIn("farcall HandlePoisonBurnLeechSeed_IncreaseEnemyHP", seam)

    def test_full_immunity_is_checked_before_rest_status_is_written(self) -> None:
        heal = (
            REPO_ROOT / "engine" / "battle" / "move_effects" / "heal.asm"
        ).read_text()
        self.assertLess(
            heal.index("farcall BridgePlayerRestIsBlocked"),
            heal.index("ld [hl], 2"),
        )

    def test_damage_bonus_order_places_life_orb_before_critical_mastery(self) -> None:
        core = (REPO_ROOT / "engine" / "battle" / "core.asm").read_text()
        exit_path = core.split("BridgeTrySuperEffectiveDamageBoost:", 1)[0]
        self.assertLess(
            exit_path.rindex("farcall BridgeApplyLifeOrbDamageBoost"),
            exit_path.rindex("farcall BridgeApplyCriticalDamageBoost"),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
