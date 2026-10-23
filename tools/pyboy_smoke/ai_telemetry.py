"""Per-battle AI telemetry for the autoplay swarm (autoplay.py --ai-telemetry).

One record per TRAINER battle: which moves the enemy chose, how often it
repeated a status move, switched, hit Struggle with a reserve in hand, missed a
reliable KO, picked a move the Redundant layer penalised, and what its
decisions cost in cycles. Read-only: it only reads memory in hook callbacks,
and every callback catches its own exceptions (a raising callback ends an
autoplay run as "error", see autoplay.py), so a run plays identically with or
without it.

The hooks are the harness's own (hook_ai_scores, hook_ai_personality_timing,
hook_trainer_ai_calls, hook_flag) plus two of this module's: SelectEnemyMove.done
(what was chosen, PP and reserves at that moment) and MainInBattleLoop (a turn
counter). The harness lists grow for the whole run and are never cleared
(hook_ai_scores keeps indices into its list mid-decision): each battle reads
the slice from the length it had when the battle began.

battle_record() and summarize() are pure, so test_ai_telemetry.py needs no ROM.
"""
from __future__ import annotations

from collections import Counter
from math import ceil
from pathlib import Path

from run_ai_benchmark import (
    FRAME_CYCLES,
    classify_decisions,
    first_decision_records,
    parse_move_powers,
    trainer_ai_timing_metrics,
)
from source_constants import parse_rgbds_constants

PARTYMON_STRUCT_LENGTH = 44
MON_HP, MON_MAXHP = 0x01, 0x22  # constants/pokemon_data_constants.asm, big-endian words
AI_SCORE_DISABLED = 80  # trainer_ai.asm: a slot with no move or no PP is pre-marked with this
NO_SELECTION = 0xFF  # SelectEnemyMove's "unable to select a move" value

# The flags (battle_record's "flags"). Flags are findings to read, not failures.
STATUS_SPAM_STREAK = 4  # the same power-0 move, by the same enemy mon, this many times in a row
FLAG_RULES = {
    "missed_ko": "missed_ko > 0 (a DAMAGE-layer reliable KO exists and another slot was selected)",
    "status_spam": f"the same power-0 move by the same enemy mon {STATUS_SPAM_STREAK}+ times in a row"
                   " (forced picks, the only usable move, break the run)",
    "struggle_with_reserve": "Struggle selected while a reserve was alive",
    "over_frame_trainer_ai": f"a planned commit (AICommitEnemyTurn, move path) over {FRAME_CYCLES} cycles",
    "redundant_pick": "the selected slot carried a positive Redundant-layer penalty (not when forced)",
    "telemetry_error": "a telemetry hook raised during the battle",
}

# result: 0 the player won, 1 lost. wBattleResult says 0 win/1 lose/2 draw, but a blackout never writes it,
# so autoplay.py passes 1 when a blackout happened during the battle.
RESULT_PLAYER_WON = 0


def _p95(values: list[int]) -> int | None:
    ordered = sorted(values)
    return ordered[max(0, ceil(0.95 * len(ordered)) - 1)] if ordered else None


def _rate(numerator: int, denominator: int) -> float | None:
    return round(numerator / denominator, 4) if denominator else None


def _min_slots(scores: list[int]) -> frozenset[int]:
    """Slots holding the minimum score among usable slots (below AI_SCORE_DISABLED).
    A slot with no move or no PP is pre-marked disabled, so this is the set the
    final pick is drawn from. All disabled: fall back to every slot."""
    live = [slot for slot, score in enumerate(scores) if score < AI_SCORE_DISABLED]
    pool = live or list(range(len(scores)))
    best = min(scores[slot] for slot in pool)
    return frozenset(slot for slot in pool if scores[slot] == best)


def _forced_decision(record: dict[str, object]) -> bool:
    """One usable slot: the rest are empty, or have no PP or are disabled (pre-marked
    AI_SCORE_DISABLED). Empty slots keep an ordinary score (measured: [78, 80, 20, 20]
    for Withdraw, Disabled Tackle, two empty slots), so the moves decide which count."""
    return sum(bool(move) and score < AI_SCORE_DISABLED
               for score, move in zip(record["scores"], record["moves"])) == 1


