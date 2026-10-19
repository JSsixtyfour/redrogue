"""Equipment capacity, legacy-save repair and the independent Poke Flute slot."""
import re

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

ITEMS = parse_rgbds_constants(REPO_ROOT / "constants/item_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
NAMES = re.findall(
    r"^\s+db (\w+),\s+KEY_ITEM_BIT_\w+_OWNED",
    (REPO_ROOT / "custom_functions/key_item_pocket.asm").read_text(), re.M,
)


def bits(owned=(), active=()):
    value = 0
    for name in owned:
        value |= 1 << RAM[f"KEY_ITEM_BIT_{name}_OWNED"]
    for name in active:
        value |= 2 << RAM[f"KEY_ITEM_BIT_{name}_OWNED"]
    return list(value.to_bytes(4, "little"))


class KeyItemEquipmentTest(HarnessTestCase):
    def boot(self):
        self.harness.boot_fight2(seed=17)
        return self.harness

    def select(self, routine, name):
        h = self.harness
        h.write8("wCurItem", ITEMS[name])
        h.call_routine(routine)
        return bool(h.last_call_registers["F"] & 0x10)

    def flags(self):
        return self.harness.read_sram_bytes("sKeyItemsBitfield", 4)

    def test_every_item_respects_full_bag_and_can_fill_a_free_slot(self):
        h = self.boot()
        for name in NAMES:
            others = [n for n in reversed(NAMES) if n != name][:3]
            for count in (2, 3):
                with self.subTest(item=name, equipped=count):
                    active = others[:count]
                    owned = active + [name]
                    h.write_sram_bytes("sKeyItemsBitfield", bits(owned, active))
                    self.assertEqual(self.select("WithdrawKeyItem", name), count == 2)
                    expected = active + [name] if count == 2 else active
                    self.assertEqual(self.flags(), bits(owned, expected))

    def test_new_grants_autoequip_only_when_space_exists(self):
        h = self.boot()
        for name in NAMES:
            others = [n for n in reversed(NAMES) if n != name][:3]
            for count in (0, 1, 2, 3):
                with self.subTest(item=name, equipped=count):
                    active = others[:count]
                    h.write_sram_bytes("sKeyItemsBitfield", bits(active, active))
                    self.select("OwnKeyItem", name)
                    expected = active + [name] if count < 3 else active
                    self.assertEqual(self.flags(), bits(active + [name], expected))
                    self.assertEqual(h.read8("hSpriteOffset"), 0 if count < 3 else 255)
        self.select("OwnKeyItem", active[0])
        self.assertEqual(h.read8("hSpriteOffset"), 0, "repeat equipped grant is not sent to PC")

    def test_repair_keeps_first_three_and_preserves_persistent_data(self):
        h = self.boot()
        tiers = [0x24, 0x49, 0x92, 0x24]
        h.write_sram_bytes("sKeyItemTiers", tiers)
        h.write_sram_bytes("sElementPrismType", [0x14])
        h.write_sram_bytes("sPrismCartridges", [0x55, 0x15])
        for routine in ("BuildKeyItemBagList", "BuildKeyItemPCWithdrawList", "IsKeyItemActive"):
            with self.subTest(entry=routine):
                h.write_sram_bytes("sKeyItemsBitfield", bits(NAMES, NAMES))
                self.select(routine, "ELEMENT_PRISM")
                self.assertEqual(self.flags(), bits(NAMES, NAMES[:3]))
                self.assertEqual(h.read_sram_bytes("sKeyItemTiers", 4), tiers)
                self.assertEqual(h.read_sram_bytes("sElementPrismType", 1), [0x14])
                self.assertEqual(h.read_sram_bytes("sPrismCartridges", 2), [0x55, 0x15])
                h.call_routine("BuildKeyItemPCWithdrawList")
                expected = [len(NAMES) - 3]
                for name in NAMES[3:]:
                    expected.extend([ITEMS[name], 1])
                expected.append(255)
                self.assertEqual(h.read_bytes("wKeyItemPocketBuf", len(expected)), expected)

    def test_deposit_then_withdraw_prism_and_reject_unowned(self):
        h = self.boot()
        active = NAMES[:3]
        owned = active + ["ELEMENT_PRISM"]
        h.write_sram_bytes("sKeyItemsBitfield", bits(owned, active))
        self.assertFalse(self.select("WithdrawKeyItem", "ELEMENT_PRISM"))
        self.assertTrue(self.select("DepositKeyItem", active[0]))
        self.assertTrue(self.select("WithdrawKeyItem", "ELEMENT_PRISM"))
        self.assertFalse(self.select("WithdrawKeyItem", "ELEMENT_PRISM"))
        self.assertEqual(self.flags(), bits(owned, active[1:] + ["ELEMENT_PRISM"]))
        h.write_sram_bytes("sKeyItemsBitfield", [0] * 4)
        for name in NAMES:
            self.assertFalse(self.select("WithdrawKeyItem", name))
            self.assertEqual(self.flags(), [0] * 4)

    def test_retired_bits_do_not_use_capacity_and_orphans_do_not_apply(self):
        h = self.boot()
        active = NAMES[:2]
        owned = active + ["ELEMENT_PRISM"]
        state = bits(owned, active)
        state[0] |= 0xC0  # retired EXP ALL pair
        state[3] |= 0xC0  # reserved pair
        h.write_sram_bytes("sKeyItemsBitfield", state)
        self.assertTrue(self.select("WithdrawKeyItem", "ELEMENT_PRISM"))
        expected = bits(owned, owned)
        expected[0] |= 0xC0
        expected[3] |= 0xC0
        self.assertEqual(self.flags(), expected)
        for name in NAMES:
            h.write_sram_bytes("sKeyItemsBitfield", bits([], [name]))
            self.select("GetKeyItemPowerInE", name)
            self.assertEqual(h.last_call_registers["E"], 0)
            self.assertEqual(self.flags(), [0] * 4)

    def test_run_reset_preserves_equipment_ownership_and_prism_settings(self):
        h = self.boot()
        active = ["SHINY_CHARM", "RARE_LENS", "ELEMENT_PRISM"]
        expected = bits(NAMES, active)
        h.write_sram_bytes("sKeyItemsBitfield", expected)
        h.write_sram_bytes("sKeyItemTiers", [0x24, 0x49, 0x92, 0x24])
        h.write_sram_bytes("sElementPrismType", [0x14])
        h.write_sram_bytes("sPrismCartridges", [0x55, 0x15])
        h.call_routine("RogueResetRunState")
        self.assertEqual(self.flags(), expected)
        self.assertEqual(h.read_sram_bytes("sKeyItemTiers", 4), [0x24, 0x49, 0x92, 0x24])
        self.assertEqual(h.read_sram_bytes("sElementPrismType", 1), [0x14])
        self.assertEqual(h.read_sram_bytes("sPrismCartridges", 2), [0x55, 0x15])

    def test_flute_is_independent_and_battle_buffer_stays_bounded(self):
        h = self.boot()
        active = ["LEFTOVERS", "PP_TONIC", "ELEMENT_PRISM"]
        for flute in (0, 1):
            h.write_sram_bytes("sKeyItemsBitfield", bits(active, active))
            h.write8("wRecoveryItemCounts", flute, offset=20)
            size = h.address("wBattleItemListEnd") - h.address("wBattleItemList")
            # The adjacent bytes are RNG state, which legitimately advances
            # when call_routine resumes a frame. Compare at routine seams.
            guards = {}
            def capture_guard(label):
                guards[label] = h.read_bytes("wBattleItemListEnd", 8)
            seams = ("BuildBattleItemList", "BuildBattleItemList.noFlute")
            for label in seams:
                h.pyboy.hook_register(*h.symbols.get(label), capture_guard, label)
            enemy_len = h.address("wEnemyMonNicks") + 66 - h.address("wEnemyPartyCount")
            enemy = h.read_bytes("wEnemyPartyCount", enemy_len)
            h.call_routine("BuildBattleItemList")
            for label in seams:
                h.pyboy.hook_deregister(*h.symbols.get(label))
            names = active + (["POKE_FLUTE"] if flute else [])
            expected = [len(names)]
            for name in names:
                expected.extend([ITEMS[name], 1])
            expected.append(255)
            self.assertLessEqual(len(expected), size)
            self.assertEqual(h.read_bytes("wBattleItemList", len(expected)), expected)
            self.assertEqual(guards[seams[1]], guards[seams[0]])
            self.assertEqual(h.read_bytes("wEnemyPartyCount", enemy_len), enemy)
            self.assertEqual(self.flags(), bits(active, active))
            self.assertEqual(h.read8("wRecoveryItemCounts", offset=20), flute)
        self.assertFalse(self.select("IsKeyPocketItem", "POKE_FLUTE"))
        h.write8("hIsInBattle", 1)
        h.write8("wBattleType", 0)
        h.write8("wActionResultOrTookBattleTurn", 1)
        self.assertFalse(self.select("BattleKeyItemGate", "POKE_FLUTE"))
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)

