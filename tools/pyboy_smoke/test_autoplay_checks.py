"""The autoplay bug detectors (autoplay_checks.py): a clean lobby reports
nothing, and each kind of damage they look for is reported when planted."""
import unittest

import autoplay
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

MOVES = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")


class AutoplayChecksTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        autoplay.boot(self.harness, seed=1)
        self.agent = autoplay.AutoplayAgent(self.harness, seed=1)
        self.checks = self.agent.checks

    def details(self) -> list[str]:
        return [f"{a['check']}: {a['detail']}" for a in self.checks.anomalies]

    def test_clean_lobby_reports_nothing(self) -> None:
        self.checks.check_world()
        self.checks.after_step()
        self.assertEqual(self.details(), [])
        self.assertIsNone(self.checks.crash)

    def test_moveless_party_mon(self) -> None:
        for i in range(4):
            self.harness.write8("wPartyMon1Moves", 0, offset=i)
            self.harness.write8("wPartyMon1PP", 0, offset=i)
        self.checks.check_party()
        self.assertTrue(any("slot 1" in d and "no moves" in d for d in self.details()), self.details())

    def test_duplicate_move_and_pp_over_max(self) -> None:
        tackle = MOVES["TACKLE"]  # 35 PP
        for i, move in enumerate((tackle, tackle, 0, 0)):
            self.harness.write8("wPartyMon1Moves", move, offset=i)
            self.harness.write8("wPartyMon1PP", 50 if i == 0 else (35 if move else 0), offset=i)
        self.checks.check_party()
        found = self.details()
        self.assertTrue(any("duplicate moves" in d for d in found), found)
        self.assertTrue(any("slot 1 PP 50 over max" in d for d in found), found)

    def test_warp_to_a_map_that_does_not_exist(self) -> None:
        self.harness.write8("wWarpEntries", self.checks.num_maps, offset=3)
        self.checks.check_map()
        self.assertTrue(any("warp 0 leads to map" in d for d in self.details()), self.details())

    def test_jump_to_null_is_a_crash(self) -> None:
        self.harness.pyboy.register_file.PC = 0x0000
        self.harness.tick(1)
        crash = self.checks.crash
        self.assertIsNotNone(crash)
        self.assertEqual(crash["kind"], "rst $38")
        self.assertEqual(crash["from"]["label"], "NULL")

    def test_stack_outside_its_range_is_a_crash(self) -> None:
        self.checks.after_step()  # arms the check: SP is in the stack
        self.harness.pyboy.register_file.SP = 0xC100
        self.checks.after_step()
        self.assertIsNotNone(self.checks.crash)
        self.assertEqual(self.checks.crash["kind"], "stack_out_of_range")


if __name__ == "__main__":
    unittest.main(verbosity=2)