def _streaks(selections: list[dict[str, object]], move_powers: dict[int, int]) -> tuple[dict, dict]:
    """Longest run of the same move by the same enemy mon: any move, and power-0 moves only.
    A forced pick (the only usable move, e.g. the other one Disabled) is no choice, so it
    breaks the power-0 run (seed 117: ten Withdraws, six of them under the player's Disable)."""
    best_any = {"move": None, "length": 0}
    best_status = {"move": None, "length": 0}
    run_key: tuple[object, object] | None = None
    length = status_length = 0
    for selection in selections:
        move = selection["move"]
        key = (selection.get("enemy_pos"), move)
        status_length = status_length + 1 if key == run_key else 1
        length = length + 1 if key == run_key else 1
        run_key = key
        if selection.get("forced"):
            status_length = 0
        if length > best_any["length"]:
            best_any = {"move": move, "length": length}
        if move_powers.get(move, 1) == 0 and status_length > best_status["length"]:
            best_status = {"move": move, "length": status_length}
    return best_any, best_status


def battle_record(
    *,
    opponent: str,
    trainer_class: int,
    trainer_no: int,
    result: int | None,
    decisions: list[dict[str, object]],
    personality_records: list[dict[str, object]],
    trainer_ai_calls: list[dict[str, object]],
    selections: list[dict[str, object]],
    enemy_switches: int,
    turns: int,
    move_powers: dict[int, int],
    struggle: int,
    player_hp: tuple[int, int, int] | None = None,
    player_fainted: int | None = None,
    plan_turns: list[dict[str, object]] | None = None,
) -> dict[str, object]:
    """One battle's AI record from that battle's slices of the harness lists."""
    first = first_decision_records(decisions)
    classified = classify_decisions(decisions)
    forced = {int(r["decision"]) for r in first if _forced_decision(r)}
    chosen_freely = classify_decisions([r for r in decisions if int(r["decision"]) not in forced])
    tiers = Counter(int(record["tier"]) for record in first)
    # Only real choices: SelectEnemyMove's $FF is "no selection this turn".
    chosen = [s for s in selections if s["move"] != NO_SELECTION]
    struggles = [s for s in chosen if s["move"] == struggle]
    personalities = [s["personality"] for s in selections if s.get("personality") is not None]
    flips = sum(
        _min_slots(list(p["scores_before"])) != _min_slots(list(p["scores_after"]))
        for p in personality_records
    )
    streak_any, streak_status = _streaks(chosen, move_powers)

    per_decision: dict[int, int] = {}
    for record in decisions:  # a decision's cycles grow with each capture; keep the last
        per_decision[int(record["decision"])] = int(record["decision_cycles"])
    cycles = list(per_decision.values())
    move_calls = [call for call in trainer_ai_calls if call["outcome"] == "move"]
    move_timing = trainer_ai_timing_metrics(move_calls)
    trainer_ai = {
        key: value
        for key, value in move_timing.items()
        if key.startswith("trainer_ai")
        and "item_or_switch" not in key  # empty here: only move-path calls were passed in
        and key.endswith(("_calls", "_p95_cycles", "_max_cycles", "_over_frame_calls"))
    }
    trainer_ai["item_or_switch_calls"] = len(trainer_ai_calls) - len(move_calls)

    record = {
        "opponent": opponent,
        "trainer_class": trainer_class,
        "trainer_no": trainer_no,
        "tier": tiers.most_common(1)[0][0] if tiers else None,
        "personality": personalities[-1] if personalities else None,
        "result": result,
        "turns": turns,
        # Pressure: the share of the player party's total max HP lost over the battle, and mons fainted.
        # player_hp = (HP at start, HP at end, total max HP). Win rate alone is too sparse (~1% losses).
        "player_hp_lost": (
            round(max(0, player_hp[0] - player_hp[1]) / player_hp[2], 4)
            if player_hp and player_hp[2] else None
        ),
        "player_fainted": player_fainted,
        "decisions": classified["decisions"],
        "moves": [int(s["move"]) for s in chosen],
        "struggle_turns": len(struggles),
        "struggle_with_reserve": sum(int(s.get("reserves_alive", 0)) > 0 for s in struggles),
        "max_pp_out": max((int(s.get("pp_out", 0)) for s in chosen), default=0),
        "enemy_switches": enemy_switches,
        "ko_candidates": classified["damage_layer_ko_candidates"],
        "missed_ko": classified["damage_layer_missed_ko_candidates"],
        "explosion_vetoes": classified["explosion_vetoed_ko_candidates"],
        # Per planned turn (a real battle menu), whether the player then switched.
        **player_switch_counts(plan_turns or []),
        "redundant_picks": chosen_freely["selected_redundant_penalty_decisions"],
        "forced_picks": sum(bool(s.get("forced")) for s in chosen),
        "personality_flips": flips,
        "max_status_streak": streak_status,
        "max_streak": streak_any,
        "decision_cycles": {
            "mean": round(sum(cycles) / len(cycles)) if cycles else None,
            "p95": _p95(cycles),
            "max": max(cycles, default=None),
            "over_frame": sum(c > FRAME_CYCLES for c in cycles),
            "all": cycles,
        },
        "trainer_ai": trainer_ai,
        # Planned commits only: an unplanned one (a forced turn, FINAL_AI) runs the whole
        # decision there, which decision_cycles already times (2026-10-22).
        "move_path_cycles": [int(call["cycles"]) for call in move_calls
                             if call.get("caller_path") == "planned"],
    }
    record["flags"] = flag_battle(record)
    return record


