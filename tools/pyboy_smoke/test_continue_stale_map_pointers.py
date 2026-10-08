"""Continue must not trust the saved ROM map pointers (FOLLOWUPS #51).

wCurMapDataPtr/TextPtr/ScriptPtr and the connection strip sources are ROM
addresses saved with the game. A new release moves map data, so a save from the
old build carries addresses that point at something else in the new ROM; the
facility hung on exactly that. LoadMapHeader now reloads the fixed header and
connection headers from this ROM even on Continue.

The tileset header has the same hazard and a different reload: Continue skips
LoadTilesetHeader, so LoadMainData refreshes it. The collision lists sit in HOME
and move with any HOME edit; a stale wTilesetCollisionPtr made every tile a wall.

The save is shifted the way a moved map would leave it, and the test checks the
live pointers after Continue, not just that it arrived: on the unfixed build
these particular wrong pointers continue without hanging, so arrival alone
cannot fail.
"""

from __future__ import annotations

import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants
from test_save_header import ARTIFACTS, REPO_ROOT, BANK, ColdBoot, SRAM_LABELS, dump_sram

POINTERS = (
    "wCurMapDataPtr", "wCurMapTextPtr", "wCurMapScriptPtr",
    "wTilesetBlocksPtr", "wTilesetGfxPtr", "wTilesetCollisionPtr",
)
SHIFT = 0x01FC  # the facility's measured move between schema 2 and 3 builds


def read16(h: RedRogueHarness, label: str) -> int:
    return h.read8(label) | h.read8(label, 1) << 8


def sram_offset(label: str) -> int:
    bank, addr = SRAM_LABELS[label]
    return BANK * bank + addr - 0xA000


class ContinueStaleMapPointersTest(unittest.TestCase):
    def test_facility_continue_reloads_rom_map_pointers(self) -> None:
        ids = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby(battle_count=11, encounter_kind=4)
            h.preload_and_enter_wild_area(ids["PROCEDURAL_FACILITY"], "facility")
            h.tick(240)
            facility = h.read8("hCurMap")
            expected = {label: read16(h, label) for label in POINTERS}
            main_data = h.address("wMainDataStart")
            offsets = {label: sram_offset("sMainData") + h.address(label) - main_data for label in POINTERS}
            h.call_routine("SaveGameData")
            sav = bytearray(dump_sram(h))
        finally:
            h.close()

        for label, offset in offsets.items():
            self.assertEqual(sav[offset] | sav[offset + 1] << 8, expected[label], f"{label} not at its SRAM offset")
            stale = (expected[label] - SHIFT) & 0xFFFF
            sav[offset], sav[offset + 1] = stale & 0xFF, stale >> 8
        first, end = sram_offset("sGameData"), sram_offset("sGameDataEnd")
        sav[sram_offset("sMainDataCheckSum")] = ~sum(sav[first:end]) & 0xFF

        boot = ColdBoot(bytes(sav))
        try:
            self.assertEqual(boot.to_menu(), 2, "the shifted save was not offered CONTINUE")
            boot.continue_game()
            self.assertEqual(boot.h.read8("hCurMap"), facility)
            got = {label: read16(boot.h, label) for label in POINTERS}
        finally:
            boot.close()
        self.assertEqual(got, expected, "Continue kept the saved ROM map pointers")


if __name__ == "__main__":
    unittest.main()
