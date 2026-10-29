"""The slot text handler deliberately advances past its winning-symbol icon."""
import unittest
from pathlib import Path
from harness import RedRogueHarness
from test_move_tutor_prices import run_entry

ROOT = Path(__file__).resolve().parents[2]


class SlotTextCursorTest(unittest.TestCase):
    def exercise(self, cgb=False):
        h = RedRogueHarness(ROOT, Path(__file__).parent / "artifacts", cgb_mode=cgb)
        self.addCleanup(h.close)
        h.tick(120)
        bank, address = h.symbols.get("SymbolLinedUpSlotMachineText")
        # Direct entry after the text_asm opcode, using the established caller.
        alias = "SlotTextCursorTestBody"
        h.symbols._symbols[alias] = (bank, address + 1)
        cursor = h.address("wTileMap") + 14 * 20 + 1
        for symbol in (0, 4, 8, 12, 16, 20):
            with self.subTest(symbol=symbol):
                def setup(h):
                    h.write8("wSlotMachineWinningSymbol", symbol)
                    base = h.address("wTileMap")
                    h.pyboy.memory[base:base + 360] = [0x7f] * 360

                def capture(h):
                    cpu = h.pyboy.register_file
                    tiles = h.read_bytes("wTileMap", 360)
                    return {"bc": (cpu.B << 8) | cpu.C, "hl": cpu.HL,
                            "icon": [tiles[262], tiles[263], tiles[282], tiles[283]]}

                result = run_entry(h, alias, registers={"B": cursor >> 8, "C": cursor & 255},
                                   setup=setup, capture=capture, limit=30)
                self.assertEqual(result["bc"], cursor + 4)
                self.assertEqual(result["hl"], h.address("LinedUpText"))
                self.assertEqual(result["icon"], [symbol + 0x27, symbol + 0x28,
                                                  symbol + 0x25, symbol + 0x26])

    def test_all_winning_symbols_advance_cursor_and_keep_text_continuation(self):
        self.exercise()
