"""Nightly regression bookkeeping (nightly.py): what counts as worse than last
night. Source-only: synthetic reports, no emulator."""
import tempfile
import json
import unittest
from pathlib import Path

import nightly


def suite(name, exit=0, failing=(), kinds=(), champion=None):
    return {"suite": name, "exit": exit, "failing": list(failing),
            "findings": [{"kind": k, "what": k} for k in kinds], "champion_rate": champion}


class RegressionsTest(unittest.TestCase):
    def regressions(self, old_suites, new_suites):
        previous = {"suites": old_suites}
        return nightly.regressions({"suites": new_suites}, previous)

    def test_failure_without_baseline_is_visible(self) -> None:
        self.assertEqual(nightly.regressions({"suites": [suite("smoke", exit=1)]}, None), ["smoke: issue has no baseline"])

    def test_newly_failing_test_and_suite(self) -> None:
        found = self.regressions([suite("smoke", failing=["a.A.test_old"])],
                                 [suite("smoke", exit=1, failing=["a.A.test_old", "b.B.test_new"])])
        self.assertIn("smoke: newly failing b.B.test_new", found)
        self.assertFalse(any("test_old" in f for f in found))
        self.assertIn("smoke: passed last night, fails now (exit 1)", found)

    def test_only_new_kinds_of_finding_count(self) -> None:
        found = self.regressions([suite("lobby", kinds=["party"])],
                                 [suite("lobby", kinds=["party", "party", "crashed"])])
        self.assertEqual(found, ["lobby: new kind of finding: crashed"])

    def test_champion_rate_drop_beyond_noise(self) -> None:
        self.assertEqual(self.regressions([suite("lobby", champion=0.5)], [suite("lobby", champion=0.45)]), [])
        found = self.regressions([suite("lobby", champion=0.5)], [suite("lobby", champion=0.2)])
        self.assertEqual(found, ["lobby: champion rate 50% -> 20%"])


class ReportingTest(unittest.TestCase):
    def test_headlines(self):
        self.assertEqual(nightly.status({"failed": False}), "clean")
        self.assertEqual(nightly.status({"failed": True}), "known issues only")
        self.assertEqual(nightly.status({"failed": False, "regressions": ["coverage"]}), "NEW regression")
        self.assertEqual(nightly.status({"runner_error": "blocked"}), "NEW regression")

    def test_stale_marker_recovers_and_live_lock_blocks(self):
        try:
            import fcntl
        except ImportError:
            self.skipTest("nightly uses a WSL file lock")
        with tempfile.TemporaryDirectory() as root:
            reports = Path(root)
            marker = reports / "nightly.lock"
            marker.touch()
            with nightly.nightly_lock(reports):
                owner = json.loads(marker.read_text())
                self.assertIn("started_at", owner)
                with self.assertRaises(nightly.NightlyBusy):
                    with nightly.nightly_lock(reports):
                        self.fail("second owner acquired the lock")
            self.assertFalse(marker.exists())

    def test_coverage_requires_three_comparable_maps(self):
        with tempfile.TemporaryDirectory() as root:
            folders = [Path(root) / str(index) for index in range(4)]
            for index, folder in enumerate(folders):
                counts = {"src::Persistent": int(index > 0), "src::Intermittent": int(index in (1, 2))}
                folder.mkdir()
                (folder / "newgame_coverage_summary.json").write_text(json.dumps({
                    "routine_identity": "source-name-v1", "routine_run_counts": counts,
                    "files": {}, "totals": {"routines_run": sum(counts.values())},
                }))
            delta, messages = nightly.coverage_regression(folders[0], folders[1:])
            self.assertEqual(delta["persistent_lost"], ["src::Persistent"])
            self.assertEqual(len(messages), 1)
            self.assertEqual(nightly.coverage_regression(folders[0], folders[1:3]), ({}, []))


class QuickModeTest(unittest.TestCase):
    def test_quick_flags_exist_in_their_suites(self) -> None:
        for name, flags in nightly.QUICK.items():
            for flag in flags:
                self.assertIn(flag, nightly.SUITES[name][0], (name, flag))


class ArtifactRetentionTest(unittest.TestCase):
    def test_failed_seed_keeps_nested_save_packages_and_repeated_findings(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            worktree, night = root / "worktree", root / "night"
            artifacts = worktree / nightly.ARTIFACTS
            artifacts.mkdir(parents=True)
            night.mkdir()
            package = artifacts / "autoplay_seed7_save-123" / "cold_boot"
            package.mkdir(parents=True)
            (package / "initial.state").write_bytes(b"retained state")
            (artifacts / "autoplay_seed7.json").write_text('{"seed":7}')
            (artifacts / "autoplay_seed70.json").write_text("unrelated")
            row = {"seed": 7, "outcome": "stalled", "detail": "no progress",
                   "map": "PROCEDURAL_FACILITY", "anomalies": [],
                   "save_findings": [{"check": "round_trip"}]}
            (night / "newgame_autoplay_summary.json").write_text(
                json.dumps({"runs": [row, row]}))
            result = nightly.autoplay_findings("newgame", worktree, night)
            kept = night / "newgame_seeds"
            self.assertEqual((kept / "autoplay_seed7_save-123" / "cold_boot" /
                              "initial.state").read_bytes(), b"retained state")
            self.assertEqual((kept / "autoplay_seed7.json").read_text(), '{"seed":7}')
            self.assertFalse((kept / "autoplay_seed70.json").exists())
            self.assertEqual(len(result["findings"]), 4)
            self.assertEqual(result["findings"][0]["kind"], "stalled")
            self.assertEqual(result["findings"][1]["kind"], "save round_trip")
            self.assertTrue((package / "initial.state").exists())

    def test_clean_seed_does_not_copy_unneeded_package(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            (root / "lobby_autoplay_summary.json").write_text(json.dumps({
                "runs": [{"seed": 7, "outcome": "champion", "detail": "",
                          "map": "HALL_OF_FAME", "anomalies": []}]}))
            result = nightly.autoplay_findings("lobby", root / "absent", root)
            self.assertEqual(result["findings"], [])
            self.assertFalse((root / "lobby_seeds").exists())


if __name__ == "__main__":
    unittest.main()
