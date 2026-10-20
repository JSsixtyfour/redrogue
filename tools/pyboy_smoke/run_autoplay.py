"""Soak test: play many seeded runs with the autoplay agent, in parallel.

    make autoplay
    make autoplay AUTOPLAY_ARGS='--seeds 1-64 --stages 40'
    python3 tools/pyboy_smoke/run_autoplay.py --seeds 3,9,12 --jobs 2

Each seed is one full run from the Debug 2 lobby (autoplay.py), in its own
process. Reports go to artifacts/autoplay_seed<N>.json, failed runs also get a
screenshot and state dump, and artifacts/autoplay_summary.json collects one row
per seed. Exits non-zero when any run failed (stalled, crashed, hung,
frame_limit or error) or reported an anomaly (autoplay_checks.py); a blackout
or a champion is a game result, not a failure.

A seed still running after --timeout seconds is killed and reported `hung`
with the last place its heartbeat recorded: an illegal opcode makes the
emulator spin inside one tick, where nothing in the worker can notice.

Reproduce one seed with `python3 tools/pyboy_smoke/autoplay.py --seed N`: runs
are deterministic for a given ROM.
"""
from __future__ import annotations

import argparse
import json
import multiprocessing
import os
import queue
import sys
import time
import traceback
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


def report_path(seed: int) -> Path:
    return autoplay.ARTIFACTS / f"autoplay_seed{seed}.json"


def heartbeat_path(seed: int) -> Path:
    return autoplay.ARTIFACTS / f"autoplay_seed{seed}.heartbeat.json"


def run_seed(seed: int, options: dict[str, object]) -> dict[str, object]:
    heartbeat = heartbeat_path(seed)
    heartbeat.parent.mkdir(parents=True, exist_ok=True)
    data = autoplay.play(seed, heartbeat=heartbeat, **options)
    heartbeat.unlink(missing_ok=True)
    path = report_path(seed)
    path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    finish = next((e for e in reversed(data["events"]) if e["kind"] == "finish"), {})
    return {name: data[name] for name in SUMMARY_FIELDS} | {
        "detail": data["detail"],
        "run_records": data["runs"],
        "map": finish.get("map"),
        "position": finish.get("position"),
        "anomalies": data["anomalies"],
        "menus": data["menus"],
        "report": str(path),
    }


