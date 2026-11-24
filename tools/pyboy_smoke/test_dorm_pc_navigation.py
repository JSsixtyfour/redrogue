"""Dorm PC navigation: B goes back exactly one stage with the cursor where it was,
the RECORDS cursor sits on its rows while TOGGLES is unlocked, the key item list
empties when its last item moves out, and no sprite draws over a menu box.

The box check runs at every stop, with and without TOGGLES, because the PC's menu
is a different height in each: the player used to be hidden by one tile only, so a
box ending on the row above it left the head on top.
"""

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
from test_eevee_form_gate import CHAR_TO_BYTE

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
EVENTS = parse_rgbds_constants(ROOT / "constants" / "event_constants.asm")
RAM = parse_rgbds_constants(ROOT / "constants" / "ram_constants.asm")
MAPS = parse_map_constants(ROOT / "constants" / "map_constants.asm")
KEY_ITEMS, FURNITURE, DECORATIONS, RECORDS, CHALLENGES = range(5)
CURSOR = 0xED
DORM_TILE_LIMIT = 0x79  # GetMapTileLimit on the DORM tileset


def text(value):
    return [CHAR_TO_BYTE[c] for c in value]


class DormPCNavigationTest(unittest.TestCase):
    toggles = False

    def open_pc(self):
        h = self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_debug1(MAPS["SILPH_CO_DORM"])
        if self.toggles:
            h.set_event(EVENTS["EVENT_JOHTO_ACTIVATED"])
        for _ in range(10):
            if h.read8("wYCoord") <= 2:
                break
            self.step("up")
        self.step("left")
        self.step("up")
        self.press("a", 60)
        for _ in range(40):
            if h.read8("wMaxMenuItem") == 5 + self.toggles:
                break
            self.press("a", 20)
        h.tick(30)
        self.at_main(0)

    def step(self, direction):
        self.h.pyboy.button_press(direction)
        self.h.tick(3)
        self.h.pyboy.button_release(direction)
        self.h.tick(30)

    def press(self, button, settle=16):
        self.h.tap(button, 4)
        self.h.tick(settle)

    def choose(self, row, settle=40):
        for _ in range(8):
            current = self.h.read8("hCurrentMenuItem")
            if current == row:
                break
            self.press("down" if current < row else "up")
        self.assertEqual(self.h.read8("hCurrentMenuItem"), row)
        self.press("a", settle)

    def tiles(self):
        flat = self.h.read_bytes("wTileMap", 360)
        return [flat[i * 20:i * 20 + 20] for i in range(18)]

    def no_sprite_over_a_box(self):
        """Every drawn sprite stands on map tiles only."""
        if self.h.read8("hUpdateSpritesEnabled") != 1:
            return
        rows = self.tiles()
        for slot in range(16):
            data = self.h.read_bytes("wSpriteStateData1", 16, slot * 16)
            if not data[0] or data[2] == 0xFF:
                continue
            y, x = (data[4] + 4) & 0xFF, data[6]
            if y >= 144 or x >= 160:
                continue
            for row in (y // 8, y // 8 + 1):
                for col in (x // 8, x // 8 + 1):
                    if row < 18 and col < 20:
                        self.assertLess(rows[row][col], DORM_TILE_LIMIT,
                                        f"sprite {slot} is drawn over the box tile at {col},{row}")

    def at(self, label, row_tile, cursor):
        """The menu holding `label` at screen row `row_tile`, cursor on item `cursor`."""
        rows = self.tiles()
        self.assertEqual(rows[row_tile][2:2 + len(label)], text(label))
        self.assertEqual(self.h.read8("hCurrentMenuItem"), cursor)
        self.no_sprite_over_a_box()

    def at_main(self, cursor):
        top = 1 if self.toggles else 2
        self.at("KEY ITEMS", top, cursor)
        stride = 1 if self.toggles else 2
        self.assertEqual(self.tiles()[top + stride * cursor][1], CURSOR)

    def at_furniture(self, cursor):
        self.at("MIDDLE", 6, cursor)
        self.assertEqual(self.tiles()[2 + 2 * cursor][1], CURSOR)

    def test_furniture_backs_out_one_stage_at_a_time(self):
        self.open_pc()
        self.choose(FURNITURE)
        self.at_furniture(0)
        for row in range(4):
            self.choose(row)
            self.no_sprite_over_a_box()
            self.press("b", 40)
            self.at_furniture(row)
        self.choose(1)
        self.press("a", 40)                    # a choice comes back here as well
        self.at_furniture(1)
        self.press("b", 40)
        self.at_main(FURNITURE)

    def test_decorations_back_out_through_the_spot_picker(self):
        self.open_pc()
        # LONG DESK: the PC area then has two spots.
        furniture = self.h.read_sram_bytes("sRoomFurniture", 2)
        self.h.write_sram_bytes("sRoomFurniture", [furniture[0], furniture[1] | 1])
        self.choose(DECORATIONS)
        self.at("BEDSIDE", 10, 0)
        self.press("a", 40)
        self.at("SPOT 2", 3, 0)
        self.choose(1)                         # the decoration list
        self.at("NONE", 1, 0)
        self.press("b", 40)
        self.at("SPOT 2", 3, 0)
        self.press("b", 40)
        self.at("BEDSIDE", 10, 0)
        self.choose(4)                         # BEDSIDE has no spot picker
        self.at("NONE", 1, 0)
        self.press("a", 40)
        self.at("BEDSIDE", 10, 4)
        self.press("b", 40)
        self.at_main(DECORATIONS)

    def test_records_cursor_is_on_its_rows_and_is_kept(self):
        self.open_pc()
        self.h.write8("wNumHoFTeams", 0)
        self.choose(RECORDS)
        for row in range(5):
            self.at("RUN TIMES", 2, row)
            self.assertEqual(self.tiles()[2 + 2 * row][1], CURSOR, f"cursor off row {row}")
            if row < 4:
                self.press("down")
        for row, name in ((0, "RUN TIMES"), (1, "FURTHEST"), (3, "CHALLENGES")):
            self.choose(row, 60)
            self.no_sprite_over_a_box()
            self.press("b", 60)
            self.at("RUN TIMES", 2, row)
        self.press("b", 40)
        self.at_main(RECORDS)

    def test_challenges_toggle_and_return(self):
        self.open_pc()
        self.choose(CHALLENGES)
        self.at("POOR REWARDS", 1, 0)
        self.assertEqual(self.tiles()[1][16:19], [0x7F] + text("--"))
        self.press("a", 20)
        self.assertEqual(self.tiles()[1][16:19], [0x7F] + text("ON"))
        self.press("b", 40)
        self.at_main(CHALLENGES)

    def test_locked_challenges_say_so(self):
        self.open_pc()
        self.h.set_event(EVENTS["EVENT_GOT_STARTER"])
        self.choose(CHALLENGES)
        before = self.h.read_bytes("wRunChallenges", 2)
        self.press("down")
        self.press("a", 30)
        self.assertEqual(self.tiles()[14][1:13], text("Locked until"))
        self.assertEqual(self.h.read_bytes("wRunChallenges", 2), before)
        self.assertEqual(self.h.read8("hCurrentMenuItem"), 1)
        self.press("down")
        self.assertNotEqual(self.tiles()[14][1:13], text("Locked until"))
        cursor_column = [row[1] for row in self.tiles()[1:9]]
        self.assertEqual(cursor_column, [0x7F, 0x7F, CURSOR] + [0x7F] * 5, "a stale arrow is left behind")
        for _ in range(5):
            self.press("down")
        self.press("a", 30)                    # locked on the last row...
        self.press("down")                     # ...DOWN still turns the page
        self.assertEqual(self.tiles()[1][2:12], text("NO HEALING"))
        self.press("b", 40)
        self.at_main(CHALLENGES)

    def test_key_item_lists_empty_when_the_last_item_moves(self):
        self.open_pc()
        owned = 0
        for name in ("LEFTOVERS", "PP_TONIC"):
            owned |= 3 << RAM[f"KEY_ITEM_BIT_{name}_OWNED"]
        self.h.write_sram_bytes("sKeyItemsBitfield", list(owned.to_bytes(4, "little")))
        self.choose(KEY_ITEMS, 60)
        for row, message in ((1, "Bag is empty."), (0, "Nothing to")):
            self.choose(row, 90)               # DEPOSIT, then WITHDRAW
            for _ in range(2):
                self.press("a", 60)            # the item
                self.press("a", 60)            # its message
            rows = self.tiles()
            self.assertEqual(rows[14][1:1 + len(message)], text(message))
            for line in rows[:12]:
                self.assertEqual(line, [0x7F] * 20, "the moved item is still listed")
            self.no_sprite_over_a_box()
            self.press("a", 60)
            self.at("WITHDRAW", 2, row)
        self.press("b", 60)
        self.at_main(KEY_ITEMS)


class DormPCNavigationTogglesTest(DormPCNavigationTest):
    """The same, with the single-spaced seven-row menu."""
    toggles = True


if __name__ == "__main__":
    unittest.main()
