from __future__ import annotations

import argparse
import csv
import io
import json
from pathlib import Path
from statistics import mean

from harness import RedRogueHarness


AI_KILL = 5


def layer(record: dict[str, object], name: str) -> dict[str, object] | None:
    return next(
        (entry for entry in record.get("layer_trace", []) if entry["layer"] == name),
        None,
    )


def classify_decisions(records: list[dict[str, object]]) -> tuple[int, int, int]:
    opportunities = missed = wasted = 0
    for record in records:
        selected = record.get("selected_slot")
        if not isinstance(selected, int):
            continue
        damage = layer(record, "DAMAGE")
        if damage is not None:
            lethal = {
                slot for slot, delta in enumerate(damage["delta"])
                if delta <= -AI_KILL
            }
            if lethal:
                opportunities += 1
                missed += selected not in lethal
        redundant = layer(record, "REDUNDANT")
        if redundant is not None and redundant["delta"][selected] > 0:
            wasted += 1
    return opportunities, missed, wasted


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark deterministic FIGHT 2 battles")
    parser.add_argument("--seed", type=int, default=17)
    parser.add_argument("--trials", type=int, default=1)
    parser.add_argument("--max-steps", type=int, default=5000)
    parser.add_argument(
        "--output", type=Path,
        default=Path(__file__).with_name("artifacts") / "ai_benchmark.json",
    )
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("--trials must be positive")

    repo_root = Path(__file__).resolve().parents[2]
    harness = RedRogueHarness(repo_root, args.output.parent)
    trials = []
    try:
        scores = harness.hook_ai_scores()
        turns = harness.hook_turn_telemetry()
        switches = harness.hook_flag("SwitchEnemyMon")
        items = [
            harness.hook_flag(label) for label in (
                "AIUseFullRestore", "AIUsePotion", "AIUseSuperPotion",
                "AIUseHyperPotion", "AIUseFullHeal", "AIUseXAccuracy",
                "AIUseGuardSpec", "AIUseDireHit", "AIUseXAttack",
                "AIUseXDefend", "AIUseXSpeed", "AIUseXSpecial",
            )
        ]
        victories = harness.hook_flag("TrainerBattleVictory")
        defeats = harness.hook_flag("HandlePlayerBlackOut")
        # Blind A presses are only safe when the battle cursor is forced back
        # to FIGHT. Otherwise the saved cursor can reopen PARTY and repeatedly
        # select the already-active TEST mon.
        harness.hook_flag(
            "DisplayBattleMenu",
            action=lambda: harness.write8("wBattleAndStartSavedMenuItem", 0),
        )
        harness.hook_flag(
            "MoveSelectionMenu",
            action=lambda: harness.write8("wPlayerMoveListIndex", 0),
        )
        party_menu_modes: list[bool] = []
        party_menu_trace: list[dict[str, object]] = []
        party_context = {"choose_next": False}

        harness.hook_flag(
            "ChooseNextMon",
            action=lambda: party_context.update(choose_next=True),
        )
        harness.hook_flag(
            "MainInBattleLoop",
            action=lambda: party_context.update(choose_next=False),
        )

        def prepare_party_menu() -> None:
            forced = bool(
                harness.read8("wForcePlayerToChooseMon")
                or party_context["choose_next"]
            )
            party_menu_modes.append(forced)
            if not forced:
                return
            current = harness.read8("wPlayerMonNumber")
            count = harness.read8("wPartyCount")
            hp_base = harness.address("wPartyMon1HP")
            hp_values = []
            for slot in range(count):
                hp = (
                    harness.pyboy.memory[hp_base + slot * 44] << 8
                    | harness.pyboy.memory[hp_base + slot * 44 + 1]
                )
                hp_values.append(hp)
                if slot != current and hp:
                    harness.write8("wPartyAndBillsPCSavedMenuItem", slot)
                    party_menu_trace.append(
                        {"forced": forced, "current": current, "selected": slot, "hp": hp_values}
                    )
                    return
            party_menu_trace.append(
                {"forced": forced, "current": current, "selected": None, "hp": hp_values}
            )

        harness.hook_flag("PartyMenuInit", action=prepare_party_menu)
        party_inputs = harness.hook_flag("HandlePartyMenuInput")
        harness.boot_fight2(seed=args.seed)
        baseline = io.BytesIO()
        harness.save_state(baseline)

        for trial_index in range(args.trials):
            harness.load_state(baseline)
            score_start, turn_start = len(scores), len(turns)
            switch_start = switches["count"]
            item_start = sum(item["count"] for item in items)
            victory_start, defeat_start = victories["count"], defeats["count"]
            handled_party_inputs = party_inputs["count"]
            party_mode_index = len(party_menu_modes)
            for _ in range(args.max_steps):
                if party_inputs["count"] > handled_party_inputs:
                    harness.tick(2)
                    if party_menu_modes[party_mode_index]:
                        harness.tap("a")
                    else:
                        harness.tap("b")
                    handled_party_inputs = party_inputs["count"]
                    party_mode_index += 1
                else:
                    harness.tap("a", 1)
                    harness.tick(8)
                if victories["count"] > victory_start or defeats["count"] > defeat_start:
                    break
            else:
                image_path, state_path = harness.write_failure_artifacts(
                    f"ai_benchmark_seed{args.seed}_trial{trial_index}"
                )
                raise AssertionError(
                    f"trial {trial_index} exceeded {args.max_steps} input steps: "
                    f"artifacts={image_path},{state_path} "
                    f"party_menus={party_menu_trace[-8:]} "
                    f"{json.dumps(harness.diagnostic_state(), sort_keys=True)}"
                )

            trial_scores = scores[score_start:]
            trial_turns = turns[turn_start:]
            opportunities, missed, wasted = classify_decisions(trial_scores)
            cycle_total = sum(
                int(turn.get("end_cycle", turn["start_cycle"])) - int(turn["start_cycle"])
                for turn in trial_turns
            )
            trials.append(
                {
                    "trial": trial_index,
                    "result": "win" if victories["count"] > victory_start else "loss",
                    "turns": len(trial_turns),
                    "cycles": cycle_total,
                    "switches": switches["count"] - switch_start,
                    "items": sum(item["count"] for item in items) - item_start,
                    "ai_decisions": len(trial_scores),
                    "ko_opportunities": opportunities,
                    "missed_kos": missed,
                    "wasted_turns": wasted,
                }
            )
    finally:
        harness.close()

    total_opportunities = sum(trial["ko_opportunities"] for trial in trials)
    total_decisions = sum(trial["ai_decisions"] for trial in trials)
    summary = {
        "seed": args.seed,
        "trials": len(trials),
        "win_rate": sum(trial["result"] == "win" for trial in trials) / len(trials),
        "average_turns": mean(trial["turns"] for trial in trials),
        "average_cycles": mean(trial["cycles"] for trial in trials),
        "switch_rate_per_turn": sum(trial["switches"] for trial in trials)
        / max(1, sum(trial["turns"] for trial in trials)),
        "item_rate_per_turn": sum(trial["items"] for trial in trials)
        / max(1, sum(trial["turns"] for trial in trials)),
        "missed_ko_rate": sum(trial["missed_kos"] for trial in trials)
        / max(1, total_opportunities),
        "wasted_turn_rate": sum(trial["wasted_turns"] for trial in trials)
        / max(1, total_decisions),
    }
    report = {"summary": summary, "trial_results": trials}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    csv_path = args.output.with_suffix(".csv")
    with csv_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=trials[0].keys())
        writer.writeheader()
        writer.writerows(trials)
    print(args.output)
    print(csv_path)
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
