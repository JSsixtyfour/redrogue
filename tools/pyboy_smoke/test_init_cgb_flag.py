"""Init keeps the CGB flag across in-game restarts (FOLLOWUPS #84).

The credits, Hall of Fame, AI Lair, cable club and clear-save paths all end in
`jp Init`. Init wipes WRAM0 and restores wOnCGB from E, and those callers used
to arrive with whatever E held: measured 2026-10-21, a DMG came back from the
credits with wOnCGB = $CA, ran the CGB palette code, and that code's WRAM bank 2
workspace ($D000-$D035) is bank 1 on a DMG, so it overwrote wBattleMonNick and
wBattleMon in every later battle. Init now reloads E from wOnCGB; only
_Start enters at InitFromBoot with E set from the boot value.
"""
from __future__ import annotations

import unittest
from pathlib import Path

from harness import RedRogueHarness

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
GARBAGE_E = 0xCA  # the value the swarm measured


class InitCgbFlagTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.h.tick(120)
        self.assertEqual(self.h.read8("wOnCGB"), 0, "this harness boots as a DMG")

    def tearDown(self) -> None:
        self.h.close()

    def enter(self, label: str) -> int:
        registers = self.h.pyboy.register_file
        registers.E = GARBAGE_E
        registers.PC = self.h.address(label)
        self.h.tick(30)
        return self.h.read8("wOnCGB")

    def test_init_keeps_the_flag_whatever_e_holds(self) -> None:
        self.assertEqual(self.enter("Init"), 0)

    def test_init_from_boot_takes_the_flag_from_e(self) -> None:
        # The control: the boot entry trusts E, so this is the old Init's behaviour.
        self.assertEqual(self.enter("InitFromBoot"), GARBAGE_E)


if __name__ == "__main__":
    unittest.main()