def player_switch_counts(plan_turns: list[dict[str, object]]) -> dict[str, int]:
    planned = [t for t in plan_turns if t.get("planned") and "switched" in t]
    return {
        "planned_turns": len(planned),
        "player_switches": sum(bool(t["switched"]) for t in planned),
    }


def flag_battle(record: dict[str, object]) -> list[str]:
    flags = []
    if record["missed_ko"] > 0:
        flags.append("missed_ko")
    if record["max_status_streak"]["length"] >= STATUS_SPAM_STREAK:
        flags.append("status_spam")
    if record["struggle_with_reserve"] > 0:
        flags.append("struggle_with_reserve")
    if record["trainer_ai"].get("trainer_ai_planned_move_over_frame_calls", 0) > 0:
        flags.append("over_frame_trainer_ai")
    if record["redundant_picks"] > 0:
        flags.append("redundant_pick")
    return flags


def _group(records: list[dict[str, object]]) -> dict[str, object]:
    decisions = sum(r["decisions"] for r in records)
    ko_candidates = sum(r["ko_candidates"] for r in records)
    return {
        "battles": len(records),
        "decisions": decisions,
        "player_win_rate": _rate(sum(r["result"] == RESULT_PLAYER_WON for r in records), len(records)),
        "mean_turns": round(sum(r["turns"] for r in records) / len(records), 2) if records else None,
        "missed_ko_rate": _rate(sum(r["missed_ko"] for r in records), ko_candidates),
        "redundant_pick_rate": _rate(sum(r["redundant_picks"] for r in records), decisions),
        "enemy_switch_rate": _rate(sum(r["enemy_switches"] for r in records), decisions),
        "struggle_battles": sum(r["struggle_turns"] > 0 for r in records),
        "status_spam_battles": sum("status_spam" in r["flags"] for r in records),
        "personality_flip_rate": _rate(sum(r["personality_flips"] for r in records), decisions),
        "mean_player_hp_lost": _mean([r.get("player_hp_lost") for r in records]),
        "mean_player_fainted": _mean([r.get("player_fainted") for r in records]),
        "player_switch_rate": _rate(sum(r.get("player_switches", 0) for r in records),
                                    sum(r.get("planned_turns", 0) for r in records)),
    }


def _mean(values: list) -> float | None:
    present = [value for value in values if value is not None]
    return round(sum(present) / len(present), 4) if present else None


