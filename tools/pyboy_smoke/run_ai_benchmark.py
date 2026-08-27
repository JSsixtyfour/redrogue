from __future__ import annotations

import argparse
import csv
import io
import json
from pathlib import Path
from statistics import mean

from harness import RedRogueHarness


AI_KILL = 5
FRAME_CYCLES = 70_224
PARTYMON_STRUCT_LENGTH = 44


def layer(record: dict[str, object], name: str) -> dict[str, object] | None:
    return next(
        (entry for entry in record.get("layer_trace", []) if entry["layer"] == name),
        None,
    )


def first_decision_records(records: list[dict[str, object]]) -> list[dict[str, object]]:
    first: dict[int, dict[str, object]] = {}
    for record in records:
        first.setdefault(int(record["decision"]), record)
    return list(first.values())


def classify_decisions(records: list[dict[str, object]]) -> dict[str, int]:
    decisions = first_decision_records(records)
    opportunities = missed = wasted = 0
    for record in decisions:
        selected = record.get("selected_slot")
        if not isinstance(selected, int):
            continue
        damage = layer(record, "DAMAGE")
        if damage is not None and damage["enabled"]:
            lethal = {
                slot
                for slot, delta in enumerate(damage["delta"])
                if delta <= -AI_KILL
            }
            if lethal:
                opportunities += 1
                missed += selected not in lethal
        redundant = layer(record, "REDUNDANT")
        if (
            redundant is not None
            and redundant["enabled"]
            and redundant["delta"][selected] > 0
        ):
            wasted += 1
    return {
        "decisions": len(decisions),
        "ko_opportunities": opportunities,
        "missed_kos": missed,
        "wasted_turns": wasted,
    }


def nullable_rate(numerator: int, denominator: int) -> float | None:
    return numerator / denominator if denominator else None


def parse_move_powers(path: Path) -> dict[int, int]:
    powers: dict[int, int] = {}
    move_id = 1
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split(";", 1)[0].strip()
        if not line.startswith("move "):
            continue
        fields = [field.strip() for field in line[len("move ") :].split(",")]
        if len(fields) != 6:
            raise ValueError(f"malformed move row: {raw_line}")
        powers[move_id] = int(fields[2], 0)
        move_id += 1
    return powers


def choose_player_move(
    harness: RedRogueHarness, policy: str, powers: dict[int, int]
) -> int:
    moves = harness.read_bytes("wBattleMonMoves", 4)
    pp = harness.read_bytes("wBattleMonPP", 4)
    legal = [
        (slot, move)
        for slot, (move, move_pp) in enumerate(zip(moves, pp))
        if move and move_pp & 0x3F
    ]
    if not legal:
        return moves[0]
    if policy == "first_slot":
        return legal[0][1]
    return max(legal, key=lambda entry: (powers.get(entry[1], 0), -entry[0]))[1]


def prepare_party_driver(
    harness: RedRogueHarness,
) -> tuple[dict[str, int], list[bool], list[dict[str, object]]]:
    party_menu_modes: list[bool] = []
    party_menu_trace: list[dict[str, object]] = []
    party_context = {"choose_next": False}
    harness.hook_flag(
        "ChooseNextMon", action=lambda: party_context.update(choose_next=True)
    )
    harness.hook_flag(
        "MainInBattleLoop", action=lambda: party_context.update(choose_next=False)
    )

    def prepare_party_menu() -> None:
        forced = bool(
            harness.read8("wForcePlayerToChooseMon") or party_context["choose_next"]
        )
        party_menu_modes.append(forced)
        if not forced:
            return
        current = harness.read8("wPlayerMonNumber")
        count = harness.read8("wPartyCount")
        hp_base = harness.address("wPartyMon1HP")
        hp_values = [
            (
                harness.pyboy.memory[hp_base + slot * PARTYMON_STRUCT_LENGTH] << 8
                | harness.pyboy.memory[
                    hp_base + slot * PARTYMON_STRUCT_LENGTH + 1
                ]
            )
            for slot in range(count)
        ]
        selected = next(
            (slot for slot, hp in enumerate(hp_values) if slot != current and hp),
            None,
        )
        if selected is None:
            # ChooseNextMon can remain the last observed caller while an
            # immediately-following optional shift prompt opens. With no
            # living alternative, cancellation is the only valid action.
            forced = False
            party_menu_modes[-1] = False
        if selected is not None:
            harness.write8("wPartyAndBillsPCSavedMenuItem", selected)
        party_menu_trace.append(
            {
                "forced": forced,
                "current": current,
                "selected": selected,
                "hp": hp_values,
            }
        )

    harness.hook_flag("PartyMenuInit", action=prepare_party_menu)
    return (
        harness.hook_flag("HandlePartyMenuInput"),
        party_menu_modes,
        party_menu_trace,
    )


