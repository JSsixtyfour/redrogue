"""Evidence reliability: isolation, incomplete workers, and stable classification."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import run_campaign as campaign


class CampaignTest(unittest.TestCase):
    def test_timeout_and_missing_results_cannot_pass(self):
        clean = {"runs": [{"outcome": "completed"}]}
        self.assertEqual(campaign.classify(0, clean, "budget_exhausted"), "incomplete")
        self.assertEqual(campaign.classify(0, None, "completed"), "harness_error")
        self.assertEqual(campaign.classify(0, {"runs": []}, "completed"), "harness_error")
        self.assertEqual(campaign.classify(0, {"runs": [{"outcome": "hung"}]}, "completed"), "incomplete")

    def test_blackout_is_not_a_failure_and_save_mismatch_is_a_suspect(self):
        clean = {"runs": [{"outcome": "blackout"}]}
        self.assertEqual(campaign.classify(0, clean, "completed"), "no_issue_detected")
        clean["runs"][0]["save_findings"] = [{"check": "round_trip"}]
        self.assertEqual(campaign.classify(0, clean, "completed"), "suspected_issue")

    def test_duplicate_seed_or_case_is_rejected(self):
        with self.assertRaises(ValueError):
            campaign.validate_config({"cases": [{"id": "a", "args": ["--seeds", "1,1"]}]})
        with self.assertRaises(ValueError):
            campaign.validate_config({"cases": [{"id": "../escape", "args": []}]})

    def test_worker_exit_without_summary_remains_visible(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runner = root / "worker.py"
            runner.write_text("raise SystemExit(7)\n")
            with patch.object(campaign, "RUNNER", runner):
                result = campaign.execute_case({"id": "failed", "args": []}, root / "case", 10)
            self.assertEqual(result["exit"], 7)
            self.assertEqual(result["verdict"], "harness_error")
            self.assertEqual(json.loads((root / "case/result.json").read_text()), result)

    def test_same_seed_configurations_and_attempts_do_not_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runner = root / "worker.py"
            runner.write_text(
                "import json, os\nfrom pathlib import Path\n"
                "p = Path(os.environ['REDROGUE_AUTOPLAY_ARTIFACTS'])\n"
                "(p/'autoplay_summary.json').write_text(json.dumps({'runs': [{'seed': 1, 'outcome': 'completed'}]}))\n")
            with patch.object(campaign, "RUNNER", runner):
                first = campaign.execute_case({"id": "a", "args": ["--seeds", "1"]}, root / "a", 10)
                second = campaign.execute_case({"id": "b", "args": ["--seeds", "1", "--cgb"]}, root / "b", 10)
                retry = campaign.execute_case({"id": "a", "args": ["--seeds", "1"]}, root / "a", 10)
            self.assertEqual(len({r["summary"] for r in (first, second, retry)}), 3)
            for result in (first, second, retry):
                self.assertTrue(Path(result["summary"]).exists())
                self.assertEqual(result["verdict"], "no_issue_detected")

    def test_resume_keeps_completed_case_and_flags_lost_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = root / "config.json"
            config.write_text(json.dumps({"cases": [{"id": "one", "args": ["--seeds", "1"]}]}))
            runner = root / "worker.py"
            runner.write_text(
                "import json, os\nfrom pathlib import Path\n"
                "p = Path(os.environ['REDROGUE_AUTOPLAY_ARTIFACTS'])\n"
                "(p/'autoplay_summary.json').write_text(json.dumps({'runs': [{'seed': 1, 'outcome': 'completed'}]}))\n")
            argv = [str(config), "--output", str(root / "campaign")]
            with patch.object(campaign, "RUNNER", runner), \
                    patch.object(campaign, "source_identity", return_value={"files": {}}), \
                    patch.object(campaign, "build_identity", return_value={}):
                self.assertEqual(campaign.main(argv), 0)
                result_path = root / "campaign/one/result.json"
                first = result_path.read_bytes()
                self.assertEqual(campaign.main(argv), 0)
                self.assertEqual(result_path.read_bytes(), first)
                result = json.loads(first)
                Path(result["summary"]).unlink()
                self.assertEqual(campaign.main(argv), 1)
                self.assertEqual(len(list((root / "campaign/one").glob("attempt-*"))), 1)
                self.assertEqual(json.loads(result_path.read_text())["verdict"], "harness_error")

    def test_budget_kills_worker_and_is_incomplete(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runner = root / "worker.py"
            runner.write_text("import time\ntime.sleep(20)\n")
            with patch.object(campaign, "RUNNER", runner):
                result = campaign.execute_case({"id": "slow", "args": []}, root / "case", 0.1)
            self.assertEqual(result["execution"], "budget_exhausted")
            self.assertEqual(result["verdict"], "incomplete")

    def test_skipped_save_checks_do_not_satisfy_exposure(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / "report.json"
            report.write_text(json.dumps({"save_checks": {"round_trips": [
                {"skipped": "no idle overworld", "status": None},
                {"status": 2, "overworld": True}], "power_cuts": [{"loads": "old"}]}}))
            counts = campaign.achieved_exposure({"runs": [{"report": str(report), "run_records": [1, 2]}]})
            self.assertEqual(counts["save_round_trips"], 1)
            self.assertEqual(counts["power_cuts"], 1)
            self.assertEqual(counts["completed_runs"], 2)

    def test_sram_normalization_preserves_findings_and_exposure(self):
        normalized = campaign.normalize_summary({"scenario": "sram"}, {
            "seeds": [1, 2], "fills": ["ff"], "divergences": [{"seed": 2, "fill": "ff"}]})
        self.assertEqual(campaign.achieved_exposure(normalized)["sram_fills"], 2)
        self.assertEqual(campaign.classify(1, normalized, "completed"), "suspected_issue")

    def test_missing_required_exposure_cannot_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runner = root / "worker.py"
            runner.write_text(
                "import json, os\nfrom pathlib import Path\n"
                "p = Path(os.environ['REDROGUE_AUTOPLAY_ARTIFACTS'])\n"
                "(p/'autoplay_summary.json').write_text(json.dumps({'runs': [{'seed': 1, 'outcome': 'completed'}]}))\n")
            with patch.object(campaign, "RUNNER", runner):
                result = campaign.execute_case({"id": "a", "args": ["--seeds", "1"],
                                                "required_exposure": {"save_round_trips": 1}}, root / "a", 10)
            self.assertEqual(result["verdict"], "incomplete")
            self.assertEqual(result["missing_exposure"]["save_round_trips"], {"required": 1, "achieved": 0})


if __name__ == "__main__":
    unittest.main()
