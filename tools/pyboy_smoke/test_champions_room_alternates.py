"""Runtime checks for Phase 7e: Lance and Oak as alternate Champions.

ChampionsRoomHideUnusedChampion (scripts/ChampionsRoom.asm) reads wRunChampion
(rolled by RollChampion, custom_functions/final_sequence.asm), shows the
selected champion even if an earlier run hid it, and hides
whichever two of {CHAMPIONSROOM_RIVAL, CHAMPIONSROOM_LANCE,
CHAMPIONSROOM_OAK_CHAMPION} are not this run's Champion, mirroring
FuchsiaGymHideUnusedLeader's two-way form extended to three candidates.
Checks both new-game visible defaults and stale hidden flags from prior runs.
Exactly the two unselected champions must end up hidden in either case.

Roll budget: call_routine corrupts the machine after roughly ten invocations
on one boot (project_call_routine_harness_limits); each test method below
gets its own fresh harness (HarnessTestCase.setUp) and makes one call.
"""
import unittest

from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

TRAINER_CONSTANTS = REPO_ROOT / "constants" / "trainer_constants.asm"
TOGGLE_CONSTANTS = REPO_ROOT / "constants" / "toggle_constants.asm"


class ChampionsRoomAlternatesTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.classes = parse_trainer_class_indexes(TRAINER_CONSTANTS)
        self.toggles = parse_rgbds_constants(TOGGLE_CONSTANTS)
        self.rival_toggle = self.toggles["TOGGLE_CHAMPIONS_ROOM_RIVAL"]
        self.lance_toggle = self.toggles["TOGGLE_CHAMPIONS_ROOM_LANCE"]
        self.oak_toggle = self.toggles["TOGGLE_CHAMPIONS_ROOM_OAK_CHAMPION"]

    # -- helpers ------------------------------------------------------------

    def _is_hidden(self, toggle_index: int) -> bool:
        h = self.harness
        assert h is not None
        byte = h.read8("wToggleableObjectFlags", offset=toggle_index // 8)
        return bool(byte & (1 << (toggle_index % 8)))

    def _set_all_three(self, hidden: bool = False) -> None:
        # ToggleableObjectFlagAction's bit test is (index & 7) into byte
        # (index >> 3) of wToggleableObjectFlags - the same arithmetic here.
        h = self.harness
        assert h is not None
        for toggle_index in (self.rival_toggle, self.lance_toggle, self.oak_toggle):
            byte_offset = toggle_index // 8
            bit = 1 << (toggle_index % 8)
            current = h.read8("wToggleableObjectFlags", offset=byte_offset)
            value = current | bit if hidden else current & ~bit & 0xFF
            h.write8("wToggleableObjectFlags", value, offset=byte_offset)

    def _run_for(self, champion_class: str, hidden: bool = False) -> None:
        h = self.harness
        assert h is not None
        self._set_all_three(hidden)
        h.write8("wRunChampion", self.classes[champion_class])
        h.park_before_hijack()
        h.call_routine("ChampionsRoomHideUnusedChampion")

    def _check_stale_hidden_champion(self, champion_class: str, selected: int) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        # Earlier runs may have hidden any champion, including the new selection.
        self._run_for(champion_class, hidden=True)
        for toggle in (self.rival_toggle, self.lance_toggle, self.oak_toggle):
            self.assertEqual(self._is_hidden(toggle), toggle != selected)

    def test_rival3_restores_stale_hidden_champion(self) -> None:
        self._check_stale_hidden_champion("RIVAL3", self.rival_toggle)

    def test_lance_restores_stale_hidden_champion(self) -> None:
        self._check_stale_hidden_champion("LANCE", self.lance_toggle)

    def test_oak_restores_stale_hidden_champion(self) -> None:
        self._check_stale_hidden_champion("PROF_OAK", self.oak_toggle)

    # -- one call per test, one fresh boot per test --------------------------

    def test_rival3_hides_lance_and_oak_leaves_itself_visible(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self._run_for("RIVAL3")
        self.assertFalse(
            self._is_hidden(self.rival_toggle), "the actual Champion got hidden"
        )
        self.assertTrue(self._is_hidden(self.lance_toggle))
        self.assertTrue(self._is_hidden(self.oak_toggle))

    def test_lance_hides_rival_and_oak_leaves_itself_visible(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self._run_for("LANCE")
        self.assertTrue(self._is_hidden(self.rival_toggle))
        self.assertFalse(
            self._is_hidden(self.lance_toggle), "the actual Champion got hidden"
        )
        self.assertTrue(self._is_hidden(self.oak_toggle))

    def test_oak_hides_rival_and_lance_leaves_itself_visible(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self._run_for("PROF_OAK")
        self.assertTrue(self._is_hidden(self.rival_toggle))
        self.assertTrue(self._is_hidden(self.lance_toggle))
        self.assertFalse(
            self._is_hidden(self.oak_toggle), "the actual Champion got hidden"
        )


if __name__ == "__main__":
    unittest.main()
