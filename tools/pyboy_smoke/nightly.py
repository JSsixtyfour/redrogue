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
    builds     compare_builds: seeds 1-8 on the debug, Blue and Red builds
    sram       sram_fuzz: seeds 1-4

Each night writes <reports>/<date>_<sha>/ (default ../redrogue_nightly_reports):
the logs, each suite's summary JSON, copies of every failed seed's report,
state and screenshot (the next suite overwrites artifacts/), report.json, and
report.md with a replay command for each finding, pinned to the commit. The
previous night's report.json is the baseline: a smoke test that newly fails,
an anomaly or failure kind not seen before, a champion rate or coverage drop
are listed as regressions. Coverage loss requires the same routine to have
been reached on each of three prior nights.

Exits 1 for new regressions and 2 for runner failures. The Windows task uses
nightly_windows.ps1 with --force so the scheduled run stays daily.
"""
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
import traceback
from contextlib import contextmanager
from urllib.parse import quote
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SMOKE_DIR = Path("tools/pyboy_smoke")
ARTIFACTS = SMOKE_DIR / "artifacts"
FAILURES = ("stalled", "frame_limit", "error", "crashed", "hung")
CHAMPION_DROP = 0.15  # a champion rate this far below last night's counts as a regression
COVERAGE_NIGHTS = 3

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
    "builds": (["python3", str(SMOKE_DIR / "compare_builds.py"), "--seeds", "1-8", "--jobs", "6",
                "--max-frames", "1000000"], 7200, ["build_compare.json"]),
    "sram": (["python3", str(SMOKE_DIR / "sram_fuzz.py"), "--seeds", "1-4", "--matched-controls"], 3600, ["sram_fuzz_summary.json"]),
}
# --quick: a few seeds per suite, to check the runner itself.
QUICK = {"lobby": {"--seeds": "1-2"}, "newgame": {"--seeds": "1-2", "--runs": "1"},
         "cgb": {"--seeds": "1-2", "--stages": "3", "--branches": "1",
                 "--snapshots": "1", "--branch-frames": "300"},
         "builds": {"--seeds": "1-2"}, "sram": {"--seeds": "1"}}
# The flags a replay of one autoplay seed needs, per suite.
REPLAY_FLAGS = {"lobby": "", "newgame": " --new-game --runs 2 --vary --save-checks",
                "cgb": " --cgb --stages 12 --vary --save-checks --branches 2 --snapshots 1 --branch-frames 900"}


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
    for file in keep:
        (worktree / ARTIFACTS / file).unlink(missing_ok=True)
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
    summary_name = "autoplay_summary_cgb.json" if name == "cgb" else "autoplay_summary.json"
    path = night / f"{name}_{summary_name}"
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
            if file.is_dir():
                # Save checks retain complete packages, including nested cold
                # boot states. A seed can have several finding rows.
                shutil.copytree(file, kept / file.name, dirs_exist_ok=True)
            else:
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


def previous_reports(reports: Path, current: Path, quick: bool, suites: list[str]):
    for folder, report in report_history(reports, current):
        requested = report.get("requested_suites", [s["suite"] for s in report["suites"]])
        if not report.get("runner_error") and report.get("quick", False) == quick and requested == suites:
            yield folder, report


def regressions(report: dict[str, object], previous: dict[str, object] | None) -> list[str]:
    if previous is None:
        return [f"{suite['suite']}: issue has no baseline"
                for suite in report["suites"] if has_issue(suite)]
    found = []
    old = {s["suite"]: s for s in previous["suites"]}
    for suite in report["suites"]:
        before = old.get(suite["suite"])
        if before is None:
            continue
        if suite["exit"] != 0 and before["exit"] == 0:
            found.append(f"{suite['suite']}: passed last night, fails now (exit {suite['exit']})")
        elif suite["exit"] != 0 and suite["exit"] != before["exit"]:
            found.append(f"{suite['suite']}: exit changed from {before['exit']} to {suite['exit']}")
        for test in sorted(set(suite.get("failing", [])) - set(before.get("failing", []))):
            found.append(f"smoke: newly failing {test}")
        kinds = lambda s: {f["kind"] for f in s.get("findings", [])}
        for kind in sorted(kinds(suite) - kinds(before)):
            found.append(f"{suite['suite']}: new kind of finding: {kind}")
        if suite.get("champion_rate") is not None and before.get("champion_rate") is not None \
                and suite["champion_rate"] < before["champion_rate"] - CHAMPION_DROP:
            found.append(f"{suite['suite']}: champion rate {before['champion_rate']:.0%} -> {suite['champion_rate']:.0%}")
    return found


def coverage_regression(night: Path, history: list[Path]) -> tuple[dict, list[str]]:
    """Intersect proven losses against three distinct prior calendar nights."""
    from contextlib import redirect_stdout
    from io import StringIO
    import autoplay_coverage

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
    lost = sorted(set.intersection(*(set(delta["lost"]) for delta in deltas)))
    return {"gained": len(deltas[0]["gained"]), "lost": len(deltas[0]["lost"]),
            "persistent_lost": lost}, ([f"coverage: {len(lost)} routines reached on all three prior nights were missed"]
                                      if lost else [])


def has_issue(suite: dict) -> bool:
    return bool(suite["exit"] != 0 or suite.get("failing") or suite.get("findings"))


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
        if suite.get("failing"):
            notes.append(f"{len(suite['failing'])} failing")
        if suite.get("findings"):
            notes.append(f"{len(suite['findings'])} findings")
        if suite.get("champion_rate") is not None:
            notes.append(f"champion {suite['champion_rate']:.0%}, stages {suite['stages_mean']}")
        lines.append(f"| {suite['suite']} | {suite['exit']} | {suite['seconds'] // 60} | {'; '.join(notes)} |")
    if report.get("runner_error"):
        lines += ["", f"Runner failure: {report['runner_error']}"]
    if report.get("coverage_delta"):
        delta = report["coverage_delta"]
        lines += ["", f"Coverage versus last night: {delta['gained']} routines newly reached, {delta['lost']} lost."]
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
        if (not latest and not report.get("runner_error") and
                [s["suite"] for s in report["suites"]] == list(SUITES)):
            latest = report.get("finished_at") or dt.datetime.fromtimestamp(
                (folder / "report.json").stat().st_mtime, dt.timezone.utc).isoformat()
        outcomes = {s["suite"]: ("Issue" if has_issue(s) else "Pass") for s in report["suites"]}
        headline = report.get("status") or ("Historical issues" if report.get("failed") else "clean")
        cells = "".join(f"<td>{outcomes.get(name, '-')}</td>" for name in SUITES)
        rows.append(f'<tr><th scope="row"><a href="{quote(folder.name)}/report.md">'
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
    report["seconds"] = round(time.monotonic() - started)
    report["finished_at"] = timestamp()
    report["failed"] = bool(report.get("runner_error")) or any(has_issue(s) for s in report["suites"])
    report["status"] = status(report)
    write_markdown(report, night)
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

    args.reports.mkdir(parents=True, exist_ok=True)
    if args.index_only:
        write_index(args.reports)
        return 0
    started = time.monotonic()
    now = dt.datetime.now()
    worktree = args.worktree.resolve()
    report = {"date": f"{now:%Y-%m-%d %H:%M}", "sha": "unknown", "quick": args.quick,
              "subject": "", "ref": args.ref, "worktree": str(worktree),
              "suites": [], "requested_suites": suites, "regressions": []}
    night = None
    try:
        with nightly_lock(args.reports):
            sha = git("rev-parse", "--verify", f"{args.ref}^{{commit}}")
            history = list(previous_reports(args.reports, args.reports, args.quick, suites))
            last = history[0][1] if history else None
            if last and last["sha"] == sha and not args.force:
                print(f"{sha[:8]} already has a report ({last['night']}); --force to run again")
                return 0
            night = args.reports / f"{now:%Y-%m-%d_%H%M%S_%f}_{sha[:8]}"
            night.mkdir()
            report.update(sha=sha, subject=git("log", "-1", "--format=%s", sha), night=str(night))
            prepare_worktree(worktree, sha)
            for name in suites:
                print(f"[{dt.datetime.now():%H:%M}] {name} ...", flush=True)
                result = run_suite(name, worktree, night, args.quick)
                report["suites"].append(result)
                print(f"    exit {result['exit']} in {result['seconds'] // 60} min"
                      + (f", {len(result.get('findings', []))} findings" if "findings" in result else "")
                      + (f", {len(result['failing'])} failing" if result.get("failing") else ""), flush=True)
                if name == "build" and result["exit"] != 0:
                    break
            report["regressions"] = regressions(report, last)
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
            return 1 if report["regressions"] else 0
    except Exception as error:
        if not isinstance(error, NightlyBusy):
            traceback.print_exc()
        if night is None:
            night = args.reports / f"{now:%Y-%m-%d_%H%M%S_%f}_runner"
            night.mkdir()
        report.update(runner_error=str(error), night=str(night))
        finish_report(report, night, started)
        return 2


if __name__ == "__main__":
    sys.exit(main())
