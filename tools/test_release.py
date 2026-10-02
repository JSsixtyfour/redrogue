"""Tests for tools/release.py with git, make and Discord replaced by fakes over a
temporary artifact tree. Never runs a real build or sends anything.

    python3 -m unittest tools/test_release.py      (from the repo root)
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import time
import unittest
from email.parser import BytesParser
from email.policy import HTTP
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release  # noqa: E402

SHORT, FULL = "abcd1234", "abcd1234" + "0" * 32
STAMP = "2026-10-02_120000"


def args(**kw):
    base = dict(notes="n", testing="t", save_compat="unverified", save_compat_from=None, save_compat_notes=None,
                no_announce=False, dry_run=False)
    base.update(kw)
    return SimpleNamespace(**base)


class Tree(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        (self.repo / "builds").mkdir()
        patches = {"REPO": self.repo, "BUILDS": self.repo / "builds", "RELEASES": self.repo / "builds" / "releases"}
        for name, value in patches.items():
            p = mock.patch.object(release, name, value)
            p.start()
            self.addCleanup(p.stop)
        for name, value in {"check_git": lambda: (FULL, SHORT), "git": lambda *a: "subject",
                            "tool_versions": lambda: {"rgbasm": "fake"}, "webhook_url": lambda: "https://x/hook",
                            "ask": lambda prompt: ""}.items():
            p = mock.patch.object(release, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.sent = []
        p = mock.patch.object(release, "send",
                              lambda url, rom, meta, sym=None, converter=None:
                              self.sent.append((rom, meta, sym, converter)) or {"id": "1"})
        p.start()
        self.addCleanup(p.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def fake_build(self, *, rom_bytes=b"ROM", skip=(), corrupt=None):
        """What `make` leaves behind: root outputs plus stamped archives."""
        def checks(log_dir, space_json):
            (log_dir / "build.log").write_text("ok\n")
            space_json.write_text("{}")
            for rom in release.ROMS:
                data = rom_bytes + rom.encode()
                for suffix, content in ((".gbc", data), (".sym", b"SYM" + data), (".map", b"MAP" + data)):
                    if (rom, suffix) in skip:
                        continue
                    (self.repo / f"{rom}{suffix}").write_bytes(content)
                    if suffix != ".map":
                        archived = content if corrupt != (rom, suffix) else content + b"!"
                        (self.repo / "builds" / f"{rom}_{STAMP}_{SHORT}{suffix}").write_bytes(archived)
            return [{"name": "build", "exit_code": 0}]
        return mock.patch.object(release, "checks", checks)


class ReleaseFlow(Tree):
    def test_release_packages_everything_and_sends_the_debug_rom(self):
        with self.fake_build():
            self.assertEqual(release.release(args()), 0)
        [(rom, meta, sym, converter)] = self.sent
        self.assertEqual(rom.name, f"pokeblue_debug_{STAMP}_{SHORT}.gbc")
        self.assertEqual(sym.name, f"pokeblue_debug_{STAMP}_{SHORT}.sym")
        pkg = self.repo / "builds" / "releases" / f"pokeblue_debug_{STAMP}_{SHORT}"
        for r in release.ROMS:
            for suffix in (".gbc", ".sym", ".map"):
                self.assertTrue((pkg / f"{r}_{STAMP}_{SHORT}{suffix}").is_file(), (r, suffix))
        manifest = json.loads((pkg / "manifest.json").read_text())
        self.assertEqual(manifest, meta["manifest"])
        self.assertEqual(manifest["commit"], FULL)
        self.assertEqual(manifest["manual_acceptance"]["status"], "pending")
        self.assertEqual(manifest["artifacts"]["pokeblue_debug"]["gbc"]["sha256"], release.sha256(rom))
        self.assertTrue((pkg / "logs" / "build.log").is_file() and (pkg / "space.json").is_file())
        self.assertTrue((pkg / "sent.json").is_file())
        self.assertTrue((self.repo / "builds" / "releases" / rom.name).is_file())  # crash_lookup's spot
        self.assertEqual(meta["save_compatibility"], "unverified")
        save = manifest["save"]
        self.assertEqual(save["target_rom_sha256"], release.sha256(rom))
        self.assertTrue(converter.is_file() and converter.name.startswith("save-convert-"))
        self.assertEqual(release.sha256(converter), save["converter_sha256"])
        self.assertEqual(pkg / save["converter"], converter)
        self.assertIsInstance(save["schema"], int)
        self.assertFalse(list((self.repo / "builds" / "releases").glob(".staging-*")))

    def test_dry_run_sends_nothing(self):
        with self.fake_build():
            self.assertEqual(release.release(args(dry_run=True)), 0)
        self.assertEqual(self.sent, [])
        pkg = self.repo / "builds" / "releases" / f"pokeblue_debug_{STAMP}_{SHORT}"
        self.assertTrue((pkg / "manifest.json").is_file() and not (pkg / "sent.json").exists())

    def test_failed_check_prevents_send(self):
        def failing(log_dir, space_json):
            release.fail("`make smoke` failed")
        with mock.patch.object(release, "checks", failing):
            with self.assertRaises(release.ReleaseError):
                release.release(args())
        self.assertEqual(self.sent, [])
        self.assertFalse(any((self.repo / "builds" / "releases").iterdir()))  # staging cleaned up

    def test_missing_map_or_sym_fails_before_sending(self):
        for skip in (("pokered", ".map"), ("pokeblue", ".sym")):
            for f in self.repo.rglob("*"):
                if f.is_file():
                    f.unlink()
            with self.subTest(skip=skip), self.fake_build(skip={skip}):
                with self.assertRaises(release.ReleaseError) as e:
                    release.release(args())
                self.assertIn("missing", str(e.exception))
        self.assertEqual(self.sent, [])

    def test_archive_that_differs_from_the_build_is_rejected(self):
        with self.fake_build(corrupt=("pokered", ".gbc")):
            with self.assertRaises(release.ReleaseError) as e:
                release.release(args())
        self.assertIn("doesn't match", str(e.exception))
        self.assertEqual(self.sent, [])

    def test_stale_archive_is_not_picked_up(self):
        old = self.repo / "builds" / f"pokeblue_debug_2026-01-01_000000_{SHORT}.gbc"
        old.write_bytes(b"OLD")
        past = time.time() - 3600
        os.utime(old, (past, past))
        with self.fake_build():
            release.release(args())
        self.assertEqual(self.sent[0][0].name, f"pokeblue_debug_{STAMP}_{SHORT}.gbc")

    def test_retry_with_same_bytes_reuses_and_different_bytes_refuses(self):
        with self.fake_build():
            release.release(args())
            release.release(args())  # identical retry: fine
        self.assertEqual(len(self.sent), 2)
        with self.fake_build(rom_bytes=b"CHANGED"):
            with self.assertRaises(release.ReleaseError) as e:
                release.release(args())
        self.assertIn("never overwritten", str(e.exception))
        self.assertEqual(len(self.sent), 2)


class SaveCompat(unittest.TestCase):
    def test_supported_needs_a_tested_build(self):
        with mock.patch.object(release, "ask", lambda prompt: ""):
            with self.assertRaises(release.ReleaseError):
                release.save_compat(args(save_compat="supported"))
        got = release.save_compat(args(save_compat="supported", save_compat_from="74f82c1b"))
        self.assertEqual(got, {"status": "supported", "tested_from": "74f82c1b", "notes": None})

    def test_default_and_bad_values(self):
        with mock.patch.object(release, "ask", lambda prompt: ""):
            self.assertEqual(release.save_compat(args(save_compat=None))["status"], "unverified")
        with mock.patch.object(release, "ask", lambda prompt: "sure"):
            with self.assertRaises(release.ReleaseError):
                release.save_compat(args(save_compat=None))


class Checks(unittest.TestCase):
    def test_failing_command_is_logged_and_stops(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(release.ReleaseError):
                release.run_check("boom", [sys.executable, "-c", "print('hi'); raise SystemExit(3)"], Path(tmp))
            log = (Path(tmp) / "boom.log").read_text()
            self.assertIn("hi", log)
            self.assertIn("[exit 3]", log)

    def test_passing_command_entry(self):
        with tempfile.TemporaryDirectory() as tmp:
            entry = release.run_check("ok", [sys.executable, "-c", "print('fine')"], Path(tmp))
        self.assertEqual((entry["exit_code"], entry["log"]), (0, "logs/ok.log"))


class Multipart(unittest.TestCase):
    def test_round_trip(self):
        rom = bytes(range(256)) * 4 + b"\r\n--tricky\r\n"
        body, ctype = release.multipart([
            ("payload_json", "", json.dumps({"content": "hi"}).encode(), "application/json"),
            ("files[0]", "pokeblue_debug_x.gbc", rom, None),
            ("files[1]", "release.json", b'{"a": 1}', "application/json"),
        ])
        msg = BytesParser(policy=HTTP).parsebytes(b"Content-Type: " + ctype.encode() + b"\r\n\r\n" + body)
        parts = list(msg.iter_parts())
        self.assertEqual(parts[1].get_payload(decode=True), rom)
        self.assertEqual(json.loads(parts[0].get_payload(decode=True)), {"content": "hi"})


if __name__ == "__main__":
    unittest.main()
