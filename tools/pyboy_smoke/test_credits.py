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
        # Boundary n is the end of screen n (boundary 0 is the roll's start).
        # Screens 2, 4 and 7 are all CRED_TEXT_FADE, so they compare like for
        # like; each toggle happens one screen before the one measured.
        self.wait_boundaries(3)
        normal = self.boundaries[2] - self.boundaries[1]
        self.tap("select")  # fast from inside screen 3
        self.wait_boundaries(5)
        fast = self.boundaries[4] - self.boundaries[3]
        self.tap("select")  # back to normal inside screen 5
        self.wait_boundaries(8)
        restored = self.boundaries[7] - self.boundaries[6]

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

    def test_start_held_from_the_menu_does_not_skip(self) -> None:
        # Pick CREDITS with START and keep holding it well into the roll.
        self.open_credits("start", hold=90)
        self.wait_boundaries(3)
        self.assertEqual(self.the_end["count"], 0, "a START held since the menu skipped the roll")
        self.tap("start")
        self.wait_for(lambda: self.the_end["count"], "THE END after a fresh START", 200)


if __name__ == "__main__":
    unittest.main()
