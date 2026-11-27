"""Nightly runs: test one commit with every long-running check, keep the
report, and flag what got worse since the last night.

    python3 tools/pyboy_smoke/nightly.py                  # master, every suite
    python3 tools/pyboy_smoke/nightly.py --suites smoke,lobby --force
    make nightly NIGHTLY_ARGS='--ref my-branch'

The commit is tested in its own worktree (--worktree, default
../redrogue_nightly), checked out clean at --ref, never in the shared tree,
where other sessions may be halfway through an edit. Nothing is committed or
pushed. The worktree is reset to the commit each night; do not work in it.

Suites (all by default, in this order):

    build      make all three ROMs
    smoke      run_smoke.py (the whole PyBoy suite)
    audit      make audit (static analyzers, source-only tests)
    lobby      run_autoplay: Debug 2 seeds 1-24, with branching
    newgame    run_autoplay: new-game seeds 1-16, 2 runs, --vary, save checks, coverage map
    cgb        run_autoplay: CGB seeds 1-4, --vary, save checks, branches, coverage map
    cgb_full   CGB full circuits with save checks
    menus      varied real-input item use and directed PC, rental and lobby menus
    room_menu  cold-start Room PC exercises across blackouts
    discovery  rotating stronger-player cold starts
    directed   Endless and key-item save/Continue integration checks
    stack      runtime stack headroom and SRAM latch checks on DMG and CGB
    builds     compare_builds: seeds 1-8 on the debug, Blue and Red builds
    sram       sram_fuzz: seeds 1-4
    battle_fuzz  random battles of unusual moves with random input
    menu_fuzz  random input in Bill's PC, the START menu and the slot machine
    guards     one rotating share of standalone guards, all on Sunday

Seeds (SEED_PLAN): most suites play a few fixed seeds, which the comparisons with
other nights use, plus fresh ones drawn from the date, so every night plays new
games and the same night can be replayed. newgame keeps all its seeds: the
coverage comparison needs the same games.

Each night writes <reports>/<date>_<sha>/ (default ../redrogue_nightly_reports):
the logs, each suite's summary JSON, copies of every failed seed's report,
state and screenshot when available, report.json, and
report.md with a replay command for each finding, pinned to the commit. The
previous night's report.json is the baseline: a smoke test that newly fails,
an anomaly or failure kind not seen before, a champion rate or coverage drop
are listed as regressions. Coverage loss requires the same routine to have
been reached on each of three prior nights.

Regular nights have a two-hour budget, so menu_fuzz and the guards run. Sunday has three hours for the full
standalone guard registry. Exits 1 for new regressions and 2 for runner failures. The Windows task uses
nightly_windows.ps1 with --force so the scheduled run stays daily.
"""
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import os
import random
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import traceback
from collections import Counter
from contextlib import contextmanager
from urllib.parse import quote
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SMOKE_DIR = Path("tools/pyboy_smoke")
ARTIFACTS = SMOKE_DIR / "artifacts"
FAILURES = ("stalled", "frame_limit", "error", "crashed", "hung")
CHAMPION_DROP = 0.15  # a champion rate this far below last night's counts as a regression
COVERAGE_NIGHTS = 3
DAILY_BUDGET = 7200  # 3600 ran out before menu_fuzz (2026-11-25): the suites up to battle_fuzz took 3192 s
WEEKLY_BUDGET = 10800
LEGACY_SUITES = ("build", "smoke", "audit", "lobby", "newgame", "cgb", "builds", "sram")
AUTOPLAY_COMMAND = ["python3", str(SMOKE_DIR / "run_autoplay.py")]
DIRECTED_TESTS = [
    "integration_endless_journey",
    "integration_endless_save_boundaries",
    "integration_key_item_persistence",
    "integration_service_history.DirectedServiceHistoryIntegrationTest."
    "test_three_natural_runs_clerk_nurse_clerk_with_exact_transaction_deltas",
]

# name -> (command, timeout in seconds, summary files to keep)
SUITES = {
    "build": (["make", "-j6", "pokered.gbc", "pokeblue.gbc", "pokeblue_debug.gbc"], 1800, []),
    "smoke": (["python3", str(SMOKE_DIR / "run_smoke.py")], 1800, []),
    "audit": (["make", "audit"], 2400, []),
    "lobby": (["python3", str(SMOKE_DIR / "run_autoplay.py"), "--seeds", "1-24", "--jobs", "6",
               "--branches", "4", "--snapshots", "2"], 5400, ["autoplay_summary.json"]),
    "newgame": (["python3", str(SMOKE_DIR / "run_autoplay.py"), "--seeds", "1-16", "--jobs", "6",
                 "--new-game", "--runs", "2", "--vary", "--save-checks", "--coverage",
                 "--max-frames", "2500000", "--timeout", "2400"], 7200,
                ["autoplay_summary.json", "coverage_summary.json"]),
    "cgb": (["python3", str(SMOKE_DIR / "run_autoplay.py"), "--seeds", "1-4", "--jobs", "2",
             "--stages", "12", "--vary", "--save-checks", "--coverage", "--cgb",
             "--branches", "2", "--snapshots", "1", "--branch-frames", "900", "--timeout", "2400"],
            5400, ["autoplay_summary_cgb.json", "coverage_summary_cgb.json"]),
    "cgb_full": (AUTOPLAY_COMMAND + ["--seeds", "1-16", "--jobs", "4", "--cgb",
                    "--difficulty", "NORMAL", "--player", "strong",
                    "--save-checks", "--coverage", "--timeout", "600"], 1200,
                 ["autoplay_summary_cgb.json", "coverage_summary_cgb.json"]),
    "menus": (AUTOPLAY_COMMAND + ["--seeds", "1-16", "--jobs", "6", "--runs", "2",
                  "--stages", "10", "--vary", "--errands", "all", "--save-checks", "--coverage",
                  "--max-frames", "750000", "--timeout", "450"], 1200,
              ["autoplay_summary.json", "coverage_summary.json"]),
    "room_menu": (AUTOPLAY_COMMAND + ["--seeds", "1-4", "--jobs", "4", "--runs", "2",
                     "--new-game", "--vary", "--errands", "roompc", "--save-checks", "--coverage",
                     "--max-frames", "500000", "--timeout", "300"], 600,
                  ["autoplay_summary.json", "coverage_summary.json"]),
    "discovery": (AUTOPLAY_COMMAND + ["--seeds", "17-40", "--jobs", "6", "--new-game",
                      "--runs", "2", "--vary", "--player", "strong", "--save-checks",
                      "--menu-chaos", "0.1",
                      "--coverage", "--max-frames", "2500000", "--timeout", "450"], 1200,
                  ["autoplay_summary.json", "coverage_summary.json"]),
    "directed": (["python3", "-m", "unittest", "-v", *DIRECTED_TESTS], 900, []),
    "stack": (["python3", str(SMOKE_DIR / "audit_runtime_stack_sram.py"), "--dmg-seeds", "3", "--cgb-seeds", "5"],
              600, []),
    "builds": (["python3", str(SMOKE_DIR / "compare_builds.py"), "--seeds", "1-8", "--jobs", "6",
                "--max-frames", "1000000"], 7200, ["build_compare.json"]),
    "sram": (["python3", str(SMOKE_DIR / "sram_fuzz.py"), "--seeds", "1-4", "--matched-controls"], 3600, ["sram_fuzz_summary.json"]),
    "battle_fuzz": (["python3", str(SMOKE_DIR / "battle_fuzz.py"), "--seeds", "1-2000", "--jobs", "6",
                     "--minutes", "8"], 900, ["battle_fuzz.json"]),
    "menu_fuzz": (["python3", str(SMOKE_DIR / "menu_fuzz.py"), "--seeds", "1-120", "--jobs", "6"], 1200,
                  ["menu_fuzz.json"]),
    "guards": (["python3", str(SMOKE_DIR / "run_audits.py")], 5400, []),}