def run_tier(
    repo_root: Path,
    artifacts_dir: Path,
    *,
    seed: int,
    trials_count: int,
    max_steps: int,
    tier: int | None,
    player_policy: str,
    move_powers: dict[int, int],
) -> dict[str, object]:
    harness = RedRogueHarness(repo_root, artifacts_dir)
    trials: list[dict[str, object]] = []
    tier_override = 0 if tier is None else tier + 1
    try:
        harness.write8("wAIDebugTierOverride", tier_override)
        harness.hook_flag(
            "DebugFight2Setup",
            action=lambda: harness.write8("wAIDebugTierOverride", tier_override),
        )
        scores = harness.hook_ai_scores()
        harness.register_hook(
            "MainInBattleLoop.noLinkBattle",
            lambda _context: harness.write8(
                "wTestBattlePlayerSelectedMove",
                choose_player_move(harness, player_policy, move_powers),
            ),
        )
        # Register telemetry after the policy hook so its recorded player move
        # is the move this benchmark actually selected for the turn.
        turns = harness.hook_turn_telemetry()
        switches = harness.hook_flag("SwitchEnemyMon")
        items = [
            harness.hook_flag(label)
            for label in (
                "AIUseFullRestore", "AIUsePotion", "AIUseSuperPotion",
                "AIUseHyperPotion", "AIUseFullHeal", "AIUseXAccuracy",
                "AIUseGuardSpec", "AIUseDireHit", "AIUseXAttack",
                "AIUseXDefend", "AIUseXSpeed", "AIUseXSpecial",
            )
        ]
        victories = harness.hook_flag("TrainerBattleVictory")
        defeats = harness.hook_flag("HandlePlayerBlackOut")
        harness.hook_flag(
            "DisplayBattleMenu",
            action=lambda: harness.write8("wBattleAndStartSavedMenuItem", 0),
        )
        harness.hook_flag(
            "MoveSelectionMenu",
            action=lambda: harness.write8("wPlayerMoveListIndex", 0),
        )
        party_inputs, party_modes, party_trace = prepare_party_driver(harness)
        harness.boot_fight2(seed=seed)
        baseline = io.BytesIO()
        harness.save_state(baseline)

        for trial_index in range(trials_count):
            harness.load_state(baseline)
            harness.write8("wAIDebugTierOverride", tier_override)
            score_start, turn_start = len(scores), len(turns)
            switch_start = switches["count"]
            item_start = sum(item["count"] for item in items)
            victory_start, defeat_start = victories["count"], defeats["count"]
            handled_party_inputs = party_inputs["count"]
            party_mode_index = len(party_modes)
            for _ in range(max_steps):
                if party_inputs["count"] > handled_party_inputs:
                    harness.tick(2)
                    harness.tap("a" if party_modes[party_mode_index] else "b")
                    handled_party_inputs = party_inputs["count"]
                    party_mode_index += 1
                else:
                    harness.tap("a", 1)
                    harness.tick(8)
                if victories["count"] > victory_start or defeats["count"] > defeat_start:
                    break
            else:
                image_path, state_path = harness.write_failure_artifacts(
                    f"ai_benchmark_seed{seed}_tier{tier}_trial{trial_index}"
                )
                raise AssertionError(
                    f"trial {trial_index} exceeded {max_steps} input steps: "
                    f"artifacts={image_path},{state_path} "
                    f"party_menus={party_trace[-8:]}"
                )

            trial_scores = scores[score_start:]
            trial_turns = turns[turn_start:]
            classified = classify_decisions(trial_scores)
            real_decisions = first_decision_records(trial_scores)
            decision_cycles = [int(record["decision_cycles"]) for record in real_decisions]
            resolved_tiers = {int(record["tier"]) for record in real_decisions}
            if len(resolved_tiers) != 1:
                raise AssertionError(f"trial resolved inconsistent AI tiers: {resolved_tiers}")
            resolved_tier = resolved_tiers.pop()
            if classified["decisions"] > max(1, len(trial_turns) * 3):
                raise AssertionError(
                    f"implausible AI decision ratio: {classified['decisions']} decisions "
                    f"across {len(trial_turns)} turns"
                )
            cycle_total = sum(
                int(turn.get("end_cycle", turn["start_cycle"]))
                - int(turn["start_cycle"])
                for turn in trial_turns
            )
            trials.append(
                {
                    "trial": trial_index,
                    "tier": resolved_tier,
                    "result": "win" if victories["count"] > victory_start else "loss",
                    "turns": len(trial_turns),
                    "cycles": cycle_total,
                    "switches": switches["count"] - switch_start,
                    "items": sum(item["count"] for item in items) - item_start,
                    "ai_decisions": classified["decisions"],
                    "ko_opportunities": classified["ko_opportunities"],
                    "missed_kos": classified["missed_kos"],
                    "wasted_turns": classified["wasted_turns"],
                    "mean_ai_decision_cycles": mean(decision_cycles),
                    "max_ai_decision_cycles": max(decision_cycles),
                    "over_frame_ai_decisions": sum(
                        cycles > FRAME_CYCLES for cycles in decision_cycles
                    ),
                }
            )
    finally:
        harness.close()

    total_turns = sum(int(trial["turns"]) for trial in trials)
    decisions = sum(int(trial["ai_decisions"]) for trial in trials)
    opportunities = sum(int(trial["ko_opportunities"]) for trial in trials)
    missed = sum(int(trial["missed_kos"]) for trial in trials)
    wasted = sum(int(trial["wasted_turns"]) for trial in trials)
    switches_count = sum(int(trial["switches"]) for trial in trials)
    items_count = sum(int(trial["items"]) for trial in trials)
    resolved_tier = int(trials[0]["tier"])
    if resolved_tier >= 2 and opportunities == 0:
        raise AssertionError(
            f"AI_DAMAGE is enabled at tier {resolved_tier}, but the benchmark "
            "recorded zero KO opportunities"
        )
    wins = sum(trial["result"] == "win" for trial in trials)
    summary = {
        "seed": seed,
        "requested_tier": "auto" if tier is None else tier,
        "resolved_tier": resolved_tier,
        "player_policy": player_policy,
        "trials": len(trials),
        "wins": wins,
        "turns": total_turns,
        "decisions": decisions,
        "ko_opportunities": opportunities,
        "missed_kos": missed,
        "wasted_turns": wasted,
        "switches": switches_count,
        "items": items_count,
        "win_rate": nullable_rate(wins, len(trials)),
        "average_turns": mean(int(trial["turns"]) for trial in trials),
        "average_cycles": mean(int(trial["cycles"]) for trial in trials),
        "switch_rate_per_turn": nullable_rate(switches_count, total_turns),
        "item_rate_per_turn": nullable_rate(items_count, total_turns),
        "missed_ko_rate": nullable_rate(missed, opportunities),
        "wasted_turn_rate": nullable_rate(wasted, decisions),
        "mean_ai_decision_cycles": (
            sum(
                float(trial["mean_ai_decision_cycles"])
                * int(trial["ai_decisions"])
                for trial in trials
            )
            / decisions
            if decisions
            else None
        ),
        "max_ai_decision_cycles": max(
            int(trial["max_ai_decision_cycles"]) for trial in trials
        ),
        "over_frame_ai_decisions": sum(
            int(trial["over_frame_ai_decisions"]) for trial in trials
        ),
        "notes": [
            note
            for note in (
                "missed_ko_rate is null because no KO opportunity was observed"
                if opportunities == 0 else None,
                "wasted_turn_rate is null because no AI decision was observed"
                if decisions == 0 else None,
                "no strategic switch was observed"
                if resolved_tier == 3 and switches_count == 0 else None,
                "one or more AI decisions exceeded the 70,224-cycle frame budget"
                if any(int(trial["over_frame_ai_decisions"]) for trial in trials)
                else None,
            )
            if note is not None
        ],
    }
    return {"summary": summary, "trial_results": trials}


