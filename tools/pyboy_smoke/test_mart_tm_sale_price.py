"""TM confirmation must calculate its own offer, independent of stale hMoney."""
import io
from pathlib import Path
import unittest

from harness import SymbolTable
from pyboy import PyBoy


ROOT = Path(__file__).resolve().parents[2]


class MartTMSalePriceTest(unittest.TestCase):
    def test_tm_offer_replaces_stale_money_in_all_roms(self):
        # One machine from every price tier, including the reported Fissure.
        cases = ((0xC4, 500), (0xC9, 1500), (0xE3, 2500),
                 (0xCC, 4000), (0xC6, 6000), (0xD0, 8500))
        for variant in ("pokered", "pokeblue", "pokeblue_debug"):
            self.check_rom(variant, cases)

    def check_rom(self, variant, cases):
        symbols = SymbolTable(ROOT / f"{variant}.sym")
        rom = bytearray((ROOT / f"{variant}.gbc").read_bytes())
        rom[0x143] = 0  # Isolated DMG routine fixture, no gameplay resume.
        rom[0x14D] = (-sum(rom[0x134:0x14D]) - 25) & 0xFF
        pb = PyBoy(io.BytesIO(rom), cgb=False, window="null",
                   sound_emulated=False, log_level="CRITICAL")
        try:
            pb.tick(80, False)
            pb.memory[0xFFFF] = 0
            pb.memory[0xFF40] = 0
            pb.memory[0xC100:0xC102] = [0x18, 0xFE]
            finished = []

            def stop(_):
                finished.append(True)
                pb.register_file.PC = 0xC100

            bank, sale = symbols.get("DisplayPokemartDialogue_.sellTMConfirm")
            pb.hook_register(*symbols.get("DisplayPokemartDialogue_.sellShowPrice"), stop, None)
            for item, expected in cases:
                for stale in ([0, 0, 1], [0x09, 0x87, 0x65]):
                    with self.subTest(variant=variant, item=item, stale=stale):
                        finished.clear()
                        pb.memory[symbols.address("wCurItem")] = item
                        pb.memory[symbols.address("wListMenuID")] = 0
                        pb.memory[symbols.address("hHalveItemPrices")] = 1
                        pb.memory[symbols.address("hLoadedROMBank")] = bank
                        pb.memory[0x2000] = bank
                        money = symbols.address("hMoney")
                        pb.memory[money:money + 3] = stale
                        # Price resolver returns into the real TM confirm path.
                        pb.memory[0xDFE0:0xDFE2] = [sale & 0xFF, sale >> 8]
                        pb.register_file.SP = 0xDFE0
                        pb.register_file.PC = symbols.address("GetItemPrice")
                        for _ in range(30):
                            pb.tick(1, False)
                            if finished:
                                break
                        self.assertTrue(finished, "TM confirmation did not reach quote")
                        digits = f"{expected:06d}"
                        expected_bcd = [int(digits[i:i + 2], 16) for i in (0, 2, 4)]
                        self.assertEqual(list(pb.memory[money:money + 3]), expected_bcd)
                        self.assertEqual(pb.memory[symbols.address("wItemQuantity")], 1)
                        self.assertEqual(pb.register_file.SP, 0xDFE2)
                        self.assertEqual(pb.memory[symbols.address("hLoadedROMBank")], bank)
            # Ordinary quantity menus retain multiplication and sale halving.
            quote = symbols.address("DisplayPokemartDialogue_.sellShowPrice")
            for halve, expected in ((0, 900), (1, 450)):
                with self.subTest(variant=variant, quantity=3, halve=halve):
                    finished.clear()
                    price = symbols.address("hItemPrice")
                    pb.memory[price:price + 3] = [0, 3, 0]  # Potion: 300
                    pb.memory[money:money + 3] = [0x09, 0x87, 0x65]
                    pb.memory[symbols.address("wItemQuantity")] = 3
                    pb.memory[symbols.address("hHalveItemPrices")] = halve
                    pb.memory[0xDFE0:0xDFE2] = [quote & 0xFF, quote >> 8]
                    pb.register_file.SP = 0xDFE0
                    pb.register_file.PC = symbols.address("CalculateItemQuantityPrice")
                    for _ in range(30):
                        pb.tick(1, False)
                        if finished:
                            break
                    self.assertTrue(finished)
                    digits = f"{expected:06d}"
                    self.assertEqual(list(pb.memory[money:money + 3]),
                                     [int(digits[i:i + 2], 16) for i in (0, 2, 4)])
                    self.assertEqual(pb.register_file.SP, 0xDFE2)
        finally:
            pb.stop(save=False)
