from __future__ import annotations

import argparse
import csv
import io
import json
from pathlib import Path

from ai_scenarios import load_scenarios
from harness import RedRogueHarness


def assert_expectations(expect: dict[str, object], telemetry: dict[str, object]) -> None:
    """Apply the declarative expectation vocabulary used by AI scenarios."""
    supported = {
        "enemy_move_slots", "scores", "tier", "pick_slot", "never_pick",
        "score_lt", "score_lte", "switch", "no_switch",
    }
    unknown = set(expect) - supported
    if unknown:
        raise AssertionError(f"unsupported expectation keys: {sorted(unknown)}")

    moves = list(telemetry.get("moves", []))
    scores = list(telemetry.get("scores", []))
    selected_slot = telemetry.get("selected_slot")
    eligible_slots = list(telemetry.get("eligible_slots", []))
    switched = bool(telemetry.get("switched", False))

    if "enemy_move_slots" in expect:
        actual = [slot for slot, move in enumerate(moves) if move]
        assert actual == expect["enemy_move_slots"], (
            f"enemy move slots {actual} != {expect['enemy_move_slots']}"
        )
    if "scores" in expect:
        assert scores == expect["scores"], f"scores {scores} != {expect['scores']}"
    if "tier" in expect:
        assert telemetry.get("tier") == expect["tier"], (
            f"tier {telemetry.get('tier')} != {expect['tier']}"
        )
    if "pick_slot" in expect:
        allowed = expect["pick_slot"]
        if isinstance(allowed, int):
            allowed = [allowed]
        assert eligible_slots and set(eligible_slots).issubset(set(allowed)), (
            f"eligible slots {eligible_slots} are not contained in {allowed}"
        )
    if "never_pick" in expect:
        forbidden = set(expect["never_pick"])
        assert not forbidden.intersection(eligible_slots), (
            f"forbidden slots remain eligible: {sorted(forbidden.intersection(eligible_slots))}"
        )
    for left, right in expect.get("score_lt", []):
        assert scores[left] < scores[right], (
            f"score[{left}]={scores[left]} is not less than score[{right}]={scores[right]}"
        )
    for left, right in expect.get("score_lte", []):
        assert scores[left] <= scores[right], (
            f"score[{left}]={scores[left]} exceeds score[{right}]={scores[right]}"
        )
    if "switch" in expect:
        assert switched is bool(expect["switch"]), (
            f"switch={switched} != {expect['switch']}"
        )
    if expect.get("no_switch"):
        assert not switched, "enemy switched when the scenario forbids it"


def main() -> int:
    parser = argparse.ArgumentParser(description="Run deterministic Red Rogue AI scenarios")
    parser.add_argument("--scenarios", type=Path, default=Path(__file__).with_name("ai_scenarios.json"))
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("artifacts") / "ai_scenarios.json")
    parser.add_argument("--trials", type=int, default=1)
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    reports = []

    for scenario in load_scenarios(args.scenarios, repo_root):
        harness = RedRogueHarness(repo_root, args.output.parent)
        try:
            harness.inject_fight2_spec(
                [mon.as_fixture() for mon in scenario.player],
                [mon.as_fixture() for mon in scenario.enemy],
                trainer_class=scenario.trainer_class,
                ai_tier=scenario.ai_tier,
            )
            scores = harness.hook_ai_scores()
            switches = harness.hook_flag("SwitchEnemyMon")
            harness.boot_fight2(seed=1)
            baseline = io.BytesIO()
            harness.save_state(baseline)
            for trial in range(args.trials):
                harness.load_state(baseline)
                record_index = len(scores)
                switch_count = switches["count"]
                # Advance through the battle menu and choose the lead's first
                # move. FIGHT 2 mirrors the human choice into the test-policy
                # byte; future policies can write that byte at the same point.
                for _ in range(300):
                    harness.tap("a", 1)
                    harness.tick(8)
                    if len(scores) > record_index or switches["count"] > switch_count:
                        break
                switched = switches["count"] > switch_count
                if len(scores) == record_index and not switched:
                    raise AssertionError("the first AI decision was not reached")
                telemetry = (
                    scores[record_index]
                    if len(scores) > record_index
                    else {"switched": True, "frame": harness.pyboy.frame_count}
                )
                telemetry["switched"] = switched
                assert_expectations(scenario.expect, telemetry)
                reports.append(
                    {
                        "name": scenario.name,
                        "trial": trial,
                        "expected": scenario.expect,
                        "telemetry": telemetry,
                        "state": harness.diagnostic_state(),
                    }
                )
        finally:
            harness.close()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(reports, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    csv_path = args.output.with_suffix(".csv")
    with csv_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(
            output_file,
            fieldnames=("scenario", "trial", "tier", "moves", "scores", "frame"),
        )
        writer.writeheader()
        for report in reports:
            telemetry = report["telemetry"]
            writer.writerow(
                {
                    "scenario": report["name"],
                    "trial": report["trial"],
                    "tier": telemetry.get("tier"),
                    "moves": json.dumps(telemetry.get("moves")),
                    "scores": json.dumps(telemetry.get("scores")),
                    "frame": telemetry["frame"],
                }
            )
    print(args.output)
    print(csv_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
