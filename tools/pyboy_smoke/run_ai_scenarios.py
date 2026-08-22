from __future__ import annotations

import argparse
import csv
import io
import json
from pathlib import Path

from ai_scenarios import load_scenarios
from harness import RedRogueHarness


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
            harness.boot_fight2(seed=1)
            baseline = io.BytesIO()
            harness.save_state(baseline)
            for trial in range(args.trials):
                harness.load_state(baseline)
                record_index = len(scores)
                # Advance through the battle menu and choose the lead's first
                # move. FIGHT 2 mirrors the human choice into the test-policy
                # byte; future policies can write that byte at the same point.
                for _ in range(300):
                    harness.tap("a", 1)
                    harness.tick(8)
                    if len(scores) > record_index:
                        break
                if len(scores) == record_index:
                    raise AssertionError("the first AI scoring decision was not reached")
                reports.append(
                    {
                        "name": scenario.name,
                        "trial": trial,
                        "expected": scenario.expect,
                        "telemetry": scores[record_index],
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
                    "tier": telemetry["tier"],
                    "moves": json.dumps(telemetry["moves"]),
                    "scores": json.dumps(telemetry["scores"]),
                    "frame": telemetry["frame"],
                }
            )
    print(args.output)
    print(csv_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
