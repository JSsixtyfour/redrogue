"""Save and reload checks (save_reload.py): a lobby save made at an idle
overworld frame comes back byte for byte on a fresh emulator, and a power cut
between the save's parts is classified, not crashed on."""
import io

import autoplay
import autoplay_branch
import save_reload
from test_smoke import HarnessTestCase


class SaveReloadTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        autoplay.boot(self.harness, seed=1)
        state = io.BytesIO()
        self.harness.save_state(state)
        self.lobby = autoplay_branch.Snapshot("lobby", 1, self.harness.pyboy.frame_count, {}, state.getvalue())

    def test_lobby_save_round_trips(self) -> None:
        trip = save_reload.round_trip(self.harness, self.lobby, None, "test")
        self.assertEqual(trip["status"], 2, trip)  # TryLoadSaveFile: loaded
        self.assertTrue(trip["overworld"], trip)
        self.assertEqual(trip["differences"], [])

    def test_power_cuts_are_classified(self) -> None:
        cuts = save_reload.power_cuts(self.harness, self.lobby, self.lobby)
        outcomes = {cut["cut"].split(" at ")[1]: cut["loads"] for cut in cuts}
        self.assertEqual(outcomes["after the save"], "new")
        self.assertTrue(set(outcomes.values()) <= {"new", "old", "mixed", "refused"}, outcomes)
