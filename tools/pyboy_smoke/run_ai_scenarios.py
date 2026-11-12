from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from ai_scenarios import load_scenarios, validate_scenario_coverage
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
    scenarios = load_scenarios(args.scenarios, repo_root)
    coverage = validate_scenario_coverage(scenarios)

    scenario_count = len(scenarios)
    failures: list[str] = []
    for scenario_index, scenario in enumerate(scenarios, start=1):
        print(f"[{scenario_index}/{scenario_count}] {scenario.name}", flush=True)
        for trial in range(args.trials):
            try:
                reports.append(run_scenario(scenario, trial, repo_root, args.output.parent))
            except AssertionError as error:
                failures.append(str(error))
                print(f"    FAIL {error}", flush=True)
    write_reports(args.output, reports, coverage)
    if failures:
        print(f"{len(failures)} of {scenario_count * args.trials} scenario runs failed:")
        for failure in failures:
            print(f"  {failure}")
        return 1
    return 0


# The battle's FIRST decision is the one each scenario describes: turn 1 on the
# untouched board. Since 2026-10-22 the enemy plans its turn before the battle
# menu (ai_turn_plan.asm), i.e. inside boot_fight2, and this runner used to judge
# the decision AFTER boot - turn 2, after a turn of RNG-dependent damage. That,
# plus the optional personality pass (Checkpoint E, rolled at random per battle),
# failed 45 of 86 scenarios on a build that had not changed them (2026-11-12).
# The personality is pinned to NONE: no scenario tests it, and its random +-1
# nudges are not what any scenario asserts. A scenario's own prime still wins.
PERSONALITY_NONE_RESOLVED = 1  # wAIRandomPersonality: personality id + 1


def run_scenario(scenario, trial: int, repo_root: Path, artifacts: Path) -> dict[str, object]:
    harness = RedRogueHarness(repo_root, artifacts)
    try:
        harness.inject_fight2_spec(
            [mon.as_fixture() for mon in scenario.player],
            [mon.as_fixture() for mon in scenario.enemy],
            trainer_class=scenario.trainer_class,
            ai_tier=scenario.ai_tier,
        )
        scores = harness.hook_ai_scores()
        switches = harness.hook_flag("SwitchEnemyMon")

        # Fires once per AI decision, after AITrackLastMove has already run this
        # cycle (so wAILastMove* pokes land after the routine that would
        # otherwise immediately overwrite them) but before ANY scoring layer -
        # including AI_REDUNDANT, which runs first - reads WRAM. Priming later
        # (e.g. at AILayerSmart's own entry) left AI_REDUNDANT scoring off the
        # mon's real, undamaged fixture HP instead of the primed value. See
        # AIScenario.prime / .prime_hp.
        def apply_prime() -> None:
            harness.write8("wAIRandomPersonality", PERSONALITY_NONE_RESOLVED)
            if scenario.personality is not None:
                # The cached roll outranks the class allowlist (AIGetSoftPersonality),
                # so any trainer class plays the scenario's profile.
                harness.write8("wAIRandomPersonality", scenario.personality + 1)
            for label, value in scenario.prime.items():
                harness.write8(label, value)
            for entry in scenario.prime_hp:
                max_hi, max_lo = harness.read_bytes(str(entry["max_label"]), 2)
                max_hp = (max_hi << 8) | max_lo
                value = max_hp * int(entry["numerator"]) // int(entry["denominator"])
                value = max(1, min(max_hp, value))
                current_label = str(entry["current_label"])
                harness.write8(current_label, value >> 8, offset=0)
                harness.write8(current_label, value & 0xFF, offset=1)

        harness.hook_flag("AIEnemyTrainerChooseMoves.beforeLayers", action=apply_prime)
        if scenario.personality:
            # The profile applies on half of its decisions (F4): one Random, top
            # bit = heads. Set it here, as test_ai_personality does, to choose.
            def coin(_context, lean=scenario.personality_lean) -> None:
                harness.pyboy.register_file.A = 0x80 if lean else 0x00

            harness.register_hook("AIRunPersonality.coinDrawn", coin)
        harness.boot_fight2(seed=1)
        # The turn-1 decision is normally made inside boot_fight2. A class that
        # decides at commit instead (AIOpponentIsPsychic) makes it once the lead's
        # first move is chosen: FIGHT 2 mirrors that choice into the test-policy
        # byte.
        for _ in range(300):
            if scores or switches["count"]:
                break
            harness.tap("a", 1)
            harness.tick(8)
        switched = switches["count"] > 0
        if not scores and not switched:
            raise AssertionError(f"{scenario.name}: the first AI decision was not reached")
        telemetry = scores[0] if scores else {"switched": True, "frame": harness.pyboy.frame_count}
        telemetry["switched"] = switched
        try:
            assert_expectations(scenario.expect, telemetry)
        except AssertionError as error:
            raise AssertionError(f"{scenario.name}: {error}") from error
        return {
            "name": scenario.name,
            "trial": trial,
            "phase": scenario.phase,
            "heuristic": scenario.heuristic,
            "case": scenario.case,
            "tags": scenario.tags,
            "expected": scenario.expect,
            "telemetry": telemetry,
            "state": harness.diagnostic_state(),
        }
    finally:
        harness.close()


def write_reports(output: Path, reports: list[dict[str, object]], coverage) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(reports, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    coverage_path = output.with_name(f"{output.stem}.coverage.json")
    coverage_path.write_text(json.dumps(coverage, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    csv_path = output.with_suffix(".csv")
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
    print(output)
    print(csv_path)
    print(coverage_path)


if __name__ == "__main__":
    raise SystemExit(main())
