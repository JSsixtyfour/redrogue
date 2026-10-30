"""Runtime checks for FuchsiaGymHideUnusedLeader (scripts/FuchsiaGym.asm).

The routine reads wRunGymLineup (JANINE anywhere in it = a Janine run), shows
this run's leader and hides the other. HideObject flags persist between runs,
so a Koga run left Janine hidden and a later Janine run then hid Koga as well:
an empty gym (hardware save "Red Rogue 2026-10-28 212507c4.srm"). This mirrors
test_champions_room_alternates.py's stale-hidden cases.

One call_routine per test on a fresh boot (project_call_routine_harness_limits).
"""
import unittest

from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

TRAINER_CONSTANTS = REPO_ROOT / "constants" / "trainer_constants.asm"
TOGGLE_CONSTANTS = REPO_ROOT / "constants" / "toggle_constants.asm"


class FuchsiaGymLeaderTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.classes = parse_trainer_class_indexes(TRAINER_CONSTANTS)
        self.toggles = parse_rgbds_constants(TOGGLE_CONSTANTS)
        self.koga_toggle = self.toggles["TOGGLE_FUCHSIA_KOGA"]
        self.janine_toggle = self.toggles["TOGGLE_FUCHSIA_JANINE"]

    def _is_hidden(self, toggle_index: int) -> bool:
        h = self.harness
        assert h is not None
        byte = h.read8("wToggleableObjectFlags", offset=toggle_index // 8)
        return bool(byte & (1 << (toggle_index % 8)))

    def _set_both(self, hidden: bool) -> None:
        h = self.harness
        assert h is not None
        for toggle_index in (self.koga_toggle, self.janine_toggle):
            byte_offset = toggle_index // 8
            bit = 1 << (toggle_index % 8)
            current = h.read8("wToggleableObjectFlags", offset=byte_offset)
            value = current | bit if hidden else current & ~bit & 0xFF
            h.write8("wToggleableObjectFlags", value, offset=byte_offset)

    def _run_for(self, leader_class: str, hidden: bool) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self._set_both(hidden)
        lineup = ["BROCK", "MISTY", "LT_SURGE", "ERIKA", leader_class, "SABRINA", "BLAINE", "GIOVANNI"]
        for i, name in enumerate(lineup):
            h.write8("wRunGymLineup", self.classes[name], offset=i)
        h.park_before_hijack()
        h.call_routine("FuchsiaGymHideUnusedLeader")

    def _check(self, leader_class: str, selected: int, hidden: bool) -> None:
        self._run_for(leader_class, hidden)
        for toggle in (self.koga_toggle, self.janine_toggle):
            self.assertEqual(self._is_hidden(toggle), toggle != selected)

    def test_koga_restores_stale_hidden_leader(self) -> None:
        self._check("KOGA", self.koga_toggle, hidden=True)

    def test_janine_restores_stale_hidden_leader(self) -> None:
        self._check("JANINE", self.janine_toggle, hidden=True)

    def test_koga_from_visible_defaults(self) -> None:
        self._check("KOGA", self.koga_toggle, hidden=False)

    def test_janine_from_visible_defaults(self) -> None:
        self._check("JANINE", self.janine_toggle, hidden=False)


if __name__ == "__main__":
    unittest.main()