def summarize(records: list[dict[str, object]], flagged_cap: int = 50) -> dict[str, object]:
    """The summary's "ai" block from records already tagged with seed, run_index
    and battle_index. by_personality keys: "0".."3" are the rolled profiles
    (NONE, OFFENSE, CONTROL, DEFENSIVE); "unrolled" is a fixed-class AI (no roll)."""
    by_tier: dict[str, list] = {}
    by_class: dict[str, list] = {}
    by_personality: dict[str, list] = {}
    for record in records:
        by_tier.setdefault(str(record["tier"]), []).append(record)
        by_class.setdefault(str(record["opponent"]), []).append(record)
        key = "unrolled" if record["personality"] is None else str(record["personality"])
        by_personality.setdefault(key, []).append(record)

    cycles = [c for r in records for c in r["decision_cycles"]["all"]]
    move_cycles = [c for r in records for c in r["move_path_cycles"]]
    flag_counts = Counter(flag for r in records for flag in r["flags"])
    flagged = sorted(
        (r for r in records if r["flags"]),
        key=lambda r: (-len(r["flags"]), r.get("seed", 0), r.get("battle_index", 0)),
    )[:flagged_cap]
    return {
        "battles": len(records),
        "decisions": sum(r["decisions"] for r in records),
        "turns": sum(r["turns"] for r in records),
        "by_tier": {key: _group(group) for key, group in sorted(by_tier.items())},
        "by_class": {key: _group(group) for key, group in sorted(by_class.items())},
        "by_personality": {
            key: {
                name: value
                for name, value in _group(group).items()
                if name in ("battles", "decisions", "personality_flip_rate", "status_spam_battles",
                            "player_win_rate", "mean_turns", "mean_player_hp_lost", "mean_player_fainted")
            }
            for key, group in sorted(by_personality.items())
        },
        "timing": {
            "decision_mean_cycles": round(sum(cycles) / len(cycles)) if cycles else None,
            "decision_p95_cycles": _p95(cycles),
            "decision_max_cycles": max(cycles, default=None),
            "trainer_ai_move_p95_cycles": _p95(move_cycles),
            "trainer_ai_move_max_cycles": max(move_cycles, default=None),
            "trainer_ai_move_over_frame_calls": sum(c > FRAME_CYCLES for c in move_cycles),
        },
        "flag_counts": dict(flag_counts.most_common()),
        "flagged": [
            {
                "seed": r.get("seed"),
                "run_index": r.get("run_index"),
                "battle_index": r.get("battle_index"),
                "opponent": r["opponent"],
                "flags": r["flags"],
                "moves": r["moves"][:12],
            }
            for r in flagged
        ],
    }


