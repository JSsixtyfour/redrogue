"""New-game difficulty screen (engine/menus/difficulty_select.asm).

Cold-boots to the main menu, takes NEW GAME (which clears the debug flags, so
Prof Palm's full speech runs instead of .skipSpeech), and drives the slider the
way a player does. Checks that the tier starts on NORMAL, clamps at both ends,
lands in wOptions2's difficulty bits without touching the others, and hands
over to character select.
"""

from __future__ import annotations

import unittest
from pathlib import Path

from harness import RedRogueHarness

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

DIFFICULTY_MASK = 0b111
# constants/ram_constants.asm (stored order, not display order)
DIFFICULTY_NORMAL = 0
DIFFICULTY_VERY_EASY = 2
DIFFICULTY_HARD = 3
DIFFICULTY_VERY_HARD = 4

SCREEN_WIDTH = 20
MARKER_ROW = 5
TRACK_X = 1
STOP_SPACING = 4
TILE_MARKER = 0xEE  # '▼'
TILE_BLANK = 0x7F


class DifficultySelectTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.menu = self.h.hook_flag("MainMenu.mainMenuLoop")
        self.loop = self.h.hook_flag("DifficultySelect.inputLoop")
        self.character = self.h.hook_flag("ChoosePlayerCharacter")

    def tearDown(self) -> None:
        self.h.close()

    def reach_difficulty_screen(self) -> None:
        h = self.h
        h.tick(240)
        for _ in range(300):
            h.tap("start", 2)
            h.tick(2)
            if self.menu["count"]:
                break
        self.assertTrue(self.menu["count"], "main menu never appeared")
        h.tick(30)
        # A through NEW GAME and the speech. Stop the instant the slider's input
        # loop runs: one more A there would choose the tier.
        for _ in range(400):
            h.tap("a", 2)
            for _ in range(8):
                h.tick(1)
                if self.loop["count"]:
                    break
            if self.loop["count"]:
                break
        self.assertTrue(self.loop["count"], "the difficulty screen never took input")
        self.assertEqual(self.character["count"], 0, "character select ran before the difficulty screen")
        h.tick(10)

    def press(self, button: str) -> None:
        self.h.tap(button, 2)
        self.h.tick(10)

    def tier(self) -> int:
        return self.h.read8("wOptions2") & DIFFICULTY_MASK

    def marker_columns(self) -> list[int]:
        row = MARKER_ROW * SCREEN_WIDTH
        return [x for x in range(SCREEN_WIDTH) if self.h.read8("wTileMap", row + x) == TILE_MARKER]

    def test_slider_clamps_commits_and_hands_over(self) -> None:
        self.reach_difficulty_screen()
        other_bits = self.h.read8("wOptions2") & ~DIFFICULTY_MASK & 0xFF

        self.assertEqual(self.tier(), DIFFICULTY_NORMAL, "a new game must start on NORMAL")
        self.assertEqual(self.marker_columns(), [TRACK_X + 2 * STOP_SPACING])
        description = [self.h.read8("wTileMap", 14 * SCREEN_WIDTH + x) for x in range(1, 19)]
        self.assertTrue(any(t != TILE_BLANK for t in description), "no description in the text box")

        for _ in range(3):  # two steps to VERY EASY, then one that must clamp
            self.press("left")
        self.assertEqual(self.tier(), DIFFICULTY_VERY_EASY)
        self.assertEqual(self.marker_columns(), [TRACK_X])

        for _ in range(3):
            self.press("right")
        self.assertEqual(self.tier(), DIFFICULTY_HARD)

        for _ in range(3):  # one step to VERY HARD, then two that must clamp
            self.press("right")
        self.assertEqual(self.tier(), DIFFICULTY_VERY_HARD)
        self.assertEqual(self.marker_columns(), [TRACK_X + 4 * STOP_SPACING])
        self.assertEqual(self.h.read8("wOptions2") & ~DIFFICULTY_MASK & 0xFF, other_bits,
                         "the slider changed wOptions2 bits outside DIFFICULTY_MASK")

        self.assertEqual(self.character["count"], 0)
        self.press("a")
        self.h.wait_until(lambda: self.character["count"] > 0, "character select after A", 600)
        self.assertEqual(self.tier(), DIFFICULTY_VERY_HARD)


if __name__ == "__main__":
    unittest.main()
