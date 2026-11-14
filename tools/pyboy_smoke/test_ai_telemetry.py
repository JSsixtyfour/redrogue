from __future__ import annotations

from pathlib import Path
import unittest

from ai_telemetry import BattleAITelemetry, entry_speed, STATUS_SPAM_STREAK, b5_summary, battle_record, classify_b5, classify_setup, parse_setup_moves, summarize
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


SD, AGILITY = 14, 97
SETUP = {SD: "SWORDS_DANCE", AGILITY: "AGILITY"}


def select(move, *, hp=100, faster=False, reserves=1):
    return {"kind": "select", "move": move, "hp_pct": hp, "faster": faster, "reserves": reserves}


def act(move, *, hp=100, faster=False, reserves=1):
    return {"kind": "act", "move": move, "hp_pct": hp, "faster": faster, "reserves": reserves}


FAINT, SWITCH = {"kind": "faint"}, {"kind": "switch"}


class ClassifyB5Test(unittest.TestCase):
    """B5 (AISacrificeBeatsSwitch) verdicts followed through the enemy-side trace."""

    @staticmethod
    def decision(verdict, *, pos=0, reserve=1, reserve_hp=100):
        return {"kind": "b5", "verdict": verdict, "pos": pos, "reserve": reserve, "reserve_hp": reserve_hp,
                "active_hp_pct": 40, "active_faster": False, "reserve_hp_pct": 100,
                "reserve_faster": False, "reserve_half": 1, "reserves": 2}

    def test_switch_counts_hits_until_the_reserve_moves(self):
        events = [self.decision("switch"),
                  {"kind": "switch", "pos": 0, "hp": 30},
                  {"kind": "turn", "pos": 1, "hp": 60},   # the entry hit
                  {"kind": "turn", "pos": 1, "hp": 20},   # slower: hit again
                  {"kind": "act", "pos": 1, "hp": 20},
                  {"kind": "act", "pos": 0, "hp": 30}]    # the saved mon moves later
        (record,) = classify_b5(events)
        self.assertEqual((record["acted"], record["hits_before_act"], record["saved_later_acted"]), (True, 2, True))

    def test_switch_into_a_reserve_that_faints_first(self):
        events = [self.decision("switch"), {"kind": "switch", "pos": 0, "hp": 30},
                  {"kind": "turn", "pos": 1, "hp": 40}, {"kind": "faint", "pos": 1, "hp": 0}]
        (record,) = classify_b5(events)
        self.assertEqual((record["acted"], record["hits_before_act"]), (False, 2))

    def test_sacrifice_follows_the_free_replacement(self):
        events = [self.decision("sacrifice"),
                  {"kind": "act", "pos": 0, "hp": 30},    # faster: its last attack lands
                  {"kind": "faint", "pos": 0, "hp": 0},
                  {"kind": "turn", "pos": 2, "hp": 90},   # enters free
                  {"kind": "act", "pos": 2, "hp": 90}]
        (record,) = classify_b5(events)
        self.assertEqual((record["active_acted_first"], record["active_fainted"],
                          record["replacement_acted"], record["replacement_hits_before_act"]), (True, True, True, 0))

    def test_switch_in_stay_records_what_it_did(self):
        events = [self.decision("switch"),
                  {"kind": "switch", "pos": 0, "hp": 30, "php": 200, "pko": 0},
                  {"kind": "turn", "pos": 1, "hp": 60, "php": 200, "pko": 0},   # the entry hit
                  {"kind": "act", "pos": 1, "hp": 60, "php": 150, "pko": 0},
                  {"kind": "turn", "pos": 1, "hp": 35, "php": 150, "pko": 0},
                  {"kind": "act", "pos": 1, "hp": 35, "php": 100, "pko": 1},
                  {"kind": "faint", "pos": 1, "hp": 0, "php": 100, "pko": 1},
                  {"kind": "turn", "pos": 0, "hp": 30, "php": 100, "pko": 1}]
        (record,) = classify_b5(events)
        self.assertEqual(record["switch_in"], {"stay_end": "fainted", "stay_turns": 2, "stay_acts": 2,
                                               "hp_at_first_act": 60, "dealt_hp": 100, "dealt_kos": 1})

    def test_sacrificed_mon_stay_ends_when_it_faints(self):
        events = [self.decision("sacrifice") | {"php": 80, "pko": 0},
                  {"kind": "act", "pos": 0, "hp": 30, "php": 50, "pko": 0},
                  {"kind": "faint", "pos": 0, "hp": 0, "php": 50, "pko": 0},
                  {"kind": "turn", "pos": 2, "hp": 90, "php": 50, "pko": 0}]
        (record,) = classify_b5(events)
        self.assertEqual(record["doomed"], {"stay_end": "fainted", "stay_turns": 0, "stay_acts": 1,
                                            "hp_at_first_act": 30, "dealt_hp": 30, "dealt_kos": 0})

    # --- SF2 (2026-11-13): the terminal "end" event --------------------------
    def test_a_battle_winning_attack_counts_its_damage_and_ko(self):
        # The switch-in's attack KOs the player's last mon: the act event was logged
        # before the hit landed, so only the end event carries its damage and KO.
        events = [self.decision("switch"),
                  {"kind": "switch", "pos": 0, "hp": 30, "php": 120, "pko": 2},
                  {"kind": "turn", "pos": 1, "hp": 60, "php": 120, "pko": 2},
                  {"kind": "act", "pos": 1, "hp": 60, "php": 120, "pko": 2},
                  {"kind": "end", "pos": 1, "hp": 60, "php": 0, "pko": 3}]
        (record,) = classify_b5(events)
        self.assertEqual(record["switch_in"], {"stay_end": "player_blacked_out", "stay_turns": 1, "stay_acts": 1,
                                               "hp_at_first_act": 60, "dealt_hp": 120, "dealt_kos": 1})
        self.assertEqual((record["acted"], record["hits_before_act"]), (True, 1))

    def test_without_the_end_event_the_final_hit_is_lost(self):
        # The v1 shape (what old runs hold): same battle, no end event.
        events = [self.decision("switch"),
                  {"kind": "switch", "pos": 0, "hp": 30, "php": 120, "pko": 2},
                  {"kind": "turn", "pos": 1, "hp": 60, "php": 120, "pko": 2},
                  {"kind": "act", "pos": 1, "hp": 60, "php": 120, "pko": 2}]
        (record,) = classify_b5(events)
        self.assertEqual((record["switch_in"]["stay_end"], record["switch_in"]["dealt_hp"],
                          record["switch_in"]["dealt_kos"]), ("battle_end", 0, 0))

    def test_ordinary_attack_then_another_turn_is_unchanged(self):
        events = [self.decision("sacrifice") | {"php": 200, "pko": 0},
                  {"kind": "act", "pos": 0, "hp": 30, "php": 200, "pko": 0},
                  {"kind": "turn", "pos": 0, "hp": 10, "php": 150, "pko": 0},
                  {"kind": "faint", "pos": 0, "hp": 0, "php": 150, "pko": 0}]
        (record,) = classify_b5(events)
        self.assertEqual(record["doomed"], {"stay_end": "fainted", "stay_turns": 1, "stay_acts": 1,
                                            "hp_at_first_act": 30, "dealt_hp": 50, "dealt_kos": 0})

    def test_the_end_event_is_not_credited_to_a_replacement(self):
        # The doomed mon faints, the replacement comes in, acts, and the player blacks out:
        # the doomed stay ends at its faint, the replacement acted, and the end event is
        # not mistaken for another mon entering.
        events = [self.decision("sacrifice") | {"php": 100, "pko": 0},
                  {"kind": "act", "pos": 0, "hp": 30, "php": 100, "pko": 0},
                  {"kind": "faint", "pos": 0, "hp": 0, "php": 60, "pko": 0},
                  {"kind": "turn", "pos": 2, "hp": 90, "php": 60, "pko": 0},
                  {"kind": "act", "pos": 2, "hp": 90, "php": 60, "pko": 0},
                  {"kind": "end", "pos": 2, "hp": 90, "php": 0, "pko": 1}]
        (record,) = classify_b5(events)
        self.assertEqual(record["doomed"]["stay_end"], "fainted")
        self.assertEqual((record["doomed"]["dealt_hp"], record["doomed"]["dealt_kos"]), (40, 0))
        self.assertEqual((record["replacement_acted"], record["replacement_hits_before_act"]), (True, 0))

    def test_an_end_event_for_another_mon_does_not_extend_a_stay(self):
        # A sacrificed mon that left before the end: its stay ended at "left".
        events = [self.decision("sacrifice") | {"php": 100, "pko": 0},
                  {"kind": "switch", "pos": 0, "hp": 30, "php": 100, "pko": 0},
                  {"kind": "turn", "pos": 3, "hp": 80, "php": 100, "pko": 0},
                  {"kind": "end", "pos": 3, "hp": 80, "php": 0, "pko": 1}]
        (record,) = classify_b5(events)
        self.assertEqual((record["doomed"]["stay_end"], record["doomed"]["dealt_hp"]), ("left", 0))

    def test_enemy_switch_and_enemy_faint_still_end_a_stay(self):
        switch = [self.decision("sacrifice") | {"php": 100, "pko": 0},
                  {"kind": "turn", "pos": 0, "hp": 30, "php": 90, "pko": 0},
                  {"kind": "turn", "pos": 1, "hp": 70, "php": 90, "pko": 0}]
        (record,) = classify_b5(switch)
        self.assertEqual((record["doomed"]["stay_end"], record["doomed"]["dealt_hp"]), ("left", 10))
        faint = [self.decision("sacrifice") | {"php": 100, "pko": 0},
                 {"kind": "faint", "pos": 0, "hp": 0, "php": 90, "pko": 0}]
        (record,) = classify_b5(faint)
        self.assertEqual((record["doomed"]["stay_end"], record["doomed"]["dealt_hp"]), ("fainted", 10))

    def test_summary_groups_by_verdict_and_reserve_speed(self):
        events = [self.decision("switch"), {"kind": "switch", "pos": 0, "hp": 30},
                  {"kind": "turn", "pos": 1, "hp": 60}, {"kind": "act", "pos": 1, "hp": 60}]
        summary = b5_summary(classify_b5(events))
        self.assertEqual(summary["decisions"], 1)
        self.assertEqual(summary["switch/reserve_slower"]["reserve_acted_rate"], 1.0)