def hung_row(seed: int, timeout: float) -> dict[str, object]:
    """A seed killed at the timeout: all that is left is its heartbeat."""
    try:
        beat = json.loads(heartbeat_path(seed).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        beat = {}
    path = report_path(seed)
    path.write_text(json.dumps({"seed": seed, "outcome": "hung", "heartbeat": beat}, indent=1) + "\n",
                    encoding="utf-8")
    return {"seed": seed, "outcome": "hung", "stages_cleared": 0, "battles_won": 0,
            "frames": beat.get("frame"), "wall_seconds": timeout,
            "detail": f"no result within {timeout:.0f}s (emulator hung, e.g. an illegal opcode); "
                      f"last heartbeat in mode {beat.get('mode')}",
            "run_records": [], "map": beat.get("map"), "position": beat.get("position"),
            "anomalies": [], "report": str(path)}


def _worker(seed: int, options: dict[str, object], results) -> None:
    try:
        results.put((seed, run_seed(seed, options)))
    except BaseException:
        results.put((seed, {"seed": seed, "outcome": "error", "stages_cleared": 0, "battles_won": 0,
                            "frames": 0, "wall_seconds": 0, "detail": traceback.format_exc(limit=3),
                            "run_records": [], "map": None, "position": None, "anomalies": [],
                            "report": None}))


def run_all(seeds: list[int], options: dict[str, object], jobs: int, timeout: float):
    """Yield one row per seed as each finishes, each seed in its own process
    so a hung emulator can be killed."""
    results = multiprocessing.Queue()
    waiting = list(seeds)
    running: dict[int, tuple[multiprocessing.Process, float]] = {}
    while waiting or running:
        while waiting and len(running) < jobs:
            seed = waiting.pop(0)
            process = multiprocessing.Process(target=_worker, args=(seed, options, results))
            process.start()
            running[seed] = (process, time.monotonic())
        try:
            seed, row = results.get(timeout=1)
        except queue.Empty:
            now = time.monotonic()
            for seed, (process, started) in list(running.items()):
                if now - started > timeout:
                    process.kill()
                    process.join()
                    del running[seed]
                    yield hung_row(seed, timeout)
            continue
        running.pop(seed)[0].join()
        yield row


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
    parser.add_argument("--menu-input", default="real", choices=autoplay.MENU_INPUTS)
    parser.add_argument("--menu-chaos", type=float, default=0.0,
                        help="chance of a stray press at each menu step (0-1)")
    parser.add_argument("--timeout", type=float, default=900,
                        help="seconds before a seed counts as hung and is killed")
    args = parser.parse_args(argv)

    seeds = parse_seeds(args.seeds)
    options = {
        "runs": args.runs,
        "new_game": args.new_game,
        "stages": args.stages,
        "max_frames": args.max_frames,
        "stall_frames": args.stall_frames,
        "battle_policy": args.battle_policy,
        "menu_input": args.menu_input,
        "menu_chaos": args.menu_chaos,
    }
    rows = []
    for row in run_all(seeds, options, max(1, args.jobs), args.timeout):
        rows.append(row)
        mark = ("FAIL" if row["outcome"] in autoplay.FAILURES
                else "ANOM" if row["anomalies"] else "ok  ")
        print(f"{mark} seed {row['seed']:>4}  {row['outcome']:<11} "
              f"stages={row['stages_cleared']:<3} won={row['battles_won']:<3} "
              f"{row['map']} {row['position']}  {row['detail']}", flush=True)
        for anomaly in row["anomalies"][:3]:
            print(f"       anomaly on {anomaly['map']}: {anomaly['check']}: {anomaly['detail']}")
    rows.sort(key=lambda row: row["seed"])

    outcomes: dict[str, int] = {}
    for row in rows:
        outcomes[row["outcome"]] = outcomes.get(row["outcome"], 0) + 1
    failures = [row for row in rows if row["outcome"] in autoplay.FAILURES or row["anomalies"]]
    balance = run_statistics([run for row in rows for run in row["run_records"]])
    menus: dict[str, dict[str, int]] = {}
    for row in rows:
        for kind, counts in row.get("menus", {}).items():
            total = menus.setdefault(kind, {})
            for key, value in counts.items():
                total[key] = total.get(key, 0) + value
    anomalies: dict[str, int] = {}
    for row in rows:
        for anomaly in row["anomalies"]:
            key = f"{anomaly['check']}: {anomaly['detail']}"
            anomalies[key] = anomalies.get(key, 0) + 1
    summary = {"options": options, "outcomes": outcomes, "balance": balance, "menus": menus,
               "anomalies": dict(sorted(anomalies.items(), key=lambda item: -item[1])), "runs": rows}
    path = autoplay.ARTIFACTS / "autoplay_summary.json"
    path.write_text(json.dumps(summary, indent=1) + "\n", encoding="utf-8")
    print_statistics(balance)
    if menus:
        print("  menus answered with presses: " + ", ".join(
            f"{kind} {c['choices']} ({c['moves']} cursor moves, {c['stray']} stray)"
            for kind, c in sorted(menus.items())))
    print(f"\n{len(rows)} seeds: " + ", ".join(f"{n} {k}" for k, n in sorted(outcomes.items()))
          + f", {sum(bool(row['anomalies']) for row in rows)} with anomalies -> {path}")
    for finding, seeds_with_it in list(summary["anomalies"].items())[:12]:
        print(f"  anomaly in {seeds_with_it} seed(s): {finding}")
    for row in failures:
        flags = " --new-game" * args.new_game + f" --runs {args.runs}" * (args.runs != 1)
        why = row["outcome"] if row["outcome"] in autoplay.FAILURES else "anomaly"
        print(f"  reproduce: python3 tools/pyboy_smoke/autoplay.py --seed {row['seed']}{flags}"
              f"   # {why} at {row['map']}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
