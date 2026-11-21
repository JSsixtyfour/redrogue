"""Lobby Move Tutor greets once per lobby visit (2026-11-20).

The first talk of a visit shows the two-page greeting and its yes/no. Later
talks go straight to "Which #MON should I tutor?" and the party menu, where B
already declines. BIT_MOVE_TUTOR_GREETED (wElite4Flags bit 3) is set when the
greeting is shown and cleared by PCPsychicSetup on each fresh lobby entry. The
forest rest house tutor shares the routine and the bit.

The real PCMoveTutorTalk.teach runs; text, yes/no, party menu and screen
helpers are mocked seams so the path taken is observed directly.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_move_tutor_prices import ARTIFACTS, REPO_ROOT, return_from_call, run_entry

RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")
GREETED = 1 << RAM["BIT_MOVE_TUTOR_GREETED"]
OTHER_BITS = 0xFF & ~GREETED

MOCKED_HELPERS = (
    "SaveScreenTilesToBuffer2",
    "GBPalWhiteOutWithDelay3",
    "RestoreScreenTilesAndReloadTilePatterns",
    "LoadGBPal",
    "DisplayTextBoxID",
)


class MoveTutorGreetingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        cls.harness.boot_fight2(seed=3)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.harness.close()

    def _talk(self, *, flags: int, yes_no_choice: int) -> dict[str, object]:
        """Run one talk; the party menu is always cancelled (B)."""
        h = self.harness
        names = {
            h.address(label): label
            for label in (
                "PCMoveTutorGreetingText",
                "PCMoveTutorSaidYesText",
                "PCMoveTutorByeText",
            )
        }
        observed: dict[str, object] = {
            "texts": [], "yes_no_calls": 0, "party_menu_calls": 0,
            "flags_at_yes_no": None,
        }

        def print_text(_context) -> None:
            hl = h.pyboy.register_file.HL
            observed["texts"].append(names.get(hl, f"${hl:04x}"))
            return_from_call(h)

        def yes_no(_context) -> None:
            observed["yes_no_calls"] += 1
            observed["flags_at_yes_no"] = h.read8("wElite4Flags")
            h.write8("hCurrentMenuItem", yes_no_choice)
            return_from_call(h)

        def party_menu(_context) -> None:
            observed["party_menu_calls"] += 1
            h.pyboy.register_file.F |= 0x10  # carry: cancelled
            return_from_call(h)

        def skip(_context) -> None:
            return_from_call(h)

        hooks: dict[str, object] = {label: skip for label in MOCKED_HELPERS}
        hooks.update({
            "PrintText": print_text,
            "YesNoChoice": yes_no,
            "DisplayPartyMenu": party_menu,
        })

        def setup(harness: RedRogueHarness) -> None:
            harness.write8("wElite4Flags", flags)

        def capture(harness: RedRogueHarness) -> dict[str, object]:
            return {"flags_after": harness.read8("wElite4Flags"), **observed}

        return run_entry(h, "PCMoveTutorTalk.teach", setup=setup, hooks=hooks,
                         capture=capture, limit=1200)

    def test_first_talk_greets_and_sets_the_bit(self) -> None:
        actual = self._talk(flags=OTHER_BITS, yes_no_choice=1)  # answers No
        self.assertEqual(actual["texts"], ["PCMoveTutorGreetingText", "PCMoveTutorByeText"])
        self.assertEqual(actual["yes_no_calls"], 1)
        self.assertEqual(actual["party_menu_calls"], 0)
        self.assertEqual(actual["flags_after"], 0xFF, "bit set, other bits untouched")

    def test_first_talk_yes_reaches_the_party_menu(self) -> None:
        actual = self._talk(flags=0, yes_no_choice=0)
        self.assertEqual(actual["texts"], [
            "PCMoveTutorGreetingText", "PCMoveTutorSaidYesText", "PCMoveTutorByeText",
        ])
        self.assertEqual(actual["party_menu_calls"], 1)
        self.assertEqual(actual["flags_after"], GREETED)

    def test_later_talk_skips_greeting_and_yes_no(self) -> None:
        actual = self._talk(flags=GREETED, yes_no_choice=1)
        self.assertEqual(actual["texts"], ["PCMoveTutorSaidYesText", "PCMoveTutorByeText"])
        self.assertEqual(actual["yes_no_calls"], 0)
        self.assertEqual(actual["party_menu_calls"], 1)
        self.assertEqual(actual["flags_after"], GREETED)

    def test_fresh_lobby_entry_clears_only_the_greeted_bit(self) -> None:
        h = self.harness
        seen: dict[str, int] = {}

        def extras(_context) -> None:
            # PCPsychicSetup clears the bit before rolling the residents; stop
            # here (the WRAM spin loop is run_entry's return) rather than run
            # the lobby object setup outside the lobby.
            seen["flags"] = h.read8("wElite4Flags")
            h.pyboy.register_file.PC = 0xC100

        def setup(harness: RedRogueHarness) -> None:
            harness.write8("wElite4Flags", 0xFF)

        run_entry(h, "PCPsychicSetup", setup=setup,
                  hooks={"PCLobbyExtrasSetup": extras})
        self.assertEqual(seen.get("flags"), OTHER_BITS)


if __name__ == "__main__":
    unittest.main(verbosity=2)