class ClassifySetupTest(unittest.TestCase):
    def outcomes(self, *events):
        return [item["outcome"] for item in classify_setup(list(events), SETUP)]

    def test_table_ids_and_names_come_from_the_move_table(self) -> None:
        moves = parse_setup_moves(REPO_ROOT / "data/moves/moves.asm")
        constants = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        self.assertEqual(moves[constants["SWORDS_DANCE"]], "SWORDS_DANCE")
        self.assertEqual(moves[SD], "SWORDS_DANCE")
        self.assertEqual(moves[AGILITY], "AGILITY")
        for name in ("SUBSTITUTE", "REFLECT", "LIGHT_SCREEN", "FOCUS_ENERGY", "AMNESIA", "DOUBLE_TEAM"):
            self.assertIn(constants[name], moves)
        self.assertNotIn(constants["GROWL"], moves)  # lowers THEIR stat: not an investment
        self.assertNotIn(constants["RECOVER"], moves)
        self.assertEqual(len(moves), 17)

    def test_boost_then_an_attack_is_used(self) -> None:
        self.assertEqual(self.outcomes(select(SD), act(SD), select(TACKLE), act(TACKLE), FAINT), ["used"])

    def test_boost_then_faint_is_wasted(self) -> None:
        self.assertEqual(self.outcomes(select(SD), act(SD), select(TACKLE), FAINT), ["wasted"])

    def test_a_later_boost_is_not_acting_again(self) -> None:
        self.assertEqual(self.outcomes(act(SD), act(SD), FAINT), ["wasted", "wasted"])
        self.assertEqual(self.outcomes(act(SD), act(AGILITY), act(TACKLE)), ["used", "used"])

    def test_selected_but_died_first_is_preempted_and_never_ran(self) -> None:
        self.assertEqual(self.outcomes(select(SD), FAINT), ["preempted"])

    def test_preempted_and_wasted_can_share_a_faint(self) -> None:
        self.assertEqual(self.outcomes(select(SD), act(SD), select(SD), FAINT), ["wasted", "preempted"])

    def test_a_selected_boost_replaced_by_a_switch_is_not_counted(self) -> None:
        self.assertEqual(self.outcomes(select(SD), SWITCH), [])

    def test_switching_out_holding_a_boost_is_left(self) -> None:
        self.assertEqual(self.outcomes(act(SD), SWITCH, act(TACKLE)), ["left"])

    def test_a_stint_does_not_leak_into_the_next_mon(self) -> None:
        self.assertEqual(self.outcomes(act(SD), FAINT, select(TACKLE), act(TACKLE), FAINT), ["wasted"])
        self.assertEqual(self.outcomes(select(SD), FAINT, select(TACKLE), FAINT), ["preempted"])

    def test_battle_ending_with_the_boost_held_is_survived(self) -> None:
        self.assertEqual(self.outcomes(act(SD)), ["survived"])

    def test_non_setup_moves_alone_produce_nothing(self) -> None:
        self.assertEqual(self.outcomes(select(TACKLE), act(TACKLE), FAINT), [])

    def test_entries_carry_the_board_they_boosted_on(self) -> None:
        item = classify_setup([act(SD, hp=40, faster=True, reserves=0), FAINT], SETUP)[0]
        self.assertEqual((item["name"], item["hp_pct"], item["faster"], item["reserves"]),
                         ("SWORDS_DANCE", 40, True, 0))

    def test_decided_hp_is_from_the_selection_not_the_hit_that_followed(self) -> None:
        # Slower mon: chose the boost at 80%, took the player's hit, then it ran at 15%.
        item = classify_setup([select(SD, hp=80), act(SD, hp=15), FAINT], SETUP)[0]
        self.assertEqual((item["decided_hp_pct"], item["hp_pct"], item["outcome"]), (80, 15, "wasted"))

    def test_a_called_boost_with_no_matching_selection_keeps_its_own_hp(self) -> None:
        # Metronome selected, Agility is what ran.
        item = classify_setup([select(TACKLE), act(AGILITY, hp=60), FAINT], SETUP)[0]
        self.assertEqual(item["decided_hp_pct"], 60)

    def test_groups_rate_only_boosts_that_ran(self) -> None:
        events = [act(SD, faster=True), FAINT, act(AGILITY, reserves=0), FAINT, select(SD), FAINT,
                  act(SD), act(TACKLE)]
        rec = record([], setup_events=events, setup_moves=SETUP)
        rec["tier"] = 3
        summary = summarize([rec])
        setup = summary["by_tier"]["3"]["setup"]
        self.assertEqual((setup["ran"], setup["wasted"], setup["preempted"], setup["used"]), (3, 2, 1, 1))
        self.assertEqual(setup["wasted_rate"], round(2 / 3, 4))
        self.assertEqual((setup["wasted_slower"], setup["wasted_last_mon"]), (1, 1))
        self.assertEqual(summary["setup_by_move"]["AGILITY"]["wasted"], 1)
        self.assertEqual(summary["setup_by_move"]["SWORDS_DANCE"]["preempted"], 1)

    def test_no_setup_has_no_rate(self) -> None:
        rec = record([])
        self.assertEqual(rec["setup"], [])
        rec["tier"] = 3
        self.assertIsNone(summarize([rec])["by_tier"]["3"]["setup"]["wasted_rate"])


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


