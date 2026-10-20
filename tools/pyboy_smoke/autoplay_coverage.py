"""Code coverage map: which routines and branches autoplay never runs.

`--coverage` on autoplay.py / run_autoplay.py hooks every code label in the
debug ROM (coverage_inventory.py) until it first runs; each seed's report
then lists the labels it ran. This merges those lists, from main runs and
their branches, into a per-file map:

- a routine is a global label, a branch a local one (`.loop`, `.alreadyKnown`):
  a routine that runs with a local label that never does is a path no play
  took;
- `never` lists routines no seed ran, by file, most first;
- `once` lists labels only one seed ran: covered, but thinly.

Coverage hooks do not change play: a seed plays the same events on the same
frames with and without them (measured 2026-10-20, Debug 2 and new game).

    make autoplay AUTOPLAY_ARGS='--seeds 1-16 --coverage'    # writes artifacts/coverage_summary.json
    python3 tools/pyboy_smoke/autoplay_coverage.py            # re-summarise the last reports
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

import coverage_inventory

ARTIFACTS = coverage_inventory.ARTIFACTS
SUMMARY = ARTIFACTS / "coverage_summary.json"

# Routines no play can reach by design, kept out of the `never` lists (so the
# gaps that remain are real) and counted on their own. Reason, then routines.
KNOWN_DEAD = {
    "Poke Balls and X items cannot be obtained in Red Rogue (2026-10-20)": (
        "ItemUseBall", "ThrowBallAtTrainerMon", "BoxFullCannotThrowBall",
        "ItemUseXAccuracy", "ItemUseXStat", "ItemUseGuardSpec", "ItemUseDireHit"),
}
DEAD = {name for names in KNOWN_DEAD.values() for name in names}


def summarise(hit_lists: dict[str, list[str]]) -> dict[str, object]:
    """hit_lists: run name (seed) -> labels it ran."""
    labels, hooks, inferred = coverage_inventory.plan()
    seeds_per_label = Counter(name for hits in hit_lists.values()
                              for name in coverage_inventory.ran_labels(hits, inferred))
    untracked = sorted(label["name"] for label in labels
                       if label["name"] not in hooks and label["name"] not in inferred)
    files: dict[str, dict[str, object]] = defaultdict(lambda: {
        "routines": 0, "routines_run": 0, "labels": 0, "labels_run": 0,
        "never": [], "branches_never": []})
    once = []
    routine_ran: dict[str, bool] = {}
    for label in labels:
        name, ran = label["name"], seeds_per_label[label["name"]]
        row = files[label["file"]]
        row["labels"] += 1
        row["labels_run"] += bool(ran)
        if label["global"]:
            row["routines"] += 1
            row["routines_run"] += bool(ran)
            routine_ran[name] = bool(ran)
            if not ran and name not in DEAD:
                row["never"].append(name)
        if ran == 1 and len(hit_lists) > 1:
            once.append(name)
    # A branch label never taken inside a routine that did run.
    for label in labels:
        name = label["name"]
        if not label["global"] and not seeds_per_label[name]:
            parent = name.split(".", 1)[0]
            if routine_ran.get(parent):
                files[label["file"]]["branches_never"].append(name)
    total = Counter()
    for row in files.values():
        for key in ("routines", "routines_run", "labels", "labels_run"):
            total[key] += row[key]
    ordered = dict(sorted(files.items(), key=lambda item: (-len(item[1]["never"]), item[0])))
    return {
        "runs": sorted(hit_lists),
        "totals": dict(total),
        "files": ordered,
        "once": sorted(once),
        "known_dead": {reason: list(names) for reason, names in KNOWN_DEAD.items()},
        "inferred": len(inferred),
        "untracked": untracked,
    }


def percent(part: int, whole: int) -> str:
    return f"{100 * part / whole:.0f}%" if whole else "-"


def print_summary(summary: dict[str, object], top: int = 25) -> None:
    total = summary["totals"]
    print(f"\ncoverage over {len(summary['runs'])} run(s): routines {total['routines_run']}/"
          f"{total['routines']} ({percent(total['routines_run'], total['routines'])}), "
          f"all code labels {total['labels_run']}/{total['labels']} "
          f"({percent(total['labels_run'], total['labels'])}); "
          f"{len(summary['once'])} labels ran in only one run; {summary['inferred']} labels "
          f"inferred, {len(summary['untracked'])} untracked (coverage_inventory.hook_plan)")
    for reason, names in summary.get("known_dead", {}).items():
        print(f"  known dead, not listed below ({len(names)} routines): {reason}")
    print(f"  files with the most routines never run (of {len(summary['files'])} files):")
    for file, row in list(summary["files"].items())[:top]:
        if not row["never"]:
            break
        print(f"    {file:<52} {row['routines_run']:>4}/{row['routines']:<4} routines run, "
              f"never: {', '.join(row['never'][:4])}{' ...' if len(row['never']) > 4 else ''}")


def compare(old: dict[str, object], new: dict[str, object], top: int = 20) -> dict[str, object]:
    """Routines the new map reached that the old did not, and the reverse,
    by file: what a change to the bot (or the game) added or lost."""
    def never(summary):
        return {name for row in summary["files"].values() for name in row["never"]}

    # Known-dead routines are left out of `never` lists, so a map made before
    # one joined KNOWN_DEAD would otherwise show it as newly reached.
    old_never, new_never = never(old) - DEAD, never(new) - DEAD
    gained, lost = sorted(old_never - new_never), sorted(new_never - old_never)
    by_file: dict[str, list[str]] = defaultdict(list)
    for file, row in old["files"].items():
        for name in row["never"]:
            if name in old_never - new_never:
                by_file[file].append(name)
    print(f"\nversus the old map: {len(gained)} routines newly reached, {len(lost)} no longer reached; "
          f"routines {old['totals']['routines_run']} -> {new['totals']['routines_run']}")
    for file, names in sorted(by_file.items(), key=lambda item: -len(item[1]))[:top]:
        print(f"    +{len(names):<3} {file}: {', '.join(names[:5])}{' ...' if len(names) > 5 else ''}")
    if lost:
        print(f"  no longer reached: {', '.join(lost[:12])}{' ...' if len(lost) > 12 else ''}")
    return {"gained": gained, "lost": lost}


def load_reports(paths: list[Path]) -> dict[str, list[str]]:
    hit_lists = {}
    for path in paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        coverage = data.get("coverage")
        if coverage:
            hit_lists[path.stem] = coverage["hit"]
    return hit_lists


def write_summary(hit_lists: dict[str, list[str]]) -> dict[str, object]:
    summary = summarise(hit_lists)
    SUMMARY.write_text(json.dumps(summary, indent=1) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Merge autoplay coverage into a per-file map.")
    parser.add_argument("reports", nargs="*", type=Path,
                        help="autoplay reports (default: artifacts/autoplay_seed*.json)")
    parser.add_argument("--top", type=int, default=25)
    parser.add_argument("--compare", type=Path, default=None,
                        help="an earlier coverage_summary.json: list what is newly reached or lost")
    args = parser.parse_args(argv)
    paths = args.reports or sorted(ARTIFACTS.glob("autoplay_seed*.json"))
    hit_lists = load_reports(paths)
    if not hit_lists:
        print("no reports with coverage; run autoplay with --coverage first")
        return 1
    summary = write_summary(hit_lists)
    print_summary(summary, args.top)
    if args.compare:
        compare(json.loads(args.compare.read_text(encoding="utf-8")), summary, args.top)
    print(f"-> {SUMMARY}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