# suite -> (fixed seeds from 1, fresh seeds drawn from the date). Comparisons with other nights
# use only the fixed ones. newgame is absent: its 16 stay fixed, as the coverage control.
SEED_PLAN = {"lobby": (12, 24), "cgb": (2, 4), "cgb_full": (8, 12), "menus": (8, 12), "room_menu": (2, 4),
             "discovery": (0, 32), "builds": (4, 8), "sram": (2, 4), "battle_fuzz": (0, 3000), "menu_fuzz": (0, 240)}
# --quick: a few seeds per suite, to check the runner itself.
QUICK = {"lobby": {"--seeds": "1-2"}, "newgame": {"--seeds": "1-2", "--runs": "1"},
         "cgb": {"--seeds": "1-2", "--stages": "3", "--branches": "1",
                 "--snapshots": "1", "--branch-frames": "300"},
         "cgb_full": {"--seeds": "1-2"},
         "menus": {"--seeds": "1-2", "--stages": "3"},
         "room_menu": {"--seeds": "1-2"},
         "discovery": {"--seeds": "17-18", "--runs": "1"},
         "builds": {"--seeds": "1-2"}, "sram": {"--seeds": "1"}, "battle_fuzz": {"--seeds": "1-12"},
         "menu_fuzz": {"--seeds": "1-4"}}
AUTOPLAY_SUITES = {"lobby", "newgame", "cgb", "cgb_full", "menus", "room_menu", "discovery"}
MENU_MILESTONES = {"pc": "pc_main_menu", "rental": "offer", "roompc": "top_menu"}


def nightly_seeds(name: str, day: dt.date) -> str:
    """This night's --seeds for a suite: its fixed ones, then fresh ones. The date decides them,
    so a run can be repeated and two commits tested the same day play the same games."""
    fixed, fresh = SEED_PLAN[name]
    rng = random.Random(f"{day.isoformat()}/{name}")
    parts = [f"1-{fixed}"] if fixed else []
    if fresh > 200:  # a list this long would not fit a readable command
        first = rng.randrange(10_000, 1_000_000)
        parts.append(f"{first}-{first + fresh - 1}")
    else:
        parts += map(str, sorted(rng.sample(range(10_000, 1_000_000), fresh)))
    return ",".join(parts)


def suite_command(name: str, worktree: Path, day: dt.date, quick: bool) -> list[str]:
    command = list(SUITES[name][0])
    for flag, value in (QUICK.get(name, {}) if quick else {}).items():
        command[command.index(flag) + 1] = value
    if name in SEED_PLAN and not quick:
        command[command.index("--seeds") + 1] = nightly_seeds(name, day)
    if name == "stack" and not quick:
        fresh = random.Random(f"{day.isoformat()}/stack").sample(range(10_000, 1_000_000), 2)
        command[command.index("--dmg-seeds") + 1] = f"3,{fresh[0]}"
        command[command.index("--cgb-seeds") + 1] = f"5,{fresh[1]}"
    if name == "directed":
        command[0:0] = ["env", f"PYTHONPATH={SMOKE_DIR}"]
        if quick:
            command[-len(DIRECTED_TESTS):] = [
                "integration_endless_journey.EndlessJourneyIntegrationTest.test_accept_reaches_and_exits_playable_stage"]
    if name == "guards":
        registry = json.loads((worktree / SMOKE_DIR / "audits.json").read_text(encoding="utf-8"))
        guards = sorted({row["script"] for row in registry["audits"]
                         if row["kind"] == "guard" and not row.get("in_smoke")})
        if quick:
            guards = ["audit_stage_defeat_text.py"]
        elif day.weekday() < 6:
            guards = guards[day.weekday()::6]
        else:
            return command  # Sunday runs the whole guard registry.
        for script in guards:
            command += ["--only", script]
    return command


def replay_command(seed: int, command: list[str]) -> str:
    flags = iter(command[2:])
    replay = ["python3", str(SMOKE_DIR / "autoplay.py"), "--seed", str(seed)]
    for flag in flags:
        if flag in ("--seeds", "--jobs", "--timeout"):
            next(flags)
        else:
            replay.append(flag)
    return shlex.join(replay)


def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def prepare_worktree(worktree: Path, ref: str) -> str:
    sha = git("rev-parse", "--verify", f"{ref}^{{commit}}")
    if not (worktree / ".git").exists():
        git("worktree", "add", "--detach", str(worktree), sha)
    else:
        git("checkout", "--detach", "--force", sha, cwd=worktree)
        git("clean", "-fdq", "-e", "tools/pyboy_smoke/artifacts", "-e", "builds", cwd=worktree)
    return sha