class PlayerHitDamageTest(unittest.TestCase):
    """The believed-vs-real comparison uses the hits that reached the mon, not the HP delta."""

    class _Harness:
        def __init__(self, hp: int) -> None:
            self.hp = hp

        def read8(self, label: str, offset: int = 0) -> int:
            if label == "wEnemyMonHP":
                return (self.hp >> 8, self.hp & 0xFF)[offset]
            return 0

    def finish(self, hits, hp_next):
        telemetry = BattleAITelemetry.__new__(BattleAITelemetry)
        telemetry.h = self._Harness(hp_next)
        telemetry.b5_events = []
        telemetry._why_pending = why = {"hp": 100, "player_hits": hits}
        telemetry._b5_turn(None)
        return why

    def test_hits_absorbed_by_a_substitute_do_not_count(self) -> None:
        # Substitute cost 25 HP; the player's 30 hit the sub; HP fell 25.
        why = self.finish([[TACKLE, 30, 0, True]], 75)
        self.assertEqual(why["hp_next_turn"], 75)
        self.assertEqual(why["player_hit_damage"], 0)

    def test_every_hit_on_the_mon_counts(self) -> None:
        why = self.finish([[TACKLE, 9, 0, False], [TACKLE, 9, 1, False]], 82)
        self.assertEqual(why["player_hit_damage"], 18)

    def test_no_hit_is_zero(self) -> None:
        self.assertEqual(self.finish([], 94)["player_hit_damage"], 0)


