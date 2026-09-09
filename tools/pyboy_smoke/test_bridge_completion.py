from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class BridgeCompletionRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.harness.boot_to_lobby()

    def tearDown(self) -> None:
        self.harness.close()

    def grant_global_effect(self, effect: int) -> None:
        self.harness.pyboy.register_file.E = effect
        self.harness.call_routine("BridgeGrantGlobalEffect")

    def test_research_grant_adds_twenty_percent_to_current_payout(self) -> None:
        self.harness.write8("wWitchPrizesEarned", 0)
        self.harness.pyboy.memory[
            self.harness.address("wAmountMoneyWon") :
            self.harness.address("wAmountMoneyWon") + 3
        ] = [0x00, 0x10, 0x00]  # 1000 BCD
        self.grant_global_effect(16)  # BRIDGE_EFFECT_MONEY

        self.harness.call_routine("WitchApplyMoneyEffects")

        self.assertEqual(
            self.harness.read_bytes("wAmountMoneyWon", 3), [0x00, 0x12, 0x00]
        )

    def test_research_grant_stacks_after_witch_money_prize(self) -> None:
        self.harness.write8("wWitchPrizesEarned", 1 << 2)  # PRIZE_MONEY = 3
        self.harness.pyboy.memory[
            self.harness.address("wAmountMoneyWon") :
            self.harness.address("wAmountMoneyWon") + 3
        ] = [0x00, 0x10, 0x00]
        self.grant_global_effect(16)

        self.harness.call_routine("WitchApplyMoneyEffects")

        self.assertEqual(
            self.harness.read_bytes("wAmountMoneyWon", 3), [0x00, 0x13, 0x20]
        )

    def test_second_chance_requires_active_empty_ko_defiance(self) -> None:
        self.harness.write8("wCurItem", 0x3E)
        self.harness.write8("wKODefianceUsages", 0)
        self.harness.write_sram_bytes("sKeyItemsBitfield", [0])
        self.harness.call_routine("BridgeMomSecondChanceFar")
        self.assertEqual(self.harness.read8("wKODefianceUsages"), 0)
        self.assertEqual(self.harness.read8("wCurItem"), 0x3E)

        self.harness.write_sram_bytes("sKeyItemsBitfield", [1 << 5])
        self.harness.call_routine("BridgeMomSecondChanceFar")
        self.assertEqual(self.harness.read8("wKODefianceUsages"), 1)

        self.harness.write8("wKODefianceUsages", 2)
        self.harness.call_routine("BridgeMomSecondChanceFar")
        self.assertEqual(self.harness.read8("wKODefianceUsages"), 2)


class BridgeCompletionSourceContractTest(unittest.TestCase):
    def test_better_rarity_uses_established_increment_and_stacks(self) -> None:
        source = (REPO_ROOT / "engine/pokemon/random_pokemon_selection.asm").read_text()
        bridge = source.split("Fan Club BETTER RARITY", 1)[1].split(
            "; Mini-boss framework", 1
        )[0]
        self.assertIn("ld e, BRIDGE_EFFECT_REWARD_RARITY", bridge)
        self.assertIn("farcall BridgeHasGlobalEffect", bridge)
        self.assertIn("add 51", bridge)
        self.assertIn("ld a, $ff", bridge)

    def test_mist_stone_is_a_stat_item_with_universal_dispatch(self) -> None:
        item_constants = (REPO_ROOT / "constants/item_constants.asm").read_text()
        pockets = (REPO_ROOT / "custom_functions/pocket_items.asm").read_text()
        item_use = (REPO_ROOT / "engine/items/item_effects.asm").read_text()
        evolution = (REPO_ROOT / "engine/pokemon/evos_moves.asm").read_text()
        self.assertIn("const MIST_STONE", item_constants)
        self.assertIn("SUN_STONE, DUSK_STONE, ICE_STONE, MIST_STONE", pockets)
        self.assertIn("cp MIST_STONE ; outside ItemUsePtrTable's range", item_use)
        self.assertIn("farcall MistStoneChooseEvolution", item_use)
        self.assertIn("ignore required item", evolution)
        self.assertIn("ignore minimum level", evolution)

    def test_mist_count_reclaims_padding_without_shifting_later_main_data(self) -> None:
        wram = (REPO_ROOT / "ram/wram.asm").read_text()
        self.assertIn("wStatItemCounts:: ds NUM_STAT_ITEMS", wram)
        self.assertIn("wBagItems:: ds 6", wram)
        constants = (REPO_ROOT / "constants/ram_constants.asm").read_text()
        self.assertIn("DEF NUM_STAT_ITEMS      EQU 15", constants)

    def test_second_chance_preserves_the_cur_item_alias_in_its_predicate(self) -> None:
        source = (REPO_ROOT / "custom_functions/bridge_effects_extended.asm").read_text()
        predicate = source.split("BridgeMomSecondChanceEligibleFar::", 1)[1]
        self.assertIn("ld a, [wCurItem]", predicate)
        self.assertIn("push af", predicate)
        self.assertGreaterEqual(predicate.count("ld [wCurItem], a"), 3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
