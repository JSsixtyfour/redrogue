"""Bag entry must validate shared positions before any list text is read.

Runs the real StartMenu_Item and pocket builder in every ROM. Stops at the
list box seam, before frame waits or user input; this is not visual acceptance.
"""
import io
from pathlib import Path
import unittest

from pyboy import PyBoy
from harness import SymbolTable

ROOT = Path(__file__).resolve().parents[2]


class BagEntryBoundsTest(unittest.TestCase):
    def test_rebuilt_valuables_bounds_in_all_roms(self):
        for variant in ("pokered", "pokeblue", "pokeblue_debug"):
            symbols = SymbolTable(ROOT / f"{variant}.sym")
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
                observed = {}

                def read(label):
                    return pb.memory[symbols.address(label)]

                def write(label, value):
                    pb.memory[symbols.address(label)] = value

                def box(_):
                    # StartMenu_Item draws its info box before setting the list
                    # ID. DisplayListMenuID then draws the list box itself.
                    if observed.get("info_box"):
                        observed["position"] = (read("wListScrollOffset"),
                                                read("hCurrentMenuItem"))
                        observed["count"] = read("wListCount")
                        observed["buffer"] = list(pb.memory[
                            symbols.address("wValuablePocketBuf"):
                            symbols.address("wValuablePocketBuf") + 10])
                        pb.register_file.PC = 0xC100
                    else:
                        observed["info_box"] = True
                        sp = pb.register_file.SP
                        pb.register_file.PC = pb.memory[sp] | pb.memory[sp + 1] << 8
                        pb.register_file.SP = sp + 2

                pb.hook_register(*symbols.get("DisplayTextBoxID"), box, None)
                cases = [(4, 0, 0, (0, 0)), (4, 1, 2, (1, 2)),
                         (1, 5, 2, (0, 0)), (0, 5, 2, (0, 0)),
                         (4, 255, 255, (0, 0)), (1, 0, 2, (0, 0)),
                         (4, 0, 255, (0, 0)), (4, 4, 0, (4, 0)),
                         (0, 0, 0, (0, 0))]
                for count, scroll, cursor, expected in cases:
                    with self.subTest(variant=variant, count=count,
                                      scroll=scroll, cursor=cursor):
                        observed.clear()
                        counts = symbols.address("wValuableItemCounts")
                        pb.memory[counts:counts + 4] = [7 if i < count else 0 for i in range(4)]
                        for label, value in (("wLinkState", 0), ("wBattleType", 0),
                                             ("wBagPocketsFlags", 4),
                                             ("wListScrollOffset", scroll),
                                             ("wBagSavedMenuItem", cursor)):
                            write(label, value)
                        bank, address = symbols.get("StartMenu_Item")
                        write("hLoadedROMBank", bank)
                        pb.memory[0x2000] = bank
                        pb.register_file.SP = 0xDFE0
                        pb.register_file.PC = address
                        for _ in range(20):
                            pb.tick(1, False)
                            if "position" in observed:
                                break
                        self.assertEqual(observed.get("position"), expected)
                        self.assertEqual(observed["count"], count)
                        self.assertEqual(observed["buffer"][count * 2 + 1], 255)
                        self.assertEqual(list(pb.memory[counts:counts + 4]),
                                         [7 if i < count else 0 for i in range(4)])
            finally:
                pb.stop(save=False)
