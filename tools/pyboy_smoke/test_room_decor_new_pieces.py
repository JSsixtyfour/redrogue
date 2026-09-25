"""Room decor pieces added on the Dorm's extended tiles: DINOSAUR POSTER (TOP 9)
and SPACESHIP (MIDDLE 5).

Source checks keep the vendor's piece-id tables and the stamp tables honest;
the runtime check stamps both pieces through the real LoadMapData path.
"""

from pathlib import Path
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants


ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

FIRST_BORDER = 0x79
RESERVED_GLYPHS = {0x6D, 0x70, 0x71, 0x72, 0x73, 0x75}
TOP_DINO_POSTER = 9
MIDDLE_SPACESHIP = 5


def asm(name: str) -> str:
    return (ROOT / "custom_functions" / name).read_text(encoding="utf-8")


def db_rows(source: str, label: str) -> list[list[int]]:
    """Every `db` row after `label:` up to the next label."""
    body = source.split(f"\n{label}:", 1)[1]
    rows = []
    for line in body.splitlines()[1:]:
        line = line.split(";", 1)[0].strip()
        if not line:
            continue
        if not line.startswith("db "):
            break
        rows.append([int(v) for v in line[3:].split(",")])
    return rows


def dw_count(source: str, label: str) -> int:
    body = source.split(f"\n{label}:", 1)[1]
    names = re.match(r"\s*dw ((?:[^\n]*\\\n)*[^\n]*)", body).group(1)
    return len([n for n in names.replace("\\", "").split(",") if n.strip()])


def bcd2_count(source: str, label: str) -> int:
    body = source.split(f"\n{label}:", 1)[1]
    return len(re.match(r"(\s*bcd2 \d+)+", body).group(0).split("bcd2")) - 1


class RoomDecorSourceTest(unittest.TestCase):
    def test_vendor_piece_ids_are_a_permutation_of_the_owned_bits(self) -> None:
        vendor = asm("room_vendor.asm")
        seen = []
        for category in ("Top", "Middle", "Desk", "Plant", "Pals"):
            with self.subTest(category=category):
                rows = db_rows(vendor, f"RoomVendor{category}Ids")
                count, ids = rows[0][0], [i for row in rows[1:] for i in row]
                self.assertEqual(count, len(ids))
                self.assertEqual(count, dw_count(vendor, f"RoomVendor{category}Names"))
                self.assertEqual(count, bcd2_count(vendor, f"RoomVendor{category}Prices"))
                seen += ids
        # sRoomOwned is 4 bytes; RoomGrantAllPieces sets exactly these bits.
        self.assertEqual(sorted(seen), list(range(27)))
        self.assertEqual(vendor.count("RoomVendorTopIds"), 2)  # table + its one caller

    def test_new_pieces_have_their_stamp_rows(self) -> None:
        decor = asm("room_decor.asm")
        self.assertEqual(db_rows(decor, "RoomTopBlockTable")[TOP_DINO_POSTER], [32, 3, 15])
        self.assertEqual(db_rows(decor, "RoomMiddleBlockTable")[MIDDLE_SPACESHIP], [7, 8, 15])

    def test_stamped_blocks_use_only_loaded_non_glyph_tiles(self) -> None:
        decor = asm("room_decor.asm")
        bst = (ROOT / "gfx" / "blocksets" / "dorm.bst").read_bytes()
        blocks = set((ROOT / "maps" / "SilphCoDorm.blk").read_bytes())
        for table in ("RoomTopBlockTable", "RoomMiddleBlockTable", "RoomBottomBlockTable", "RoomPCBlockTable"):
            for row in db_rows(decor, table):
                blocks.update(row)
        for block in sorted(blocks):
            tiles = bst[block * 16:(block + 1) * 16]
            with self.subTest(block=hex(block)):
                self.assertEqual(len(tiles), 16, "block is past the end of dorm.bst")
                self.assertFalse([t for t in tiles if t >= FIRST_BORDER], "tile $79+ is never loaded")
                self.assertFalse(RESERVED_GLYPHS & set(tiles), "block draws a live text glyph slot")


class RoomDecorRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(ROOT, ARTIFACTS)
        self.maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")

    def tearDown(self) -> None:
        self.harness.close()

    def park(self) -> None:
        # Same VBlank-context park as test_dorm_extended_tiles: in the Dorm every
        # frame boundary lands in PrepareOAMData, one call below VBlank.
        pc = self.harness.pyboy.register_file.PC
        if self.harness.address("VBlank") <= pc < self.harness.address("DelayFrame"):
            return
        bank = self.harness.read8("hLoadedROMBank")
        name = self.harness.symbols.nearest(bank, pc) or ""
        self.assertTrue(
            name.startswith("PrepareOAMData") and bank == self.harness.symbols.bank("PrepareOAMData"),
            f"not parked in a VBlank context: PC=${pc:04x} bank ${bank:02x} ({name})",
        )

    def test_poster_and_spaceship_stamp_and_place_their_dolls(self) -> None:
        h = self.harness
        h.boot_debug1(self.maps["SILPH_CO_DORM"])
        h.write_sram_bytes("sRoomFurniture", [TOP_DINO_POSTER | (MIDDLE_SPACESHIP << 4), 0])
        # slots 4, 5 on the ship's side; slot 6 filled to prove it stays hidden
        h.write_sram_bytes("sRoomDecorSlots", [0, 0, 0, 8, 1, 2, 0, 0])
        self.park()
        h.call_routine("LoadMapData")

        cells = {offset: h.read8("wOverworldMap", offset) for offset in (35, 36, 45, 54, 55, 64)}
        self.assertEqual(cells, {35: 32, 36: 3, 45: 15, 54: 7, 55: 8, 64: 15})

        positions = h.sprite_positions(6)
        self.assertEqual(positions[3], [4, 1], "slot 4 should stand beside the ship at (1,4)")
        self.assertEqual(positions[4], [5, 1], "slot 5 should stand beside the ship at (1,5)")
        self.assertEqual(h.read8("wSprite06StateData1"), 0, "slot 6 has no spot with the ship")
        self.assertNotEqual(h.read8("wSprite04StateData1"), 0)
        self.assertNotEqual(h.read8("wSprite05StateData1"), 0)

        h.tick(30, render=True)
        ARTIFACTS.mkdir(exist_ok=True)
        h.pyboy.screen.image.save(ARTIFACTS / "room_decor_new_pieces.png")


if __name__ == "__main__":
    unittest.main()
