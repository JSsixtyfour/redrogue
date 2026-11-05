"""A mon frozen since the battle began has chosen no move, and a Fire move can thaw it before its turn.

The menu is skipped while frozen, so wPlayerSelectedMove is still 0. ExecutePlayerMove used to run
with it: GetCurrentMove read before the move table, as code, and the battle crashed (found by a
witch matrix row on another seed: "Fire defrosted", then garbage, then SP outside the stack).
"""
from __future__ import annotations

import unittest
from pathlib import Path

from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"


class PlayerThawedNoMoveTest(unittest.TestCase):
    def test_no_chosen_move_ends_the_turn(self) -> None:
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.tick(30)
        looked_up = h.hook_flag("GetCurrentMove")
        done = h.hook_flag("ExecutePlayerMoveDone")
        for selected in (0, 0xFF):  # no move chosen, and the existing "cannot move"
            before = done["count"]
            h.write8("wPlayerSelectedMove", selected)
            h.park_before_hijack()
            h.call_routine("ExecutePlayerMove", limit=20000)
            self.assertEqual(done["count"], before + 1, f"move {selected}: the turn did not end")
            self.assertEqual(looked_up["count"], 0, f"move {selected}: read a move that does not exist")


if __name__ == "__main__":
    unittest.main()
