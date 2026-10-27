"""Credits roll: title-menu entry, SELECT fast-forward, START skip, data shape.

The roll (engine/movie/credits.asm) is reachable from the title menu's last
item, CREDITS. SELECT toggles 4x speed, START jumps to THE END, and a START
still held from picking the item must not count as a skip. The source checks
guard the CreditsOrder rules the engine relies on but cannot assert itself.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from harness import RedRogueHarness

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

MON_COMMANDS = ("CRED_TEXT_MON", "CRED_TEXT_FADE_MON")
SCREEN_COMMANDS = ("CRED_TEXT", "CRED_TEXT_FADE", "CRED_TEXT_MON", "CRED_TEXT_FADE_MON")


def _db_tokens(path: Path) -> list[str]:
    tokens: list[str] = []
    for line in path.read_text().splitlines():
        line = line.split(";", 1)[0].strip()
        if line.startswith("db "):
            tokens += [t.strip() for t in line[3:].split(",") if t.strip()]
    return tokens


class CreditsSourceContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.order = _db_tokens(REPO_ROOT / "data/credits/credits_order.asm")

    def test_screens_fit_four_lines(self) -> None:
        lines = 0
        for token in self.order:
            if token in SCREEN_COMMANDS:
                self.assertLessEqual(lines, 4, "credits text extends into the bottom black bar")
                lines = 0
            elif token not in ("CRED_COPYRIGHT", "CRED_THE_END"):
                lines += 1

    def test_strings_are_unique_reachable_and_match_the_pointer_order(self) -> None:
        text = (REPO_ROOT / "data/credits/credits_text.asm").read_text()
        constants = (REPO_ROOT / "constants/credits_constants.asm").read_text()
        pointers = re.findall(r"^\s*dw (Cred\w+)$", text, re.M)
        ids = re.findall(r"^\s*const (CRED_\w+)", constants.split("DEF NUM_CRED_STRINGS")[0], re.M)
        self.assertEqual(len(pointers), len(ids))
        definitions = re.findall(r"^(Cred\w+):", text, re.M)
        self.assertEqual(len(definitions), len(set(definitions)), "duplicate credit label")
        self.assertTrue(set(pointers) <= set(definitions), "undefined credit pointer target")
        rr_strings = re.findall(r'^(CredRR\w+):\s+credits_string "([^"]+)"', text, re.M)
        self.assertEqual(pointers[64:], [label for label, _ in rr_strings])
        for label, value in rr_strings:
            with self.subTest(label=label):
                self.assertGreater(len(value), 0)
                self.assertLessEqual(len(value), 20)
                self.assertIn(label, pointers, "string has no pointer entry")
                self.assertIn(ids[pointers.index(label)], self.order, "string never appears in the roll")
        for token in self.order:
            self.assertIn(token, ids + list(SCREEN_COMMANDS) + ["CRED_COPYRIGHT", "CRED_THE_END"])

    def test_every_mon_screen_has_a_creditsmons_entry(self) -> None:
        mons = _db_tokens(REPO_ROOT / "data/credits/credits_mons.asm")
        used = sum(1 for t in self.order if t in MON_COMMANDS)
        self.assertEqual(used, len(mons), "DisplayCreditsMon reads CreditsMons + the mon count")

    def test_first_screen_and_every_screen_after_a_mon_fade_in(self) -> None:
        # The roll starts, and every mon scroll ends, with the text palette at
        # %11000000, where the shifted font is invisible until FadeInCredits.
        screens = [t for t in self.order if t in SCREEN_COMMANDS]
        self.assertIn("FADE", screens[0])
        for index in range(1, len(screens)):
            if screens[index - 1] in MON_COMMANDS:
                self.assertIn("FADE", screens[index], f"screen {index + 1} follows a mon without fading in")

    def test_order_ends_with_copyright_and_the_end(self) -> None:
        self.assertEqual(self.order[-3:], ["CRED_COPYRIGHT", "CRED_TEXT_FADE_MON", "CRED_THE_END"])

    def test_hall_of_fame_clear_rolls_no_credits(self) -> None:
        credits = (REPO_ROOT / "engine/movie/credits.asm").read_text()
        body = re.search(r"^HallOfFamePC:\n(.*?)(?=^\S)", credits, re.M | re.S)
        self.assertIsNotNone(body)
        self.assertEqual(body.group(1).strip(), "farjp AnimateHallOfFame")
        script = (REPO_ROOT / "scripts/HallOfFame.asm").read_text()
        normal = script.split("jr nz, .warpToAILair", 1)[1].split(".warpToAILair", 1)[0]
        self.assertNotIn("WaitForTextScrollButtonPress", normal, "a blank screen would wait for a button")
        self.assertIn("jp Init", normal)


class CreditsMenuRollTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.menu = self.h.hook_flag("MainMenu.mainMenuLoop")
        self.roll = self.h.hook_flag("Credits")
        self.the_end = self.h.hook_flag("Credits.showTheEnd")
        self.init = {"count": 0}
        self.frame = 0
        self.boundaries: list[int] = []
        self.h.hook_flag("Credits.nextCreditsScreen", lambda: self.boundaries.append(self.frame))

    def tearDown(self) -> None:
        self.h.close()

    def step(self, frames: int = 1) -> None:
        for _ in range(frames):
            self.h.tick(1)
            self.frame += 1

    def tap(self, button: str) -> None:
        self.h.pyboy.button_press(button)
        self.step(2)
        self.h.pyboy.button_release(button)
        self.step(2)

    def wait_for(self, predicate, what: str, limit: int) -> None:
        for _ in range(limit):
            if predicate():
                return
            self.step()
        self.fail(f"timed out waiting for {what}")

    def open_credits(self, button: str, hold: int = 0) -> None:
        h = self.h
        self.step(240)
        for _ in range(300):
            self.tap("start")
            if self.menu["count"]:
                break
        self.assertTrue(self.menu["count"], "title menu never appeared")
        self.step(30)
        for _ in range(h.read8("wMaxMenuItem")):  # CREDITS is the last item
            self.tap("down")
            self.step(4)
        if hold:
            h.pyboy.button_press(button)
            self.wait_for(lambda: self.roll["count"], "the roll to start", 600)
            self.step(hold)
            h.pyboy.button_release(button)
            self.step(2)
        else:
            self.tap(button)
            self.wait_for(lambda: self.roll["count"], "the roll to start", 600)

    def wait_boundaries(self, n: int) -> None:
        self.wait_for(lambda: len(self.boundaries) >= n, f"{n} credits screens", 3000)

    def test_select_toggles_fast_and_start_skips(self) -> None:
        self.open_credits("a")
        # Pick equivalent display commands from the data. Toggle at the start
        # of the preceding screen, leaving the measured screen wholly in one mode.
        commands = [t for t in _db_tokens(REPO_ROOT / "data/credits/credits_order.asm") if t in SCREEN_COMMANDS]
        candidates = [i for i, command in enumerate(commands) if command == "CRED_TEXT_FADE"]
        measured = []
        for index in candidates:
            if index >= 1 and (not measured or index >= measured[-1] + 2):
                measured.append(index)
            if len(measured) == 3:
                break
        self.assertEqual(len(measured), 3, "need three separated fade screens for timing comparison")
        durations = []
        for sample, index in enumerate(measured):
            self.wait_boundaries(index)  # preceding screen has just started
            if sample:
                self.tap("select")
            self.wait_boundaries(index + 2)
            durations.append(self.boundaries[index + 1] - self.boundaries[index])
        normal, fast, restored = durations

        self.assertGreater(normal, 120)
        self.assertLess(fast, normal / 2, f"fast {fast} vs normal {normal}")
        self.assertGreater(restored, normal * 0.8, f"restored {restored} vs normal {normal}")

        self.assertEqual(self.the_end["count"], 0)
        self.tap("start")
        self.wait_for(lambda: self.the_end["count"], "THE END after START", 200)
        # The menu roll ends with a button wait and a soft reset to the title.
        self.h.register_hook("Init", lambda _c: self.init.__setitem__("count", self.init["count"] + 1))
        self.step(120)
        for _ in range(60):
            self.tap("a")
            if self.init["count"]:
                break
        self.assertTrue(self.init["count"], "the menu roll never returned to the title")

    def test_zero_offset_string_renders_at_the_center_column(self) -> None:
        # Override only the first string in this emulator instance with "BY".
        # Its offset is zero: the old unconditional $ff high byte wrote 256
        # bytes before the intended tilemap row instead.
        bank, address = self.h.symbols.get("CredRRTitle")
        for offset, value in enumerate((0, 0x81, 0x98, 0x50)):
            self.h.pyboy.memory[bank, address + offset] = value
        rows = []
        self.h.hook_flag("FadeInCredits", lambda: rows.append([
            self.h.read8("wTileMap", offset=6 * 20 + 9 + column) for column in range(2)
        ]))
        self.open_credits("a")
        self.wait_for(lambda: bool(rows), "first credits text", 300)
        self.assertEqual(rows[0], [0x81, 0x98])

    def test_entire_roll_has_centered_text_with_no_row_overflow(self) -> None:
        screens = []

        def capture(_context):
            screens.append([
                self.h.read8("wTileMap", offset=offset) for offset in range(20 * 18)
            ])

        for label in ("Credits.fadeInText", "Credits.showText",
                      "Credits.fadeInTextAndShowMon", "Credits.showTextAndShowMon"):
            self.h.register_hook(label, capture)
        self.open_credits("a")
        self.tap("select")
        self.wait_for(lambda: self.the_end["count"], "the complete credits roll", 14000)
        commands = [token for token in _db_tokens(REPO_ROOT / "data/credits/credits_order.asm")
                    if token in SCREEN_COMMANDS]
        self.assertEqual(len(screens), len(commands))
        # The last screen uses copyright graphics rather than font characters.
        for index, screen in enumerate(screens[:-1]):
            for y in range(18):
                row = screen[y * 20:(y + 1) * 20]
                with self.subTest(screen=index + 1, row=y, tiles=row):
                    if y < 4 or y >= 14:
                        self.assertEqual(row, [0x7e] * 20)
                    elif y not in (6, 8, 10, 12):
                        self.assertEqual(row, [0x7f] * 20)
                    else:
                        occupied = [x for x, tile in enumerate(row) if tile != 0x7f]
                        if occupied:
                            left, right = occupied[0], 19 - occupied[-1]
                            self.assertLessEqual(abs(left - right), 1)

        def encoded(value):
            return [0x7f if char == " " else ord(char) - ord("A") + 0x80
                    for char in value]

        for screen_index, y, value in ((2, 6, "BUILT FROM WORK"),
                                       (2, 8, "IN THESE PROJECTS"),
                                       (12, 8, "POKEFAN MARCEL"),
                                       (14, 6, "KANTO"),
                                       (14, 8, "EXPANSION PAK"),
                                       (14, 10, "MEMENTOMARTHA"),
                                       (14, 12, "ALBATROSS")):
            row = screens[screen_index][y * 20:(y + 1) * 20]
            start = (20 - len(value)) // 2
            self.assertEqual(row, [0x7f] * start + encoded(value)
                             + [0x7f] * (20 - start - len(value)))

    def test_start_held_from_the_menu_does_not_skip(self) -> None:
        # Pick CREDITS with START and keep holding it well into the roll.
        self.open_credits("start", hold=90)
        self.wait_boundaries(3)
        self.assertEqual(self.the_end["count"], 0, "a START held since the menu skipped the roll")
        self.tap("start")
        self.wait_for(lambda: self.the_end["count"], "THE END after a fresh START", 200)


if __name__ == "__main__":
    unittest.main()
