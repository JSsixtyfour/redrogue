"""DORM-only tileset extension: vChars2 $60-$78 belong to the Dorm's tileset.

Every other tileset still ends at $5F, with font_extra's glyphs at $60-$78.
The Dorm keeps six of those glyphs alive by baking them into dorm.png at the
same IDs (constants/tileset_constants.asm), so text there still renders.
"""

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants


ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

TILE = 16
FIRST_EXTRA = 0x60
FIRST_BORDER = 0x79
RESERVED_GLYPHS = (0x6D, 0x70, 0x71, 0x72, 0x73, 0x75)
VCHARS2 = 0x9000


def dorm_gfx() -> bytes:
    return (ROOT / "gfx" / "tilesets" / "dorm.2bpp").read_bytes()


def font_extra() -> bytes:
    return (ROOT / "gfx" / "font" / "font_extra.2bpp").read_bytes()


class DormExtendedTilesAssetTest(unittest.TestCase):
    def test_dorm_sheet_is_exactly_the_extended_size(self) -> None:
        # The Makefile's --preserve=0x78 keeps trailing blank slots; without it
        # the $790-byte load would read Dorm_Block into VRAM.
        self.assertEqual(len(dorm_gfx()), FIRST_BORDER * TILE)

    def test_reserved_glyph_slots_match_font_extra(self) -> None:
        dorm, font = dorm_gfx(), font_extra()
        for tile in RESERVED_GLYPHS:
            with self.subTest(tile=hex(tile)):
                offset = (tile - FIRST_EXTRA) * TILE
                self.assertEqual(
                    dorm[tile * TILE:(tile + 1) * TILE],
                    font[offset:offset + TILE],
                    f"dorm.png slot ${tile:02X} is a live text glyph; restore it "
                    "from font_extra.png instead of drawing over it",
                )


class DormExtendedTilesRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(ROOT, ARTIFACTS)
        self.maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")

    def tearDown(self) -> None:
        self.harness.close()

    def vram(self, first_tile: int, last_tile: int) -> bytes:
        start = VCHARS2 + first_tile * TILE
        memory = self.harness.pyboy.memory
        return bytes(memory[start + i] for i in range((last_tile - first_tile) * TILE))

    def park(self) -> None:
        # In the Dorm every frame boundary lands in PrepareOAMData, which the
        # VBlank handler calls after saving registers and the ROM bank - the same
        # safe interrupt context park_before_hijack looks for, one call deeper
        # than its address window. Accept either.
        pc = self.harness.pyboy.register_file.PC
        if self.harness.address("VBlank") <= pc < self.harness.address("DelayFrame"):
            return
        bank = self.harness.read8("hLoadedROMBank")
        name = self.harness.symbols.nearest(bank, pc) or ""
        self.assertTrue(
            name.startswith("PrepareOAMData") and bank == self.harness.symbols.bank("PrepareOAMData"),
            f"not parked in a VBlank context: PC=${pc:04x} bank ${bank:02x} ({name})",
        )

    def scribble(self) -> None:
        memory = self.harness.pyboy.memory
        for address in range(VCHARS2 + FIRST_EXTRA * TILE, VCHARS2 + 0x80 * TILE):
            memory[address] = 0xA5
        self.assertEqual(self.vram(FIRST_EXTRA, 0x80), bytes([0xA5]) * (0x20 * TILE),
                         "VRAM scribble did not land; the reload checks would prove nothing")

    def assert_dorm_tiles(self, when: str) -> None:
        self.assertEqual(
            self.vram(FIRST_EXTRA, FIRST_BORDER),
            dorm_gfx()[FIRST_EXTRA * TILE:],
            f"$60-$78 are not the Dorm's tiles {when}",
        )
        self.assertEqual(
            self.vram(FIRST_BORDER, 0x80),
            font_extra()[(FIRST_BORDER - FIRST_EXTRA) * TILE:],
            f"$79-$7F are not the text-box borders {when}",
        )

    def test_dorm_owns_60_to_78_through_every_reload_path(self) -> None:
        self.harness.boot_debug1(self.maps["SILPH_CO_DORM"])
        self.assert_dorm_tiles("after entering the Dorm")

        self.park()
        self.scribble()
        self.harness.call_routine("ReloadTilesetTilePatterns")
        self.assertEqual(
            self.vram(FIRST_EXTRA, FIRST_BORDER),
            dorm_gfx()[FIRST_EXTRA * TILE:],
            "ReloadTilesetTilePatterns (Bill's PC, evolution exits) did not restore $60-$78",
        )

        self.scribble()
        self.harness.call_routine("ReloadMapData")
        self.assert_dorm_tiles("after ReloadMapData")

    def test_leaving_the_dorm_restores_font_glyphs(self) -> None:
        # LoadMapData loads the text box BEFORE LoadMapHeader, while the
        # tileset still says DORM. The glyphs must still come back.
        self.harness.boot_debug1(self.maps["SILPH_CO_DORM"])
        self.assert_dorm_tiles("before leaving")
        self.assertNotEqual(self.vram(FIRST_EXTRA, 0x80), font_extra(),
                            "precondition: Dorm VRAM must differ from font_extra")
        self.park()
        self.harness.write8("hCurMap", self.maps["SILPH_CO_B1F"])
        self.harness.call_routine("LoadMapData")
        self.assertEqual(
            self.vram(FIRST_EXTRA, 0x80),
            font_extra(),
            "font_extra glyphs were not restored after leaving the Dorm",
        )


if __name__ == "__main__":
    unittest.main()
