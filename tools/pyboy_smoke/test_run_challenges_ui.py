"""The Dorm PC's CHALLENGES row (RunChallengesMenu, custom_functions/run_challenges.asm).

Drives the real PC: walk to it, open CHALLENGES, toggle rows, turn the page, and
check the list is read only once a run has begun. Screenshots land in artifacts/
for a look, since a passing tile check does not prove the page reads well.
"""

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
from test_eevee_form_gate import CHAR_TO_BYTE

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
EVENTS = parse_rgbds_constants(ROOT / "constants" / "event_constants.asm")
ROW_CHALLENGES = 4
TILE_ROW = 20  # wTileMap bytes per screen row


def text(value):
    return [CHAR_TO_BYTE[c] if not c.isdigit() else 0xF6 + int(c) for c in value]


class RunChallengesUITest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)
        self.maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")

    def press(self, button, settle=8):
        self.h.tap(button, 4)
        self.h.tick(settle)

    def step(self, direction):
        h = self.h
        h.pyboy.button_press(direction)
        h.tick(3)
        h.pyboy.button_release(direction)
        h.tick(30)

    def row(self, row, length, col=2):
        return self.h.read_bytes("wTileMap", length, row * TILE_ROW + col)

    def shot(self, name):
        self.h.tick(3, render=True)
        ARTIFACTS.mkdir(exist_ok=True)
        self.h.pyboy.screen.image.save(ARTIFACTS / name)

    def open_pc(self):
        h = self.h
        h.boot_debug1(self.maps["SILPH_CO_DORM"])
        h.write8("wRunChallenges", 0)
        h.write8("wRunChallenges", 0, offset=1)
        for _ in range(10):
            if h.read8("wYCoord") <= 2:
                break
            self.step("up")
        self.step("left")
        self.step("up")
        self.press("a", 60)
        for _ in range(40):
            if h.read8("wMaxMenuItem") >= ROW_CHALLENGES + 1 and h.read8("wTopMenuItemY") == 2:
                break
            self.press("a", 20)
        self.assertEqual(h.read8("wMaxMenuItem"), 5, "KEY ITEMS..CHALLENGES, LOG OFF")
        self.assertEqual(self.row(10, 10), text("CHALLENGES"))

    def open_challenges(self):
        self.open_pc()
        for _ in range(ROW_CHALLENGES):
            self.press("down")
        self.press("a", 30)

    def test_toggle_page_lock_and_return(self):
        h = self.h
        self.open_challenges()
        self.assertEqual(self.row(1, 12), text("POOR REWARDS"))
        self.assertEqual(self.row(1, 3, 16), text("OFF"))
        self.assertEqual(h.read8("wMaxMenuItem"), 7)
        self.shot("run_challenges_page1.png")

        self.press("a", 20)                       # toggle POOR REWARDS
        self.assertEqual(h.read8("wRunChallenges") & 1, 1)
        self.assertEqual(self.row(1, 2, 16), text("ON"))
        self.press("down")
        self.press("a", 20)                       # RARER FOES
        self.assertEqual(h.read8("wRunChallenges") & 3, 3)
        self.press("a", 20)                       # and off again
        self.assertEqual(h.read8("wRunChallenges") & 3, 1)
        self.assertEqual(self.row(9, 1, 8), [0xF6 + 1], "HEAT shows the one weight-1 challenge on")

        for i in range(7):                        # row 1 -> past row 7: page 2
            self.press("down")
        self.assertEqual(h.read8("wBuffer", offset=8), 1, "DOWN past the last row did not turn the page")
        self.assertEqual(self.row(1, 10), text("NO HEALING"))
        self.shot("run_challenges_page2.png")
        self.press("a", 20)                       # first row of page 2 = id 8
        self.assertEqual(h.read8("wRunChallenges", offset=1) & 1, 1)

        h.set_event(EVENTS["EVENT_GOT_STARTER"])  # a run begins: the list locks
        self.press("a", 20)
        self.assertEqual(h.read8("wRunChallenges", offset=1) & 1, 1, "locked list changed")
        self.assertEqual(self.row(9, 6, 9), text("LOCKED"))
        self.shot("run_challenges_locked.png")

        self.press("b", 40)
        self.assertEqual(h.read8("wMaxMenuItem"), 5, "did not return to the PC menu")
        self.assertEqual(self.row(10, 10), text("CHALLENGES"))

    def test_records_page_shows_badges_and_best_heat(self):
        h = self.h
        self.open_pc()
        h.write8("wChallengeBadges", 0b00000101)      # POOR REWARDS, HIGHER LEVELS
        h.write8("wChallengeBadgesHi", 0b01000000)    # id 14: FEWER REWARDS
        h.write8("wChallengeBadges2", 0b00100001)     # IRONMAN, ALL AT ONCE
        h.write8("wBestHeat", 12)
        for _ in range(3):                            # RECORDS
            self.press("down")
        self.press("a", 30)
        for _ in range(3):                            # RUN TIMES, FURTHEST, SPECIAL, CHALLENGES
            self.press("down")
        self.press("a", 30)
        self.assertEqual(self.row(1, 10), text("CHALLENGES"))
        self.assertEqual(self.row(2, 12), text("POOR REWARDS"))
        marks = [self.row(2 + i, 1, 17)[0] for i in range(15)]
        plus, minus = CHAR_TO_BYTE["+"], CHAR_TO_BYTE["-"]
        self.assertEqual(marks, [plus if i in (0, 2, 14) else minus for i in range(15)])
        self.shot("run_challenges_records1.png")
        self.press("a", 20)                           # page 2
        self.assertEqual(self.row(3, 7), text("IRONMAN"))
        marks = [self.row(3 + i, 1, 17)[0] for i in range(6)]
        self.assertEqual(marks, [plus, minus, minus, minus, minus, plus])
        self.assertEqual(self.row(11, 3, 13), [0x7F, 0xF7, 0xF8])  # " 12", leading zero blank
        self.shot("run_challenges_records2.png")
        self.press("b", 30)
        self.assertEqual(self.row(8, 10), text("CHALLENGES"), "B did not return to RECORDS")


if __name__ == "__main__":
    unittest.main()
