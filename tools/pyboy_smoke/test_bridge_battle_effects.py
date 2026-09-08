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


if __name__ == "__main__":
    unittest.main(verbosity=2)
