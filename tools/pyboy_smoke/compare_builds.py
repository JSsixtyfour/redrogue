"""Compare builds: play the same seeds from NEW GAME on the debug, Blue and Red
ROMs and report what differs.

    make compare_builds
    make compare_builds COMPARE_ARGS='--seeds 1-32 --runs 2 --vary'
    python3 tools/pyboy_smoke/compare_builds.py --seeds 3 --builds pokeblue_debug,pokeblue

Every bot run and smoke test plays pokeblue_debug, but players get pokered and
pokeblue. The debug build is not just the release plus a menu: _DEBUG changes
text scrolling (TX_SCROLL never pauses), overworld input (SELECT counts),
B-held trainer and script skips, crash traps, and the whole code layout. Red
and Blue share code but not version data. So a bug can live in one build only.

Each build plays every seed with all of autoplay's checks (run_autoplay.run_all,
one process per seed). The report lists, per build, the failed runs and the
anomaly checks, and flags any failure or check that one build hits and another
does not. Per seed and pair of builds it also gives where the two runs first
part ways: the first event (map entered, battle, stage) that differs, with the
frame gap just before it.

Expect every pair to split sooner or later; a split is not a finding. Measured
2026-10-20 by stepping two builds in lockstep: RAM matches (bar frame-phase
bytes) until the main code's Random is interrupted by VBlank's own Random call
at a different instruction in each build (Blue at $3AE9, after the slot index
is stored; Red at $3AE5, before it). Both states stay valid, but the draws
reorder and the battle plays out differently. Which instruction VBlank lands on
is set by the main code's cycle budget per frame, which already differs by
then (Red's battle transition was 44 tiles ahead on the same frame). Red's
title screen is also 8 frames shorter than Blue's, which every event's frame
shows; that offset alone does not change play.
So the per-build failure and anomaly totals are the comparison; the splits
say how far the builds stayed comparable, and a split before the first battle
is worth reading.

Writes artifacts/build_compare.json. Exits non-zero when any build has a failed
run or an anomaly; the summary says which build.
"""
from __future__ import annotations

import argparse
import json
import sys
from itertools import combinations
from pathlib import Path

import autoplay
import coverage_inventory
import run_autoplay

SUMMARY = autoplay.ARTIFACTS / "build_compare.json"
# The events that say where a run went; frames and positions are left out,
# since builds that differ in timing put the same event on different frames.
EVENT_FIELDS = ("kind", "map", "opponent", "stage", "result", "door")
PATH_EVENTS = {"start", "enter_map", "battle_start", "battle_won", "battle_end", "door", "blackout"}


def signature(event: dict[str, object]) -> tuple:
    return tuple(event.get(field) for field in EVENT_FIELDS)


def path_events(report: dict[str, object]) -> list[dict[str, object]]:
    return [e for e in report.get("events", []) if e.get("kind") in PATH_EVENTS]


def first_split(a: list[dict[str, object]], b: list[dict[str, object]]) -> dict[str, object]:
    """Where two runs of one seed part ways: the shared event count, the frame
    gap at the last shared event, and the first event of each side after it."""
    shared = 0
    while shared < min(len(a), len(b)) and signature(a[shared]) == signature(b[shared]):
        shared += 1
    last = shared - 1
    return {
        "shared_events": shared,
        "identical": shared == len(a) == len(b),
        "frame_gap_before": (b[last]["frame"] - a[last]["frame"]) if last >= 0 else 0,
        "last_shared": a[last] if last >= 0 else None,
        "split": [a[shared] if shared < len(a) else None, b[shared] if shared < len(b) else None],
    }


def play_build(rom: str, seeds: list[int], options: dict[str, object], jobs: int,
               timeout: float) -> dict[int, dict[str, object]]:
    autoplay.ROM = rom  # the parent's report paths (a hung seed's row)
    coverage_inventory.code_labels(rom)  # once, before the workers (autoplay_screen.py)
    rows = {}
    for row in run_autoplay.run_all(seeds, options | {"rom": rom, "new_game": True}, jobs, timeout):
        failed = row["outcome"] in autoplay.FAILURES or row["anomalies"]
        print(f"  {rom:<15} seed {row['seed']:>4}: {'FAIL' if failed else 'ok  '} {row['outcome']}, "
              f"{row['stages_cleared']} stages, {len(row['anomalies'])} anomalies", flush=True)
        rows[row["seed"]] = row
    return rows


def load_report(row: dict[str, object]) -> dict[str, object]:
    try:
        return json.loads(Path(row["report"]).read_text(encoding="utf-8"))
    except (OSError, TypeError, ValueError):
        return {}


def build_totals(rows: dict[int, dict[str, object]]) -> dict[str, object]:
    outcomes: dict[str, int] = {}
    checks: dict[str, list[int]] = {}
    for seed, row in rows.items():
        outcomes[row["outcome"]] = outcomes.get(row["outcome"], 0) + 1
        for anomaly in row["anomalies"]:
            seeds = checks.setdefault(anomaly["check"], [])
            if seed not in seeds:
                seeds.append(seed)
    runs = [run for row in rows.values() for run in row["run_records"]]
    return {
        "outcomes": outcomes,
        "failed_seeds": sorted(s for s, row in rows.items() if row["outcome"] in autoplay.FAILURES),
        "anomaly_checks": checks,
        "balance": run_autoplay.run_statistics(runs) if runs else None,
    }