class TerminalEventRuntimeTest(unittest.TestCase):
    """SF2 (2026-11-13): event order when the enemy wins, on the real ROM. A level-5
    Magikarp (Splash) against a level-70 Mewtwo: the enemy's first hit ends the battle."""

    def test_a_battle_ending_hit_is_followed_by_the_end_event(self) -> None:
        from harness import RedRogueHarness
        from source_constants import parse_trainer_constants
        species = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
        moves = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
        trainers = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")
        h = RedRogueHarness(REPO_ROOT, Path(__file__).resolve().parent / "artifacts")
        try:
            telemetry = BattleAITelemetry(h, REPO_ROOT)
            h.inject_fight2_spec(
                [{"species": species["MAGIKARP"], "level": 5, "moves": [moves["SPLASH"]]}],
                [{"species": species["MEWTWO"], "level": 70, "moves": [moves["PSYCHIC_M"]]}],
                trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
            h.boot_fight2(seed=1)
            telemetry.begin_battle("test")
            start = len(telemetry.b5_events)
            for _ in range(600):
                if not h.read8("hIsInBattle"):
                    break
                h.tap("a", 1)
                h.tick(8)
            self.assertEqual(h.read8("hIsInBattle"), 0, "the battle never ended")
            self.assertEqual(telemetry.errors, [])
            events = telemetry.b5_events[start:]
            kinds = [e["kind"] for e in events]
            self.assertIn("end", kinds, kinds)
            end = kinds.index("end")
            self.assertEqual(kinds[end + 1:], [], "nothing after the terminal event")
            self.assertEqual(kinds[end - 1], "act", "the battle-ending hit comes right before it")
            self.assertEqual((events[end]["php"], events[end]["pko"]), (0, 1))
            self.assertGreater(events[end - 1]["php"], 0, "the act was logged before its hit landed")
            # Whatever the game does with the party after the battle, the terminal
            # numbers were recorded at the blackout and stay as they were.
            record = telemetry.end_battle(1)
            self.assertEqual(record["b5_telemetry"], 2)
            self.assertEqual((events[end]["php"], events[end]["pko"]), (0, 1))
        finally:
            h.close()

    def test_won_battle_hp_lost_is_read_before_the_leftovers_heal(self) -> None:
        # A level-50 Snorlax takes a Swift from a faster level-20 Electrode and wins, holding
        # Leftovers. EndOfBattle heals the winner before hIsInBattle clears; the pressure
        # numbers must be the party as the fight left it, not after that heal.
        from harness import RedRogueHarness
        from source_constants import parse_trainer_constants
        from test_key_item_effects import all_tiers
        from test_key_item_equipment import bits
        species = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
        moves = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
        trainers = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")
        h = RedRogueHarness(REPO_ROOT, Path(__file__).resolve().parent / "artifacts")
        try:
            telemetry = BattleAITelemetry(h, REPO_ROOT)
            h.inject_fight2_spec(
                [{"species": species["SNORLAX"], "level": 50, "moves": [moves["TACKLE"]]}],
                [{"species": species["ELECTRODE"], "level": 20, "moves": [moves["SWIFT"]]}],
                trainer_class=trainers["COOLTRAINER_M"], ai_tier=0)
            h.boot_fight2(seed=1)
            h.write_sram_bytes("sKeyItemsBitfield", bits(["LEFTOVERS"], ["LEFTOVERS"]))
            h.write_sram_bytes("sKeyItemTiers", all_tiers({"LEFTOVERS": 2}))
            h.call_routine("ApplyKeyItemTierEffects")
            telemetry.begin_battle("test")
            start_hp, _, max_hp = telemetry._start["party"]
            at_entry = {}
            h.register_hook("EndOfBattle", lambda _c: at_entry.setdefault(
                "hp", h.read8("wBattleMonHP") << 8 | h.read8("wBattleMonHP", 1)))
            for _ in range(900):
                if not h.read8("hIsInBattle"):
                    break
                h.tap("a", 1)
                h.tick(8)
            self.assertEqual(h.read8("hIsInBattle"), 0, "the battle never ended")
            self.assertLess(at_entry["hp"], start_hp, "the Swift never landed")
            healed = h.read8("wPartyMon1HP") << 8 | h.read8("wPartyMon1HP", 1)
            self.assertGreater(healed, at_entry["hp"], "Leftovers healed after the fight")
            record = telemetry.end_battle(0)
            self.assertEqual(telemetry.errors, [])
            self.assertEqual(record["player_hp_lost"], round((start_hp - at_entry["hp"]) / max_hp, 4))
            self.assertGreater(record["player_hp_lost"], 0)
        finally:
            h.close()


class EntrySpeedTest(unittest.TestCase):
    """reserve_faster uses the Speed a reserve will have once sent out (AI review CP1)."""

    def test_healthy_is_unchanged(self) -> None:
        self.assertEqual(entry_speed(120, 0), 120)

    def test_paralysis_quarters(self) -> None:
        self.assertEqual(entry_speed(120, 1 << 6), 30)

    def test_minimum_one(self) -> None:
        for speed in (0, 1, 3):
            self.assertEqual(entry_speed(speed, 1 << 6), 1)

    def test_other_status_is_unchanged(self) -> None:
        self.assertEqual(entry_speed(120, 1 << 4), 120)  # burn halves Attack, not Speed
