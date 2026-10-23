from __future__ import annotations

from pathlib import Path
import unittest

from ai_telemetry import STATUS_SPAM_STREAK, battle_record, summarize
from run_ai_benchmark import FRAME_CYCLES, parse_move_powers
from source_constants import parse_rgbds_constants


REPO_ROOT = Path(__file__).resolve().parents[2]
STRUGGLE = 165
TACKLE, GROWL = 33, 45  # only their power matters below: given by POWERS
POWERS = {TACKLE: 35, GROWL: 0, STRUGGLE: 50}


def selection(move, pos=0, *, reserves=1, pp_out=0, personality=None, forced=False):
    return {"move": move, "enemy_pos": pos, "reserves_alive": reserves, "pp_out": pp_out,
            "personality": personality, "slot": 0, "struggle": move == STRUGGLE, "frame": 0,
            "forced": forced}


def decision(number, scores, *, selected, damage_delta=None, redundant_delta=None, cycles=1000, tier=3):
    trace = []
    if damage_delta is not None:
        trace.append({"layer": "DAMAGE", "enabled": True, "before": [50] * 4, "after": scores,
                      "delta": damage_delta})
    if redundant_delta is not None:
        trace.append({"layer": "REDUNDANT", "enabled": True, "before": [50] * 4, "after": scores,
                      "delta": redundant_delta})
    return {"decision": number, "scores": scores, "moves": [1, 2, 0, 0], "tier": tier,
            "decision_cycles": cycles, "layer_trace": trace, "selected_slot": selected}


def record(selections, **overrides):
    arguments = dict(
        opponent="BUG_CATCHER", trainer_class=2, trainer_no=1, result=0, decisions=[],
        personality_records=[], trainer_ai_calls=[], selections=selections, enemy_switches=0,
        turns=len(selections), move_powers=POWERS, struggle=STRUGGLE)
    arguments.update(overrides)
    return battle_record(**arguments)


