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
    routine_run_counts: dict[str, int] = {}
    routine_files: dict[str, str] = {}
    routine_names: dict[str, str] = {}
    for label in labels:
        name, ran = label["name"], seeds_per_label[label["name"]]
        row = files[label["file"]]
        row["labels"] += 1
        row["labels_run"] += bool(ran)
        if label["global"]:
            row["routines"] += 1
            row["routines_run"] += bool(ran)
            routine_ran[name] = bool(ran)
            # Assembly can define same-named labels in separate source files.
            # Compare source/name identities so a moved or removed label is
            # inventory drift, not a newly covered routine. Multiple source
            # definitions of the same symbol in one file intentionally share
            # one identity and one runtime hit count.
            identity = f"{label['file']}::{name}"
            routine_run_counts[identity] = ran
            routine_files[identity] = label["file"]
            routine_names[identity] = name
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
        # Keep complete identity and hit evidence. Older summaries only stored
        # the unhit names, which made additions/renames look like new coverage.
        "routine_identity": "source-name-v1",
        "routine_run_counts": dict(sorted(routine_run_counts.items())),
        "routine_files": dict(sorted(routine_files.items())),
        "routine_names": dict(sorted(routine_names.items())),
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
    """Compare only identities and hit evidence the two maps can establish.

    New summaries carry complete per-routine counts. Legacy summaries do not:
    they prove that a name in `never` was present and unhit, and `once` proves
    that a global name with one hit was present and hit, but omission from
    either list is ambiguous (it may have run more than once or be new).
    """
    def never(summary: dict[str, object]) -> set[str]:
        return {name for row in summary["files"].values() for name in row["never"]}

    old_counts = old.get("routine_run_counts")
    new_counts = new.get("routine_run_counts")
    old_dead = {name for names in old.get("known_dead", {}).values() for name in names}
    new_dead = {name for names in new.get("known_dead", {}).values() for name in names}
    comparison_dead = old_dead | new_dead
    old_never = never(old) | old_dead
    new_routine_names = new.get("routine_names", {})
    if not isinstance(new_routine_names, dict):
        new_routine_names = {}

    def routine_name(identity: str) -> str:
        return new_routine_names.get(identity, identity.rsplit("::", 1)[-1])

    exact_identity = (old.get("routine_identity") == "source-name-v1" and
                      new.get("routine_identity") == "source-name-v1")
    if (isinstance(old_counts, dict) and isinstance(new_counts, dict) and
            exact_identity):
        old_ids, new_ids = set(old_counts), set(new_counts)
        common = old_ids & new_ids
        gained = sorted(identity for identity in common
                        if routine_name(identity) not in comparison_dead
                        and not old_counts[identity] and new_counts[identity])
        lost = sorted(identity for identity in common
                      if routine_name(identity) not in comparison_dead
                      and old_counts[identity] and not new_counts[identity])
        removed = sorted(old_ids - new_ids)
        added = sorted(new_ids - old_ids)
        unclassified: list[str] = []
        uncertain: list[str] = []
        complete = True
    elif isinstance(new_counts, dict):
        new_ids = set(new_counts)
        new_label_names = {identity: routine_name(identity) for identity in new_ids}
        old_once = {name for name in old.get("once", []) if "." not in name}
        gained = sorted(identity for identity in new_ids
                        if new_label_names[identity] in old_never
                        and new_label_names[identity] not in comparison_dead
                        and new_counts[identity])
        lost_names = {name for name in old_once & set(new_label_names.values())
                      if name not in comparison_dead and
                      not any(new_counts[identity] for identity in new_ids
                              if new_label_names[identity] == name)}
        lost = sorted(identity for identity in new_ids
                      if new_label_names[identity] in lost_names)
        removed = sorted(identity for identity in old_never
                         if not any(new_label_names[other] == identity.rsplit("::", 1)[-1]
                                    for other in new_ids))
        # The legacy format cannot distinguish a previously hit routine from
        # a new name unless it appeared in `once` or `never`.
        unclassified = sorted(identity for identity in new_ids
                              if new_label_names[identity] not in old_never | old_once)
        added = []
        uncertain = []
        complete = False
    else:
        # Neither map records complete identities or hit counts. A change in
        # the never lists could reflect source inventory drift, so report it
        # as uncertain rather than claiming that a routine became reached.
        new_never = never(new)
        gained = []
        lost = []
        removed = []
        added = []
        unclassified = []
        old_ids = {f"{file}::{name}" for file, row in old["files"].items()
                   for name in row["never"]}
        new_ids = {f"{file}::{name}" for file, row in new["files"].items()
                   for name in row["never"]}
        uncertain = sorted(old_ids ^ new_ids)
        complete = False

    new_files = new.get("routine_files", {})
    if not isinstance(new_files, dict):
        new_files = {}
    by_file: dict[str, list[str]] = defaultdict(list)
    for identity in gained:
        by_file[new_files.get(identity, "(source unknown)")].append(routine_name(identity))

    if complete:
        print(f"\nversus the old map: {len(gained)} routines newly reached, "
              f"{len(lost)} no longer reached; {len(added)} added and {len(removed)} "
              f"removed/renamed from the routine inventory; routines "
              f"{old['totals']['routines_run']} -> {new['totals']['routines_run']}")
    else:
        print(f"\nversus the legacy map: {len(gained)} confirmed newly reached, "
              f"{len(lost)} confirmed no longer reached (old one-hit evidence), "
              f"{len(removed)} old never/dead names absent now; "
              f"{len(unclassified)} current routines lack exact old hit evidence; "
              f"routine inventory {old['totals']['routines']} -> {new['totals']['routines']}")
    for file, names in sorted(by_file.items(), key=lambda item: -len(item[1]))[:top]:
        print(f"    +{len(names):<3} {file}: {', '.join(names[:5])}{' ...' if len(names) > 5 else ''}")
    if lost:
        lost_display = [routine_name(identity) for identity in lost]
        print(f"  no longer reached: {', '.join(lost_display[:12])}"
              f"{' ...' if len(lost_display) > 12 else ''}")
    if removed:
        display = [routine_name(identity) for identity in removed]
        print(f"  no longer in inventory: {', '.join(display[:12])}"
              f"{' ...' if len(display) > 12 else ''}")
    if added:
        display = [routine_name(identity) for identity in added]
        print(f"  new inventory names: {', '.join(display[:12])}"
              f"{' ...' if len(display) > 12 else ''}")
    if uncertain:
        print(f"  unconfirmed never-list changes: {', '.join(uncertain[:12])}"
              f"{' ...' if len(uncertain) > 12 else ''}")
    return {"gained": gained, "lost": lost, "removed": removed, "added": added,
            "unclassified": unclassified, "uncertain": uncertain,
            "inventory_complete": complete}


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
