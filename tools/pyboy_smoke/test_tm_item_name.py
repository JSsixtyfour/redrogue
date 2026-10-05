"""Selected items must not inherit MOVE_NAME from the TM description.

Exercise the actual selection/copy path in every ROM: release Blue's old
lookup produced an unterminated name, while Debug's garbage happened to end.
"""
import io
from pathlib import Path
import unittest

from harness import SymbolTable
from pyboy import PyBoy


ROOT = Path(__file__).resolve().parents[2]


class TMItemNameTest(unittest.TestCase):
    def test_selection_resets_name_type_in_all_roms(self):
        for variant in ("pokered", "pokeblue", "pokeblue_debug"):
            symbols = SymbolTable(ROOT / f"{variant}.sym")
            rom = bytearray((ROOT / f"{variant}.gbc").read_bytes())
            rom[0x143] = 0  # DMG fixture, as in the shared harness.
            rom[0x14D] = (-sum(rom[0x134:0x14D]) - 25) & 0xFF
            checksum = (sum(rom) - rom[0x14E] - rom[0x14F]) & 0xFFFF
            rom[0x14E:0x150] = checksum.to_bytes(2, "big")
            pb = PyBoy(io.BytesIO(rom), cgb=False, window="null",
                       sound_emulated=False, log_level="CRITICAL")
            try:
                pb.tick(80, False)
                # Isolated HOME routine fixture; no interrupts or gameplay resume.
                pb.memory[0xFFFF] = 0
                pb.memory[0xFF40] = 0
                pb.memory[0xC100:0xC102] = [0x18, 0xFE]
                start = symbols.address("wStringBuffer")
                result = {}

                def finished(_):
                    result["finished"] = True
                    pb.register_file.PC = 0xC100

                def bound_copy(_):
                    if pb.register_file.HL == start + 400:
                        result["overflow"] = True
                        pb.register_file.PC = 0xC100

                pb.hook_register(*symbols.get("DisplayListMenuIDLoop.skipStoringItemName"), finished, None)
                pb.hook_register(*symbols.get("CopyString"), bound_copy, None)
                # TM12, TM24, HM01, plus a normal item with a stale move type.
                for item, expected in ((0xD4, "TM12"), (0xE0, "TM24"),
                                       (0xC4, "HM01"), (0x14, "POTION")):
                    with self.subTest(variant=variant, item=item):
                        result.clear()
                        pb.memory[start:start + 400] = [0xA5] * 400
                        for label, value in (("wCurItem", item), ("wNameListType", 2),
                                             ("wCurOpponent", 0), ("wBattleType", 0),
                                             ("hLoadedROMBank", 1)):
                            pb.memory[symbols.address(label)] = value
                        pb.memory[0x2000] = 1
                        pb.register_file.SP = 0xDFE0
                        pb.register_file.PC = symbols.address("DisplayListMenuIDLoop.skipGettingQuantity")
                        for _ in range(120):
                            pb.tick(1, False)
                            if result:
                                break
                        self.assertTrue(result.get("finished"), result)
                        encoded = [ord(c) - ord("A") + 0x80 if c.isalpha()
                                   else int(c) + 0xF6 for c in expected] + [0x50]
                        self.assertEqual(list(pb.memory[start:start + len(encoded)]), encoded)
                        # The name routine legitimately writes control fields
                        # farther away; guard the buffer and its immediate tail.
                        self.assertEqual(list(pb.memory[start + len(encoded):start + 64]),
                                         [0xA5] * (64 - len(encoded)))
                        self.assertEqual(pb.memory[symbols.address("wCurOpponent")], 0)
                        self.assertEqual(pb.memory[symbols.address("wBattleType")], 0)
            finally:
                pb.stop(save=False)


if __name__ == "__main__":
    unittest.main()
