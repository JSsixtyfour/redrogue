"""Save and reload checks (save_reload.py): a lobby save made at an idle
overworld frame comes back byte for byte on a fresh emulator, and a power cut
between the save's parts is classified, not crashed on."""
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import autoplay
import autoplay_branch
import save_reload
from test_smoke import HarnessTestCase


class NaturalSaveExposureTest(unittest.TestCase):
    def test_first_stage_blackout_still_retains_an_early_natural_save(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(autoplay, "ARTIFACTS", Path(tmp)):
            report = autoplay.play(1, new_game=True, save_checks=True, stages=1, max_frames=100000)
            trips = report["save_checks"]["round_trips"]
            early = [trip for trip in trips if trip.get("source_snapshot", {}).get("kind") == "save_overworld"]
            self.assertEqual(len(early), 1, report["save_checks"])
            self.assertEqual(early[0]["status"], 2, early)
            self.assertTrue(early[0]["overworld"], early)
            self.assertFalse(early[0]["source_snapshot"]["info"]["clock_injected"])
            self.assertTrue(Path(early[0]["source_snapshot"]["state"]).is_file())
            self.assertEqual(early[0]["run_timer_comparison"]["status"], "accounted", early)
            self.assertEqual(report["save_checks"]["findings"], [])


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
        # Both snapshots are the same fixture, so all completed regions agree.
        self.assertEqual(outcomes["after the save"], "unchanged")
        self.assertTrue(set(outcomes.values()) <= {"new", "old", "unchanged", "mixed", "refused"}, outcomes)

    def test_active_rollover_saturation_and_paused_clock_round_trips(self):
        h = self.harness
        for clock, enabled in (([1, 0, 0, 59, 50], True), ([1, 0, 59, 59, 50], True),
                               ([1, 255, 59, 59, 50], True), ([2, 0, 2, 3, 4], True),
                               ([1, 0, 2, 3, 4], False)):
            with self.subTest(clock=clock, enabled=enabled):
                h.load_state(io.BytesIO(self.lobby.state))
                for offset, value in enumerate(clock):
                    h.write8("wRunTimerState", value, offset)
                h.write8("wStatusFlags6", (h.read8("wStatusFlags6") & ~1) | int(enabled))
                state = io.BytesIO()
                h.save_state(state)
                fixture = autoplay_branch.Snapshot("lobby", 1, h.pyboy.frame_count,
                    {"provenance": "constructed timer boundary"}, state.getvalue())
                trip = save_reload.round_trip(h, fixture, None, "clock-boundary")
                self.assertEqual(trip["status"], 2, trip)
                self.assertTrue(trip["overworld"], trip)
                self.assertEqual(trip["run_timer_comparison"]["status"], "accounted", trip)
                self.assertEqual(trip["differences"], [], trip)

    def test_active_clock_power_cut_classification_uses_published_clock_and_ticks(self):
        h = self.harness
        fixtures = []
        for clock in ([1, 0, 0, 10, 10], [1, 0, 1, 10, 10]):
            h.load_state(io.BytesIO(self.lobby.state))
            for offset, value in enumerate(clock):
                h.write8("wRunTimerState", value, offset)
            h.write8("wStatusFlags6", h.read8("wStatusFlags6") | 1)
            state = io.BytesIO()
            h.save_state(state)
            fixtures.append(autoplay_branch.Snapshot("lobby", len(fixtures) + 1, h.pyboy.frame_count,
                {"provenance": "constructed active clock checkpoint"}, state.getvalue()))
        cuts = save_reload.power_cuts(h, *fixtures)
        self.assertEqual(cuts[-1]["loads"], "new", cuts)
        self.assertTrue(all(cut["loads"] in ("old", "new", "unchanged", "refused") for cut in cuts), cuts)


class NaturalRunTimerTest(HarnessTestCase):
    def setUp(self):
        super().setUp()
        h = self.harness
        autoplay.boot_new_game(h, seed=1)
        agent = autoplay.AutoplayAgent(h, seed=1)
        for _ in range(20000):
            agent.step()
            if h.pyboy.frame_count > 50000:
                self.fail("natural active-run fixture exceeded frame budget")
            if h.read8("wRunTimerState") == 1 and agent.mode() == "overworld":
                break
        else:
            self.fail("natural active-run fixture not reached")
        state = io.BytesIO()
        h.save_state(state)
        self.snapshot = autoplay_branch.Snapshot("natural_overworld", 1, h.pyboy.frame_count,
            {"provenance": "natural active run; no clock injection"}, state.getvalue())

    def test_natural_active_clock_round_trip_is_accounted(self):
        trip = save_reload.round_trip(self.harness, self.snapshot, None, "natural-clock")
        self.assertEqual(trip["status"], 2, trip)
        self.assertTrue(trip["overworld"], trip)
        self.assertEqual(trip["run_timer_comparison"]["status"], "accounted", trip)
        self.assertGreater(trip["run_timer_comparison"]["active_ticks"], 0, trip)
        self.assertEqual(trip["differences"], [], trip)

    def test_controlled_load_corruption_remains_a_finding(self):
        original = save_reload.Reboot
        for field in ("wRunTimerFrames", "wRunTimerState", "wStatusFlags6", "wPartyCount", "detector_error", "overworld_timeout"):
            with self.subTest(field=field):
                class CorruptLoad(original):
                    def load(self):
                        def corrupt(_):
                            if field == "detector_error":
                                self.h.hook_errors.append("controlled observer failure")
                            elif field != "overworld_timeout":
                                self.h.write8(field, self.h.read8(field) ^ 1)
                        self.h.register_hook("TryLoadSaveFile.done", corrupt)
                        super().load()
                        if field == "overworld_timeout":
                            self.overworld = False
                with patch.object(save_reload, "Reboot", CorruptLoad):
                    trip = save_reload.round_trip(self.harness, self.snapshot, None, "controlled-load-corruption")
                self.assertTrue(trip["differences"] or trip.get("problem"), trip)
