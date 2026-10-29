"""Credit list prices, benefits and cursor restoration in the built ROM."""
import re
import json
import hashlib
from pathlib import Path
import unittest
import autoplay
import autoplay_world as world
from harness import RedRogueHarness
from source_constants import parse_map_constants
from test_key_item_equipment import bits
from purchase_scenario import act, evidence, snapshot
from source_constants import parse_rgbds_constants
from test_item_descriptions import ItemDescriptionRuntimeBase
from test_smoke import REPO_ROOT

ITEMS = parse_rgbds_constants(REPO_ROOT / "constants/item_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
MENUS = parse_rgbds_constants(REPO_ROOT / "constants/list_constants.asm")
SOURCE = (REPO_ROOT / "engine/events/credit_mart.asm").read_text()
UPGRADES = re.findall(r"^\s*db (\w+),\s+KEY_ITEM_BIT_\w+_OWNED / 2,\s+\$([0-9a-fA-F]+),\s+\$([0-9a-fA-F]+)", SOURCE, re.M)


APPROVED_PURCHASES = {'SHINY_CHARM': 11, 'AMULET_COIN': 8, 'TURN_REWIND': 10, 'RARE_SCOPE': 10, 'RARE_LENS': 10, 'DV_BOOSTER': 14, 'STAT_BOOSTER': 11, 'DOOR_DICE': 6, 'MON_DICE': 6, 'ITEM_DICE': 6}
APPROVED_UPGRADES = {'LEFTOVERS': (6, 12), 'PP_TONIC': (6, 12), 'KO_DEFIANCE': (12, 24), 'SHINY_CHARM': (18, 36), 'AMULET_COIN': (9, 18), 'TURN_REWIND': (15, 30), 'RARE_SCOPE': (12, 24), 'RARE_LENS': (12, 24), 'DV_BOOSTER': (15, 30), 'STAT_BOOSTER': (12, 24), 'DOOR_DICE': (9, 18), 'MON_DICE': (9, 18), 'ITEM_DICE': (9, 18), 'ELEMENT_PRISM': (12, 24)}


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
        self.assertIn("36", self.tile_row(11, 5, 8))

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


class CreditStoreLiveTest(unittest.TestCase):
    """Constructed arrival/ownership fixture; genuine vendor inputs and return."""

    def live(self, case, *, cgb=False):
        upgrade = case.startswith("upgrade_")
        tier = 2 if case == "upgrade_max" else int(case == "upgrade_final")
        target = (4, 3) if upgrade else (2, 3)
        art = Path(__file__).parent / "artifacts" / f"credit_live_{case}_{'cgb' if cgb else 'dmg'}"
        art.mkdir(parents=True, exist_ok=True)
        h = RedRogueHarness(REPO_ROOT, art, cgb_mode=cgb)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.tick(180)
        maps = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")
        # Reuse the entrance-warp fixture pattern. This does not claim natural
        # hub progression: only the destination of the arrival warp is changed.
        h.write8("wWarpEntries", 0, offset=2)
        h.write8("wWarpEntries", maps["CREDIT_EXCHANGE"], offset=3)
        h.move_tile("up")
        h.pyboy.button_press("down")
        try:
            h.wait_until(lambda: h.read8("hCurMap") == maps["CREDIT_EXCHANGE"], "credit entry", 600)
        finally:
            h.pyboy.button_release("down")
        h.tick(180)
        agent = autoplay.AutoplayAgent(h, seed=7)
        for _ in range(50):
            if agent.position() == target:
                break
            path = world.find_path(agent.read_grid(), agent.position(), {target}, agent.obstacles())
            self.assertTrue(path, f"credit counter unreachable from {agent.position()}")
            agent.walk(path[0])
        self.assertEqual(agent.position(), target)
        agent.press("up", 2, 20)
        owned = ("LEFTOVERS", "PP_TONIC", "KO_DEFIANCE") if case == "full_active" else ()
        if upgrade:
            owned = ("SHINY_CHARM",)
        active = () if case == "upgrade_pc" else owned
        before_flags = bits(owned, active)
        h.write_sram_bytes("sKeyItemsBitfield", before_flags)
        tiers = [0] * 4
        index = RAM["KEY_ITEM_BIT_SHINY_CHARM_OWNED"] // 2
        tiers[index // 4] = tier << (2 * (index % 4))
        h.write_sram_bytes("sKeyItemTiers", tiers)
        funds = ({"upgrade_exact":18, "upgrade_final":36, "upgrade_decline":18,
                  "upgrade_insufficient":17, "upgrade_pc":18, "upgrade_max":99}[case]
                 if upgrade else 10 if case == "insufficient" else 11)
        h.write8("wPlayerCoins", 0)
        h.write8("wPlayerCoins", int(f"{funds:02d}", 16), 1)
        party = h.read_bytes("wPartyDataStart", h.address("wPartyDataEnd") - h.address("wPartyDataStart"))
        counts = h.read_bytes("wRecoveryItemCounts", h.address("wItemCountsEnd") - h.address("wRecoveryItemCounts"))
        visits = h.hook_flag("DisplayListMenuID")
        confirm = h.hook_flag("YesNoChoice")
        paid = h.hook_flag("SubtractCredits")
        grant = h.hook_flag("GiveItem")
        changed_tier = h.hook_flag("SetKeyItemTier")
        exited = h.hook_flag("CreditVendorMenu.exit")
        wait = {"frame": -100}
        h.register_hook("JoypadLowSensitivity", lambda _: wait.update(frame=h.pyboy.frame_count))
        initial = art / "initial.state"
        with initial.open("wb") as out:
            h.save_state(out)
        started = h.pyboy.frame_count
        inputs = []
        agent.press = lambda button, hold=2, after=6: act(h, inputs, button, hold, after)
        agent.press("a")
        captured_list = False
        for _ in range(500):
            if exited["count"] and not h.read8("wFontLoaded") & 1:
                break
            if h.pyboy.frame_count - wait["frame"] > 2:
                h.tick(2)
                continue
            if visits["count"] == 1 and not captured_list:
                evidence(h, art, "list")
                captured_list = True
            if confirm["count"] and visits["count"] == 1:
                agent.press("b" if case in ("decline", "upgrade_decline") else "a")
            elif visits["count"] >= 2:
                agent.press("b")
            else:
                agent.press("a")
        bought = case in ("exact", "full_active", "upgrade_exact", "upgrade_final", "upgrade_pc")
        self.assertEqual(exited["count"], 1)
        self.assertEqual(visits["count"], 0 if case == "upgrade_max" else 1 if case == "upgrade_final" else 2)
        self.assertFalse(h.read8("wFontLoaded") & 1, "vendor did not return to overworld")
        self.assertEqual(confirm["count"], int(case not in ("insufficient", "upgrade_insufficient", "upgrade_max")))
        self.assertEqual(paid["count"], int(bought))
        self.assertEqual(grant["count"], int(bought and not upgrade))
        self.assertEqual(changed_tier["count"], int(bought and upgrade))
        stock = h.read_bytes("wCreditItemList", h.read8("wCreditItemList") + 1)[1:]
        self.assertEqual(ITEMS["SHINY_CHARM"] in stock, tier + int(bought) < 2 if upgrade else not bought,
                         "vendor shelf did not reflect ownership after the transaction")
        self.assertEqual(h.read_bytes("wPlayerCoins", 2), [0, 0] if bought else [0, int(f"{funds:02d}", 16)])
        self.assertEqual(h.read_sram_bytes("sKeyItemsBitfield", 4),
                         before_flags if upgrade or not bought else bits((*owned, "SHINY_CHARM"), owned if owned else ("SHINY_CHARM",)))
        if bought and upgrade:
            tiers[index // 4] = (tier + 1) << (2 * (index % 4))
        self.assertEqual(h.read_sram_bytes("sKeyItemTiers", 4), tiers)
        self.assertEqual(h.read_bytes("wPartyDataStart", len(party)), party)
        self.assertEqual(h.read_bytes("wRecoveryItemCounts", len(counts)), counts)
        self.assertEqual(h.read8("hJoyIgnore"), 0)
        agent.press("down", 20, 20)
        self.assertEqual(h.read8("hCurMap"), maps["CREDIT_EXCHANGE"])
        self.assertNotEqual(agent.position(), target, "legal movement did not recover")
        evidence(h, art, "after")
        (art / "result.json").write_text(json.dumps({"case": case, "cgb": cgb,
            "fixture": "retargeted arrival warp, explicit tiers, ownership and funds",
            "rom_sha256": h.rom_sha256, "sym_sha256": h.sym_sha256,
            "initial_state_sha256": hashlib.sha256(initial.read_bytes()).hexdigest(),
            "started_frame": started, "final_frame": h.pyboy.frame_count,
            "inputs": inputs, "paid": paid["count"], "grant": grant["count"],
            "changed_tier": changed_tier["count"],
            "after": snapshot(h), "coins": h.read_bytes("wPlayerCoins", 2),
            "flags": h.read_sram_bytes("sKeyItemsBitfield", 4),
            "tiers": h.read_sram_bytes("sKeyItemTiers", 4),
            "position": agent.position()}, indent=2))

    def test_live_exact_funds(self):
        self.live("exact")

    def test_live_decline(self):
        self.live("decline")

    def test_live_insufficient(self):
        self.live("insufficient")

    def test_live_full_active_sends_owned_item_to_pc(self):
        self.live("full_active")

    def test_live_upgrade_exact_funds(self):
        self.live("upgrade_exact")

    def test_live_upgrade_final_tier_empties_shelf(self):
        self.live("upgrade_final")

    def test_live_upgrade_decline(self):
        self.live("upgrade_decline")

    def test_live_upgrade_insufficient(self):
        self.live("upgrade_insufficient")

    def test_live_upgrade_pc_owned_item_stays_inactive(self):
        self.live("upgrade_pc")

    def test_live_upgrade_max_tier_has_no_stock(self):
        self.live("upgrade_max")

