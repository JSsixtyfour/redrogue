"""Room decor pieces added on the Dorm's extended tiles, DINOSAUR POSTER (TOP 9)
and SPACESHIP (MIDDLE 5), plus the decoration dolls 12-21 and the scrolling
pick list they need.

Source checks keep the vendor's piece-id tables, the stamp tables and the
Dorm's collision honest; the runtime checks stamp both pieces through the real
LoadMapData path and drive the PC's decoration picker past its first screen.
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
NUM_DECORATIONS = 21
NUM_PIECES = 37


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
    return len(re.findall(r"^\s*bcd2 \d+", re.match(r"(\s*bcd2 \d+[^\n]*)+", body).group(0), re.M))


def dorm_passable_tiles() -> set[int]:
    source = (ROOT / "data" / "tilesets" / "collision_tile_ids.asm").read_text(encoding="utf-8")
    body = source.split("\nDorm_Coll::", 1)[1]
    line = next(l for l in body.splitlines() if "coll_tiles" in l)
    return {int(v.strip().lstrip("$"), 16) for v in line.split("coll_tiles", 1)[1].split(",")}


def block_steps(block: int) -> list[list[int]]:
    """Collision tile of each 16px step: the lower-left tile of its 2x2."""
    tiles = (ROOT / "gfx" / "blocksets" / "dorm.bst").read_bytes()[block * 16:(block + 1) * 16]
    return [[tiles[(sy * 2 + 1) * 4 + sx * 2] for sx in range(2)] for sy in range(2)]


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
        # RoomGrantAllPieces sets exactly these bits across sRoomOwned + sRoomOwnedExt.
        self.assertEqual(sorted(seen), list(range(NUM_PIECES)))

    def test_decoration_tables_agree_on_the_count(self) -> None:
        pc = asm("room_pc.asm")
        self.assertEqual(dw_count(pc, "RoomDecorationNameTable"), NUM_DECORATIONS + 1)
        self.assertEqual(dw_count(pc, "RoomDecorationDescTable"), NUM_DECORATIONS + 1)
        self.assertIn(f"ld b, {NUM_DECORATIONS + 1}\n\tcall RoomDrawPickList", pc)
        self.assertIn(f"DEF NUM_ROOM_DECORATIONS EQU {NUM_DECORATIONS}", asm("room_decor.asm"))
        script = (ROOT / "scripts" / "SilphCoDorm.asm").read_text(encoding="utf-8")
        table = script.split("RoomDecorationTextTable:", 1)[1].split("\n\n", 1)[0]
        self.assertEqual(table.count("dw ."), NUM_DECORATIONS + 1)

    def test_new_pieces_have_their_stamp_rows(self) -> None:
        decor = asm("room_decor.asm")
        self.assertEqual(db_rows(decor, "RoomTopBlockTable")[TOP_DINO_POSTER], [32, 3, 15])
        middle = db_rows(decor, "RoomMiddleBlockTable")
        self.assertTrue(all(len(row) == 4 for row in middle), "MIDDLE rows are (1,2) (2,2) (3,2) (1,3)")
        self.assertEqual(middle[MIDDLE_SPACESHIP], [15, 7, 8, 15])

    def test_spaceship_cannot_be_walked_on(self) -> None:
        passable = dorm_passable_tiles()
        left, right = block_steps(7), block_steps(8)
        solid = [left[0][0], left[0][1], left[1][0], left[1][1], right[0][0], right[1][0]]
        self.assertFalse([f"${t:02X}" for t in solid if t in passable],
                         "a ship step is walkable")

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
        # slots 4, 5 beside the ship; slot 6 filled to prove it stays hidden
        h.write_sram_bytes("sRoomDecorSlots", [0, 0, 0, 8, 1, 2, 0, 0])
        self.park()
        h.call_routine("LoadMapData")

        cells = {offset: h.read8("wOverworldMap", offset) for offset in (35, 36, 45, 54, 55, 56, 64)}
        self.assertEqual(cells, {35: 32, 36: 3, 45: 15, 54: 15, 55: 7, 56: 8, 64: 15})

        positions = h.sprite_positions(6)
        self.assertEqual(positions[3], [4, 3], "slot 4 should stand beside the ship at (3,4)")
        self.assertEqual(positions[4], [5, 3], "slot 5 should stand beside the ship at (3,5)")
        self.assertEqual(h.read8("wSprite06StateData1"), 0, "slot 6 has no spot with the ship")
        self.assertNotEqual(h.read8("wSprite04StateData1"), 0)
        self.assertNotEqual(h.read8("wSprite05StateData1"), 0)

        h.tick(30, render=True)
        ARTIFACTS.mkdir(exist_ok=True)
        h.pyboy.screen.image.save(ARTIFACTS / "room_decor_new_pieces.png")

    def press(self, button: str, settle: int = 8) -> None:
        self.harness.tap(button, 4)
        self.harness.tick(settle)

    def test_decoration_picker_scrolls_to_the_new_dolls(self) -> None:
        h = self.harness
        h.boot_debug1(self.maps["SILPH_CO_DORM"])
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (1, 7), "spawn moved; re-plan the walk")
        def step(direction: str) -> None:
            # move_tile's 20-frame hold outlasts a 16-frame step in this small
            # room and walks two tiles; a short press walks exactly one.
            h.pyboy.button_press(direction)
            h.tick(3)
            h.pyboy.button_release(direction)
            h.tick(30)

        for _ in range(10):
            if h.read8("wYCoord") <= 2:
                break
            step("up")
        step("left")
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (0, 2), "did not reach the PC's front")
        step("up")  # the desk blocks the step; this only turns to face it

        picker = h.hook_flag("RoomPickDecorationForSlot")
        self.press("a", 60)
        for _ in range(40):  # PC boot text, if any, then the RoomPC menu
            if h.read8("wMaxMenuItem") >= 3 and h.read8("wTopMenuItemY") == 2:
                break
            self.press("a", 20)
        self.press("down")
        self.press("down")
        self.press("a", 30)      # DECORATIONS
        for _ in range(4):
            self.press("down")
        self.press("a", 30)      # BEDSIDE (slot 0)
        self.assertEqual(picker["count"], 1, "the decoration picker did not open")
        self.assertEqual(h.read8("wMaxMenuItem"), 11, "the picker should show 12 of its 22 rows")

        def state() -> tuple[int, int]:
            return h.read8("wBuffer", 14), h.read8("hCurrentMenuItem")

        for _ in range(21):
            self.press("down")
        self.assertEqual(state(), (10, 11), "down to MEWTWO: offset 10, bottom row")
        for _ in range(12):
            self.press("up")
        self.assertEqual(state(), (9, 0), "back up past the top row scrolls one entry")
        for _ in range(12):
            self.press("down")
        self.assertEqual(state(), (10, 11))
        h.tick(10, render=True)
        ARTIFACTS.mkdir(exist_ok=True)
        h.pyboy.screen.image.save(ARTIFACTS / "room_decor_scrolled_picker.png")
        self.press("a", 30)
        self.assertEqual(h.read_sram_bytes("sRoomDecorSlots", 1), [NUM_DECORATIONS], "MEWTWO was not stored")
        self.assertEqual(h.read8("wMenuWatchMovingOutOfBounds"), 0, "left the out-of-bounds watch on")


if __name__ == "__main__":
    unittest.main()