def run_suite(name: str, worktree: Path, night: Path, day: dt.date,
              quick: bool = False, remaining: float = DAILY_BUDGET) -> dict[str, object]:
    _, timeout, keep = SUITES[name]
    command = suite_command(name, worktree, day, quick)
    log = night / f"{name}.log"
    # The scheduled runner is the shared tree's nightly.py, but the tested commit can be
    # older than a suite just added there. A script missing from both still runs and fails.
    newer = [part for part in command if part.startswith(f"{SMOKE_DIR}/")
             and (ROOT / part).exists() and not (worktree / part).exists()]
    if newer:
        log.write_text(f"skipped: {newer[0]} is not in the tested commit\n", encoding="utf-8")
        return {"suite": name, "exit": 0, "seconds": 0, "command": shlex.join(command),
                "skipped": f"{newer[0]} is not in the tested commit", "tail": []}
    if name == "sram":
        artifacts = night / "sram_evidence"
        artifacts.mkdir()
        result = execute_suite(name, command, worktree, night, log, min(timeout, remaining), keep, artifacts)
        if not has_issue(result):
            shutil.rmtree(artifacts)
    elif name in AUTOPLAY_SUITES or name in ("builds", "stack", "battle_fuzz", "menu_fuzz"):
        # Keep suites and attempts separate, including failure snapshots with the same seed.
        with tempfile.TemporaryDirectory(prefix=f".{name}-", dir=night) as scratch:
            result = execute_suite(name, command, worktree, night, log, min(timeout, remaining),
                                   keep, Path(scratch))
    else:
        result = execute_suite(name, command, worktree, night, log, min(timeout, remaining), keep)
    if name == "guards":
        result["rotation"] = day.weekday()
    if name in SEED_PLAN:
        result["seeds"] = command[command.index("--seeds") + 1]
        if not SEED_PLAN[name][0]:
            result["rotating_seeds"] = True
    return result


def stop_suite(process: subprocess.Popen) -> None:
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def copy_inventory_cache(source: Path, destination: Path) -> None:
    """Reuse the worker's symbol-hash-keyed cache across suites on this ROM build."""
    for cache in source.glob("coverage_inventory_*_v*_*.json"):
        target = destination / cache.name
        if cache.is_file() and not target.exists():
            destination.mkdir(exist_ok=True)
            shutil.copyfile(cache, target)