class BattleRecordTest(unittest.TestCase):
    def test_struggle_constant_parses(self) -> None:
        constants = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        self.assertEqual(constants["STRUGGLE"], STRUGGLE)

    def test_real_move_table_has_power_zero_status_moves(self) -> None:
        powers = parse_move_powers(REPO_ROOT / "data/moves/moves.asm")
        self.assertEqual(powers[GROWL], 0)
        self.assertGreater(powers[TACKLE], 0)

    def test_status_streak_of_four_flags_and_three_does_not(self) -> None:
        self.assertIn("status_spam", record([selection(GROWL)] * STATUS_SPAM_STREAK)["flags"])
        self.assertNotIn("status_spam", record([selection(GROWL)] * (STATUS_SPAM_STREAK - 1))["flags"])

    def test_damaging_streak_is_context_only(self) -> None:
        result = record([selection(TACKLE)] * 6)
        self.assertEqual(result["max_streak"], {"move": TACKLE, "length": 6})
        self.assertEqual(result["max_status_streak"]["length"], 0)
        self.assertEqual(result["flags"], [])

    def test_streak_resets_when_the_enemy_mon_changes(self) -> None:
        picks = [selection(GROWL, 0), selection(GROWL, 0), selection(GROWL, 1), selection(GROWL, 1)]
        result = record(picks)
        self.assertEqual(result["max_status_streak"]["length"], 2)
        self.assertNotIn("status_spam", result["flags"])

    def test_streak_resets_when_the_move_changes(self) -> None:
        picks = [selection(GROWL)] * 3 + [selection(TACKLE)] + [selection(GROWL)] * 3
        self.assertEqual(record(picks)["max_status_streak"]["length"], 3)

    def test_forced_picks_break_the_status_streak(self) -> None:
        # Seed 117: two free Withdraws, then the player Disabled the other move.
        picks = [selection(GROWL)] * 2 + [selection(GROWL, forced=True)] * 8
        result = record(picks)
        self.assertEqual(result["max_status_streak"]["length"], 2)
        self.assertNotIn("status_spam", result["flags"])
        self.assertEqual(result["forced_picks"], 8)
        self.assertEqual(result["max_streak"]["length"], 10)  # context still sees the run

    def test_free_picks_after_a_forced_one_start_a_new_run(self) -> None:
        picks = [selection(GROWL, forced=True)] + [selection(GROWL)] * STATUS_SPAM_STREAK
        self.assertIn("status_spam", record(picks)["flags"])

    def test_struggle_flags_only_with_a_reserve(self) -> None:
        self.assertEqual(record([selection(STRUGGLE, reserves=0)])["struggle_with_reserve"], 0)
        self.assertNotIn("struggle_with_reserve", record([selection(STRUGGLE, reserves=0)])["flags"])
        result = record([selection(STRUGGLE, reserves=2)])
        self.assertEqual(result["struggle_turns"], 1)
        self.assertEqual(result["struggle_with_reserve"], 1)
        self.assertIn("struggle_with_reserve", result["flags"])

    def test_no_selection_marker_is_ignored(self) -> None:
        result = record([selection(0xFF), selection(TACKLE)])
        self.assertEqual(result["moves"], [TACKLE])

    def test_pp_out_and_personality(self) -> None:
        result = record([selection(TACKLE, pp_out=1, personality=2), selection(TACKLE, pp_out=3),
                         selection(TACKLE, pp_out=2, personality=None)])
        self.assertEqual(result["max_pp_out"], 3)
        self.assertEqual(result["personality"], 2)

    def test_personality_flips_count_only_min_set_changes(self) -> None:
        same = {"scores_before": [50, 50, 80, 80], "scores_after": [50, 50, 80, 80]}
        same_set = {"scores_before": [50, 50, 80, 80], "scores_after": [49, 49, 80, 80]}  # both still min
        flipped = {"scores_before": [50, 50, 80, 80], "scores_after": [50, 51, 80, 80]}
        result = record([selection(TACKLE)], personality_records=[same, same_set, flipped])
        self.assertEqual(result["personality_flips"], 1)

    def test_missed_ko_comes_from_classify_decisions(self) -> None:
        kill = [-5, 0, 0, 0]
        missed = decision(1, [45, 50, 80, 80], selected=1, damage_delta=kill)
        hit = decision(2, [45, 50, 80, 80], selected=0, damage_delta=kill)
        result = record([selection(TACKLE)], decisions=[missed, hit])
        self.assertEqual(result["ko_candidates"], 2)
        self.assertEqual(result["missed_ko"], 1)
        self.assertIn("missed_ko", result["flags"])

    def test_redundant_pick_and_decision_cycles(self) -> None:
        picked = decision(1, [55, 50, 80, 80], selected=0, redundant_delta=[5, 0, 0, 0], cycles=300_000)
        grown = dict(picked, decision_cycles=310_000)  # the same decision captured again
        ok = decision(2, [50, 55, 80, 80], selected=0, redundant_delta=[0, 5, 0, 0], cycles=50_000)
        result = record([selection(TACKLE)], decisions=[picked, grown, ok])
        self.assertEqual(result["redundant_picks"], 1)
        self.assertIn("redundant_pick", result["flags"])
        self.assertEqual(result["decisions"], 2)
        self.assertEqual(sorted(result["decision_cycles"]["all"]), [50_000, 310_000])
        self.assertEqual(result["decision_cycles"]["over_frame"], 1)
        self.assertEqual(result["tier"], 3)

    def test_a_forced_redundant_pick_is_not_counted(self) -> None:
        # Seed 117's scores: Withdraw 78, Disabled Tackle 80, two empty slots at 20.
        forced = decision(1, [78, 80, 20, 20], selected=0, redundant_delta=[58, 0, 0, 0])
        result = record([selection(GROWL, forced=True)], decisions=[forced])
        self.assertEqual(result["redundant_picks"], 0)
        self.assertNotIn("redundant_pick", result["flags"])

    def test_over_frame_trainer_ai_uses_the_move_path_only(self) -> None:
        animation = {"caller_path": "planned", "outcome": "item_or_switch", "cycles": 11_000_000}
        quick = {"caller_path": "planned", "outcome": "move", "cycles": 30_000}
        self.assertEqual(record([selection(TACKLE)], trainer_ai_calls=[animation, quick])["flags"], [])
        slow = dict(quick, cycles=FRAME_CYCLES + 1)
        result = record([selection(TACKLE)], trainer_ai_calls=[animation, slow])
        self.assertIn("over_frame_trainer_ai", result["flags"])
        self.assertEqual(result["trainer_ai"]["item_or_switch_calls"], 1)

    def test_over_frame_trainer_ai_ignores_unplanned_decisions(self) -> None:
        # a forced turn or FINAL_AI decides at commit: decision_cycles times that
        decided = {"caller_path": "unplanned", "outcome": "move", "cycles": 300_000}
        result = record([selection(TACKLE)], trainer_ai_calls=[decided])
        self.assertNotIn("over_frame_trainer_ai", result["flags"])
        self.assertEqual(result["move_path_cycles"], [])

    def test_player_switches_count_only_planned_committed_turns(self) -> None:
        turns = [
            {"mon": 0, "planned": True, "switched": True},
            {"mon": 1, "planned": True, "switched": False},
            {"mon": 1, "planned": False, "switched": True},  # a forced turn: no menu
            {"mon": 1},  # the battle ended before the commit
        ]
        result = record([selection(TACKLE)], plan_turns=turns)
        self.assertEqual((result["planned_turns"], result["player_switches"]), (2, 1))

    def test_pressure_is_the_share_of_party_hp_lost(self) -> None:
        result = record([selection(TACKLE)], player_hp=(300, 150, 400), player_fainted=1)
        self.assertEqual(result["player_hp_lost"], 0.375)
        self.assertEqual(result["player_fainted"], 1)
        self.assertEqual(record([selection(TACKLE)], player_hp=(100, 180, 400))["player_hp_lost"], 0)
        self.assertIsNone(record([selection(TACKLE)])["player_hp_lost"])

    def test_empty_battle(self) -> None:
        result = record([])
        self.assertIsNone(result["tier"])
        self.assertEqual(result["moves"], [])
        self.assertEqual(result["flags"], [])


