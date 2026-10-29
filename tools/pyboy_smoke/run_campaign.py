"""Isolated, resumable bounded autoplay cases. No checkout or game mutations.

Config format: {"cases": [{"id": "dmg", "args": ["--seeds", "1", ...]}]}.
Run: python3 tools/pyboy_smoke/run_campaign.py config.json --output <new directory>
Resume with the same command. Each case runs run_autoplay.py in a separate
process and artifact directory. scenario='purchase' or 'sram' selects a directed
worker. A timeout is budget exhaustion, not a game hang.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
RUNNER = Path(__file__).with_name("run_autoplay.py")


def case_parser(case):
    kind = case.get("scenario", "autoplay")
    if kind == "purchase":
        import purchase_scenario
        return purchase_scenario.build_parser()
    if kind == "sram":
        import sram_fuzz
        return sram_fuzz.build_parser()
    if kind != "autoplay":
        raise ValueError(f"unknown scenario: {kind}")
    import run_autoplay
    return run_autoplay.build_parser()


def normalize_summary(case, summary):
    if case.get("scenario") == "sram":
        expected = summary["expected_fills"]
        records = summary["records"]
        if not isinstance(expected, list) or not isinstance(records, list) or not expected:
            raise ValueError("SRAM requires expected and observed per-fill records")
        key = lambda row: (row["seed"], row["fill"], row["repetition"])
        if len({key(row) for row in expected}) != len(expected) or len({key(row) for row in records}) != len(records):
            raise ValueError("duplicate SRAM fill identities")
        if {task["seed"] for task in expected} != set(summary["seeds"]):
            raise ValueError("expected SRAM fills do not match seeds")
        if any(key(row) not in {key(task) for task in expected} for row in records):
            raise ValueError("unexpected SRAM fill")
        rows = []
        for seed in summary["seeds"]:
            actual = [row for row in records if row["seed"] == seed]
            wanted = [row for row in expected if row["seed"] == seed]
            complete = len(actual) == len(wanted) and all(row["execution"] == "completed" for row in actual)
            compared = complete and all(type(row.get("equivalent")) is bool for row in actual)
            rows.append({"seed": seed, "outcome": "completed" if compared else "unreached",
                         "anomalies": [d for d in summary["divergences"] if d["seed"] == seed] +
                                      [a for row in actual for a in row.get("anomalies", [])],
                         "sram_fills": sum(row["execution"] == "completed" and row.get("equivalent") is True
                                           and row["fill"] != "zero" for row in actual) if compared else 0})
        return {"runs": rows}
    return summary


def achieved_exposure(summary):
    if not isinstance(summary, dict) or not isinstance(summary.get("runs", []), list):
        raise ValueError("summary runs must be a list")
    counts = dict(completed_runs=0, stages=0, save_round_trips=0, power_cuts=0, purchase_cases=0, sram_fills=0)
    for row in summary.get("runs", []):
        if not isinstance(row, dict):
            raise ValueError("run must be an object")
        for field in ("stages_cleared", "sram_fills"):
            value = row.get(field, 0)
            if type(value) is not int or value < 0:
                raise ValueError(f"invalid nonnegative count: {field}")
        for field in ("run_records", "cases"):
            if not isinstance(row.get(field, []), list):
                raise ValueError(f"{field} must be a list")
        counts["completed_runs"] += len(row.get("run_records", []))
        counts["stages"] += row.get("stages_cleared", 0)
        counts["purchase_cases"] += sum(c.get("execution") == "completed" for c in row.get("cases", []))
        counts["sram_fills"] += row.get("sram_fills", 0)
        if row.get("report"):
            data = json.loads(Path(row["report"]).read_text())
            if not isinstance(data, dict):
                raise ValueError("per-seed report must be an object")
            checks = data.get("save_checks")
            if checks is None:
                checks = {}
            if not isinstance(checks, dict):
                raise ValueError("save_checks must be an object")
            for field in ("round_trips", "power_cuts"):
                if not isinstance(checks.get(field, []), list) or any(
                        not isinstance(item, dict) for item in checks.get(field, [])):
                    raise ValueError(f"{field} must contain objects")
            counts["save_round_trips"] += sum(t.get("status") == 2 and t.get("overworld") and not t.get("skipped")
                                                for t in checks.get("round_trips", []))
            counts["power_cuts"] += len(checks.get("power_cuts", []))
    return counts


def evidence_inventory(attempt, summary):
    """Required evidence is immutable; screenshots alone are optional on resume.

    Inventory all worker artifacts, including unreferenced replay states. Reports
    named by the summary must exist inside this attempt, never another run.
    """
    artifacts = (attempt / "artifacts").resolve()
    for row in summary["runs"]:
        if row.get("report"):
            report = Path(row["report"]).resolve()
            if not report.is_relative_to(artifacts) or not report.is_file():
                raise ValueError("referenced report missing or outside attempt")
    entries = []
    for path in sorted(artifacts.rglob("*")):
        if not path.is_file():
            continue
        if path.is_symlink() or not path.resolve().is_relative_to(artifacts):
            raise ValueError("artifact escapes attempt")
        kind = ("replay_state" if path.suffix == ".state" else
                "case_record" if path.name == "case.json" else
                "input_log" if "input" in path.name else
                "build_identity" if "identity" in path.name else
                "report" if path.suffix == ".json" else
                "screenshot" if path.suffix == ".png" else "worker_evidence")
        entries.append({"path": str(path.relative_to(attempt)), "kind": kind,
                        "required": kind != "screenshot", "sha256": digest(path)})
    return entries


def validate_retained_evidence(result):
    inventory = result.get("evidence_dependencies")
    if not isinstance(inventory, list) or not inventory:
        return "required evidence inventory missing; legacy result is unverified"
    attempt = Path(result["attempt"]).resolve()
    for entry in inventory:
        if not entry.get("required"):
            continue
        path = (attempt / entry["path"]).resolve()
        if not path.is_relative_to(attempt) or not path.is_file() or digest(path) != entry["sha256"]:
            return f"required {entry['kind']} missing or changed: {entry['path']}"
    summary = Path(result["summary"]) if result.get("summary") else None
    if summary is None or not summary.is_file() or digest(summary) != result.get("summary_sha256"):
        return "completed case summary missing or changed"
    return None


def validate_campaign_archive(output, manifest):
    for name, expected in manifest["identity"]["builds"].items():
        path = output / "build" / name
        if not path.is_file() or digest(path) != expected:
            raise ValueError(f"archived build missing or changed: {name}")
    for name, expected in manifest.get("archive_hashes", {}).items():
        path = output / name
        if not path.is_file() or digest(path) != expected:
            raise ValueError(f"campaign archive missing or changed: {name}")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def source_identity():
    snapshot_path = ROOT / "snapshot_identity.json"
    if snapshot_path.exists():
        snapshot = json.loads(snapshot_path.read_text())
        names = [name for name in snapshot["files"] if not name.endswith((".gbc", ".sym"))]
        return {"head": snapshot["head"], "status": "dedicated source snapshot",
                "files": {name: digest(ROOT / name) if (ROOT / name).is_file() else None for name in names}}
    def git(*args):
        return subprocess.check_output(["git", *args], cwd=ROOT)
    paths = git("ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0")
    files = {}
    for raw in paths:
        if raw:
            name = os.fsdecode(raw)
            path = ROOT / name
            files[name] = digest(path) if path.is_file() else None
    return {"head": git("rev-parse", "HEAD").decode().strip(),
            "status": git("status", "--porcelain=v1").decode(), "files": files}


def build_identity():
    return {f"{rom}.{ext}": digest(ROOT / f"{rom}.{ext}")
            for rom in ("pokered", "pokeblue", "pokeblue_debug") for ext in ("gbc", "sym")}


def validate_config(config):
    import run_autoplay
    cases = config["cases"]
    if not cases:
        raise ValueError("campaign has no cases")
    ids = set()
    for case in cases:
        name = case["id"]
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}", name) or name in ids:
            raise ValueError(f"unsafe or duplicate case id: {name}")
        ids.add(name)
        args = case_parser(case).parse_args(case["args"])
        expected_verdict = case.get("expected_verdict", "no_issue_detected")
        if expected_verdict not in ("no_issue_detected", "contract_violation"):
            raise ValueError("unsupported expected verdict")
        if expected_verdict == "contract_violation" and not (
                case.get("scenario") == "purchase" and args.control_overcharge):
            raise ValueError("an expected violation requires the isolated purchase detector control")
        if expected_verdict == "contract_violation":
            expected = case.get("expected_findings")
            if not isinstance(expected, list) or not expected or any(
                    not isinstance(finding, dict) or set(finding) != {
                        "check", "version", "field", "evidence_origin"} or
                    finding["evidence_origin"] != "controlled_detector_input" for finding in expected):
                raise ValueError("expected control requires an exact finding multiset with provenance")
        seeds = run_autoplay.parse_seeds(args.seeds)
        if not seeds or len(seeds) != len(set(seeds)):
            raise ValueError("case seeds must be nonempty and unique")
        if args.jobs < 1 or args.timeout <= 0:
            raise ValueError("jobs and timeout must be positive")
        for key, value in case.get("required_exposure", {}).items():
            if key not in achieved_exposure({}) or not isinstance(value, int) or value < 0:
                raise ValueError(f"invalid exposure quota: {key}={value}")
    return cases


def classify(exit_code, summary, execution):
    if execution != "completed":
        return "incomplete"
    if summary is None:
        return "harness_error"
    rows = summary.get("runs", [])
    if not rows:
        return "harness_error"
    if any(row.get("outcome") == "error" for row in rows):
        return "harness_error"
    if any(row.get("outcome") in ("hung", "frame_limit") for row in rows):
        return "incomplete"
    if any(row.get("outcome") not in ("completed", "blackout", "champion", "stalled", "crashed") for row in rows):
        return "incomplete"
    if any(row.get("contract_findings") for row in rows):
        return "contract_violation"
    return "suspected_issue" if exit_code or any(
        row.get("anomalies") or row.get("save_findings") or
        (row.get("branches") or {}).get("findings") or
        row.get("outcome") in ("stalled", "crashed") for row in rows) else "no_issue_detected"


def control_matches(case, summary, execution, exit_code, missing):
    """A controlled fault never excuses an extra finding or incomplete work."""
    if execution != "completed" or missing or summary is None or exit_code != 1:
        return False
    rows = summary.get("runs", [])
    if not rows or any(row.get("outcome") != "completed" or row.get("anomalies") or
                       row.get("save_findings") or (row.get("branches") or {}).get("findings")
                       for row in rows):
        return False
    keys = ("check", "version", "field", "evidence_origin")
    actual = Counter(tuple(finding.get(key) for key in keys)
                     for row in rows for finding in row.get("contract_findings", []))
    expected = Counter(tuple(finding.get(key) for key in keys)
                       for finding in case.get("expected_findings", []))
    return bool(expected) and actual == expected


def execute_case(case, directory, budget):
    directory.mkdir(parents=True, exist_ok=True)
    # Keep interrupted attempts intact, including their partial output.
    attempt = directory / f"attempt-{time.time_ns()}"
    attempt.mkdir()
    artifacts = attempt / "artifacts"
    artifacts.mkdir()
    workers = {"purchase": "purchase_scenario.py", "sram": "sram_fuzz.py"}
    runner = Path(__file__).with_name(workers[case["scenario"]]) if case.get("scenario") in workers else RUNNER
    command = [sys.executable, str(runner), *case["args"]]
    memory_log = attempt / "peak_rss_kib.txt"
    if shutil.which("time"):
        command = [shutil.which("time"), "-f", "%M", "-o", str(memory_log), *command]
    env = dict(os.environ, REDROGUE_AUTOPLAY_ARTIFACTS=str(artifacts))
    started = time.monotonic()
    execution, code = "completed", None
    with (attempt / "worker.log").open("w") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=budget)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
            execution = "budget_exhausted" if isinstance(error, subprocess.TimeoutExpired) else "cancelled"
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
    summaries = list(artifacts.glob("sram_fuzz_summary.json" if case.get("scenario") == "sram" else "autoplay_summary*.json"))
    summary, detail = None, None
    exposure, missing = {}, {}
    dependencies = []
    if len(summaries) == 1:
        try:
            summary = normalize_summary(case, json.loads(summaries[0].read_text()))
            import run_autoplay
            expected = run_autoplay.parse_seeds(case_parser(case).parse_args(case["args"]).seeds)
            if sorted(row["seed"] for row in summary["runs"]) != sorted(expected):
                detail, summary = "missing or duplicated seed results", None
            if summary is not None:
                exposure = achieved_exposure(summary)
                dependencies = evidence_inventory(attempt, summary)
                missing = {key: {"required": value, "achieved": exposure[key]}
                           for key, value in case.get("required_exposure", {}).items() if exposure[key] < value}
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
            detail = f"invalid worker summary: {error}"
            summary = None
    else:
        detail = f"expected one summary, found {len(summaries)}"
    if summary is None:
        # A partial read is not a measured zero, nor evidence of satisfied quotas.
        exposure = {}
        missing = {key: {"required": value, "achieved": None, "status": "unknown"}
                   for key, value in case.get("required_exposure", {}).items()}
    verdict = classify(code, summary, execution)
    if missing and verdict == "no_issue_detected":
        verdict = "incomplete"
    peak_rss = None
    if memory_log.exists():
        lines = memory_log.read_text().splitlines()
        if lines and lines[-1].isdigit():
            peak_rss = int(lines[-1])
    result = {"schema_version": 1, "case": case, "execution": execution,
              "verdict": verdict, "exit": code, "achieved_exposure": exposure, "missing_exposure": missing,
              "worker_tree_peak_rss_kib": peak_rss,
              "seconds": round(time.monotonic() - started, 3), "detail": detail,
              "attempt": str(attempt), "command": command,
              "environment": {"REDROGUE_AUTOPLAY_ARTIFACTS": str(artifacts)},
              "summary": str(summaries[0]) if len(summaries) == 1 else None,
              "summary_sha256": digest(summaries[0]) if len(summaries) == 1 else None,
              "evidence_dependencies": dependencies,
              "expected_control_matched": control_matches(case, summary, execution, code, missing)
                  if case.get("expected_verdict") == "contract_violation" else None,
              "artifact_bytes": sum(p.stat().st_size for p in attempt.rglob("*") if p.is_file())}
    atomic_json(directory / "result.json", result)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--case-budget", type=float, default=300)
    parser.add_argument("--campaign-budget", type=float, default=900)
    args = parser.parse_args(argv)
    if os.name != "posix":
        parser.error("run under WSL; worker process groups require POSIX")
    if args.case_budget <= 0 or args.campaign_budget <= 0:
        parser.error("budgets must be positive")
    config = json.loads(args.config.read_text())
    cases = validate_config(config)
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    import fcntl
    with (output.parent / f".{output.name}.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("another controller holds this campaign") from None
        return run_campaign(args, config, cases)


def run_campaign(args, config, cases):
    started = time.monotonic()
    output = args.output.resolve()
    manifest_path = output / "manifest.json"
    identity = {"source": source_identity(), "builds": build_identity(),
                "python": platform.python_version(), "pyboy": importlib.metadata.version("pyboy"),
                "platform": platform.platform(), "config": config, "case_budget": args.case_budget,
                "campaign_budget": args.campaign_budget}
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        if manifest["identity"] != identity:
            raise ValueError("source, build, runtime, or configuration changed; use a new campaign directory")
    else:
        output.mkdir(parents=True, exist_ok=False)
        manifest = {"schema_version": 1, "identity": identity, "created_unix": time.time(),
                    "replay": [sys.executable, str(Path(__file__).resolve()),
                               str(output / "config.json"), "--output", str(output),
                               "--case-budget", str(args.case_budget), "--campaign-budget", str(args.campaign_budget)]}
        atomic_json(output / "config.json", config)
        build_dir = output / "build"
        build_dir.mkdir()
        for name in identity["builds"]:
            shutil.copyfile(ROOT / name, build_dir / name)
        with tarfile.open(output / "source.tar.gz", "w:gz") as archive:
            for name, sha in identity["source"]["files"].items():
                if sha is not None:
                    archive.add(ROOT / name, arcname=name, recursive=False)
        (output / "source.patch").write_bytes(b"" if (ROOT / "snapshot_identity.json").exists() else
            subprocess.check_output(["git", "diff", "HEAD", "--binary"], cwd=ROOT))
        manifest["archive_hashes"] = {name: digest(output / name)
                                      for name in ("source.tar.gz", "source.patch", "config.json")}
        atomic_json(manifest_path, manifest)
    validate_campaign_archive(output, manifest)
    results = []
    for case in cases:
        if source_identity() != identity["source"] or build_identity() != identity["builds"]:
            raise ValueError("source/build changed during campaign; stopped before next case")
        directory = output / case["id"]
        path = directory / "result.json"
        result = json.loads(path.read_text()) if path.exists() else None
        if result is not None and result["execution"] == "completed":
            evidence_error = validate_retained_evidence(result)
            if evidence_error:
                result.setdefault("original_verdict", result["verdict"])
                result.update(verdict="harness_error", detail=evidence_error)
                atomic_json(path, result)
        if result is None or result["execution"] != "completed":
            remaining = args.campaign_budget - (time.monotonic() - started)
            if remaining <= 0:
                result = {"case": case, "execution": "budget_exhausted", "verdict": "incomplete", "seconds": 0}
                atomic_json(path, result)
            else:
                result = execute_case(case, directory, min(args.case_budget, remaining))
        if source_identity() != identity["source"] or build_identity() != identity["builds"]:
            result.update(execution="invalidated", verdict="incomplete", detail="source/build changed during case")
            atomic_json(path, result)
        results.append(result)
        atomic_json(output / "results.json", {"schema_version": 1, "cases": results})
        (output / "summary.md").write_text(
            "# Bounded autoplay campaign\n\n"
            + "\n".join(f"- {r['case']['id']}: {r['execution']} / {r['verdict']} ({r['seconds']}s); "
                        f"expected {r['case'].get('expected_verdict', 'no_issue_detected')}"
                        for r in results)
            + "\n\nNo issue detected applies only to the recorded checks and achieved exposure.\n",
            encoding="utf-8")
        print(f"{case['id']}: {result['execution']} / {result['verdict']}", flush=True)
        if result["execution"] in ("cancelled", "invalidated"):
            break
    return int(len(results) != len(cases) or any(
        r["verdict"] != r["case"].get("expected_verdict", "no_issue_detected") or r.get("missing_exposure") or
        (r["case"].get("expected_verdict") == "contract_violation" and not r.get("expected_control_matched"))
        for r in results))


if __name__ == "__main__":
    sys.exit(main())
