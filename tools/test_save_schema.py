#!/usr/bin/env python3
"""Tests for tools/save_schema.py's constant comparison. Pure data: no build,
no rgbasm. Run: python3 -m unittest tools/test_save_schema.py"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import save_schema as ss  # noqa: E402

LAYOUT = {"sram": [{"label": "sA", "bank": 1, "address": "a000", "size": 2}],
          "saved_wram": [{"label": "wA", "block": "sMainData", "offset": 0, "size": 2}]}


def schema(constants, **extra):
    return {**LAYOUT, "constants": constants, **extra}


class Renumbered(unittest.TestCase):
    def test_comments_and_additions_are_identical(self):
        old = schema({"ITEM_A": 1, "ITEM_B": 2})
        new = schema({"ITEM_A": 1, "ITEM_B": 2, "ITEM_C": 3})
        self.assertEqual(ss.diff(old, new)["kind"], "identical")

    def test_a_shifted_constant_is_semantic(self):
        report = ss.diff(schema({"TOGGLE_A": 0x10, "TOGGLE_B": 0x11}), schema({"TOGGLE_A": 0x11, "TOGGLE_B": 0x12}))
        self.assertEqual(report["kind"], "semantic")
        self.assertEqual(report["semantic"]["TOGGLE_A"], {"old": 0x10, "new": 0x11})

    def test_a_removed_constant_is_semantic(self):
        report = ss.diff(schema({"EVENT_A": 1, "EVENT_B": 2}), schema({"EVENT_B": 2}))
        self.assertEqual(report["semantic"], {"EVENT_A": {"old": 1, "new": None}})

    def test_layout_outranks_semantic(self):
        moved = {**schema({"A": 2}), "sram": [{"label": "sA", "bank": 1, "address": "a001", "size": 2}]}
        self.assertEqual(ss.diff(schema({"A": 1}), moved)["kind"], "layout")

    def test_baseline_without_constants_compares_as_none(self):
        self.assertEqual(ss.diff({**LAYOUT, "semantic_sources": {}}, schema({"A": 1}))["kind"], "identical")


class Releases(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def release(self, name, sid, constants):
        (self.root / name).mkdir()
        (self.root / name / ss.RELEASE_VALUES).write_text(json.dumps({"schema_id": sid, "constants": constants}))

    def test_newest_release_of_the_same_schema_wins(self):
        self.release("pokeblue_debug_2026-10-01_100000_aaaa", 1, {"A": 1})
        self.release("pokeblue_debug_2026-10-05_100000_bbbb", 1, {"A": 1, "B": 2})
        self.release("pokeblue_debug_2026-10-09_100000_cccc", 2, {"A": 9})
        (self.root / "pokeblue_debug_2026-10-10_100000_dddd").mkdir()  # no values: an older-style package
        self.assertEqual(ss.newest_release_values(1, self.root),
                         ("pokeblue_debug_2026-10-05_100000_bbbb", {"A": 1, "B": 2}))
        self.assertIsNone(ss.newest_release_values(3, self.root))

    def test_a_constant_added_after_the_schema_is_protected_once_released(self):
        stored = {"constants": {"A": 1}}
        release = ("pokeblue_debug_2026-10-05_100000_bbbb", {"A": 1, "B": 2})
        expected, against = ss.expected_constants(stored, release)
        self.assertEqual(expected, {"A": 1, "B": 2})
        self.assertIn("bbbb", against)
        self.assertEqual(ss.diff(schema(expected), schema({"A": 1, "B": 3}))["kind"], "semantic")

    def test_accept_after_a_release_ignores_that_release_but_not_a_later_one(self):
        stored = {"constants": {"A": 5}, "accepted_after_release": "pokeblue_debug_2026-10-05_100000_bbbb"}
        self.assertEqual(ss.expected_constants(stored, ("pokeblue_debug_2026-10-05_100000_bbbb", {"A": 1}))[0],
                         {"A": 5})
        self.assertEqual(ss.expected_constants(stored, ("pokeblue_debug_2026-10-07_100000_eeee", {"A": 5, "C": 1}))[0],
                         {"A": 5, "C": 1})


if __name__ == "__main__":
    unittest.main()