def compare(results: dict[str, dict[int, dict[str, object]]]) -> dict[str, object]:
    builds = list(results)
    totals = {rom: build_totals(rows) for rom, rows in results.items()}
    # A failure kind or anomaly check one build hits and another never does.
    only = []
    for rom in builds:
        mine = set(totals[rom]["anomaly_checks"]) | {
            results[rom][s]["outcome"] for s in totals[rom]["failed_seeds"]}
        for thing in sorted(mine):
            missing = [other for other in builds if other != rom and thing not in (
                set(totals[other]["anomaly_checks"])
                | {results[other][s]["outcome"] for s in totals[other]["failed_seeds"]})]
            if missing:
                only.append({"build": rom, "what": thing, "not_in": missing,
                             "seeds": totals[rom]["anomaly_checks"].get(thing)
                             or [s for s in totals[rom]["failed_seeds"] if results[rom][s]["outcome"] == thing]})
    pairs = {}
    for a, b in combinations(builds, 2):
        splits = {}
        for seed in sorted(set(results[a]) & set(results[b])):
            ea, eb = (path_events(load_report(results[r][seed])) for r in (a, b))
            if ea and eb:
                splits[seed] = first_split(ea, eb)
        shared = sorted(s["shared_events"] for s in splits.values())
        pairs[f"{a} vs {b}"] = {
            "seeds": len(splits),
            "identical": sum(s["identical"] for s in splits.values()),
            "shared_events_median": shared[len(shared) // 2] if shared else None,
            "split_in_opening": sorted(seed for seed, s in splits.items() if s["shared_events"] < 8),
            "splits": splits,
        }
    return {"builds": builds, "totals": totals, "only_in_one_build": only, "pairs": pairs}


def describe(event: dict[str, object] | None) -> str:
    if event is None:
        return "(run ended)"
    return " ".join(f"{v}" for k, v in event.items() if k in EVENT_FIELDS and v is not None) + \
        f" @{event.get('frame')}"


def print_report(report: dict[str, object]) -> None:
    print()
    for rom, total in report["totals"].items():
        balance = total["balance"] or {}
        print(f"{rom}: {total['outcomes']}, champion rate {balance.get('champion_rate')}, "
              f"stages mean {(balance.get('stages_cleared') or {}).get('mean')}; "
              f"failed seeds {total['failed_seeds'] or 'none'}; "
              f"anomalies {dict((k, len(v)) for k, v in total['anomaly_checks'].items()) or 'none'}")
    for row in report["only_in_one_build"]:
        print(f"  ONLY {row['build']}: {row['what']} (seeds {row['seeds']}), not in {', '.join(row['not_in'])}")
    for name, pair in report["pairs"].items():
        print(f"{name}: {pair['identical']}/{pair['seeds']} seeds play identically, "
              f"median {pair['shared_events_median']} shared events; "
              f"split in the opening: {pair['split_in_opening'] or 'none'}")
        for seed in pair["split_in_opening"][:8]:
            split = pair["splits"][seed]
            print(f"    seed {seed}: after {describe(split['last_shared'])} "
                  f"(gap {split['frame_gap_before']} frames): "
                  f"{describe(split['split'][0])} | {describe(split['split'][1])}")
    print(f"-> {SUMMARY}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Play the same seeds on several builds and compare.")
    parser.add_argument("--seeds", default="1-8")
    parser.add_argument("--builds", default=",".join(autoplay.ROMS),
                        help=f"comma-separated, from {', '.join(autoplay.ROMS)}")
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--max-frames", type=int, default=1_000_000)
    parser.add_argument("--vary", action="store_true", help="each seed's own profile (autoplay --vary)")
    parser.add_argument("--difficulty", choices=autoplay.DIFFICULTIES, default=None)
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--timeout", type=float, default=900)
    args = parser.parse_args(argv)
    builds = [b.strip() for b in args.builds.split(",") if b.strip()]
    unknown = [b for b in builds if b not in autoplay.ROMS]
    if unknown or len(builds) < 2:
        parser.error(f"need two or more of {autoplay.ROMS}, got {builds}")

    seeds = run_autoplay.parse_seeds(args.seeds)
    options = {"runs": args.runs, "max_frames": args.max_frames, "vary": args.vary,
               "difficulty": args.difficulty}
    results = {rom: play_build(rom, seeds, options, max(1, args.jobs), args.timeout) for rom in builds}
    report = compare(results)
    SUMMARY.write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    print_report(report)
    bad = [rom for rom, total in report["totals"].items() if total["failed_seeds"] or total["anomaly_checks"]]
    if bad:
        print(f"failed runs or anomalies in: {', '.join(bad)}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
