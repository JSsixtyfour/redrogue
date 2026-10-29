"""Unchanged regions cannot turn a completely old checkpoint into a mix."""
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from save_reload import checkpoint_kind, classify, account_run_timer, advance_run_clock


class RunTimerAccountingTest(unittest.TestCase):
    def test_raw_byte_match_cannot_override_wrong_published_clock(self):
        labels = {"wMainDataStart": 0x100, "wRunTimerState": 0x100, "wStatusFlags6": 0x105}
        h = SimpleNamespace(address=labels.__getitem__, symbols=SimpleNamespace(
            get=lambda _: (1, 0xa000), nearest=lambda _bank, addr: f"byte{addr}"))
        old = {"main data": bytes([1, 0, 0, 1, 9, 1])}
        new = {"main data": bytes([1, 0, 0, 2, 9, 1])}
        sram = bytearray(8192 + 6)
        sram[8192:] = bytes([1, 0, 0, 1, 0, 1])
        _, ticks = self.evidence([1, 0, 0, 1, 0], 9)
        with patch("save_reload.region_spans", return_value=[("main data", 0x100, 6)]):
            self.assertEqual(classify(h, old, new, old, timer_context=(sram, ticks)), {"main data": "other"})
            sram[8192:] = old["main data"]
            loaded, ticks = self.evidence(list(old["main data"][:5]), 9)
            self.assertEqual(classify(h, old, new, {"main data": bytes(loaded + [1])},
                                     timer_context=(sram, ticks)), {"main data": "old"})

    def evidence(self, clock, ticks):
        ledger = []
        for frame in range(ticks):
            if clock[0] == 1:
                ledger.append({"frame": frame, "clock": clock, "timer_enabled": True})
            clock = advance_run_clock(clock, 1)
        return clock, ledger

    def test_exact_rollovers_saturation_and_stopped_clocks(self):
        for initial, expected in (([1, 0, 0, 59, 52], [1, 0, 1, 0, 1]),
                                  ([1, 0, 59, 59, 52], [1, 1, 0, 0, 1]),
                                  ([1, 255, 59, 59, 52], [2, 255, 59, 59, 59]),
                                  ([2, 1, 2, 3, 4], [2, 1, 2, 3, 4]),
                                  ([0, 255, 255, 255, 255], [0, 255, 255, 255, 255])):
            with self.subTest(initial=initial):
                loaded, ledger = self.evidence(initial, 9)
                self.assertEqual(loaded, expected)
                self.assertEqual(account_run_timer(initial, initial, loaded, ledger,
                    saved_enabled=True, loaded_enabled=True)["status"], "accounted")

    def test_corruption_missing_ticks_and_publication_changes_are_not_allowed(self):
        saved = [1, 0, 0, 59, 52]
        loaded, ledger = self.evidence(saved, 9)
        for corrupt in ([0, *loaded[1:]], [*loaded[:4], 2], [1, 0, 2, 0, 1]):
            with self.subTest(corrupt=corrupt):
                self.assertEqual(account_run_timer(saved, saved, corrupt, ledger,
                    saved_enabled=True, loaded_enabled=True)["status"], "invalid")
        for incomplete in (ledger[1:], ledger[:-1], [ledger[0], *ledger], []):
            self.assertEqual(account_run_timer(saved, saved, loaded, incomplete,
                saved_enabled=True, loaded_enabled=True)["status"], "invalid")
        self.assertEqual(account_run_timer([1, 0, 0, 59, 53], saved, loaded, ledger,
            saved_enabled=True, loaded_enabled=True)["status"], "invalid")

    def test_disabled_timer_and_enable_mutation(self):
        clock = [1, 0, 2, 3, 4]
        self.assertEqual(account_run_timer(clock, clock, clock, [],
            saved_enabled=False, loaded_enabled=False)["status"], "accounted")
        self.assertEqual(account_run_timer(clock, clock, clock, [],
            saved_enabled=True, loaded_enabled=False)["status"], "invalid")
        loaded, ledger = self.evidence(clock, 1)
        self.assertEqual(account_run_timer(clock, clock, loaded, ledger,
            saved_enabled=False, loaded_enabled=False)["status"], "invalid")

    def test_invalid_active_clock_and_tick_evidence_fail_closed(self):
        for clock in ([1, 0, 60, 0, 0], [3, 0, 0, 0, 0], [1, 0, 0, True, 0]):
            self.assertEqual(account_run_timer(clock, clock, clock, [],
                saved_enabled=True, loaded_enabled=True)["status"], "invalid")


class SaveClassificationTest(unittest.TestCase):
    def classify_fixture(self, old, new, loaded):
        h = SimpleNamespace(symbols=SimpleNamespace(nearest=lambda _bank, addr: f"byte{addr}"))
        spans = [("main", 0x100, 2), ("party", 0x200, 2)]
        with patch("save_reload.region_spans", return_value=spans):
            return classify(h, old, new, loaded)

    def test_unchanged_party_does_not_make_old_main_a_mixed_save(self):
        old = {"main": b"ab", "party": b"cd"}
        new = {"main": b"ef", "party": b"cd"}
        result = self.classify_fixture(old, new, old)
        self.assertEqual(result, {"main": "old", "party": "unchanged"})
        self.assertEqual(checkpoint_kind(result), "old")

    def test_different_main_and_party_still_identify_a_real_mix(self):
        old = {"main": b"ab", "party": b"cd"}
        new = {"main": b"ef", "party": b"gh"}
        result = self.classify_fixture(old, new, {"main": new["main"], "party": old["party"]})
        self.assertEqual(checkpoint_kind(result), "mixed")

    def test_identical_snapshots_and_unknown_bytes_are_distinguished(self):
        image = {"main": b"ab", "party": b"cd"}
        self.assertEqual(checkpoint_kind(self.classify_fixture(image, image, image)), "unchanged")
        corrupt = {"main": b"xx", "party": b"cd"}
        self.assertEqual(checkpoint_kind(self.classify_fixture(image, image, corrupt)), "other")