def execute_suite(name, command, worktree, night, log, timeout, keep, artifacts=None):
    started = time.monotonic()
    env = os.environ.copy()
    if artifacts is not None:
        env["REDROGUE_AUTOPLAY_ARTIFACTS"] = str(artifacts)
        copy_inventory_cache(night / ".inventory", artifacts)
    with log.open("w", encoding="utf-8") as out:
        process = subprocess.Popen(command, cwd=worktree, stdout=out, stderr=subprocess.STDOUT,
                                   env=env, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            stop_suite(process)
            code = "timeout"
        except BaseException:
            stop_suite(process)
            raise
    result = {"suite": name, "exit": code, "seconds": round(time.monotonic() - started),
              "command": shlex.join(command)}
    if artifacts is not None:
        copy_inventory_cache(artifacts, night / ".inventory")
    for file in keep:
        source = artifacts / file
        if source.exists():
            shutil.copy(source, night / f"{name}_{file}")
    text = log.read_text(encoding="utf-8", errors="replace")
    result["tail"] = text.splitlines()[-15:]
    if name == "smoke":
        result["failing"] = sorted(set(re.findall(r"^\s+(?:FAIL|ERROR|TIMEOUT|CRASH)\w*\s+(\S+)$", text, re.M)))
    if name in AUTOPLAY_SUITES:
        result.update(autoplay_findings(name, worktree, night, command, artifacts))
    if name == "stack":
        result["stack_spare_bytes"] = [int(value) for value in re.findall(r"(\d+) B spare above", text)]
    if name == "guards":
        counts = re.search(r"^(\d+)/(\d+) passed,", text, re.M)
        if counts:
            result["guards_passed"], result["guards_run"] = map(int, counts.groups())
        result["findings"] = [{"kind": f"guard {script}", "what": f"{status}: {script}", "replay": None}
                              for status, script in re.findall(r"^  (TIMEOUT|FAIL\(\d+\)) +([^\s]+)", text, re.M)]
    if name == "directed":
        result["failing"] = re.findall(r"^(?:FAIL|ERROR): (.+)$", text, re.M)
        recorded = re.search(r"^Ran (\d+) tests? in ", text, re.M)
        if recorded:
            skipped = re.search(r"^.*\bskipped=(\d+)\)", text, re.M)
            skipped_count = int(skipped[1]) if skipped else 0
            cases = int(recorded[1])
            result["test_counts"] = {"run": cases, "skipped": skipped_count}
    if name == "builds":
        result.update(build_findings(night / "builds_build_compare.json"))
    if name == "sram":
        result.update(sram_findings(night / "sram_sram_fuzz_summary.json"))
    if name == "battle_fuzz":
        result.update(battle_fuzz_findings(night / "battle_fuzz_battle_fuzz.json"))
    if name == "menu_fuzz":
        result.update(menu_fuzz_findings(night / "menu_fuzz_menu_fuzz.json"))
    return result


def autoplay_findings(name: str, worktree: Path, night: Path, command=None,
                      artifacts: Path | None = None) -> dict[str, object]:
    command = command or SUITES[name][0]
    artifacts = artifacts or worktree / ARTIFACTS
    summary_name = "autoplay_summary_cgb.json" if "--cgb" in command else "autoplay_summary.json"
    path = night / f"{name}_{summary_name}"
    if not path.exists():
        return {"findings": [{"kind": "no summary", "what": "no summary written", "replay": None}]}
    summary = json.loads(path.read_text(encoding="utf-8"))
    findings, kept = [], night / f"{name}_seeds"
    menu_counts = Counter()
    menu_targets = Counter()
    menu_choices = Counter()
    for row in summary["runs"]:
        seed = row["seed"]
        if name in ("menus", "room_menu"):
            raw = artifacts / f"autoplay_seed{seed}.json"
            events = json.loads(raw.read_text(encoding="utf-8"))["events"] if raw.exists() else []
            count_menu_exposure(row, events, menu_counts, menu_targets, menu_choices)
        problems = ([(row["outcome"], row["detail"], row["map"])] if row["outcome"] in FAILURES else []) + \
            [(a["check"], f"{a['check']}: {a['detail']}", a.get("map") or row["map"])
             for a in row["anomalies"]] + \
            [(f"save {f['check']}", f"save {f['check']}", row["map"]) for f in row.get("save_findings") or []]
        branches = (row.get("branches") or {}).get("findings", [])
        if not problems and not branches:
            continue
        kept.mkdir(exist_ok=True)
        for file in artifacts.glob(f"autoplay_seed{seed}[._]*"):
            if file.is_dir():
                # Save checks retain complete packages, including nested cold
                # boot states. A seed can have several finding rows.
                shutil.copytree(file, kept / file.name, dirs_exist_ok=True)
            else:
                shutil.copy(file, kept / file.name)
        replay = replay_command(seed, command)
        for kind, what, map_name in problems:
            findings.append({"seed": seed, "kind": kind, "what": what, "map": map_name, "replay": replay})
        for branch in branches:
            branch_replay = branch["replay"].replace(str(artifacts), f"<night>/{name}_seeds").replace(str(ARTIFACTS), f"<night>/{name}_seeds")
            first = branch["anomalies"][0]["check"] if branch["anomalies"] else None
            findings.append({"seed": seed, "kind": f"branch {first or branch['outcome']}",
                             "what": f"branch {branch['key']}: {branch['outcome']} {branch['detail']}".rstrip()
                             + "".join(f"; {a['check']}: {a['detail']}" for a in branch["anomalies"][:2]),
                             "map": branch["at"].get("map"), "replay": branch_replay})
    balance = summary.get("balance") or {}
    rows = summary["runs"]
    outcomes = summary.get("outcomes") or {}
    exposure = {"seeds": len(rows), "frames": sum(row.get("frames", 0) for row in rows),
                "champions": sum(run["outcome"] == "champion"
                                 for row in rows for run in row.get("run_records", [])),
                "power_cuts": sum(len(row.get("power_cuts") or []) for row in rows),
                "palette_samples": sum((row.get("screen_checks") or {}).get("samples", 0) for row in rows),
                "branches": sum(t["branches"] for t in ((summary.get("branching") or {}).get("totals") or {}).values())}
    if "--coverage" in command:
        coverage_path = night / f"{name}_{summary_name.replace('autoplay', 'coverage')}"
        if coverage_path.exists():
            totals = json.loads(coverage_path.read_text(encoding="utf-8"))["totals"]
            exposure["routines_reached"] = totals["routines_run"]
            exposure["routines_total"] = totals["routines"]
    unreached = []
    if name in ("menus", "room_menu"):
        exposure["item_events"] = {
            key: menu_counts[key] for key in ("heal", "buy", "battle_item_attempts", "bag_attempts")}
        exposure["menu_choices"] = dict(menu_choices)
        exposure["errands_reached"] = {key: menu_targets[key] for key in (*MENU_MILESTONES, "lobby")}
        exposure["lobby_menus_reached"] = {key.removeprefix("lobby:"): count
                                          for key, count in menu_targets.items() if key.startswith("lobby:")}
        expected_errands = ("pc", "rental", "lobby") if name == "menus" else ("roompc",)
        unreached.extend(label for label in expected_errands if not menu_targets[label])
        if name == "menus":
            for key, label in (("heal", "field healing"), ("battle_item_attempts", "battle item menu"),
                               ("bag_attempts", "bag menu")):
                if not menu_counts[key]:
                    unreached.append(label)
    if name == "cgb_full" and not exposure["champions"]:
        unreached.append("CGB Hall of Fame")
    return {"findings": findings, "outcomes": outcomes, "exposure": exposure, "unreached": unreached,
            **champion_rate(name, rows, balance),
            "stages_mean": (balance.get("stages_cleared") or {}).get("mean")}


def champion_rate(name: str, rows: list[dict], balance: dict) -> dict[str, object]:
    """The rate the next night compares with: over the fixed seeds only, when a suite has both."""
    fixed = SEED_PLAN.get(name, (0, 0))[0]
    kept = [row for row in rows if row["seed"] <= fixed]
    runs = [run for row in kept for run in row.get("run_records") or []]
    if not fixed or not runs:
        return {"champion_rate": balance.get("champion_rate"), "champion_seeds": None}
    return {"champion_rate": round(sum(run["outcome"] == "champion" for run in runs) / len(runs), 3),
            "champion_seeds": sorted(row["seed"] for row in kept)}


def count_menu_exposure(row, events, item_counts, errand_counts, choices):
    for event in events:
        kind = event["kind"]
        if kind in ("heal", "buy"):
            item_counts[kind] += 1
        elif kind == "errand" and event["phase"] == "start":
            if event["errand"] == "battle":
                item_counts["battle_item_attempts"] += 1
            elif event["errand"] == "bag":
                item_counts["bag_attempts"] += 1
    for errand in row.get("directed_errands") or []:
        kind, reached = errand["errand"], errand["reached"]
        if MENU_MILESTONES.get(kind) in reached or (
                kind == "lobby" and any(step.startswith("menu:") or step in
                                        ("party_menu", "accepted", "declined") for step in reached)):
            errand_counts[kind] += 1
            if kind == "lobby" and errand.get("target"):
                errand_counts[f"lobby:{errand['target']}"] += 1
    for menu, counts in row.get("menus", {}).items():
        choices[menu] += counts["choices"]


def build_findings(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"findings": [{"kind": "no summary", "what": "no build comparison written", "replay": None}]}
    report = json.loads(path.read_text(encoding="utf-8"))
    findings = [{"seed": seed, "kind": f"{rom} {check}", "what": f"{rom}: anomaly {check}",
                 "replay": f"python3 tools/pyboy_smoke/autoplay.py --seed {seed} --new-game --rom {rom}"}
                for rom, total in report["totals"].items()
                for check, seeds in total["anomaly_checks"].items() for seed in seeds[:1]]
    findings += [{"seed": seed, "kind": f"{rom} failed run", "what": f"{rom}: failed run",
                  "replay": f"python3 tools/pyboy_smoke/autoplay.py --seed {seed} --new-game --rom {rom}"}
                 for rom, total in report["totals"].items() for seed in total["failed_seeds"]]
    return {"findings": findings, "only_in_one_build": report["only_in_one_build"]}


def menu_fuzz_findings(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"findings": [{"kind": "no summary", "what": "no menu fuzz summary written", "replay": None}]}
    report = json.loads(path.read_text(encoding="utf-8"))
    findings = []
    for what, seeds in report["findings"].items():
        tool, _, detail = what.partition(": ")
        findings.append({"seed": seeds[0] if seeds else None, "kind": f"{tool} {detail.split(':')[0]}", "what": what,
                         "replay": f"python3 tools/pyboy_smoke/{tool}.py --seeds {seeds[0]} --jobs 1" if seeds else None})
    return {"findings": findings, "exposure": {"seeds": sum(row["seeds"] for row in report["tools"].values())}}


def battle_fuzz_findings(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"findings": [{"kind": "no summary", "what": "no battle fuzz summary written", "replay": None}]}
    report = json.loads(path.read_text(encoding="utf-8"))
    return {"findings": [{"seed": seeds[0], "kind": f"battle {what.split(':')[0]}", "what": f"battle fuzz: {what}",
                          "replay": f"python3 tools/pyboy_smoke/battle_fuzz.py --seeds {seeds[0]} --jobs 1"}
                         for what, seeds in report["findings"].items()],
            "outcomes": report["outcomes"],
            "exposure": {"seeds": report["played"], "frames": report["frames"],
                         "turns": report["exposure"].get("turns", 0)},
            "unreached": [] if report["exposure"].get("turns") else ["any battle turn"]}


def sram_findings(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"findings": [{"kind": "no summary", "what": "no SRAM fuzz summary written", "replay": None}]}
    report = json.loads(path.read_text(encoding="utf-8"))
    findings = [{"seed": d["seed"], "kind": "sram divergence", "what": f"SRAM fill {d['fill']} plays differently",
                          "replay": f"python3 tools/pyboy_smoke/sram_fuzz.py --seeds {d['seed']} --matched-controls"}
                for d in report["divergences"]]
    findings.extend({"kind": "SRAM evidence incomplete", "what": error, "replay": None}
                    for error in report.get("comparison_errors", []))
    for row in report.get("initialization_comparisons", []):
        if row["status"] not in ("equivalent", "divergent"):
            findings.append({"seed": row["seed"], "kind": "SRAM evidence incomplete",
                             "what": f"SRAM fill {row['fill']}: {row['status']}",
                             "replay": f"python3 tools/pyboy_smoke/sram_fuzz.py --seeds {row['seed']} --matched-controls"})
    return {"findings": findings}


def report_history(reports: Path, current: Path):
    for night in sorted(reports.iterdir(), reverse=True):
        if not night.is_dir() or night == current:
            continue
        try:
            report = json.loads((night / "report.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        yield night, report


def previous_reports(reports: Path, current: Path, quick: bool):
    for folder, report in report_history(reports, current):
        if not report.get("runner_error") and report.get("quick", False) == quick:
            yield folder, report


def comparison_report(report: dict, history: list[tuple[Path, dict]]) -> dict:
    """Keep each suite's last comparable result as suites are added or rotated."""
    previous = []
    for current in report["suites"]:
        for _, old in history:
            match = next((suite for suite in old["suites"]
                          if suite["suite"] == current["suite"]
                          and suite.get("rotation") == current.get("rotation")), None)
            if match is not None:
                previous.append(match)
                break
    return {"suites": previous}


def is_full_report(report: dict) -> bool:
    suites = [suite["suite"] for suite in report["suites"]]
    return (not report.get("quick") and not report.get("runner_error") and
            ((report.get("full_run") and suites == report.get("requested_suites"))
             or tuple(suites) == LEGACY_SUITES))


def regressions(report: dict[str, object], previous: dict[str, object] | None) -> list[str]:
    if previous is None:
        return [f"{suite['suite']}: issue has no baseline"
                for suite in report["suites"] if has_issue(suite)]
    found = []
    old = {s["suite"]: s for s in previous["suites"]}
    for suite in report["suites"]:
        before = old.get(suite["suite"])
        if before is None:
            if has_issue(suite):
                found.append(f"{suite['suite']}: issue has no baseline")
            continue
        if suite["exit"] != 0 and before["exit"] == 0:
            found.append(f"{suite['suite']}: passed last night, fails now (exit {suite['exit']})")
        elif suite["exit"] != 0 and suite["exit"] != before["exit"]:
            found.append(f"{suite['suite']}: exit changed from {before['exit']} to {suite['exit']}")
        for test in sorted(set(suite.get("failing", [])) - set(before.get("failing", []))):
            found.append(f"{suite['suite']}: newly failing {test}")
        kinds = lambda s: {f["kind"] for f in s.get("findings", [])}
        for kind in sorted(kinds(suite) - kinds(before)):
            found.append(f"{suite['suite']}: new kind of finding: {kind}")
        for label in sorted(set(suite.get("unreached", [])) - set(before.get("unreached", []))):
            found.append(f"{suite['suite']}: no exposure to {label}")
        if not suite.get("rotating_seeds") and suite.get("champion_seeds") == before.get("champion_seeds") \
                and suite.get("champion_rate") is not None and before.get("champion_rate") is not None \
                and suite["champion_rate"] < before["champion_rate"] - CHAMPION_DROP:
            found.append(f"{suite['suite']}: champion rate {before['champion_rate']:.0%} -> {suite['champion_rate']:.0%}")
    return found


def reached_routines(folder: Path, files: set[str]) -> set[str]:
    """Routines any of the named coverage summaries in a night's folder ran at least once."""
    reached = set()
    for name in files:
        try:
            counts = json.loads((folder / name).read_text(encoding="utf-8")).get("routine_run_counts") or {}
        except (OSError, ValueError):
            continue
        reached |= {identity for identity, count in counts.items() if count}
    return reached


def pooled_coverage_delta(night: Path, previous: Path) -> tuple[int, int]:
    """Gained and lost routines over every suite, against the previous night. Only coverage
    files both nights wrote are pooled, so a night that ran extra suites (Sunday) does not
    read as a loss the night after. One suite alone swings by ~150 routines a night on seeds."""
    files = ({p.name for p in night.glob("*coverage_summary*.json")}
             & {p.name for p in previous.glob("*coverage_summary*.json")})
    tonight, before = reached_routines(night, files), reached_routines(previous, files)
    return len(tonight - before), len(before - tonight)


def coverage_regression(night: Path, history: list[Path]) -> tuple[dict, list[str]]:
    """Intersect proven losses against three distinct prior calendar nights."""
    from contextlib import redirect_stdout
    from io import StringIO
    if len(history) != COVERAGE_NIGHTS:
        return {}, []
    maps = []
    for folder in [night, *history]:
        try:
            summary = json.loads((folder / "newgame_coverage_summary.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}, []
        if summary.get("routine_identity") != "source-name-v1" or not isinstance(summary.get("routine_run_counts"), dict):
            return {}, []
        maps.append(summary)
    import autoplay_coverage

    with redirect_stdout(StringIO()):
        deltas = [autoplay_coverage.compare(old, maps[0]) for old in maps[1:]]
    lost = set.intersection(*(set(delta["lost"]) for delta in deltas))
    # Another suite reaching it tonight, or no hook on it tonight, is not a loss.
    blind = set(maps[0].get("untracked") or ())
    names = maps[0].get("routine_names") or {}
    for path in night.glob("*coverage_summary*.json"):
        try:
            counts = json.loads(path.read_text(encoding="utf-8")).get("routine_run_counts") or {}
        except (OSError, ValueError):
            continue
        lost -= {identity for identity, count in counts.items() if count}
    lost = sorted(identity for identity in lost
                  if names.get(identity, identity.rsplit("::", 1)[-1]) not in blind)
    gained, lost_count = pooled_coverage_delta(night, history[0])
    return {"gained": gained, "lost": lost_count, "pooled": True,
            "persistent_lost": lost}, ([f"coverage: {len(lost)} routines reached on all three prior nights were missed by every suite"]
                                      if lost else [])


def has_issue(suite: dict) -> bool:
    return bool(suite["exit"] != 0 or suite.get("failing") or suite.get("findings") or suite.get("unreached"))


def status(report: dict) -> str:
    if report.get("runner_error") or report.get("regressions"):
        return "NEW regression"
    return "known issues only" if report["failed"] else "clean"


def write_markdown(report: dict[str, object], night: Path) -> None:
    sha = report["sha"]
    lines = [f"# Nightly {report['date']}: {sha[:8]} {report['subject']}", "",
             f"Status: **{status(report)}**, "
             f"{report['seconds'] // 60} min. Worktree `{report['worktree']}`.", "",
             "| Suite | Exit | Minutes | Notes |", "| --- | --- | --- | --- |"]
    for suite in report["suites"]:
        notes = []
        if suite.get("skipped"):
            notes.append(f"SKIPPED: {suite['skipped']}")
        if "guards_run" in suite:
            notes.append(f"{suite['guards_passed']}/{suite['guards_run']} guards passed")
        if suite.get("stack_spare_bytes"):
            notes.append(f"{min(suite['stack_spare_bytes'])} B minimum observed stack spare")
        if suite.get("test_counts"):
            notes.append(", ".join(f"{count} {status}" for status, count in suite["test_counts"].items()))
        if suite.get("failing"):
            notes.append(f"{len(suite['failing'])} failing")
        if suite.get("findings"):
            notes.append(f"{len(suite['findings'])} findings")
        if suite.get("champion_rate") is not None:
            notes.append(f"champion {suite['champion_rate']:.0%}, stages {suite['stages_mean']}")
        exposure = suite.get("exposure") or {}
        if exposure:
            notes.append(", ".join(f"{exposure[key]:,} {label}" for key, label in (
                ("seeds", "seeds"), ("frames", "frames"), ("champions", "champions"),
                ("power_cuts", "power cuts"), ("palette_samples", "palette samples"),
                ("branches", "branches")) if exposure.get(key)))
            if "routines_reached" in exposure:
                notes.append(f"routines {exposure['routines_reached']}/{exposure['routines_total']}")
        if suite.get("unreached"):
            notes.append("Unreached: " + ", ".join(suite["unreached"]))
        lines.append(f"| {suite['suite']} | {suite['exit']} | {suite['seconds'] // 60} | {'; '.join(notes)} |")
    for suite in report["suites"]:
        menu = suite.get("exposure", {})
        if "item_events" not in menu:
            continue
        lines += ["", f"## Item and menu exposure ({suite['suite']})", "",
                  "- Confirmed field heals and purchases: "
                  f"{menu['item_events']['heal']} heals, {menu['item_events']['buy']} purchases",
                  "- Menu attempts: "
                  f"{menu['item_events']['battle_item_attempts']} battle item, {menu['item_events']['bag_attempts']} bag",
                  "- Directed menus reached: " + ", ".join(
                      f"{name} {count}" for name, count in menu["errands_reached"].items()),
                  "- Choices by menu: " + (", ".join(
                      f"{name} {count}" for name, count in sorted(menu["menu_choices"].items())) or "none")]
        if menu["lobby_menus_reached"]:
            lines.append("- Lobby menus reached: " + ", ".join(
                f"{name} {count}" for name, count in sorted(menu["lobby_menus_reached"].items())))
    if report.get("runner_error"):
        lines += ["", f"Runner failure: {report['runner_error']}"]
    if report.get("coverage_delta"):
        delta = report["coverage_delta"]
        scope = "all suites" if delta.get("pooled") else "newgame only"
        lines += ["", f"Coverage versus last night ({scope}): {delta['gained']} routines newly reached, {delta['lost']} lost."]
        missed = delta["persistent_lost"]
        if missed:
            lines += ["", f"Missed after three prior nights: {', '.join(missed)}"]
    lines += ["", "## Regressions since last night", ""]
    lines += [f"- {r}" for r in report["regressions"]] or ["None (or no previous night)."]
    lines += ["", "## Findings", "",
              f"Replay at the tested commit: `git worktree add ../rr_{sha[:8]} {sha}`, "
              f"`cd ../rr_{sha[:8]} && make`, then the command. `<night>` is `{night}`.", ""]
    for suite in report["suites"]:
        for test in suite.get("failing", []):
            lines.append(f"- smoke: `{test}`: `make smoke TEST='{test}'`")
        for finding in suite.get("findings", []):
            seed = f"seed {finding['seed']}, " if finding.get("seed") is not None else ""
            lines.append(f"- {suite['suite']}: {seed}{finding['what']}"
                         + (f" on {finding['map']}" if finding.get("map") else "")
                         + (f": `{finding['replay']}`" if finding.get("replay") else ""))
        if suite["exit"] not in (0, None) and not suite.get("failing") and not suite.get("findings"):
            lines.append(f"- {suite['suite']}: exit {suite['exit']}; see `{suite['suite']}.log`")
    (night / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_html(report: dict[str, object], night: Path) -> None:
    """The page the Windows wrapper opens on a new regression: what is new, then the findings."""
    e = html.escape
    items = [f"<li>{e(line)}</li>" for line in report["regressions"]]
    if report.get("runner_error"):
        items.insert(0, f"<li>Runner failure: {e(report['runner_error'])}</li>")
    found = []
    for name, what, replay in finding_rows(report):
        found.append(f"<li><b>{e(name)}</b>: {e(what)}" + (f"<pre>{e(replay)}</pre>" if replay else "") + "</li>")
    rows = "".join(f"<tr><th scope=\"row\">{e(s['suite'])}</th><td>{'Issue' if has_issue(s) else 'Pass'}</td>"
                   f"<td>{e(str(s['exit']))}</td><td>{s['seconds'] // 60}</td></tr>" for s in report["suites"])
    headline = status(report)
    document = f"""<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Red Rogue nightly: {e(headline)}</title>
<style>
body {{font: 1rem/1.5 system-ui; margin: 2rem auto; max-width: 60rem; padding: 0 1rem; color: #212529; background: #fff}}
table {{border-collapse: collapse}} th, td {{text-align: left; padding: .35rem .8rem; border-bottom: 1px solid #ddd}}
pre {{background: #f3f3f3; padding: .5rem; overflow-x: auto}} .NEW {{color: #a11322}}
</style>
<h1 class="{headline.split()[0]}">{e(headline)}</h1>
<p>{e(report['date'])}, commit {e(report['sha'][:8])}: {e(report['subject'])}.
<a href="report.md">Full report</a>. <a href="../index.html">All nights</a>.</p>
<h2>New since last night</h2><ul>{''.join(items) or '<li>Nothing.</li>'}</ul>
<h2>Findings</h2><ul>{''.join(found) or '<li>None.</li>'}</ul>
<h2>Suites</h2><table><thead><tr><th>Suite</th><th>Result</th><th>Exit</th><th>Minutes</th></tr></thead>
<tbody>{rows}</tbody></table></html>
"""
    (night / "report.html").write_text(document, encoding="utf-8")


def finding_rows(report: dict[str, object]) -> list[tuple[str, str, str | None]]:
    """(suite, what happened, replay command or None), in report order."""
    rows = []
    for suite in report["suites"]:
        rows += [(suite["suite"], test, f"make smoke TEST='{test}'") for test in suite.get("failing", [])]
        for finding in suite.get("findings", []):
            seed = f"seed {finding['seed']}, " if finding.get("seed") is not None else ""
            place = f" on {finding['map']}" if finding.get("map") else ""
            rows.append((suite["suite"], f"{seed}{finding['what']}{place}", finding.get("replay")))
        if suite["exit"] not in (0, None) and not suite.get("failing") and not suite.get("findings"):
            rows.append((suite["suite"], f"exit {suite['exit']}; see {suite['suite']}.log", None))
    return rows


class NightlyBusy(Exception):
    pass


@contextmanager
def nightly_lock(reports: Path):
    """A kernel-held lock survives PID reuse and releases when WSL kills the runner."""
    import fcntl

    marker = reports / "nightly.lock"
    with (reports / "nightly.guard").open("a") as guard:
        try:
            fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            try:
                owner = marker.read_text(encoding="utf-8").strip()
            except OSError:
                owner = "owner metadata unavailable"
            raise NightlyBusy(f"another nightly is running ({owner})") from None
        marker.write_text(json.dumps({"pid": os.getpid(), "started_at": timestamp()}) + "\n", encoding="utf-8")
        try:
            yield
        finally:
            marker.unlink(missing_ok=True)


def timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def write_index(reports: Path) -> None:
    rows = []
    latest = ""
    for folder, report in report_history(reports, reports):
        if report.get("quick"):
            continue
        if not latest and is_full_report(report):
            latest = report.get("finished_at") or dt.datetime.fromtimestamp(
                (folder / "report.json").stat().st_mtime, dt.timezone.utc).isoformat()
        outcomes = {s["suite"]: ("Incomplete" if s.get("unreached") and s["exit"] == 0
                                  and not s.get("findings") else "Issue" if has_issue(s) else "Pass")
                    for s in report["suites"]}
        headline = report.get("status") or ("Historical issues" if report.get("failed") else "clean")
        cells = "".join(f"<td>{outcomes.get(name, '-')}</td>" for name in SUITES)
        page = "report.html" if (folder / "report.html").exists() else "report.md"
        rows.append(f'<tr><th scope="row"><a href="{quote(folder.name)}/{page}">'
                    f'{html.escape(report["date"])}</a></th>'
                    f'<td data-status="{html.escape(headline)}">{html.escape(headline)}</td>{cells}</tr>')
    headings = "".join(f'<th scope="col">{name}</th>' for name in SUITES)
    document = f"""<!doctype html>
<html lang="en"><meta charset="utf-8"><title>Red Rogue nightly</title>
<style>
body {{font: 1rem system-ui; margin: 2rem; color: #212529}}
table {{border-collapse: collapse}} th, td {{text-align: left; padding: .55rem; border-bottom: 1px solid #ddd}}
.warning, [data-status="NEW regression"] {{color: #a11322; font-weight: bold}}
[data-status="known issues only"] {{color: #765300}}
</style>
<h1>Red Rogue nightly</h1>
<p id="freshness" data-latest="{html.escape(latest)}">Checking report age...</p>
<table><thead><tr><th scope="col">Run</th><th scope="col">Status</th>{headings}</tr></thead>
<tbody>{''.join(rows)}</tbody></table>
<script>
const banner = document.getElementById("freshness");
function updateFreshness() {{
    const latest = Date.parse(banner.dataset.latest);
    const age = (Date.now() - latest) / 3600000;
    const stale = !Number.isFinite(age) || age > 30;
    banner.classList.toggle("warning", stale);
    banner.textContent = Number.isFinite(age)
        ? `Latest full report is ${{Math.max(0, Math.floor(age))}} hours old${{stale ? " (overdue)" : ""}}.`
        : "No complete nightly report is available.";
}}
updateFreshness();
setInterval(updateFreshness, 60000);
</script></html>
"""
    # A blocked attempt can write concurrently with the active runner.
    temporary = reports / f".index.{os.getpid()}.html"
    temporary.write_text(document, encoding="utf-8")
    temporary.replace(reports / "index.html")


def finish_report(report: dict, night: Path, started: float) -> None:
    inventory = night / ".inventory"
    if inventory.is_dir():
        for cache in inventory.glob("coverage_inventory_*_v*_*.json"):
            cache.unlink()
        if not any(inventory.iterdir()):
            inventory.rmdir()
    report["seconds"] = round(time.monotonic() - started)
    report["finished_at"] = timestamp()
    report["failed"] = bool(report.get("runner_error")) or any(has_issue(s) for s in report["suites"])
    report["status"] = status(report)
    write_markdown(report, night)
    write_html(report, night)
    (night / "report.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    write_index(night.parent)
    print(f"{report['status']} -> {night / 'report.md'}", flush=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Test one commit with every long-running check.")
    parser.add_argument("--ref", default="master", help="branch, tag or commit to test")
    parser.add_argument("--worktree", type=Path, default=ROOT.parent / "redrogue_nightly")
    parser.add_argument("--reports", type=Path, default=ROOT.parent / "redrogue_nightly_reports")
    parser.add_argument("--suites", default=",".join(SUITES), help=f"from {', '.join(SUITES)}")
    parser.add_argument("--force", action="store_true", help="run even if this commit already has a report")
    parser.add_argument("--index-only", action="store_true", help="refresh the dashboard without running suites")
    parser.add_argument("--quick", action="store_true", help="a few seeds per suite, to check the runner")
    args = parser.parse_args(argv)
    suites = [s.strip() for s in args.suites.split(",") if s.strip()]
    unknown = [s for s in suites if s not in SUITES]
    if unknown:
        parser.error(f"unknown suites {unknown}; choose from {list(SUITES)}")
    if "build" not in suites:
        suites.insert(0, "build")  # every suite reads the ROMs

    args.reports = args.reports.resolve()
    args.reports.mkdir(parents=True, exist_ok=True)
    if args.index_only:
        for folder, old in report_history(args.reports, args.reports):
            if old.get("finished_at"):  # older reports lack fields the page needs
                write_html(old, folder)
        write_index(args.reports)
        return 0
    started = time.monotonic()
    now = dt.datetime.now()
    budget = WEEKLY_BUDGET if now.weekday() == 6 and "guards" in suites and not args.quick else DAILY_BUDGET
    worktree = args.worktree.resolve()
    report = {"date": f"{now:%Y-%m-%d %H:%M}", "sha": "unknown", "quick": args.quick,
              "subject": "", "ref": args.ref, "worktree": str(worktree),
              "suites": [], "requested_suites": suites, "full_run": suites == list(SUITES), "regressions": []}
    night = None
    try:
        with nightly_lock(args.reports):
            sha = git("rev-parse", "--verify", f"{args.ref}^{{commit}}")
            history = list(previous_reports(args.reports, args.reports, args.quick))
            last = next((old for _, old in history if [s["suite"] for s in old["suites"]] == suites), None)
            if last and last["sha"] == sha and not args.force:
                print(f"{sha[:8]} already has a report ({last['night']}); --force to run again")
                return 0
            night = args.reports / f"{now:%Y-%m-%d_%H%M%S_%f}_{sha[:8]}"
            night.mkdir()
            report.update(sha=sha, subject=git("log", "-1", "--format=%s", sha), night=str(night))
            prepare_worktree(worktree, sha)
            for name in suites:
                remaining = budget - (time.monotonic() - started)
                if remaining <= 0:
                    report["runner_error"] = f"Run budget exhausted before {name}"
                    break
                print(f"[{dt.datetime.now():%H:%M}] {name} ...", flush=True)
                result = run_suite(name, worktree, night, now.date(), args.quick, remaining)
                report["suites"].append(result)
                print(f"    exit {result['exit']} in {result['seconds'] // 60} min"
                      + (f", {len(result.get('findings', []))} findings" if "findings" in result else "")
                      + (f", {len(result['failing'])} failing" if result.get("failing") else ""), flush=True)
                if name == "build" and result["exit"] != 0:
                    break
            report["regressions"] = regressions(report, comparison_report(report, history))
            prior_nights = {}
            today = now.date().isoformat()
            for folder, old in history:
                day = old["date"][:10]
                if day < today and any(s["suite"] == "newgame" and s["exit"] == 0 for s in old["suites"]):
                    prior_nights.setdefault(day, folder)
            if next((s["exit"] for s in report["suites"] if s["suite"] == "newgame"), None) == 0:
                delta, missed = coverage_regression(night, list(prior_nights.values())[:COVERAGE_NIGHTS])
                report["coverage_delta"] = delta
                report["regressions"].extend(missed)
            finish_report(report, night, started)
            return 2 if report.get("runner_error") else 1 if report["regressions"] else 0
    except Exception as error:
        if not isinstance(error, NightlyBusy):
            traceback.print_exc()
        if night is None:
            night = args.reports / f"{now:%Y-%m-%d_%H%M%S_%f}_runner"
            night.mkdir()
        report.update(runner_error=str(error), night=str(night))
        finish_report(report, night, started)
        return 2


def on_terminate(_signal, _frame):
    raise SystemExit(143)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, on_terminate)
    sys.exit(main())
