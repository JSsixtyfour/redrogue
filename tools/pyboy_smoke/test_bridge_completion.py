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

    def enable_research_grant(self) -> None:
        # BRIDGE_EFFECT_MONEY is bit 16 in the global-effect registry. Other
        # tests exercise the grant routine; keep this test to one injected call.
        self.harness.write8("wBridgeGlobalEffects", 1, offset=2)

    def test_research_grant_adds_twenty_percent_to_current_payout(self) -> None:
        self.harness.write8("wWitchPrizesEarned", 0)
        self.harness.pyboy.memory[
            self.harness.address("wAmountMoneyWon") :
            self.harness.address("wAmountMoneyWon") + 3
        ] = [0x00, 0x10, 0x00]  # 1000 BCD
        self.enable_research_grant()

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
        self.enable_research_grant()

        self.harness.call_routine("WitchApplyMoneyEffects")

        self.assertEqual(
            self.harness.read_bytes("wAmountMoneyWon", 3), [0x00, 0x13, 0x20]
        )

    def test_second_chance_rejects_inactive_ko_defiance(self) -> None:
        self.harness.write8("wCurItem", 0x3E)
        self.harness.write8("wKODefianceUsages", 0)
        self.harness.write_sram_bytes("sKeyItemsBitfield", [0])
        self.harness.call_routine("BridgeMomSecondChanceFar")
        self.assertEqual(self.harness.read8("wKODefianceUsages"), 0)
        self.assertEqual(self.harness.read8("wCurItem"), 0x3E)

    def test_second_chance_restores_an_active_empty_charge(self) -> None:
        self.harness.write8("wCurItem", 0x3E)
        self.harness.write8("wKODefianceUsages", 0)
        self.harness.write_sram_bytes("sKeyItemsBitfield", [1 << 5])
        self.harness.call_routine("BridgeMomSecondChanceFar")
        self.assertEqual(self.harness.read8("wKODefianceUsages"), 1)
        self.assertEqual(self.harness.read8("wCurItem"), 0x3E)

    def test_second_chance_does_not_stack_an_existing_charge(self) -> None:
        self.harness.write8("wCurItem", 0x3E)
        self.harness.write8("wKODefianceUsages", 2)
        self.harness.write_sram_bytes("sKeyItemsBitfield", [1 << 5])
        self.harness.call_routine("BridgeMomSecondChanceFar")
        self.assertEqual(self.harness.read8("wKODefianceUsages"), 2)
        self.assertEqual(self.harness.read8("wCurItem"), 0x3E)


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

    def test_bridge_giver_identity_replacements_are_wired(self) -> None:
        trashed = (REPO_ROOT / "data/maps/objects/CeruleanTrashedHouse.asm").read_text()
        cubone = (REPO_ROOT / "data/maps/objects/LavenderCuboneHouse.asm").read_text()
        nickname = (REPO_ROOT / "data/maps/objects/ViridianNicknameHouse.asm").read_text()
        sprites = (REPO_ROOT / "data/sprites/sprites.asm").read_text()
        self.assertIn("SPRITE_OFFICER_JENNY", trashed)
        self.assertIn("SPRITE_KOGA", cubone)
        self.assertIn("SPRITE_GAMBLER", nickname)
        self.assertIn("SPRITE_OFFICER_JENNY", sprites)

    def test_flora_grotto_uses_supplied_map_and_bridge_pc(self) -> None:
        header = (REPO_ROOT / "data/maps/headers/CeruleanTradeHouse.asm").read_text()
        maps = (REPO_ROOT / "maps.asm").read_text()
        objects = (REPO_ROOT / "data/maps/objects/CeruleanTradeHouse.asm").read_text()
        hidden = (REPO_ROOT / "data/events/hidden_events.asm").read_text()
        self.assertIn("GYM", header)
        self.assertIn('CeruleanTradeHouse_Blocks: INCBIN "maps/FlorasHouse.blk"', maps)
        self.assertIn("SPRITE_BEAUTY", objects)
        self.assertIn("warp_event  3,  7", objects)
        flora_hidden = hidden.split("hidden_events_for CERULEAN_TRADE_HOUSE", 1)[1]
        self.assertIn("hidden_event  4,  0, OpenBridgeBillsPC", flora_hidden)


if __name__ == "__main__":
    unittest.main(verbosity=2)
