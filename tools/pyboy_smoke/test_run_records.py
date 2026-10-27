"""Saved per-run clock, top-five ordering and run-boundary ownership."""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class RunRecordsTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.boot_debug1(parse_map_constants(ROOT / "constants/map_constants.asm")["SILPH_CO_DORM"])
        # Freeze automatic VBlank counting for exact injected tick assertions.
        self.h.write8("wStatusFlags6", self.h.read8("wStatusFlags6") & ~1)
        self.h.call_routine("RunRecordsInit")

    def tearDown(self):
        self.h.close()

    def clock(self, state, hours=0, minutes=0, seconds=0, frames=0):
        for name, value in zip(("State", "Hours", "Minutes", "Seconds", "Frames"),
                               (state, hours, minutes, seconds, frames)):
            self.h.write8("wRunTimer" + name, value)

    def records(self):
        h = self.h
        raw = h.read_bytes("wRunRecordsFirst", 9) + h.read_bytes("wRunRecordsLast", 6)
        return [tuple(raw[i:i+3]) for i in range(0, h.read8("wRunRecordCount") * 3, 3)]

    def test_clock_rollover_stop_and_lifetime_cap_independence(self):
        h = self.h
        self.clock(1, 1, 59, 59, 59)
        h.call_routine("RunTimerTick")
        self.assertEqual(h.read_bytes("wRunTimerHours", 4), [2, 0, 0, 0])
        h.call_routine("RunTimerFinish")
        h.call_routine("RunTimerTick")
        self.assertEqual(h.read_bytes("wRunTimerState", 5), [2, 2, 0, 0, 0])
        self.clock(1, 255, 59, 59, 59)
        h.call_routine("RunTimerTick")
        self.assertEqual(h.read_bytes("wRunTimerState", 5), [2, 255, 59, 59, 59])
        self.clock(1)
        h.write8("wPlayTimeMaxed", 255)
        h.write8("wStatusFlags6", h.read8("wStatusFlags6") | 1)
        h.call_routine("TrackPlayTime")
        self.assertGreater(h.read8("wRunTimerFrames"), 0)

    def test_five_fastest_across_hour_minute_second_boundaries_and_ties(self):
        h = self.h
        times = [(2, 0, 0), (1, 59, 59), (0, 59, 59), (0, 20, 5),
                 (0, 20, 4), (0, 20, 5), (0, 10, 0), (3, 0, 0)]
        seen = []
        for value in times:
            self.clock(2, *value)
            h.call_routine("RunRecordsCommit")
            seen.append(value)
            self.assertEqual(self.records(), sorted(seen)[:5])
            h.call_routine("RunRecordsCommit")
            self.assertEqual(self.records(), sorted(seen)[:5], "duplicate publication")

    def test_loss_reset_and_unmeasured_legacy_run_do_not_rank(self):
        h = self.h
        self.clock(2, 0, 30, 0)
        h.call_routine("RunRecordsCommit")
        self.clock(1, 0, 5, 0)
        h.call_routine("RogueResetRunState")
        self.assertEqual(h.read8("wRunTimerState"), 0)
        self.assertEqual(self.records(), [(0, 30, 0)])
        h.call_routine("RunTimerFinish")
        h.call_routine("RunRecordsCommit")
        self.assertEqual(self.records(), [(0, 30, 0)])

    def test_normal_save_restores_clock_and_leaderboard_together(self):
        h = self.h
        self.clock(2, 0, 40, 0)
        h.call_routine("RunRecordsCommit")
        self.clock(1, 0, 12, 34, 56)
        h.call_routine("SaveGameData")
        self.clock(2, 0, 1, 0)
        h.call_routine("RunRecordsCommit")
        h.call_routine("LoadMainData")
        self.assertEqual(self.records(), [(0, 40, 0)])
        self.assertEqual(h.read_bytes("wRunTimerState", 5), [1, 0, 12, 34, 56])
        h.call_routine("RunTimerStart")
        self.assertEqual(h.read_bytes("wRunTimerState", 5), [1, 0, 0, 0, 0])

    def test_loss_recovery_keeps_records_and_new_game_clears_them(self):
        h = self.h
        for minutes in (40, 30, 20, 10, 5):
            self.clock(2, 0, minutes, 0)
            h.call_routine("RunRecordsCommit")
        expected = self.records()
        self.clock(1, 0, 2, 0)
        h.call_routine("LossRecoveryPrepare")
        h.call_routine("RunRecordsInit")
        self.assertEqual(self.records(), [])
        h.call_routine("LossRecoveryRestore")
        h.call_routine("RogueResetRunState")
        self.assertEqual(self.records(), expected)
        self.assertEqual(h.read8("wRunTimerState"), 0)
        h.call_routine("IronmanNewGameSRAMInit")
        self.assertEqual(self.records(), [])
