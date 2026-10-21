"""Unchanged regions cannot turn a completely old checkpoint into a mix."""
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from save_reload import checkpoint_kind, classify


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
