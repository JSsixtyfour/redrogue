"""Real gift dispatch and inventory writes, with text/input seams stubbed.

This exercises all ROM variants, including cancellation, rejected selections,
and bag context restoration. Interactive rendering remains a BGB check.
"""
import io
from pathlib import Path
import unittest

from pyboy import PyBoy
from harness import SymbolTable
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]


class OldManItemDuplicationTest(unittest.TestCase):
    def test_delivery_rejection_cancel_and_context_in_all_roms(self):
        items = parse_rgbds_constants(ROOT / "constants/item_constants.asm")
        # add_tm is a macro outside the source parser's const/DEF subset.
        items["TM_REST"] = 0xF4
        events = parse_rgbds_constants(ROOT / "constants/event_constants.asm")
        gift_event = events["EVENT_BRIDGE_RECEIVE_GIFT"]
        cases = [
            ("recovery", 0, "POTION", "wRecoveryItemCounts", 0, 7, 8, True),
            ("stat", 3, "RARE_CANDY", "wStatItemCounts", 14, 7, 8, True),
            ("valuable", 4, "NUGGET", "wValuableItemCounts", 2, 98, 99, True),
            ("full", 0, "POTION", "wRecoveryItemCounts", 0, 99, 99, False),
            ("key", 1, "POTION", "wRecoveryItemCounts", 0, 7, 7, False),
            ("tm", 2, "TM_REST", "wRecoveryItemCounts", 0, 7, 7, False),
            ("cancel", None, "POTION", "wRecoveryItemCounts", 0, 7, 7, False),
        ]
        for variant in ("pokered", "pokeblue", "pokeblue_debug"):
            sym = SymbolTable(ROOT / f"{variant}.sym")
            rom = bytearray((ROOT / f"{variant}.gbc").read_bytes())
            rom[0x143] = 0
            rom[0x14D] = (-sum(rom[0x134:0x14D]) - 25) & 255
            pb = PyBoy(io.BytesIO(rom), cgb=False, window="null",
                       sound_emulated=False, log_level="CRITICAL")
            try:
                pb.tick(80, False)
                pb.memory[0xFFFF] = 0
                pb.memory[0xFF40] = 0
                pb.memory[0xC100:0xC102] = [0x18, 0xFE]
                pending = {}

                def read(label):
                    return pb.memory[sym.address(label)]

                def write(label, value):
                    pb.memory[sym.address(label)] = value

                def return_now(_):
                    sp = pb.register_file.SP
                    pb.register_file.PC = pb.memory[sp] | pb.memory[sp + 1] << 8
                    pb.register_file.SP = sp + 2

                def select(_):
                    self.assertEqual(read("wPrintItemPrices"), 0)
                    self.assertEqual(read("wListMenuID"), 4)  # ITEMLISTMENU
                    pocket = pending.pop("pocket", None)
                    if pocket is None:
                        pb.register_file.F = 0x10
                    else:
                        write("wBagPocketsFlags", pocket)
                        write("wCurItem", pending["item"])
                        write("wMaxItemQuantity", pending["count"])
                        pb.register_file.F = 0
                    return_now(None)

                pb.hook_register(*sym.get("DisplayListMenuID"), select, None)
                pb.hook_register(*sym.get("PrintText"), return_now, None)
                pb.hook_register(*sym.get("ReceivedItem"), return_now, None)
                for name, pocket, item, counts, offset, before, after, success in cases:
                    with self.subTest(variant=variant, case=name):
                        pending.update(pocket=pocket, item=items[item], count=before)
                        at = sym.address(counts) + offset
                        pb.memory[at] = before
                        event_at = sym.address("wEventFlags") + gift_event // 8
                        pb.memory[event_at] &= ~(1 << (gift_event % 8))
                        context = {"wBagPocketsFlags": 0x14, "wListScrollOffset": 9,
                                   "wListMenuID": 7, "wPrintItemPrices": 1,
                                   "hCurrentMenuItem": 2}
                        for label, value in context.items():
                            write(label, value)
                        write("hCurMap", 0x2C)
                        write("wGift1", 8)
                        bank, address = sym.get("BridgeDoGift")
                        write("hLoadedROMBank", bank)
                        pb.memory[0x2000] = bank
                        pb.register_file.A = 0
                        pb.register_file.SP = 0xDFDE
                        pb.memory[0xDFDE:0xDFE0] = [0, 0xC1]
                        pb.register_file.PC = address
                        for _ in range(30):
                            pb.tick(1, False)
                            if pb.register_file.PC in (0xC100, 0xC101):
                                break
                        self.assertIn(pb.register_file.PC, (0xC100, 0xC101))
                        self.assertEqual(pb.memory[at], after)
                        self.assertEqual(bool(pb.memory[event_at] & (1 << (gift_event % 8))), success)
                        for label, value in context.items():
                            self.assertEqual(read(label), value, label)
                        self.assertEqual(read("wMenuWatchMovingOutOfBounds"), 0)
            finally:
                pb.stop(save=False)
