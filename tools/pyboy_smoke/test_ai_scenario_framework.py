from __future__ import annotations

import unittest

from ai_scenarios import (
    AIScenario,
    build_coverage_report,
    validate_scenario_coverage,
    validate_scenario_metadata,
)
from run_ai_scenarios import assert_expectations


def scenario(
    name: str,
    case: str,
    *,
    required_cases: tuple[str, ...] = ("positive", "negative", "boundary"),
) -> AIScenario:
    return AIScenario(
        name=name,
        player=(),
        enemy=(),
        trainer_class=1,
        ai_tier=0,
        expect={},
        phase="2a",
        heuristic="example",
        case=case,
        tags=("redundant",),
        required_cases=required_cases,
    )


class ExpectationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.telemetry = {
            "moves": [10, 20, 0, 0],
            "scores": [5, 12, 10, 10],
            "eligible_slots": [0],
            "tier": 2,
            "switched": False,
        }

    def test_combined_expectations_pass(self) -> None:
        assert_expectations(
            {
                "enemy_move_slots": [0, 1],
                "tier": 2,
                "pick_slot": 0,
                "never_pick": [1],
                "score_lt": [[0, 1]],
                "score_lte": [[0, 0]],
                "no_switch": True,
            },
            self.telemetry,
        )

    def test_unknown_expectation_fails(self) -> None:
        with self.assertRaisesRegex(AssertionError, "unsupported expectation"):
            assert_expectations({"mystery": True}, self.telemetry)

    def test_wrong_score_relationship_fails(self) -> None:
        with self.assertRaisesRegex(AssertionError, "is not less"):
            assert_expectations({"score_lt": [[1, 0]]}, self.telemetry)

    def test_forbidden_eligible_slot_fails(self) -> None:
        with self.assertRaisesRegex(AssertionError, "forbidden slots"):
            assert_expectations({"never_pick": [0]}, self.telemetry)

    def test_switch_mismatch_fails(self) -> None:
        with self.assertRaisesRegex(AssertionError, "switch=False"):
            assert_expectations({"switch": True}, self.telemetry)


class ScenarioMetadataTests(unittest.TestCase):
    def test_valid_metadata(self) -> None:
        validate_scenario_metadata(
            {
                "name": "valid",
                "phase": "2a",
                "heuristic": "redundant",
                "case": "boundary",
                "tags": ["status"],
                "required_cases": ["positive", "negative", "boundary"],
            }
        )

    def test_unknown_case_fails(self) -> None:
        with self.assertRaisesRegex(ValueError, "not one of"):
            validate_scenario_metadata(
                {
                    "name": "bad",
                    "phase": "2a",
                    "heuristic": "redundant",
                    "case": "sometimes",
                }
            )

    def test_missing_required_case_fails(self) -> None:
        with self.assertRaisesRegex(ValueError, "incomplete"):
            validate_scenario_coverage(
                [scenario("positive_only", "positive")]
            )

    def test_complete_case_matrix_passes_and_reports(self) -> None:
        scenarios = [
            scenario("positive", "positive"),
            scenario("negative", "negative"),
            scenario("boundary", "boundary"),
        ]
        report = validate_scenario_coverage(scenarios)
        group = report["heuristics"]["2a:example"]
        self.assertEqual(group["missing_cases"], [])
        self.assertEqual(group["cases"], ["boundary", "negative", "positive"])
        self.assertEqual(build_coverage_report(scenarios), report)


if __name__ == "__main__":
    unittest.main(verbosity=2)
