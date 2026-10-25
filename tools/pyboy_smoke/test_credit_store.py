"""Credit list prices, benefits and cursor restoration in the built ROM."""
import re
from source_constants import parse_rgbds_constants
from test_item_descriptions import ItemDescriptionRuntimeBase
from test_smoke import REPO_ROOT

ITEMS = parse_rgbds_constants(REPO_ROOT / "constants/item_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
MENUS = parse_rgbds_constants(REPO_ROOT / "constants/list_constants.asm")
SOURCE = (REPO_ROOT / "engine/events/credit_mart.asm").read_text()
UPGRADES = re.findall(r"^\s*db (\w+),\s+KEY_ITEM_BIT_\w+_OWNED / 2,\s+\$([0-9a-fA-F]+),\s+\$([0-9a-fA-F]+)", SOURCE, re.M)


APPROVED_PURCHASES = {'SHINY_CHARM': 11, 'AMULET_COIN': 8, 'TURN_REWIND': 10, 'RARE_SCOPE': 10, 'RARE_LENS': 10, 'DV_BOOSTER': 14, 'STAT_BOOSTER': 11, 'DOOR_DICE': 6, 'MON_DICE': 6, 'ITEM_DICE': 6}
APPROVED_UPGRADES = {'LEFTOVERS': (8, 15), 'PP_TONIC': (8, 15), 'KO_DEFIANCE': (15, 30), 'SHINY_CHARM': (23, 45), 'AMULET_COIN': (11, 23), 'TURN_REWIND': (19, 38), 'RARE_SCOPE': (15, 30), 'RARE_LENS': (15, 30), 'DV_BOOSTER': (19, 38), 'STAT_BOOSTER': (15, 30), 'DOOR_DICE': (11, 23), 'MON_DICE': (11, 23), 'ITEM_DICE': (11, 23), 'ELEMENT_PRISM': (15, 30)}


class CreditStoreRuntimeTest(ItemDescriptionRuntimeBase):
    def tier(self, item, tier):
        index = RAM[f"KEY_ITEM_BIT_{item}_OWNED"] // 2
        packed = [0] * 4
        packed[index // 4] = tier << (2 * (index % 4))
        self.h.write_sram_bytes("sKeyItemTiers", packed)

    def credit_menu(self, item, tier=0):
        h = self.h
        self.open_mart([ITEMS[item]], cursor=0)
        h.write8("wListMenuID", MENUS["CREDITLISTMENU"])
        h.write8("wWhichPrizeWindow", 1)
        h.write8("wCurItem", ITEMS[item])
        self.tier(item, tier)

    def test_each_upgrade_uses_current_tier_price_through_home_dispatch(self):
        self.assertEqual({item: (int(first), int(second)) for item, first, second in UPGRADES}, APPROVED_UPGRADES)
        for item, first, second in UPGRADES:
            for tier, price in enumerate((first, second)):
                with self.subTest(item=item, tier=tier):
                    self.credit_menu(item, tier)
                    self.run_routine("GetListEntryPrice")
                    self.assertEqual([self.h.read8("hItemPrice", offset=i) for i in range(3)], [0, 0, int(price, 16)])

    def test_purchase_list_keeps_its_prices_and_renders_upgrade_price(self):
        h = self.h
        for item, price in APPROVED_PURCHASES.items():
            expected = int(f"{price:02d}", 16)
            self.credit_menu(item)
            h.write8("wWhichPrizeWindow", 0)
            self.run_routine("PointListAtCreditStock")
            h.write8("wCurItem", ITEMS[item])
            self.run_routine("GetListEntryPrice")
            self.assertEqual(h.read8("hItemPrice", offset=2), expected)
        self.credit_menu("SHINY_CHARM", 1)
        self.run_routine("BuildCreditVendorList")
        self.run_routine("PointListAtCreditStock")
        # Seed a list containing only the owned charm, without changing ownership.
        base = h.address("wCreditItemList")
        h.pyboy.memory[base:base+3] = [1, ITEMS["SHINY_CHARM"], 0xff]
        self.run_routine("PrintListMenuEntries")
        self.assertIn("45", self.tile_row(11, 5, 8))

    def test_every_upgrade_previews_both_real_benefits_and_clears_cancel(self):
        for item, _, _ in UPGRADES:
            for tier in (0, 1):
                with self.subTest(item=item, tier=tier):
                    self.credit_menu(item, tier)
                    self.run_routine("PrintBagInfoText")
                    self.assertTrue(self.tile_row(1, 14, 17).startswith(f"T{tier+2} "))
                    self.assertIn(">", self.tile_row(1, 14, 17))
                    self.assertTrue(self.tile_row(1, 16, 17))
                    self.h.write8("hCurrentMenuItem", 1)
                    self.run_routine("PrintBagInfoText")
                    self.assertEqual(self.tile_row(1, 14, 18), "")
                    self.assertEqual(self.tile_row(1, 16, 18), "")

    def test_scroll_and_row_survive_and_last_removed_item_clamps(self):
        for count in range(1, 15):
            for scroll in range(count):
                for row in range(min(2, count - 1 - scroll) + 1):
                    for removed in (False, True):
                        if removed and count == 1:
                            continue  # the shop exits without restoring an empty list
                        with self.subTest(count=count, scroll=scroll, row=row, removed=removed):
                            new_count = count - int(removed)
                            self.h.write8("wCreditItemList", new_count)
                            self.h.pyboy.register_file.B = row
                            self.h.pyboy.register_file.C = scroll
                            self.run_routine("RestoreCreditListPosition")
                            expected = min(scroll + row, new_count - 1)
                            self.assertEqual(self.h.read8("hCurrentMenuItem") + self.h.read8("wListScrollOffset"), expected)
                            if scroll + row < new_count:
                                self.assertEqual(self.h.read8("hCurrentMenuItem"), row)
                                self.assertEqual(self.h.read8("wListScrollOffset"), scroll)

