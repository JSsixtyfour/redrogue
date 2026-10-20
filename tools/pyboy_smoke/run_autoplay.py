"""Soak test: play many seeded runs with the autoplay agent, in parallel.

    make autoplay
    make autoplay AUTOPLAY_ARGS='--seeds 1-64 --stages 40'
    python3 tools/pyboy_smoke/run_autoplay.py --seeds 3,9,12 --jobs 2

Each seed is one full run from the Debug 2 lobby (autoplay.py). Reports go to
artifacts/autoplay_seed<N>.json, failed runs also get a screenshot and state
dump, and artifacts/autoplay_summary.json collects one row per seed. Exits
non-zero when any run failed (stalled, frame_limit or error); a blackout or a
champion is a game result, not a failure.

Reproduce one seed with `python3 tools/pyboy_smoke/autoplay.py --seed N`: runs
are deterministic for a given ROM.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import autoplay

SUMMARY_FIELDS = ("seed", "outcome", "stages_cleared", "battles_won", "frames", "wall_seconds")


def parse_seeds(spec: str) -> list[int]:
    """"1-4,9" -> [1, 2, 3, 4, 9]."""
    seeds: list[int] = []
    for part in spec.split(","):
        first, _, last = part.strip().partition("-")
        seeds.extend(range(int(first), int(last or first) + 1))
    return seeds


def run_seed(seed: int, options: dict[str, object]) -> dict[str, object]:
    data = autoplay.play(seed, **options)
    path = autoplay.ARTIFACTS / f"autoplay_seed{seed}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    finish = next((e for e in reversed(data["events"]) if e["kind"] == "finish"), {})
    return {name: data[name] for name in SUMMARY_FIELDS} | {
        "detail": data["detail"],
        "run_records": data["runs"],
        "map": finish.get("map"),
        "position": finish.get("position"),
        "report": str(path),
    }


def run_statistics(runs: list[dict[str, object]]) -> dict[str, object]:
    """Balance numbers over every finished run: how often the Champion falls,
    how far runs get, and where and to whom they are lost."""
    def count(values) -> dict[str, int]:
        result: dict[str, int] = {}
        for value in values:
            result[str(value)] = result.get(str(value), 0) + 1
        return dict(sorted(result.items(), key=lambda item: (-item[1], item[0])))

    stages = sorted(run["stages_cleared"] for run in runs)
    losses = [run for run in runs if run["outcome"] == "blackout"]
    return {
        "runs": len(runs),
        "champion_rate": round(sum(run["outcome"] == "champion" for run in runs) / len(runs), 3)
        if runs else None,
        "stages_cleared": {
            "mean": round(sum(stages) / len(stages), 2) if stages else None,
            "median": stages[len(stages) // 2] if stages else None,
            "histogram": count(stages),
        },
        # The stage a run was lost on is the one after the last one cleared.
        "lost_at_stage_number": count(run["stages_cleared"] + 1 for run in losses),
        "lost_at_stage": count(run["last_stage"] for run in losses),
        "lost_to": count(run.get("lost_to") for run in losses),
    }


def print_statistics(balance: dict[str, object]) -> None:
    if not balance["runs"]:
        return
    print(f"\n{balance['runs']} finished runs, champion rate {balance['champion_rate']:.0%}, "
          f"stages cleared mean {balance['stages_cleared']['mean']} "
          f"median {balance['stages_cleared']['median']}")
    for key, title in (("lost_at_stage_number", "lost at stage #"), ("lost_at_stage", "lost at"),
                       ("lost_to", "lost to")):
        top = list(balance[key].items())[:8]
        if top:
            print(f"  {title}: " + ", ".join(f"{name} {n}" for name, n in top))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Soak-test Red Rogue with the autoplay agent.")
    parser.add_argument("--seeds", default="1-8", help="e.g. 1-16 or 3,9,12")
    parser.add_argument("--runs", type=int, default=1,
                        help="runs per seed; between runs the agent walks the hub into the next")
    parser.add_argument("--stages", type=int, default=1000)
    parser.add_argument("--new-game", action="store_true",
                        help="start each seed from power-on and NEW GAME, not the Debug 2 lobby")
    parser.add_argument("--max-frames", type=int, default=1_000_000)
    parser.add_argument("--stall-frames", type=int, default=20_000)
    parser.add_argument("--battle-policy", default="type_switcher",
                        choices=autoplay.benchmark_policies.POLICIES)
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    args = parser.parse_args(argv)

    seeds = parse_seeds(args.seeds)
    options = {
        "runs": args.runs,
        "new_game": args.new_game,
        "stages": args.stages,
        "max_frames": args.max_frames,
        "stall_frames": args.stall_frames,
        "battle_policy": args.battle_policy,
    }
    rows = []
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = {pool.submit(run_seed, seed, options): seed for seed in seeds}
        for future in as_completed(futures):
            row = future.result()
            rows.append(row)
            mark = "FAIL" if row["outcome"] in autoplay.FAILURES else "ok  "
            print(f"{mark} seed {row['seed']:>4}  {row['outcome']:<11} "
                  f"stages={row['stages_cleared']:<3} won={row['battles_won']:<3} "
                  f"{row['map']} {row['position']}  {row['detail']}", flush=True)
    rows.sort(key=lambda row: row["seed"])

    outcomes: dict[str, int] = {}
    for row in rows:
        outcomes[row["outcome"]] = outcomes.get(row["outcome"], 0) + 1
    failures = [row for row in rows if row["outcome"] in autoplay.FAILURES]
    balance = run_statistics([run for row in rows for run in row["run_records"]])
    summary = {"options": options, "outcomes": outcomes, "balance": balance, "runs": rows}
    path = autoplay.ARTIFACTS / "autoplay_summary.json"
    path.write_text(json.dumps(summary, indent=1) + "\n", encoding="utf-8")
    print_statistics(balance)
    print(f"\n{len(rows)} seeds: " + ", ".join(f"{n} {k}" for k, n in sorted(outcomes.items()))
          + f" -> {path}")
    for row in failures:
        flags = " --new-game" * args.new_game + f" --runs {args.runs}" * (args.runs != 1)
        print(f"  reproduce: python3 tools/pyboy_smoke/autoplay.py --seed {row['seed']}{flags}"
              f"   # {row['outcome']} at {row['map']}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
