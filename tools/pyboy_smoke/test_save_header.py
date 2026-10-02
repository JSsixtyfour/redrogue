"""The battery-save header (constants/save_constants.asm, sSaveHeader).

Every save writes "RRSG", SAVE_SCHEMA_ID and its complement at SRAM bank 1
$a040; Continue refuses a save without exactly that header, before reading
anything, and leaves the save untouched so the patch page can convert it.

These go through real cold boots: the save is dumped as a raw 32 KiB .sav,
then a new emulator boots from it and presses through the title and Continue,
the way a player does. No emulator state is carried between boots.
"""

from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path

from harness import RedRogueHarness

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
BANK = 0x2000
HEADER_OFFSET = BANK * 1 + 0x40  # bank 1, $a040


def sram_labels() -> dict[str, tuple[int, int]]:
    labels = {}
    for line in (REPO_ROOT / "pokeblue_debug.sym").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([0-9a-f]{2}):([0-9a-f]{4}) (s\w+)$", line.strip())
        if m and 0xA000 <= int(m.group(2), 16) < 0xC000:
            labels[m.group(3)] = (int(m.group(1), 16), int(m.group(2), 16))
    return labels


SRAM_LABELS = sram_labels()
# tools/save_schemas/policy.json "scratch": rewritten before every use, never read across a load.
SCRATCH = {"sSpriteBuffer0", "sSpriteBuffer1", "sSpriteBuffer2", "sFusionDiagBuf"}


def schema_id() -> int:
    text = (REPO_ROOT / "constants" / "save_constants.asm").read_text(encoding="utf-8")
    return int(re.search(r"DEF SAVE_SCHEMA_ID EQU (\d+)", text).group(1))


def expected_header(sid: int) -> bytes:
    inverse = ~sid & 0xFFFF
    return b"RRSG" + sid.to_bytes(2, "little") + inverse.to_bytes(2, "little")


def dump_sram(h: RedRogueHarness) -> bytes:
    data = bytearray()
    for bank in range(4):
        h.pyboy.memory[0x0000] = 0x0A
        h.pyboy.memory[0x4000] = bank
        data += bytes(h.pyboy.memory[0xA000:0xC000])
    h.pyboy.memory[0x0000] = 0
    return bytes(data)


class ColdBoot:
    """Boot a ROM from a .sav and press through the title to the main menu."""

    def __init__(self, sav: bytes | None):
        self.tmp = tempfile.TemporaryDirectory()
        ram = None
        if sav is not None:
            ram = Path(self.tmp.name) / "game.sav"
            ram.write_bytes(sav)
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS, ram_path=ram)
        self.menu = self.h.hook_flag("MainMenu.mainMenuLoop")
        self.refused = self.h.hook_flag("TryLoadSaveFile.refuse")
        self.chose = self.h.hook_flag("MainMenu.choseContinue")
        self.pressed = self.h.hook_flag("MainMenu.pressedA")
        self.entered = self.h.hook_flag("SpecialEnterMap")

    def to_menu(self) -> int:
        """Returns wSaveFileStatus as the menu shows (1: NEW GAME only, 2: CONTINUE offered)."""
        self.h.tick(240)
        for _ in range(300):
            self.h.tap("start", 2)
            self.h.tick(2)
            if self.menu["count"]:
                break
            if self.refused["count"]:
                self.h.tap("a", 2)  # dismiss the message; it ends in a prompt
        if not self.menu["count"]:
            raise AssertionError("main menu never appeared")
        return self.h.read8("wSaveFileStatus")

    def continue_game(self) -> None:
        self.h.tick(30)
        for _ in range(60):
            self.h.tap("a", 2)
            self.h.tick(4)
            if self.chose["count"]:
                break
        for _ in range(120):
            self.h.tap("a", 2)
            self.h.tick(4)
            if self.pressed["count"]:
                break
        self.h.wait_until(lambda: self.entered["count"] > 0, "entering the saved map", 900)
        self.h.tick(120)

    def close(self) -> None:
        self.h.close()
        self.tmp.cleanup()


class SaveHeaderTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby(battle_count=11)
            cls.saved_map = h.read8("hCurMap")
            cls.saved_party = h.read8("wPartyCount")
            h.call_routine("SaveGameData")
            cls.sav = dump_sram(h)
        finally:
            h.close()

    def boot(self, sav: bytes | None) -> ColdBoot:
        boot = ColdBoot(sav)
        self.addCleanup(boot.close)
        return boot

    def test_save_writes_the_header(self) -> None:
        self.assertEqual(self.sav[HEADER_OFFSET:HEADER_OFFSET + 8], expected_header(schema_id()))

    def test_cold_boot_continue_save_and_continue_again(self) -> None:
        first = self.boot(self.sav)
        self.assertEqual(first.to_menu(), 2)
        self.assertEqual(first.refused["count"], 0)
        first.continue_game()
        self.assertEqual(first.h.read8("hCurMap"), self.saved_map)
        self.assertEqual(first.h.read8("wPartyCount"), self.saved_party)
        first.h.call_routine("SaveGameData")
        resaved = dump_sram(first.h)
        self.assertEqual(resaved[HEADER_OFFSET:HEADER_OFFSET + 8], expected_header(schema_id()))

        second = self.boot(resaved)
        self.assertEqual(second.to_menu(), 2)
        second.continue_game()
        self.assertEqual(second.h.read8("hCurMap"), self.saved_map)
        self.assertEqual(second.h.read8("wPartyCount"), self.saved_party)

    def assert_refused_untouched(self, sav: bytes) -> None:
        boot = self.boot(sav)
        self.assertEqual(boot.to_menu(), 1, "a refused save must leave only NEW GAME")
        self.assertEqual(boot.refused["count"], 1)
        boot.h.tick(60)
        after = dump_sram(boot.h)
        touched = {self.label_at(i) for i, (a, b) in enumerate(zip(sav, after)) if a != b}
        # The title screen decompresses its Pokemon picture through the SRAM
        # sprite buffers (policy: scratch) on every boot; nothing else may change.
        self.assertLessEqual(touched, SCRATCH, f"a refused save must not be modified; touched {sorted(touched)}")

    def label_at(self, offset: int) -> str:
        """The SRAM label a dump offset falls in (the last one at or before it)."""
        bank, address = divmod(offset, BANK)
        address += 0xA000
        best = None
        for name, (b, a) in SRAM_LABELS.items():
            if b == bank and a <= address and (best is None or a > best[1]):
                best = (name, a)
        return best[0] if best else f"{bank}:{address:04x}"

    def test_untagged_save_is_refused_and_left_untouched(self) -> None:
        untagged = bytearray(self.sav)
        untagged[HEADER_OFFSET:HEADER_OFFSET + 8] = b"\xff" * 8  # what a 74f82c1b save holds there
        self.assert_refused_untouched(bytes(untagged))

    def test_other_schema_or_damaged_header_is_refused(self) -> None:
        sid = schema_id()
        for header in (expected_header(sid + 1), expected_header(sid)[:6] + b"\x00\x00", b"RRSX" + expected_header(sid)[4:]):
            with self.subTest(header=header.hex()):
                sav = bytearray(self.sav)
                sav[HEADER_OFFSET:HEADER_OFFSET + 8] = header
                self.assert_refused_untouched(bytes(sav))

    def test_blank_sram_is_a_plain_new_game(self) -> None:
        boot = self.boot(b"\xff" * 0x8000)
        self.assertEqual(boot.to_menu(), 1)
        self.assertEqual(boot.refused["count"], 0, "blank SRAM is no save, not a save to convert")


if __name__ == "__main__":
    unittest.main()
