"""Tests for tools/repro_bundle.py on a synthetic export, builds/ tree and evidence folder.

    python3 -m unittest tools/test_repro_bundle.py      (from the repo root)
"""

from __future__ import annotations

import hashlib
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import repro_bundle as rb  # noqa: E402

STAMP = "pokeblue_debug_2026-10-01_215151_74f82c1b"
ROM = b"\x00" * 0x150 + b"REDROGUE"


def bgb_state(rom: bytes) -> bytes:
    def rec(name: bytes, data: bytes) -> bytes:
        return name + b"\0" + struct.pack("<I", len(data)) + data
    return (rec(b"BGB1.0", b"") + rec(b"rommd5", hashlib.md5(rom).digest()) + rec(b"romfile", b"x.gbc")
            + rec(b"version", b"bgb1.6.6") + rec(b"PC", b"\x00\x01"))


class Bundle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.builds = root / "builds"
        (self.builds / "releases").mkdir(parents=True)
        (self.builds / "releases" / f"{STAMP}.gbc").write_bytes(ROM)
        (self.builds / "releases" / f"{STAMP}.sym").write_text("00:0150 Start\n")
        self.export = root / "export.json"
        self.export.write_text(json.dumps({
            "builds": [{"id": 1, "version": "2026-10-01 74f82c1b", "build_stamp": STAMP, "git_commit": "74f82c1b",
                        "rom_sha1": hashlib.sha1(ROM).hexdigest(), "rom_sha256": hashlib.sha256(ROM).hexdigest()},
                       {"id": 2, "version": "v-old", "build_stamp": None}],
            "reports": [
                {"id": 12, "report_code": "RR-0012", "report_type": "bug", "status": "FIXED", "build_id": 1,
                 "summary": "Door warps wrong", "details": "Walked into the F3 door.", "tester_name_snapshot": "Sope",
                 "discord_user_id": "111", "created_at": "2026-10-01T22:00:00+00:00",
                 "attachments": [{"filename": "shot.png"}, {"filename": "clip.mp4"}],
                 "events": [{"event_type": "tester_reply", "note": "mGBA 0.10", "created_at": "x"}],
                 "fix_attempts": [{"id": 1, "released_build_id": 1, "superseded_at": None}],
                 "retests": [{"id": 1, "outcome": "still_happens", "tested_build_id": 1, "effect": "reopened",
                              "environment": "BGB 1.6.6"}]},
                {"id": 13, "report_type": "crash", "build_id": None, "attachments": [], "events": []},
                {"id": 14, "report_type": "bug", "build_id": 2, "attachments": [], "events": []},
            ]}))
        self.evidence = root / "evidence"
        self.evidence.mkdir()
        (self.evidence / "shot.png").write_bytes(b"\x89PNG\r\n\x1a\n raw bytes \x00\xff")
        (self.evidence / "good.sn1").write_bytes(bgb_state(ROM))
        (self.evidence / "old.sn2").write_bytes(bgb_state(b"another rom"))
        (self.evidence / "broken.sn3").write_bytes(b"not a state")
        self.root = root

    def tearDown(self):
        self.tmp.cleanup()

    def make(self, report="RR-0012", **kw):
        return rb.bundle(report, self.export, kw.get("evidence", self.evidence), kw.get("out"), self.builds)

    def test_full_bundle(self):
        out = self.make()
        self.assertEqual(out, self.builds / "repro" / "RR-0012")
        manifest = json.loads((out / "manifest.json").read_text())
        self.assertEqual(manifest["artifact"]["status"], "matched")
        verdicts = {s["file"]: s["verdict"] for s in manifest["save_states"]}
        self.assertEqual(verdicts, {"good.sn1": "matched", "old.sn2": "MISMATCH", "broken.sn3": "unreadable"})
        self.assertEqual(manifest["missing_evidence"], ["clip.mp4"])
        self.assertEqual((out / "evidence" / "shot.png").read_bytes(), (self.evidence / "shot.png").read_bytes())
        self.assertEqual((out / "rom" / f"{STAMP}.gbc").read_bytes(), ROM)
        for name, digest in manifest["files"].items():
            self.assertEqual(hashlib.sha256((out / name).read_bytes()).hexdigest(), digest, name)
        md = (out / "reproduction.md").read_text()
        self.assertIn("> **Save state old.sn2: MISMATCH.**", md)
        self.assertIn("**Missing:**", md)
        self.assertIn("- clip.mp4", md)
        self.assertIn("From retests: BGB 1.6.6", md)
        self.assertNotIn("Build identity:", md)  # the build matched, so no warning

    def test_never_overwrites(self):
        self.make()
        with self.assertRaises(rb.BundleError):
            self.make()

    def test_unknown_and_unstamped_builds(self):
        out = self.make("13", out=self.root / "b13")
        self.assertIn("**Build identity: build_unknown.**", (out / "reproduction.md").read_text())
        out = self.make("RR-14", out=self.root / "b14", evidence=None)
        self.assertEqual(json.loads((out / "manifest.json").read_text())["artifact"]["status"], "no_stamp")

    def test_hash_mismatch_is_not_used_as_the_rom(self):
        (self.builds / "releases" / f"{STAMP}.gbc").write_bytes(ROM + b"changed")
        out = self.make()
        manifest = json.loads((out / "manifest.json").read_text())
        self.assertEqual(manifest["artifact"]["status"], "hash_mismatch")
        self.assertFalse((out / "rom").exists())
        self.assertEqual({s["verdict"] for s in manifest["save_states"] if s["file"] == "good.sn1"}, {"unverifiable"})

    def test_bad_inputs(self):
        for report in ("RR-0099", "nonsense"):
            with self.subTest(report=report), self.assertRaises(rb.BundleError):
                self.make(report, out=self.root / f"x-{report}")
        with self.assertRaises(rb.BundleError):
            self.make(out=self.root / "y", evidence=self.root / "nope")

    def test_bgb_parser_on_a_real_state_if_present(self):
        real = rb.REPO / "pokeblue_debug.sn1"
        if not real.is_file():
            self.skipTest("no BGB state in the repo folder")
        records = rb.bgb_records(real.read_bytes())
        self.assertEqual(len(records["rommd5"]), 16)


if __name__ == "__main__":
    unittest.main()
