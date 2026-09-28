from __future__ import annotations

from pathlib import Path
import unittest

from run_ai_benchmark import (
    classify_decisions,
    fixture_seeds,
    matchup_fingerprint,
    nullable_rate,
    parse_move_powers,
    repeated_values,
    trainer_ai_timing_metrics,
)


REPO_ROOT = Path(__file__).resolve().parents[2]


class BenchmarkMetricTest(unittest.TestCase):
    def test_whole_trainer_ai_timing_splits_paths_and_outcomes(self) -> None:
        records = [
            {"caller_path": "enemy_first", "outcome": "move", "cycles": 100},
            {"caller_path": "player_first", "outcome": "move", "cycles": 200},
            {
                "caller_path": "enemy_first",
                "outcome": "item_or_switch",
                "cycles": 80000,
            },
        ]
        metrics = trainer_ai_timing_metrics(records)
        self.assertEqual(metrics["trainer_ai_calls"], 3)
        self.assertEqual(metrics["trainer_ai_p95_cycles"], 80000)
        self.assertEqual(metrics["trainer_ai_over_frame_calls"], 1)
        self.assertEqual(metrics["trainer_ai_enemy_first_move_calls"], 1)
        self.assertEqual(metrics["trainer_ai_player_first_move_calls"], 1)
        self.assertEqual(metrics["trainer_ai_item_or_switch_calls"], 1)


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

    def test_fixture_seed_sequence_wraps_and_reports_repeats(self) -> None:
        self.assertEqual(fixture_seeds(98, 4), [98, 99, 1, 2])
        seeds = fixture_seeds(1, 101)
        self.assertEqual(repeated_values(seeds), {"1": 2, "2": 2})

    def test_matchup_fingerprint_is_canonical_and_matchup_only(self) -> None:
        identity = {
            "opponent": 201,
            "trainer_class": 31,
            "player_active_slot": 0,
            "enemy_active_slot": 0,
            "player_party": [1, 2, 3],
            "enemy_party": [4, 5, 6],
            "key_items": [3, 0, 0, 0],
        }
        reordered = dict(reversed(list(identity.items())))
        self.assertEqual(
            matchup_fingerprint(identity),
            matchup_fingerprint(reordered),
        )
        changed = dict(identity)
        changed["enemy_party"] = [4, 5, 7]
        self.assertNotEqual(
            matchup_fingerprint(identity),
            matchup_fingerprint(changed),
        )

    def test_move_power_table_matches_source_order(self) -> None:
        powers = parse_move_powers(REPO_ROOT / "data" / "moves" / "moves.asm")
        self.assertEqual(powers[1], 40)  # POUND
        self.assertEqual(powers[5], 80)  # MEGA_PUNCH


if __name__ == "__main__":
    unittest.main(verbosity=2)
