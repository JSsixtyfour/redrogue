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
    builds     compare_builds: seeds 1-8 on the debug, Blue and Red builds
    sram       sram_fuzz: seeds 1-4

Each night writes <reports>/<date>_<sha>/ (default ../redrogue_nightly_reports):
the logs, each suite's summary JSON, copies of every failed seed's report,
state and screenshot (the next suite overwrites artifacts/), report.json, and
report.md with a replay command for each finding, pinned to the commit. The
previous night's report.json is the baseline: a smoke test that newly fails,
an anomaly or failure kind not seen before, a champion rate or coverage drop
are listed as regressions. The bot's seeds play differently whenever the ROM
changes (VBlank's RNG), so balance and coverage moves are reported, not failed
on, unless large.

Exits non-zero when anything failed. A night whose commit matches the last
report is skipped unless --force.

Scheduling (Windows Task Scheduler, from PowerShell; adjust the time):

    schtasks /Create /TN "Red Rogue nightly" /SC DAILY /ST 03:00 /TR "wsl.exe bash -lc 'cd /mnt/c/Users/justi/redrogue && python3 tools/pyboy_smoke/nightly.py'"
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SMOKE_DIR = Path("tools/pyboy_smoke")
ARTIFACTS = SMOKE_DIR / "artifacts"
FAILURES = ("stalled", "frame_limit", "error", "crashed", "hung")
CHAMPION_DROP = 0.15  # a champion rate this far below last night's counts as a regression
COVERAGE_DROP = 100   # routines no longer reached, beyond which it counts as a regression

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
    "builds": (["python3", str(SMOKE_DIR / "compare_builds.py"), "--seeds", "1-8", "--jobs", "6",
                "--max-frames", "1000000"], 7200, ["build_compare.json"]),
    "sram": (["python3", str(SMOKE_DIR / "sram_fuzz.py"), "--seeds", "1-4"], 3600, ["sram_fuzz_summary.json"]),
}
# --quick: a few seeds per suite, to check the runner itself.
QUICK = {"lobby": {"--seeds": "1-2"}, "newgame": {"--seeds": "1-2", "--runs": "1"},
         "builds": {"--seeds": "1-2"}, "sram": {"--seeds": "1"}}
# The flags a replay of one autoplay seed needs, per suite.
REPLAY_FLAGS = {"lobby": "", "newgame": " --new-game --runs 2 --vary --save-checks"}


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


def run_suite(name: str, worktree: Path, night: Path, quick: bool = False) -> dict[str, object]:
    command, timeout, keep = SUITES[name]
    command = list(command)
    for flag, value in (QUICK.get(name, {}) if quick else {}).items():
        command[command.index(flag) + 1] = value
    started = time.monotonic()
    log = night / f"{name}.log"
    try:
        with open(log, "w", encoding="utf-8") as out:
            code = subprocess.run(command, cwd=worktree, stdout=out, stderr=subprocess.STDOUT,
                                  timeout=timeout).returncode
    except subprocess.TimeoutExpired:
        code = "timeout"
    result = {"suite": name, "exit": code, "seconds": round(time.monotonic() - started),
              "command": " ".join(command)}
    for file in keep:
        source = worktree / ARTIFACTS / file
        if source.exists():
            shutil.copy(source, night / f"{name}_{file}")
    text = log.read_text(encoding="utf-8", errors="replace")
    result["tail"] = text.splitlines()[-15:]
    if name == "smoke":
        result["failing"] = sorted(set(re.findall(r"^\s+(?:FAIL|ERROR|TIMEOUT|CRASH)\w*\s+(\S+)$", text, re.M)))
    if name in REPLAY_FLAGS:
        result.update(autoplay_findings(name, worktree, night))
    if name == "builds":
        result.update(build_findings(night / "builds_build_compare.json"))
    if name == "sram":
        result.update(sram_findings(night / "sram_sram_fuzz_summary.json"))
    return result