def write_report(output: Path, reports: list[dict[str, object]]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    report = (
        reports[0]
        if len(reports) == 1
        else {"mode": "tier_comparison", "tiers": reports}
    )
    output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    csv_path = output.with_suffix(".csv")
    rows = [tier_report["summary"] for tier_report in reports]
    fieldnames = [key for key in rows[0] if key != "notes"]
    with csv_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(
            output_file, fieldnames=fieldnames, extrasaction="ignore"
        )
        writer.writeheader()
        writer.writerows(rows)
    print(output)
    print(csv_path)
    print(json.dumps(rows if len(rows) > 1 else rows[0], indent=2, sort_keys=True))


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark deterministic FIGHT 2 battles")
    parser.add_argument("--seed", type=int, default=17)
    parser.add_argument("--trials", type=int, default=1)
    parser.add_argument("--max-steps", type=int, default=5000)
    parser.add_argument(
        "--tier", choices=("auto", "0", "1", "2", "3", "all"), default="3"
    )
    parser.add_argument(
        "--player-policy",
        choices=("best_power", "first_slot"),
        default="best_power",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).with_name("artifacts") / "ai_benchmark.json",
    )
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("--trials must be positive")

    repo_root = Path(__file__).resolve().parents[2]
    move_powers = parse_move_powers(repo_root / "data" / "moves" / "moves.asm")
    requested_tiers = (
        list(range(4))
        if args.tier == "all"
        else [None] if args.tier == "auto" else [int(args.tier)]
    )
    reports = [
        run_tier(
            repo_root,
            args.output.parent,
            seed=args.seed,
            trials_count=args.trials,
            max_steps=args.max_steps,
            tier=tier,
            player_policy=args.player_policy,
            move_powers=move_powers,
        )
        for tier in requested_tiers
    ]
    write_report(args.output, reports)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
