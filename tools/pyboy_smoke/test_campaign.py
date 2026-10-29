"""Evidence reliability: isolation, incomplete workers, and stable classification."""
import json
from pathlib import Path
import tempfile
import queue
import time
import unittest
from unittest.mock import patch

import run_campaign as campaign


def bounded_fill_probe(task_id, options, results):
    if task_id == 1:
        time.sleep(20)
    else:
        results.put((task_id, {"task": task_id, "execution": "completed"}))


def bounded_fill_timeout(task_id, timeout, options):
    return {"task": task_id, "execution": "budget_exhausted"}


class CampaignTest(unittest.TestCase):
    def test_sram_startup_path_comparisons_are_not_initialization_proof(self):
        from sram_fuzz import comparison_kind
        blank = {"startup_path": ["initialization_entered", "gameplay_ready"]}
        consent = {"startup_path": ["discard_prompt", "consent_accepted", "initialization_entered", "gameplay_ready"]}
        self.assertEqual(comparison_kind(blank, consent), "different_startup_paths")
        self.assertEqual(comparison_kind(consent, consent), "same_startup_path")
        self.assertEqual(comparison_kind({}, consent), "unverified_startup")

    def test_archived_build_and_source_must_remain_available(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "build").mkdir()
            (root / "build/game.gbc").write_bytes(b"rom")
            (root / "source.tar.gz").write_bytes(b"source")
            manifest = {"identity": {"builds": {"game.gbc": campaign.digest(root / "build/game.gbc")}},
                        "archive_hashes": {"source.tar.gz": campaign.digest(root / "source.tar.gz")}}
            campaign.validate_campaign_archive(root, manifest)
            (root / "source.tar.gz").write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "archive missing or changed"):
                campaign.validate_campaign_archive(root, manifest)
            (root / "build/game.gbc").unlink()
            with self.assertRaisesRegex(ValueError, "build missing or changed"):
                campaign.validate_campaign_archive(root, manifest)

    def test_fill_scheduler_keeps_successful_sibling_when_another_times_out(self):
        from run_autoplay import run_all
        rows = list(run_all([0, 1], {}, 2, 0.1, worker=bounded_fill_probe, timeout_row=bounded_fill_timeout))
        self.assertEqual({row["task"]: row["execution"] for row in rows},
                         {0: "completed", 1: "budget_exhausted"})

    def test_fill_worker_retains_input_and_error_record(self):
        import sram_fuzz
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            image = directory / "input.sram"
            image.write_bytes(bytes(32768))
            task = {"seed": 1, "fill": "zero", "repetition": 0, "directory": str(directory),
                    "input_sha256": campaign.digest(image)}
            results = queue.Queue()
            with patch.object(sram_fuzz.autoplay, "ARTIFACTS", directory), \
                    patch.object(sram_fuzz.autoplay, "play", side_effect=RuntimeError("injected boot failure")):
                sram_fuzz.fill_worker(0, {"tasks": [task], "play": {}}, results)
            record = json.loads((directory / "record.json").read_text())
            self.assertEqual(record["execution"], "error")
            self.assertIsNone(record["equivalent"])
            self.assertIn("injected boot failure", record["detail"])
            self.assertEqual(campaign.digest(image), task["input_sha256"])

    def test_negative_control_matches_only_exact_expected_findings(self):
        allowed = {"check": "mart_transaction", "version": 1, "field": "money",
                   "evidence_origin": "controlled_detector_input"}
        case = {"expected_findings": [allowed]}
        summary = {"runs": [{"outcome": "completed", "contract_findings": [allowed]}]}
        self.assertTrue(campaign.control_matches(case, summary, "completed", 1, {}))
        for findings in ([], [allowed, allowed], [allowed, {**allowed, "field": "party",
                           "evidence_origin": "actual_ROM_fixture"}], [{**allowed, "version": 2}]):
            with self.subTest(findings=findings):
                bad = {"runs": [{"outcome": "completed", "contract_findings": findings}]}
                self.assertFalse(campaign.control_matches(case, bad, "completed", 1, {}))
        self.assertFalse(campaign.control_matches(case, summary, "budget_exhausted", 1, {}))
        self.assertFalse(campaign.control_matches(case, summary, "completed", 7, {}))
        self.assertFalse(campaign.control_matches(case, summary, "completed", 1, {"stages": {}}))
        summary["runs"][0]["anomalies"] = ["unrelated"]
        self.assertFalse(campaign.control_matches(case, summary, "completed", 1, {}))

    def test_invalid_referenced_evidence_cannot_bypass_quotas(self):
        for payload in (None, "not json", "[]", '{"save_checks": []}',
                        '{"save_checks": {"round_trips": [3]}}'):
            with self.subTest(payload=payload), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                runner = root / "worker.py"
                runner.write_text(
                    "import json,os\nfrom pathlib import Path\n"
                    "p=Path(os.environ['REDROGUE_AUTOPLAY_ARTIFACTS'])\n"
                    f"payload={payload!r}\n"
                    "if payload is not None: (p/'report.json').write_text(payload)\n"
                    "(p/'autoplay_summary.json').write_text(json.dumps({'runs': ["
                    "{'seed': 1, 'outcome': 'completed', 'stages_cleared': 1},"
                    "{'seed': 2, 'outcome': 'completed', 'report': str(p/'report.json')}]}))\n")
                with patch.object(campaign, "RUNNER", runner):
                    result = campaign.execute_case({"id": "broken", "args": ["--seeds", "1,2"],
                        "required_exposure": {"stages": 1, "save_round_trips": 1}}, root / "case", 10)
                self.assertEqual(result["verdict"], "harness_error")
                self.assertEqual(result["achieved_exposure"], {})
                self.assertEqual(result["missing_exposure"]["stages"]["status"], "unknown")

    def test_invalid_summary_schema_and_count_types(self):
        for runs in (None, {}, [None], [{"stages_cleared": "1"}],
                     [{"sram_fills": True}], [{"stages_cleared": -1}],
                     [{"run_records": 1}]):
            with self.subTest(runs=runs), self.assertRaises((ValueError, TypeError)):
                campaign.achieved_exposure({"runs": runs})

    def test_resume_checks_each_required_dependency_without_rerunning(self):
        for name in ("report.json", "case.json", "initial.state", "inputs.json", "build_identity.json"):
            for action in ("delete", "tamper"):
                with self.subTest(name=name, action=action), tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    runner = root / "worker.py"
                    runner.write_text(
                        "import json,os\nfrom pathlib import Path\n"
                        "p=Path(os.environ['REDROGUE_AUTOPLAY_ARTIFACTS'])\n"
                        "for name in ('report.json','case.json','inputs.json','build_identity.json'): "
                        "(p/name).write_text('{}')\n"
                        "(p/'initial.state').write_bytes(b'replay')\n"
                        "(p/'autoplay_summary.json').write_text(json.dumps({'runs': ["
                        "{'seed':1, 'outcome':'completed', 'report':str(p/'report.json')}]}))\n")
                    config = root / "config.json"
                    config.write_text(json.dumps({"cases": [{"id": "one", "args": ["--seeds", "1"]}]}))
                    argv = [str(config), "--output", str(root / "campaign")]
                    with patch.object(campaign, "RUNNER", runner), \
                            patch.object(campaign, "source_identity", return_value={"files": {}}), \
                            patch.object(campaign, "build_identity", return_value={}), \
                            patch.object(campaign.subprocess, "check_output", return_value=b""):
                        self.assertEqual(campaign.main(argv), 0)
                        result_path = root / "campaign/one/result.json"
                        original = json.loads(result_path.read_text())
                        target = Path(original["attempt"]) / "artifacts" / name
                        target.unlink() if action == "delete" else target.write_bytes(b'tampered')
                        self.assertEqual(campaign.main(argv), 1)
                        result = json.loads(result_path.read_text())
                        self.assertEqual(result["verdict"], "harness_error")
                        self.assertEqual(result["original_verdict"], "no_issue_detected")
                        self.assertEqual(len(list((root / "campaign/one").glob("attempt-*"))), 1)

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
                    patch.object(campaign, "build_identity", return_value={}), \
                    patch.object(campaign.subprocess, "check_output", return_value=b""):
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
        tasks = [{"seed": seed, "fill": "ff", "repetition": 0} for seed in (1, 2)]
        normalized = campaign.normalize_summary({"scenario": "sram"}, {
            "seeds": [1, 2], "fills": ["ff"], "divergences": [{"seed": 2, "fill": "ff"}],
            "expected_fills": tasks, "records": [dict(task, execution="completed", equivalent=task["seed"] == 1)
                                                 for task in tasks]})
        self.assertEqual(campaign.achieved_exposure(normalized)["sram_fills"], 1)
        self.assertEqual(campaign.classify(1, normalized, "completed"), "suspected_issue")

    def test_partial_sram_records_never_fabricate_completion(self):
        task = {"seed": 1, "fill": "random1", "repetition": 3}
        for records in ([], [dict(task, execution="error", equivalent=None)],
                        [dict(task, execution="completed", equivalent=None)]):
            summary = campaign.normalize_summary({"scenario": "sram"}, {
                "seeds": [1], "divergences": [], "expected_fills": [task], "records": records})
            self.assertEqual(campaign.classify(0, summary, "completed"), "incomplete")
            self.assertEqual(campaign.achieved_exposure(summary)["sram_fills"], 0)

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
