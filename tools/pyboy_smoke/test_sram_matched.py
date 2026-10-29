"""Matched initialization evidence: controls, repeats, provenance and quotas."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import run_campaign as campaign
import sram_fuzz as fuzz

HEADER = {"label": "sSaveHeader", "offset": 0x2040, "length": 8}
CASE = {"scenario": "sram", "args": ["--seeds", "1", "--fills", "0", "--matched-controls"]}


def fixture(root):
    with patch.object(fuzz, "header_range", return_value=HEADER):
        tasks, pairs = fuzz.matched_tasks(root / "attempt", [1], ["ff"], "pokeblue_debug")
    records = []
    for task in tasks:
        baseline = task["role"] == "baseline"
        directory = Path(task["directory"])
        campaign.atomic_json(directory / "trace.json", [[10 if baseline else 11, "enter_map", json.dumps({"map": "TRUCK"}, sort_keys=True)],
                                                       ["end", "completed", "cleared one stage"]])
        row = {**copy.deepcopy(task), "execution": "completed", "outcome": "completed", "equivalent": None,
            "anomalies": [], "hardware_mode": "DMG", "build_identity": {"gbc": "a" * 64, "sym": "b" * 64},
            "startup_path": (["initialization_entered", "gameplay_ready"] if baseline else
                             ["discard_prompt", "consent_accepted", "initialization_entered", "gameplay_ready"]),
            "comparison_boundary": {"rng_boundary": "OakSpeech", "comparison_frame": 100, "comparison_cycle": 7000000,
                "comparison_ly": 21, "comparison_state": {"rng": list(range(12)), "joy": [0, 0, 0], "key1": None}},
            "trace_sha256": campaign.digest(directory / "trace.json")}
        campaign.atomic_json(directory / "report.json", {"seed": row["seed"], "outcome": row["outcome"],
            "detail": "cleared one stage", "hardware_mode": row["hardware_mode"], "build_identity": row["build_identity"],
            "anomalies": [], "events": [{"frame": 110 if baseline else 111, "kind": "enter_map", "map": "TRUCK"}],
            "startup": {**row["comparison_boundary"], "events": [{"kind": kind} for kind in row["startup_path"]]}})
        row["report_sha256"] = campaign.digest(directory / "report.json")
        records.append(row)
    summary = {"schema_version": 2, "comparison_mode": fuzz.MATCHED_MODE, "seeds": [1], "fills": ["ff"],
               "expected_fills": tasks, "expected_comparisons": pairs, "records": records, "divergences": []}
    return summary


def rewrite_trace(row, frame):
    directory = Path(row["directory"])
    campaign.atomic_json(directory / "trace.json", [[frame, "enter_map", json.dumps({"map": "TRUCK"}, sort_keys=True)],
                                                  ["end", "completed", "cleared one stage"]])
    row["trace_sha256"] = campaign.digest(directory / "trace.json")
    report = json.loads((directory / "report.json").read_text())
    report["events"][0]["frame"] = row["comparison_boundary"]["comparison_frame"] + frame
    campaign.atomic_json(directory / "report.json", report)
    row["report_sha256"] = campaign.digest(directory / "report.json")


class MatchedSRAMTest(unittest.TestCase):
    def test_plan_has_bounded_unique_repeats_and_controls(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(fuzz, "header_range", return_value=HEADER), \
                patch.object(fuzz, "fill_bytes", side_effect=lambda name, seed: bytes([0 if name == "zero" else 0x47]) * fuzz.SRAM_SIZE):
            tasks, pairs = fuzz.matched_tasks(Path(tmp), [1, 7], ["ff", "random1"], "pokeblue_debug")
            self.assertEqual(len(tasks), 20)
            self.assertEqual(len(pairs), 4)
            self.assertEqual(len({row["directory"] for row in tasks}), 20)
            self.assertEqual(sum(row["role"] == "candidate" for row in tasks), 8)
            self.assertEqual(sum(row["role"] == "matched_control" for row in tasks), 8)

    def test_rehashed_but_malformed_report_still_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            summary = fixture(Path(tmp))
            row = next(row for row in summary["records"] if row["role"] == "candidate")
            path = Path(row["directory"]) / "report.json"
            campaign.atomic_json(path, {})
            row["report_sha256"] = campaign.digest(path)
            self.assertEqual(fuzz.evaluate_matched_pair(summary["expected_comparisons"][0],
                summary["records"])["status"], "invalid_evidence")

    def test_control_copies_only_header_without_changing_candidate(self):
        candidate = bytes([0x47]) * fuzz.SRAM_SIZE
        control = fuzz.matched_header_image(candidate, HEADER)
        self.assertEqual(candidate, bytes([0x47]) * fuzz.SRAM_SIZE)
        self.assertEqual(control[:0x2040], bytes(0x2040))
        self.assertEqual(control[0x2040:0x2048], b"G" * 8)
        self.assertEqual(control[0x2048:], bytes(fuzz.SRAM_SIZE - 0x2048))

    def test_pair_success_retains_startup_difference_and_counts_one_fill(self):
        with tempfile.TemporaryDirectory() as tmp:
            summary = fixture(Path(tmp))
            self.assertEqual(fuzz.finish_matched(summary, Path(tmp) / "summary.json"), 0)
            self.assertEqual(summary["startup_comparisons"][0]["comparison_kind"], "different_startup_paths")
            self.assertFalse(summary["startup_comparisons"][0]["initialization_evidence"])
            self.assertEqual(summary["initialization_comparisons"][0]["status"], "equivalent")
            normalized = campaign.normalize_summary(CASE, summary)
            self.assertEqual(campaign.achieved_exposure(normalized)["sram_fills"], 1)
            self.assertEqual(campaign.classify(0, normalized, "completed"), "no_issue_detected")

    def test_stable_deliberate_candidate_fault_is_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            summary = fixture(Path(tmp))
            for row in summary["records"]:
                if row["role"] == "candidate":
                    rewrite_trace(row, 99)  # controlled detector input, not game RAM
            self.assertEqual(fuzz.finish_matched(summary, Path(tmp) / "summary.json", bisect=True), 1)
            self.assertEqual(summary["initialization_comparisons"][0]["status"], "divergent")
            self.assertIn("bisect_skipped", summary["initialization_comparisons"][0])
            normalized = campaign.normalize_summary(CASE, summary)
            self.assertEqual(campaign.achieved_exposure(normalized)["sram_fills"], 0)
            self.assertEqual(campaign.classify(1, normalized, "completed"), "suspected_issue")

    def test_phase_seed_build_and_context_mismatch_never_pass(self):
        for field in ("cycle", "rng", "joy", "build", "missing_state"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as tmp:
                summary = fixture(Path(tmp))
                row = next(row for row in summary["records"] if row["role"] == "candidate")
                if field == "cycle":
                    row["comparison_boundary"]["comparison_cycle"] += 4
                elif field in ("rng", "joy"):
                    row["comparison_boundary"]["comparison_state"][field][0] ^= 1
                elif field == "build":
                    row["build_identity"]["gbc"] = "c" * 64
                else:
                    del row["comparison_boundary"]["comparison_state"]
                result = fuzz.evaluate_matched_pair(summary["expected_comparisons"][0], summary["records"])
                self.assertIn(result["status"], ("confounded", "invalid_evidence"))

    def test_missing_and_changed_files_are_invalid_evidence(self):
        for name in ("input.sram", "report.json", "trace.json"):
            for change in ("delete", "tamper"):
                with self.subTest(name=name, change=change), tempfile.TemporaryDirectory() as tmp:
                    summary = fixture(Path(tmp))
                    row = next(row for row in summary["records"] if row["role"] == "candidate")
                    path = Path(row["directory"]) / name
                    path.unlink() if change == "delete" else path.write_bytes(b"tampered")
                    self.assertEqual(fuzz.evaluate_matched_pair(summary["expected_comparisons"][0],
                        summary["records"])["status"], "invalid_evidence")

    def test_repeat_instability_and_failed_sibling_are_incomplete(self):
        with tempfile.TemporaryDirectory() as tmp:
            summary = fixture(Path(tmp))
            row = next(row for row in summary["records"] if row["role"] == "candidate")
            rewrite_trace(row, 99)
            self.assertEqual(fuzz.finish_matched(summary, Path(tmp) / "summary.json"), 2)
            self.assertEqual(summary["initialization_comparisons"][0]["status"], "unstable")
            self.assertEqual(campaign.classify(2, campaign.normalize_summary(CASE, summary), "completed"), "incomplete")
        with tempfile.TemporaryDirectory() as tmp:
            summary = fixture(Path(tmp))
            summary["records"][2]["execution"] = "error"
            self.assertEqual(fuzz.finish_matched(summary, Path(tmp) / "summary.json"), 2)
            self.assertNotEqual(campaign.classify(2, campaign.normalize_summary(CASE, summary), "completed"), "no_issue_detected")

    def test_wrong_control_bytes_rejected_even_with_refreshed_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            summary = fixture(Path(tmp))
            for row in summary["records"]:
                if row["role"] == "matched_control":
                    path = Path(row["directory"]) / "input.sram"
                    image = bytearray(path.read_bytes())
                    image[5] = 1
                    path.write_bytes(image)
                    row["input_sha256"] = campaign.digest(path)
            self.assertEqual(fuzz.evaluate_matched_pair(summary["expected_comparisons"][0],
                summary["records"])["status"], "invalid_evidence")

    def test_controller_recomputes_claimed_equivalence_and_requires_full_configuration(self):
        with tempfile.TemporaryDirectory() as tmp:
            summary = fixture(Path(tmp))
            fuzz.finish_matched(summary, Path(tmp) / "summary.json")
            row = next(row for row in summary["records"] if row["role"] == "candidate")
            rewrite_trace(row, 99)
            with self.assertRaisesRegex(ValueError, "retained evidence"):
                campaign.normalize_summary(CASE, summary)
        with tempfile.TemporaryDirectory() as tmp:
            summary = fixture(Path(tmp))
            fuzz.finish_matched(summary, Path(tmp) / "summary.json")
            with self.assertRaises(ValueError):
                campaign.normalize_summary({"scenario": "sram", "args": ["--seeds", "1", "--fills", "1", "--matched-controls"]}, summary)
            summary["initialization_comparisons"] = []
            self.assertEqual(campaign.classify(0, campaign.normalize_summary(CASE, summary), "completed"), "incomplete")