class BattleAITelemetry:
    """Installs the hooks once; begin_battle/end_battle slice them per battle."""

    def __init__(self, harness, root: Path):
        self.h = harness
        self.errors: list[str] = []
        self.move_powers = parse_move_powers(root / "data/moves/moves.asm")
        self.struggle = parse_rgbds_constants(root / "constants/move_constants.asm")["STRUGGLE"]
        self.decisions = harness.hook_ai_scores()
        self.personality = harness.hook_ai_personality_timing()
        self.trainer_ai = harness.hook_trainer_ai_calls()
        self.switches = harness.hook_flag("SwitchEnemyMon")
        self.selections: list[dict[str, object]] = []
        self.turn_count = {"value": 0}
        harness.register_hook("SelectEnemyMove.done", self._guarded(self._selected))
        harness.register_hook("MainInBattleLoop", self._guarded(self._turn))
        self.plan_turns: list[dict[str, object]] = []
        try:  # a ROM from before the turn plan has no such labels
            harness.register_hook("AIPlanEnemyTurn", self._guarded(self._plan))
            harness.register_hook("AICommitEnemyTurn", self._guarded(self._commit))
        except KeyError:
            pass
        self._start: dict[str, int] | None = None
        self._opponent = ""
        self._identity: tuple[int, int] = (0, 0)
        self._errors_at_start = 0

    def _guarded(self, callback):
        def run(context) -> None:
            try:
                callback(context)
            except Exception as error:  # a raising hook callback would end the autoplay run
                self.errors.append(f"{callback.__name__}: {error!r}")

        return run

    def _turn(self, _context) -> None:
        self.turn_count["value"] += 1

    def _plan(self, _context) -> None:
        self.plan_turns.append({"mon": self.h.read8("wPlayerMonNumber")})

    def _commit(self, _context) -> None:
        turn = self.plan_turns[-1] if self.plan_turns else None
        if turn is None or "switched" in turn:
            return
        turn["planned"] = bool(self.h.read8("wAITurnPlan") & 1 << 5)  # AI_TURN_PLANNED_BIT
        turn["switched"] = self.h.read8("wPlayerMonNumber") != turn["mon"]

    def _selected(self, _context) -> None:
        h = self.h
        move = h.pyboy.register_file.A
        if move == NO_SELECTION:
            return
        moves = h.read_bytes("wEnemyMonMoves", 4)
        pp = h.read_bytes("wEnemyMonPP", 4)
        disabled_slot = h.read8("wEnemyDisabledMove") >> 4  # 1-4, 0 = none
        usable = sum(bool(m) and (p & 0x3F) > 0 and slot + 1 != disabled_slot
                     for slot, (m, p) in enumerate(zip(moves, pp)))
        position = h.read8("wEnemyMonPartyPos")
        base = h.address("wEnemyMons")
        reserves = 0
        for index in range(h.read8("wEnemyPartyCount")):
            if index == position:
                continue
            offset = base + index * PARTYMON_STRUCT_LENGTH + 1  # MON_HP, big-endian
            reserves += bool(h.pyboy.memory[offset] | h.pyboy.memory[offset + 1])
        personality = h.read8("wAIRandomPersonality")
        self.selections.append(
            {
                "move": move,
                "slot": h.read8("wEnemyMoveListIndex"),  # stale on Struggle
                "struggle": move == self.struggle,
                "forced": usable == 1 and move != self.struggle,
                "pp_out": sum(bool(m) and (p & 0x3F) == 0 for m, p in zip(moves, pp)),
                "enemy_pos": position,
                "reserves_alive": reserves,
                "personality": personality - 1 if personality else None,
                "frame": h.pyboy.frame_count,
            }
        )

    def _party_hp(self) -> tuple[int, int, int]:
        """(total HP, mons fainted, total max HP) of the player's party."""
        h = self.h
        base = h.address("wPartyMons")
        hp = max_hp = fainted = 0
        for index in range(min(6, h.read8("wPartyCount"))):
            mon = base + index * PARTYMON_STRUCT_LENGTH
            current = h.pyboy.memory[mon + MON_HP] << 8 | h.pyboy.memory[mon + MON_HP + 1]
            hp += current
            fainted += current == 0
            max_hp += h.pyboy.memory[mon + MON_MAXHP] << 8 | h.pyboy.memory[mon + MON_MAXHP + 1]
        return hp, fainted, max_hp

    def begin_battle(self, opponent: str) -> None:
        self._opponent = opponent
        self._errors_at_start = len(self.errors)
        self._start = None
        try:
            if not self.h.read8("wIsTrainerBattle"):
                return
            self._identity = (self.h.read8("wTrainerClass"), self.h.read8("wTrainerNo"))
            self._start = {
                "decisions": len(self.decisions),
                "personality": len(self.personality),
                "trainer_ai": len(self.trainer_ai),
                "selections": len(self.selections),
                "plan_turns": len(self.plan_turns),
                "switches": self.switches["count"],
                "turns": self.turn_count["value"],
                "party": self._party_hp(),
            }
        except Exception as error:
            self.errors.append(f"begin_battle: {error!r}")

    def _pressure(self, before: tuple[int, int, int], result: int) -> dict[str, object]:
        hp_before, fainted_before, max_hp = before
        if result == 1:  # a blackout: the whole party fell, whatever a heal has since rewritten
            return {"player_hp": (hp_before, 0, max_hp),
                    "player_fainted": self.h.read8("wPartyCount") - fainted_before}
        hp_after, fainted_after, _ = self._party_hp()
        return {"player_hp": (hp_before, hp_after, max_hp),
                "player_fainted": max(0, fainted_after - fainted_before)}

    def end_battle(self, result: int) -> dict[str, object] | None:
        start, self._start = self._start, None
        if start is None:
            return None
        try:
            record = battle_record(
                opponent=self._opponent,
                trainer_class=self._identity[0],
                trainer_no=self._identity[1],
                result=result,
                decisions=self.decisions[start["decisions"]:],
                personality_records=self.personality[start["personality"]:],
                trainer_ai_calls=self.trainer_ai[start["trainer_ai"]:],
                selections=self.selections[start["selections"]:],
                enemy_switches=self.switches["count"] - start["switches"],
                turns=self.turn_count["value"] - start["turns"],
                move_powers=self.move_powers,
                struggle=self.struggle,
                plan_turns=self.plan_turns[start["plan_turns"]:],
                **self._pressure(start["party"], result),
            )
        except Exception as error:
            self.errors.append(f"end_battle: {error!r}")
            return None
        if len(self.errors) > self._errors_at_start:
            record["flags"].append("telemetry_error")
        return record
