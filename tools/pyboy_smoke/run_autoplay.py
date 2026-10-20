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

With --branches N, each seed also snapshots its key moments (battle start, the
reward and gift pickers, the lobby) and plays N short random-input branches
from up to --snapshots of each kind, with the same checks (autoplay_branch.py).
A branch finding fails the batch too and prints the command that replays it.

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
        "branches": data.get("branches"),
        "difficulty": data.get("difficulty"),
        "profile": data.get("profile"),
        "save_findings": (data.get("save_checks") or {}).get("findings", []),
        "power_cuts": [(cut["cut"], cut["loads"]) for cut in (data.get("save_checks") or {}).get("power_cuts", [])],
        "coverage": (data.get("coverage") or {}).get("hit"),
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


def branch_findings(row: dict[str, object]) -> list[dict[str, object]]:
    return (row.get("branches") or {}).get("findings", [])


def branch_statistics(rows: list[dict[str, object]]) -> dict[str, object]:
    """Branches played per snapshot kind, and every finding with its replay
    command, grouped by what was found."""
    totals: dict[str, dict[str, int]] = {}
    findings = []
    longest_quiet = {"frames": 0}
    for row in rows:
        branches = row.get("branches") or {}
        quiet = branches.get("longest_quiet") or {"frames": 0}
        if quiet["frames"] > longest_quiet["frames"]:
            longest_quiet = {"seed": row["seed"], **quiet}
        for kind, counts in branches.get("totals", {}).items():
            total = totals.setdefault(kind, {})
            for key, value in counts.items():
                total[key] = total.get(key, 0) + value
        for finding in branch_findings(row):
            what = [finding["outcome"] + (f": {finding['detail']}" if finding["detail"] else "")]                 if finding["outcome"] != "ok" else []
            what += [f"{a['check']}: {a['detail']}" for a in finding["anomalies"]]
            findings.append({"seed": row["seed"], "key": finding["key"], "at": finding["at"],
                             "what": what, "replay": finding["replay"]})
    return {"totals": totals, "longest_quiet": longest_quiet, "findings": findings}


def print_branching(branching: dict[str, object]) -> None:
    totals = branching["totals"]
    print("  branches: " + ", ".join(
        f"{kind} {c['branches']} ({c['frames']} frames, {c['findings']} with findings)"
        for kind, c in sorted(totals.items()))
        + f"; longest stretch without an input poll {branching['longest_quiet']['frames']} frames")
    quiet = branching["longest_quiet"]
    if quiet.get("key"):
        print(f"    ({quiet['key']} on {quiet.get('map')}, in "
              + " < ".join(quiet.get("stack") or [str(quiet.get("in"))])[:160] + ")")
    for finding in branching["findings"][:12]:
        print(f"  branch finding, seed {finding['seed']} {finding['key']} on {finding['at'].get('map')}: "
              + "; ".join(finding["what"][:3]))
        print(f"    replay: {finding['replay']}")


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
    parser.add_argument("--branches", type=int, default=0,
                        help="random-input branches per snapshot of a key moment "
                             "(battle start, reward and gift pickers, lobby); see autoplay_branch.py")
    parser.add_argument("--snapshots", type=int, default=3, help="snapshots branched per kind and seed")
    parser.add_argument("--branch-frames", type=int, default=3000, help="frames each branch plays")
    parser.add_argument("--freeze-frames", type=int, default=None,
                        help="frames without an input poll before a branch counts as frozen")
    parser.add_argument("--save-checks", action="store_true",
                        help="save, reload and power-cut checks at lobby arrivals (save_reload.py)")
    parser.add_argument("--vary", action="store_true",
                        help="each seed plays its own profile (battle policy, ironman, errands, "
                             "items in battle, starter); see autoplay.Profile")
    parser.add_argument("--difficulty", choices=autoplay.DIFFICULTIES, default=None,
                        help="LEVELS setting (default HARD, the balance baseline; --vary mixes them)")
    parser.add_argument("--coverage", action="store_true",
                        help="record which code labels run and write artifacts/coverage_summary.json "
                             "(autoplay_coverage.py)")
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
        "branches": args.branches,
        "snapshots": args.snapshots,
        "branch_frames": args.branch_frames,
        "freeze_frames": args.freeze_frames,
        "coverage": args.coverage,
        "difficulty": args.difficulty,
        "vary": args.vary,
        "save_checks": args.save_checks,
    }
    rows = []
    for row in run_all(seeds, options, max(1, args.jobs), args.timeout):
        rows.append(row)
        findings = branch_findings(row)
        mark = ("FAIL" if row["outcome"] in autoplay.FAILURES
                else "ANOM" if row["anomalies"] else "BRCH" if findings else "ok  ")
        print(f"{mark} seed {row['seed']:>4}  {row['outcome']:<11} "
              f"stages={row['stages_cleared']:<3} won={row['battles_won']:<3} "
              f"{row['map']} {row['position']}  {row['detail']}", flush=True)
        for anomaly in row["anomalies"][:3]:
            print(f"       anomaly on {anomaly['map']}: {anomaly['check']}: {anomaly['detail']}")
        for finding in findings[:3]:
            print(f"       branch {finding['key']}: {finding['outcome']} {finding['detail']}"
                  + "".join(f"; {a['check']}: {a['detail']}" for a in finding["anomalies"][:2]))
    rows.sort(key=lambda row: row["seed"])
    # Each seed's label list goes to the coverage map, not the batch summary.
    hit_lists = {f"seed{row['seed']}": row.pop("coverage") for row in rows if row.get("coverage")}

    outcomes: dict[str, int] = {}
    for row in rows:
        outcomes[row["outcome"]] = outcomes.get(row["outcome"], 0) + 1
    failures = [row for row in rows if row["outcome"] in autoplay.FAILURES or row["anomalies"]]
    branching = branch_statistics(rows) if args.branches else None
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
               "branching": branching,
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
    if branching:
        print_branching(branching)
    if args.save_checks:
        save_findings = [(row["seed"], finding) for row in rows for finding in row.get("save_findings") or []]
        loads: dict[str, int] = {}
        for row in rows:
            for _cut, outcome in row.get("power_cuts") or []:
                loads[outcome] = loads.get(outcome, 0) + 1
        print(f"  save checks: power cuts load {loads}; {len(save_findings)} finding(s)")
        for seed, finding in save_findings[:12]:
            print(f"    seed {seed}: {finding['check']}: " + json.dumps(
                {k: v for k, v in finding.items() if k != "check"})[:300])
    if args.coverage:
        import autoplay_coverage

        if hit_lists:
            autoplay_coverage.print_summary(autoplay_coverage.write_summary(hit_lists), top=12)
            print(f"  coverage map -> {autoplay_coverage.SUMMARY}")
    for row in failures:
        flags = " --new-game" * args.new_game + f" --runs {args.runs}" * (args.runs != 1)
        why = row["outcome"] if row["outcome"] in autoplay.FAILURES else "anomaly"
        print(f"  reproduce: python3 tools/pyboy_smoke/autoplay.py --seed {row['seed']}{flags}"
              f"   # {why} at {row['map']}")
    save_failed = any(row.get("save_findings") for row in rows)
    return 1 if failures or save_failed or (branching and branching["findings"]) else 0


if __name__ == "__main__":
    sys.exit(main())