def autoplay_findings(name: str, worktree: Path, night: Path) -> dict[str, object]:
    path = night / f"{name}_autoplay_summary.json"
    if not path.exists():
        return {"findings": [{"kind": "no summary", "what": "no summary written", "replay": None}]}
    summary = json.loads(path.read_text(encoding="utf-8"))
    findings, kept = [], night / f"{name}_seeds"
    for row in summary["runs"]:
        seed = row["seed"]
        problems = ([(row["outcome"], row["detail"])] if row["outcome"] in FAILURES else []) + \
            [(a["check"], f"{a['check']}: {a['detail']}") for a in row["anomalies"]] + \
            [(f"save {f['check']}", f"save {f['check']}") for f in row.get("save_findings") or []]
        branches = (row.get("branches") or {}).get("findings", [])
        if not problems and not branches:
            continue
        kept.mkdir(exist_ok=True)
        for file in (worktree / ARTIFACTS).glob(f"autoplay_seed{seed}[._]*"):
            shutil.copy(file, kept / file.name)
        replay = f"python3 tools/pyboy_smoke/autoplay.py --seed {seed}{REPLAY_FLAGS[name]}"
        for kind, what in problems:
            findings.append({"seed": seed, "kind": kind, "what": what, "map": row["map"], "replay": replay})
        for branch in branches:
            command = branch["replay"].replace(str(ARTIFACTS), f"<night>/{name}_seeds")
            first = branch["anomalies"][0]["check"] if branch["anomalies"] else None
            findings.append({"seed": seed, "kind": f"branch {first or branch['outcome']}",
                             "what": f"branch {branch['key']}: {branch['outcome']} {branch['detail']}".rstrip()
                             + "".join(f"; {a['check']}: {a['detail']}" for a in branch["anomalies"][:2]),
                             "map": branch["at"].get("map"), "replay": command})
    balance = summary.get("balance") or {}
    return {"findings": findings, "outcomes": summary.get("outcomes"),
            "champion_rate": balance.get("champion_rate"),
            "stages_mean": (balance.get("stages_cleared") or {}).get("mean")}


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


def sram_findings(path: Path) -> dict[str, object]:
    if not path.exists():
        return {"findings": [{"kind": "no summary", "what": "no SRAM fuzz summary written", "replay": None}]}
    report = json.loads(path.read_text(encoding="utf-8"))
    return {"findings": [{"seed": d["seed"], "kind": "sram divergence", "what": f"SRAM fill {d['fill']} plays differently",
                          "replay": f"python3 tools/pyboy_smoke/sram_fuzz.py --seeds {d['seed']} --bisect"}
                         for d in report["divergences"]]}


