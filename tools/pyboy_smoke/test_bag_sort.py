"""Exercise the linked field-bag builders and SELECT handler in isolation."""
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_smoke import ARTIFACTS, REPO_ROOT


ITEMS = parse_rgbds_constants(REPO_ROOT / "constants/item_constants.asm")
MOVES = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
LISTS = parse_rgbds_constants(REPO_ROOT / "constants/list_constants.asm")
ALPHA = 1 << 6
SELECT = 1 << 2


def displayed_names(path):
    source = (REPO_ROOT / path).read_text(encoding="utf-8")
    return re.findall(r'^\s*li "([^"]+)"', source, re.M)


def machines_in_type_order():
    source = (REPO_ROOT / "constants/item_constants.asm").read_text(encoding="utf-8")
    moves = displayed_names("data/moves/names.asm")
    return {
        start + index: moves[MOVES[move] - 1]
        for kind, start in (("tm", 0xC9), ("hm", 0xC4))
        for index, move in enumerate(re.findall(rf"^\s*add_{kind}\s+(\w+)", source, re.M))
    }


class BagSortTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)
        self.h.boot_to_lobby()
        for label, value in (("wFieldBagListActive", 1), ("wMenuWatchMovingOutOfBounds", 1),
                             ("wListMenuID", LISTS["ITEMLISTMENU"]), ("hJoyPressed", SELECT),
                             ("wOptions3", 0x0A)):
            self.h.write8(label, value)

    def check_toggle(self, pocket, type_order, quantities, names):
        h = self.h
        h.write8("wBagPocketsFlags", pocket)
        h.call_routine("BuildBagPocketList")
        start = h.read8("wListPointer") | h.read8("wListPointer", 1) << 8
        alpha_order = sorted(type_order, key=lambda item: (names[item], item))

        def check(order):
            expected = [len(order)]
            for item in order:
                expected.extend((item, quantities[item]))
            expected.append(255)
            self.assertEqual(list(h.pyboy.memory[start:start + len(expected)]), expected)

        check(type_order)
        for selected in (0, min(4, len(type_order)), len(type_order)):
            scroll = max(0, selected - 2)
            h.write8("wListScrollOffset", scroll)
            h.write8("hCurrentMenuItem", selected - scroll)
            h.write8("wMenuItemToSwap", 3)
            item = (type_order + [255])[selected]
            for mode, order in ((ALPHA, alpha_order), (0, type_order)):
                h.write8("hJoyPressed", SELECT)
                h.call_routine("ToggleFieldBagSort")
                check(order)
                self.assertEqual(h.read8("wOptions3"), 0x0A | mode)
                self.assertEqual(h.read8("wMenuItemToSwap"), 0)
                index = h.read8("wListScrollOffset") + h.read8("hCurrentMenuItem")
                self.assertEqual(h.pyboy.memory[start + 1 + 2 * index], item)
                h.write8("hJoyPressed", 0)
                h.call_routine("ToggleFieldBagSort")
                self.assertEqual(h.read8("wOptions3"), 0x0A | mode)

    def test_orders_keep_items_and_quantities(self):
        h = self.h
        names = dict(enumerate(displayed_names("data/items/names.asm"), 1))
        recovery = [ITEMS[name] for name in (
            "POTION SUPER_POTION FRESH_WATER SODA_POP LEMONADE HYPER_POTION MAX_POTION "
            "FULL_RESTORE REVIVE MAX_REVIVE ANTIDOTE BURN_HEAL ICE_HEAL AWAKENING PARLYZ_HEAL "
            "FULL_HEAL ETHER MAX_ETHER ELIXER MAX_ELIXER POKE_FLUTE"
        ).split()]
        source = (REPO_ROOT / "custom_functions/pocket_items.asm").read_text(encoding="utf-8")
        for pocket, kind in ((0, "Recovery"), (3, "Stat"), (4, "Valuable")):
            table = source.split(f"{kind}ItemTable::", 1)[1].split("db $FF", 1)[0]
            rows = re.findall(r"^\s*db ([A-Z_, ]+)", table, re.M)
            storage = [ITEMS[name] for row in rows for name in row.replace(",", " ").split()]
            for counts in ([0] * len(storage), [7] + [0] * (len(storage) - 1),
                           list(range(1, len(storage) + 1))):
                with self.subTest(pocket=kind, owned=sum(bool(count) for count in counts)):
                    for index, count in enumerate(counts):
                        h.write8(f"w{kind}ItemCounts", count, index)
                    quantities = dict(zip(storage, counts))
                    order = [item for item in (recovery if pocket == 0 else storage)
                             if quantities[item]]
                    self.check_toggle(pocket, order, quantities, names)
                    self.assertEqual(h.read_bytes(f"w{kind}ItemCounts", len(counts)), counts)

        h.write_sram_bytes("sKeyItemsBitfield", [0x03, 0xCC, 0x01, 0])
        key_items = [ITEMS[key] for key in ("LEFTOVERS", "AMULET_COIN", "RARE_SCOPE")]
        self.check_toggle(1, key_items, dict.fromkeys(key_items, 1), names)
        self.assertEqual(h.read_sram_bytes("sKeyItemsBitfield", 4), [0x03, 0xCC, 0x01, 0])

        h.write_sram_bytes("sTMBitfield", [255] * 6 + [127])
        machines = machines_in_type_order()
        self.check_toggle(2, list(machines), dict.fromkeys(machines, 1), machines)
        self.assertEqual(h.read_sram_bytes("sTMBitfield", 7), [255] * 6 + [127])

    def test_stale_list_id_and_battle_do_not_toggle(self):
        h = self.h
        for active, watch, battle in ((0, 1, 0), (1, 0, 0), (1, 1, 1)):
            h.write8("wFieldBagListActive", active)
            h.write8("wMenuWatchMovingOutOfBounds", watch)
            h.write8("hIsInBattle", battle)
            h.call_routine("ToggleFieldBagSort")
            self.assertEqual(h.read8("wOptions3"), 0x0A)

    def test_held_select_resumes_input_without_redrawing(self):
        h = self.h
        paths = []

        def stop_at(path):
            def stop(_):
                paths.append(path)
                # Return from the injected dispatch at the first list-loop
                # instruction, before the list waits for input or VBlank.
                registers = h.pyboy.register_file
                sp = registers.SP
                registers.PC = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
                registers.SP = sp + 2
            return stop

        h.register_hook("DisplayListMenuIDLoop", stop_at("redraw"))
        h.register_hook("DisplayListMenuIDLoop.readInput", stop_at("input"))
        h.write8("wBagPocketsFlags", 0)
        h.write8("wListScrollOffset", 0)
        h.write8("hCurrentMenuItem", 0)
        h.call_routine("BuildBagPocketList")

        for pressed in (SELECT, 0, 0, SELECT):
            h.write8("hJoyPressed", pressed)
            h.call_routine("HandleItemListSwapping")

        self.assertEqual(paths, ["redraw", "input", "input", "redraw"])
        self.assertEqual(h.read8("wOptions3"), 0x0A)
        self.assertFalse(h.hook_errors, h.hook_errors)

    def test_save_and_run_reset_preserve_sort_preference(self):
        h = self.h
        h.write8("wOptions3", 0x0A | ALPHA)
        h.call_routine("SaveGameData")
        h.write8("wOptions3", 0x0A)
        h.call_routine("LoadMainData")
        self.assertEqual(h.read8("wOptions3"), 0x0A | ALPHA)
        h.call_routine("RogueResetRunState")
        self.assertEqual(h.read8("wOptions3"), 0x0A | ALPHA)
