from __future__ import annotations

from pathlib import Path
import unittest

from run_ai_benchmark import (
    classify_decisions,
    nullable_rate,
    parse_move_powers,
)


REPO_ROOT = Path(__file__).resolve().parents[2]


class BenchmarkMetricTest(unittest.TestCase):
    def test_zero_denominator_is_null(self) -> None:
        self.assertIsNone(nullable_rate(0, 0))
        self.assertEqual(nullable_rate(1, 4), 0.25)

    def test_classification_uses_first_record_per_decision(self) -> None:
        first = {
            "decision": 1,
            "selected_slot": 0,
            "layer_trace": [
                {"layer": "DAMAGE", "enabled": True, "delta": [-5, 0, 0, 0]},
                {"layer": "REDUNDANT", "enabled": True, "delta": [0, 0, 0, 0]},
            ],
        }
        min_find_artifact = {
            "decision": 1,
            "selected_slot": 1,
            "layer_trace": [
                {"layer": "DAMAGE", "enabled": True, "delta": [-5, 0, 0, 0]},
                {"layer": "REDUNDANT", "enabled": True, "delta": [0, 1, 0, 0]},
            ],
        }

        self.assertEqual(
            classify_decisions([first, min_find_artifact]),
            {
                "decisions": 1,
                "damage_layer_ko_candidates": 1,
                "damage_layer_missed_ko_candidates": 0,
                "selected_redundant_penalty_decisions": 0,
                "ko_opportunities": 1,
                "missed_kos": 0,
                "wasted_turns": 0,
            },
        )

    def test_classification_labels_score_diagnostics_and_keeps_aliases(self) -> None:
        record = {
            "decision": 1,
            "selected_slot": 1,
            "layer_trace": [
                {"layer": "DAMAGE", "enabled": True, "delta": [-5, 0, 0, 0]},
                {"layer": "REDUNDANT", "enabled": True, "delta": [0, 1, 0, 0]},
            ],
        }
        result = classify_decisions([record])
        self.assertEqual(result["damage_layer_ko_candidates"], 1)
        self.assertEqual(result["damage_layer_missed_ko_candidates"], 1)
        self.assertEqual(result["selected_redundant_penalty_decisions"], 1)
        self.assertEqual(result["ko_opportunities"], result["damage_layer_ko_candidates"])
        self.assertEqual(result["missed_kos"], result["damage_layer_missed_ko_candidates"])
        self.assertEqual(result["wasted_turns"], result["selected_redundant_penalty_decisions"])
    def test_move_power_table_matches_source_order(self) -> None:
        powers = parse_move_powers(REPO_ROOT / "data" / "moves" / "moves.asm")
        self.assertEqual(powers[1], 40)  # POUND
        self.assertEqual(powers[5], 80)  # MEGA_PUNCH


if __name__ == "__main__":
    unittest.main(verbosity=2)