def previous_report(reports: Path, current: Path, quick: bool = False) -> dict[str, object] | None:
    """The latest earlier night of the same size (a --quick night is no baseline for a full one)."""
    for night in sorted((p for p in reports.iterdir() if p.is_dir() and p != current), reverse=True):
        try:
            report = json.loads((night / "report.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if report.get("quick", False) == quick:
            return report
    return None


def regressions(report: dict[str, object], previous: dict[str, object] | None, night: Path) -> list[str]:
    if previous is None:
        return []
    found = []
    old = {s["suite"]: s for s in previous["suites"]}
    for suite in report["suites"]:
        before = old.get(suite["suite"])
        if before is None:
            continue
        if suite["exit"] != 0 and before["exit"] == 0:
            found.append(f"{suite['suite']}: passed last night, fails now (exit {suite['exit']})")
        for test in sorted(set(suite.get("failing", [])) - set(before.get("failing", []))):
            found.append(f"smoke: newly failing {test}")
        kinds = lambda s: {f["kind"] for f in s.get("findings", [])}
        for kind in sorted(kinds(suite) - kinds(before)):
            found.append(f"{suite['suite']}: new kind of finding: {kind}")
        if suite.get("champion_rate") is not None and before.get("champion_rate") is not None \
                and suite["champion_rate"] < before["champion_rate"] - CHAMPION_DROP:
            found.append(f"{suite['suite']}: champion rate {before['champion_rate']:.0%} -> {suite['champion_rate']:.0%}")
    old_coverage = Path(previous["night"]) / "newgame_coverage_summary.json"
    new_coverage = night / "newgame_coverage_summary.json"
    if old_coverage.exists() and new_coverage.exists():
        sys.path.insert(0, str(ROOT / SMOKE_DIR))
        import autoplay_coverage
        with open(os.devnull, "w") as quiet:
            stdout, sys.stdout = sys.stdout, quiet
            try:
                delta = autoplay_coverage.compare(json.loads(old_coverage.read_text(encoding="utf-8")),
                                                  json.loads(new_coverage.read_text(encoding="utf-8")))
            finally:
                sys.stdout = stdout
        report["coverage_delta"] = {"gained": len(delta["gained"]), "lost": len(delta["lost"]),
                                    "lost_sample": delta["lost"][:20]}
        if len(delta["lost"]) - len(delta["gained"]) > COVERAGE_DROP:
            found.append(f"coverage: {len(delta['lost'])} routines no longer reached, {len(delta['gained'])} newly")
    return found


def write_markdown(report: dict[str, object], night: Path) -> None:
    sha = report["sha"]
    lines = [f"# Nightly {report['date']}: {sha[:8]} {report['subject']}", "",
             f"Status: **{'FAILED' if report['failed'] else 'clean'}**, "
             f"{report['seconds'] // 60} min. Worktree `{report['worktree']}`.", "",
             "| Suite | Exit | Minutes | Notes |", "| --- | --- | --- | --- |"]
    for suite in report["suites"]:
        notes = []
        if suite.get("failing"):
            notes.append(f"{len(suite['failing'])} failing")
        if suite.get("findings"):
            notes.append(f"{len(suite['findings'])} findings")
        if suite.get("champion_rate") is not None:
            notes.append(f"champion {suite['champion_rate']:.0%}, stages {suite['stages_mean']}")
        lines.append(f"| {suite['suite']} | {suite['exit']} | {suite['seconds'] // 60} | {'; '.join(notes)} |")
    if report.get("coverage_delta"):
        delta = report["coverage_delta"]
        lines += ["", f"Coverage versus last night: {delta['gained']} routines newly reached, {delta['lost']} lost."]
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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Test one commit with every long-running check.")
    parser.add_argument("--ref", default="master", help="branch, tag or commit to test")
    parser.add_argument("--worktree", type=Path, default=ROOT.parent / "redrogue_nightly")
    parser.add_argument("--reports", type=Path, default=ROOT.parent / "redrogue_nightly_reports")
    parser.add_argument("--suites", default=",".join(SUITES), help=f"from {', '.join(SUITES)}")
    parser.add_argument("--force", action="store_true", help="run even if this commit already has a report")
    parser.add_argument("--quick", action="store_true", help="a few seeds per suite, to check the runner")
    args = parser.parse_args(argv)
    suites = [s.strip() for s in args.suites.split(",") if s.strip()]
    unknown = [s for s in suites if s not in SUITES]
    if unknown:
        parser.error(f"unknown suites {unknown}; choose from {list(SUITES)}")
    if "build" not in suites:
        suites.insert(0, "build")  # every suite reads the ROMs

    args.reports.mkdir(parents=True, exist_ok=True)
    lock = args.reports / "nightly.lock"
    try:
        lock.touch(exist_ok=False)
    except FileExistsError:
        print(f"another nightly run holds {lock}; remove it if none is running")
        return 2
    try:
        sha = git("rev-parse", "--verify", f"{args.ref}^{{commit}}")
        last = previous_report(args.reports, Path("/nonexistent"), args.quick)
        if last and last["sha"] == sha and not args.force:
            print(f"{sha[:8]} already has a report ({last['night']}); --force to run again")
            return 0
        started = time.monotonic()
        worktree = args.worktree.resolve()
        prepare_worktree(worktree, args.ref)
        now = dt.datetime.now()
        night = args.reports / f"{now:%Y-%m-%d_%H%M}_{sha[:8]}"
        night.mkdir()
        report = {"date": f"{now:%Y-%m-%d %H:%M}", "sha": sha, "quick": args.quick, "subject": git("log", "-1", "--format=%s", sha),
                  "ref": args.ref, "worktree": str(worktree), "night": str(night), "suites": []}
        for name in suites:
            print(f"[{dt.datetime.now():%H:%M}] {name} ...", flush=True)
            result = run_suite(name, worktree, night, args.quick)
            report["suites"].append(result)
            print(f"    exit {result['exit']} in {result['seconds'] // 60} min"
                  + (f", {len(result.get('findings', []))} findings" if "findings" in result else "")
                  + (f", {len(result['failing'])} failing" if result.get("failing") else ""), flush=True)
            if name == "build" and result["exit"] != 0:
                break
        report["seconds"] = round(time.monotonic() - started)
        report["failed"] = any(s["exit"] != 0 for s in report["suites"])
        report["regressions"] = regressions(report, previous_report(args.reports, night, args.quick), night)
        (night / "report.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
        write_markdown(report, night)
        print(f"{'FAILED' if report['failed'] else 'clean'}; {len(report['regressions'])} regression(s) "
              f"-> {night / 'report.md'}")
        return 1 if report["failed"] else 0
    finally:
        lock.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