class SummarizeTest(unittest.TestCase):
    def tagged(self, picks, seed, **overrides):
        battle = record(picks, **overrides)
        battle.update(seed=seed, run_index=0, battle_index=0)
        return battle

    def test_rates_are_null_with_zero_denominators(self) -> None:
        summary = summarize([self.tagged([selection(TACKLE)], 1)])
        group = summary["by_tier"]["None"]
        self.assertIsNone(group["missed_ko_rate"])
        self.assertIsNone(group["redundant_pick_rate"])
        self.assertIsNone(group["enemy_switch_rate"])
        self.assertIsNone(group["personality_flip_rate"])
        self.assertEqual(summarize([])["battles"], 0)
        self.assertIsNone(summarize([])["timing"]["decision_mean_cycles"])

    def test_win_rate_counts_result_zero(self) -> None:
        battles = [self.tagged([selection(TACKLE)], seed, result=result)
                   for seed, result in enumerate((0, 1, 0, 2))]
        self.assertEqual(summarize(battles)["by_class"]["BUG_CATCHER"]["player_win_rate"], 0.5)

    def test_flagged_is_sorted_by_flag_count_and_capped(self) -> None:
        one_flag = [self.tagged([selection(GROWL)] * 4, seed) for seed in range(60)]
        two_flags = self.tagged([selection(GROWL)] * 4 + [selection(STRUGGLE)], 99)
        summary = summarize(one_flag + [two_flags])
        self.assertEqual(len(summary["flagged"]), 50)
        self.assertEqual(summary["flagged"][0]["seed"], 99)
        self.assertEqual(summary["flag_counts"]["status_spam"], 61)
        self.assertEqual(summary["flagged"][1]["flags"], ["status_spam"])

    def test_by_personality_keys(self) -> None:
        battles = [self.tagged([selection(TACKLE, personality=2)], 1),
                   self.tagged([selection(TACKLE, personality=0)], 2),
                   self.tagged([selection(TACKLE)], 3)]
        self.assertEqual(sorted(summarize(battles)["by_personality"]), ["0", "2", "unrolled"])


if __name__ == "__main__":
    unittest.main()
