"""The real Pokedex menu, driven by buttons (2026-11-03, "split by kind").

ShowPokedexMenu (custom_functions/form_dex.asm) keeps its 16-bit first-row and
row count in a stack frame, so the only way to exercise that bookkeeping is the
real loop: open the Pokedex from the Start menu, scroll, page to the numbered
rows at the end, open a form's DATA page, back out. Screen text is read from
wTileMap.
"""
from pathlib import Path
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_eevee_form_gate import BYTE_TO_CHAR

REPO_ROOT = Path(__file__).resolve().parents[2]
EVENTS = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
ROWS = re.findall(r"^\s*dw DEX_ROW_(SPECIES|REGIONAL|NUMBERED) \| (\w+)",
                  (REPO_ROOT / "data" / "pokemon" / "dex_display_rows.asm").read_text(encoding="utf-8"), re.M)


class DexListMenuTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.h = RedRogueHarness(REPO_ROOT, Path(__file__).parent / "artifacts")
        cls.h.boot_to_lobby()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.h.close()

    def text(self, col: int, row: int, length: int) -> str:
        data = self.h.read_bytes("wTileMap", length, offset=row * 20 + col)
        return "".join(BYTE_TO_CHAR.get(b, "?") for b in data)

    def press(self, loops: dict, button: str, times: int = 1) -> None:
        """Press `button`, then wait for the list loop to come round again."""
        start = loops["count"]
        for _ in range(times):
            self.h.tap(button, 4)
            self.h.tick(6)
        self.h.wait_until(lambda: loops["count"] > start, f"the Pokedex list after {button}", 600)
        self.h.tick(10)

    def test_list_scrolls_pages_to_the_numbered_rows_and_opens_a_form_page(self) -> None:
        h = self.h
        h.set_event(EVENTS["EVENT_GOT_POKEDEX"])
        # Everything seen, nothing owned: the list runs all 307 rows.
        for label, size in (("wPokedexSeen", 32), ("wPokedexFormSeen", 7)):
            for i in range(size):
                h.write8(label, 0xFF, offset=i)
        for label, size in (("wPokedexOwned", 32), ("wPokedexFormOwned", 7)):
            for i in range(size):
                h.write8(label, 0, offset=i)
        loops = h.hook_flag("DexListDrawRows")  # once per list pass
        menu = h.hook_flag("ShowPokedexMenu")
        start_menu = h.hook_flag("DisplayStartMenu")
        h.tick(60)
        for _ in range(300):  # the lobby takes a few presses before it listens
            h.tap("start", 2)
            h.tick(2)
            if start_menu["count"]:
                break
        self.assertTrue(start_menu["count"], "the Start menu opened")
        h.tick(30)
        h.tap("a", 4)  # POKeDEX is the Start menu's first item
        h.wait_until(lambda: loops["count"], "the Pokedex list", 900)
        self.assertEqual(menu["count"], 1)
        h.tick(20)

        self.assertEqual(self.text(1, 1, 8), "CONTENTS")
        self.assertEqual(self.text(1, 2, 3), "001")
        self.assertEqual(self.text(16, 3, 3), "307", "SEEN = the whole collection")

        # Down past the 7th row scrolls one row at a time.
        self.press(loops, "down", 7)
        self.assertEqual(self.text(1, 2, 3), "002", "scrolled by one")

        # RIGHT pages by 7; page to the end and the last page is the last 7 of the 16 numbered species.
        self.press(loops, "right", 60)
        last_first = len(ROWS) - 7
        self.assertEqual([k for k, _ in ROWS[last_first:]], ["NUMBERED"] * 7)
        self.assertEqual(self.text(1, 2, 3), f"{253 + 16 - 7:03d}", "first row of the last page")
        self.assertEqual(self.text(1, 14, 3), "268", "the last numbered row")
        self.assertEqual(self.text(4, 15, 8), "OVERQWIL")

        # LEFT pages back; a regional row has no number above it.
        self.press(loops, "left")
        first = len(ROWS) - 14
        for i in range(7):
            kind, _ = ROWS[first + i]
            number = self.text(1, 2 + 2 * i, 3)
            if kind == "REGIONAL":
                self.assertEqual(number, "   ", f"row {first + i} is unnumbered")

        # Open the top row's side menu and DATA page, then come back to the list.
        cursor = h.read8("hCurrentMenuItem")  # A acts on the cursor's row
        name = self.text(4, 3 + 2 * cursor, 10)
        top = self.text(4, 3, 10)
        page = h.hook_flag("FormDexShowData")
        species_page = h.hook_flag("ShowPokedexDataInternal")
        h.tap("a", 4)
        h.tick(10)
        h.tap("a", 4)  # DATA
        h.wait_until(lambda: page["count"] or species_page["count"], "a data page", 600)
        h.tick(60)
        self.assertEqual(self.text(9, 2, len(name.strip())), name.strip(), "the page names the row")
        # JoypadLowSensitivity can swallow the first press after the page is up;
        # tap until the list draws again.
        start = loops["count"]
        for _ in range(20):
            h.tap("b", 4)
            h.tick(20)
            if loops["count"] > start:
                break
        self.assertGreater(loops["count"], start, "back on the list after B")
        h.tick(20)
        self.assertEqual(self.text(1, 1, 8), "CONTENTS", "back on the list")
        self.assertEqual(self.text(4, 3, 10), top, "same rows after the page")

        # B leaves the Pokedex; the stack frame must be gone (no crash on the way out).
        overworld = h.hook_flag("OverworldLoop")
        h.tap("b", 4)
        h.tick(30)
        h.tap("b", 4)
        h.wait_until(lambda: overworld["count"], "the overworld after closing the Pokedex", 900)


if __name__ == "__main__":
    unittest.main()
