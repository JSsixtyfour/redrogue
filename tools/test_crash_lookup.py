"""Tests for tools/crash_lookup.py against a synthetic builds/ tree.

    python3 -m unittest tools/test_crash_lookup.py      (from the repo root)
"""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import crash_lookup as cl  # noqa: E402

SYM = """; comment
00:0150 Start
00:3e70 HomeRoutine
1f:4000 BankStart
1f:4120 BankRoutine
1f:5a00 PaddingStart
01:c000 wRamLabel
"""


def make_rom() -> bytes:
    rom = bytearray(0x80000)
    rom[0x1F * 0x4000 + (0x5A3C - 0x4000)] = 0xFF   # padding at 1F:5A3C
    rom[0x1F * 0x4000 + (0x4123 - 0x4000)] = 0xCD   # code at 1F:4123
    return bytes(rom)


class Lookup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.builds = Path(self.tmp.name)
        (self.builds / "releases").mkdir()
        for name in ("pokeblue_debug_2026-10-01_120000_abcd1234", "pokeblue_debug_2026-10-01_130000_abcd1234",
                     "pokeblue_debug_2026-10-02_090000_abcd1234-dirty"):
            (self.builds / f"{name}.sym").write_text(SYM)
            (self.builds / f"{name}.gbc").write_bytes(make_rom())

    def tearDown(self):
        self.tmp.cleanup()

    def run_json(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            try:
                code = cl.main([*argv, "--builds-dir", str(self.builds), "--json"])
            except SystemExit as e:
                code = e.code
        return code, json.loads(out.getvalue())

    def test_exact_refuses_ambiguity_and_lists_candidates(self):
        code, doc = self.run_json("abcd1234", "1F:5A3C", "--exact")
        self.assertEqual(code, 2)
        self.assertFalse(doc["ok"])
        self.assertEqual(doc["candidates"], ["pokeblue_debug_2026-10-01_120000_abcd1234",
                                             "pokeblue_debug_2026-10-01_130000_abcd1234"])

    def test_exact_with_date_picks_one(self):
        code, doc = self.run_json("abcd1234", "1F:5A3C", "4123", "3E75", "C001", "--exact",
                                  "--built", "2026-10-01 12:00")
        self.assertEqual(code, 0)
        self.assertEqual(doc["build"], "pokeblue_debug_2026-10-01_120000_abcd1234")
        self.assertTrue(doc["pc"]["ff_padding"])
        self.assertEqual((doc["pc"]["label"], doc["pc"]["offset"]), ("PaddingStart", 0x3C))
        romx, home, ram = doc["stack"]
        self.assertEqual((romx["kind"], romx["label"], romx["offset"]), ("romx_candidate", "BankRoutine", 3))
        self.assertEqual((home["kind"], home["label"]), ("home", "HomeRoutine"))
        self.assertEqual(ram["kind"], "not_rom")
        self.assertEqual(len(doc["rom_sha256"]), 64)

    def test_releases_copy_wins_and_dirty_only_matches_dirty_in_exact_mode(self):
        (self.builds / "releases" / "pokeblue_debug_2026-10-01_120000_abcd1234.sym").write_text(SYM)
        sym = cl.find_sym("abcd1234", "2026-10-01 12:00", self.builds, exact=True)
        self.assertEqual(sym.parent.name, "releases")
        dirty = cl.find_sym("abcd1234-dirty", None, self.builds, exact=True)
        self.assertTrue(dirty.stem.endswith("-dirty"))
        # Lenient (interactive) mode still lets a clean ID find a dirty build, newest wins.
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertTrue(cl.find_sym("abcd1234", None, self.builds).stem.endswith("-dirty"))

    def test_malformed_input_is_rejected(self):
        for argv in (["abcd1234", "1F5A3C"], ["abcd1234", "80:4000"], ["abcd1234", "1F:5A3"],
                     ["abcd1234", "1F:5A3C", "12345"], ["abcd1234", "1F:5A3C", "zz00"],
                     ["../../etc", "1F:5A3C", "--exact"], ["abcd1234", "1F:5A3C", "--built", "yesterday"]):
            with self.subTest(argv=argv):
                code, doc = self.run_json(*argv)
                self.assertEqual(code, 2)
                self.assertFalse(doc["ok"])

    def test_unknown_build(self):
        code, doc = self.run_json("ffff0000", "00:0150", "--exact")
        self.assertEqual(code, 2)
        self.assertIn("no archived debug build", doc["error"])

    def test_null_pc_and_text_mode(self):
        code, doc = self.run_json("abcd1234-dirty", "00:0000", "--exact")
        self.assertEqual(doc["pc"]["kind"], "null")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            cl.main(["abcd1234-dirty", "1F:5A3C", "4123", "--builds-dir", str(self.builds)])
        self.assertIn("That byte is $FF", out.getvalue())
        self.assertIn("called from BankRoutine+$3, if this call was made in bank $1f", out.getvalue())


if __name__ == "__main__":
    unittest.main()
