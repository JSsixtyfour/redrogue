"""The debug build's crash screen (engine/debug/crash_screen.asm).

Each case crashes the ROM the way a real bug does: it maps a bank, plants a
known stack and registers, and points PC at a $FF padding byte (or at NULL),
so the CPU itself executes `rst $38`. The screen must then name exactly what
was planted. test_cgb_crash_screen.py runs the same cases in CGB mode, with a
foreign WRAM bank selected at the crash.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest

from harness import RedRogueHarness


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
BANK_SIZE = 0x4000
TILEMAP = 0x9800
STACK_TOP = 0xDFF0
CALLERS = (0x1234, 0x5678, 0x9ABC, 0xDEF0, 0x1111, 0x2222)


def load_charmap() -> dict[int, str]:
    """Byte -> character for the plain one-character entries of the game's charmap."""
    text = (REPO_ROOT / "constants" / "charmap.asm").read_text(encoding="utf-8")
    chars: dict[int, str] = {}
    for char, value in re.findall(r'charmap "(.)",\s*\$([0-9a-fA-F]{2})', text):
        chars.setdefault(int(value, 16), char)
    return chars


def padding_address(rom: bytes) -> tuple[int, int]:
    """A ROMX bank whose last 64 bytes are $FF padding, and an address in them."""
    for bank in range(1, len(rom) // BANK_SIZE):
        tail = rom[(bank + 1) * BANK_SIZE - 64:(bank + 1) * BANK_SIZE]
        if tail == b"\xff" * 64:
            return bank, 0x7FD0
    raise AssertionError("no $FF-padded bank tail in the debug ROM")


class CrashScreenCases:
    """Mixed into a TestCase that sets CGB and WRAM_BANK."""

    CGB = False
    WRAM_BANK = 1

    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=self.CGB)
        self.harness.tick(240)
        self.chars = load_charmap()

    def tearDown(self) -> None:
        self.harness.close()

    def crash_at(self, bank: int, pc: int) -> None:
        memory = self.harness.pyboy.memory
        registers = self.harness.pyboy.register_file
        if self.CGB:
            memory[0xFF70] = self.WRAM_BANK  # rSVBK: the stack below is in this bank
        for index, word in enumerate(CALLERS):
            memory[STACK_TOP + 2 * index] = word & 0xFF
            memory[STACK_TOP + 2 * index + 1] = word >> 8
        memory[0x2000] = bank  # rROMB
        self.harness.write8("hLoadedROMBank", bank)
        registers.SP = STACK_TOP
        registers.B, registers.C = 0x01, 0x02
        registers.D, registers.E = 0x03, 0x04
        registers.HL = 0x0506
        registers.F = 0x80
        registers.PC = pc
        self.harness.tick(8)

    def row(self, number: int) -> str:
        memory = self.harness.pyboy.memory
        line = "".join(self.chars.get(memory[TILEMAP + number * 32 + col], "?") for col in range(20))
        return line.rstrip()

    def assert_common_rows(self, sp: int) -> None:
        self.assertEqual(self.row(0), "RED ROGUE CRASHED")
        self.assertTrue(self.row(3).startswith("ID "), self.row(3))
        self.assertEqual(self.row(6), f"SP  {sp:04X}   WRAM {self.WRAM_BANK:02X}")
        self.assertEqual(self.row(8), "STACK 1234 5678")
        self.assertEqual(self.row(9), "      9ABC DEF0")
        self.assertEqual(self.row(10), "      1111 2222")
        self.assertEqual(self.row(12), "BC 0102  DE 0304")
        self.assertEqual(self.row(13), "HL 0506  F  80")
        self.assertTrue(self.row(14).startswith("MAP "), self.row(14))
        self.assertEqual(self.row(17), "SEND IT TO THE DEVS")

    def test_stray_jump_into_padding_names_bank_and_address(self) -> None:
        bank, pc = padding_address(self.harness.rom_path.read_bytes())
        self.crash_at(bank, pc)
        self.assertEqual(self.row(5), f"PC  {bank:02X}:{pc:04X}")
        # rst pushed the return address below the planted callers
        self.assert_common_rows(STACK_TOP - 2)

    def test_jump_to_null_reads_as_pc_zero(self) -> None:
        self.crash_at(1, 0x0000)
        self.assertEqual(self.row(5), "PC  00:0000")
        self.assert_common_rows(STACK_TOP - 2)


class CrashScreenTest(CrashScreenCases, unittest.TestCase):
    pass


if __name__ == "__main__":
    unittest.main()
