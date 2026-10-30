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
import math
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
_PHASE_SINK = None


def measured(name, operation):
    started = time.monotonic()
    if _PHASE_SINK is not None:
        _PHASE_SINK({"kind": "phase", "name": name, "state": "start"})
    try:
        return operation()
    finally:
        if _PHASE_SINK is not None:
            _PHASE_SINK({"kind": "phase", "name": name, "state": "end",
                         "seconds": round(time.monotonic() - started, 6)})


def case_parser(case):
    kind = case.get("scenario", "autoplay")
    if kind == "directed":
        import directed_scenario
        return directed_scenario.build_parser()
    if kind == "credit":
        import credit_scenario
        return credit_scenario.build_parser()
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
    if case.get('scenario') == 'directed':
        import directed_scenario
        args = case_parser(case).parse_args(case.get('args', []))
        rows = summary['runs']
        if len(rows) != 1:
            raise ValueError('directed requires one fixed catalog identity')
        row = directed_scenario.read_report(Path(rows[0]['report']), args)
        if rows != [row]:
            raise ValueError('directed summary differs from audited evidence')
        return {'runs': [row]}
    if case.get("scenario") == "credit":
        import credit_scenario
        args = case_parser(case).parse_args(case.get('args', []))
        rows = summary['runs']
        if len(rows) != 1:
            raise ValueError('credit requires one fixed fixture seed')
        row = credit_scenario.read_report(Path(rows[0]['report']), args)
        if rows != [row]:
            raise ValueError('credit summary differs from audited evidence')
        return {'runs': [row]}
    if case.get("scenario") == "sram":
        matched_requested = case_parser(case).parse_args(case.get("args", [])).matched_controls
        if matched_requested or summary.get("comparison_mode"):
            return normalize_matched_sram(case, summary)
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


def normalize_matched_sram(case, summary):
    from sram_fuzz import MATCHED_MODE, evaluate_matched_pair, play_options
    from run_autoplay import parse_seeds
    args = case_parser(case).parse_args(case.get("args", []))
    if not args.matched_controls or summary.get("schema_version") != 2 or summary.get("comparison_mode") != MATCHED_MODE:
        raise ValueError("matched-control schema/configuration mismatch")
    if summary.get("options") != play_options(args):
        raise ValueError("worker play options differ from configured scenario")
    seeds = parse_seeds(args.seeds)
    fills = ["ff"] + [f"random{k}" for k in range(1, args.fills + 1)]
    wanted_pairs = {(seed, fill) for seed in seeds for fill in fills}
    pairs, results = summary["expected_comparisons"], summary["initialization_comparisons"]
    tasks, records = summary["expected_fills"], summary["records"]
    if any(not isinstance(value, list) for value in (pairs, results, tasks, records)) or summary["seeds"] != seeds:
        raise ValueError("invalid matched-control lists/seeds")
    if any(type(seed) is not int for seed in summary["seeds"]) or any(type(row["seed"]) is not int for row in pairs + results):
        raise ValueError("invalid matched comparison seed type")
    if any(type(row["seed"]) is not int or type(row["repetition"]) is not int for row in tasks + records):
        raise ValueError("invalid seed/repetition type")
    key = lambda row: (row["seed"], row["fill"])
    identity = lambda row: (row["seed"], row["fill"], row["repetition"])
    if len(pairs) != len(wanted_pairs) or {key(pair) for pair in pairs} != wanted_pairs:
        raise ValueError("configured matched comparisons missing or duplicated")
    wanted_roles = {(seed, "zero", repetition): "baseline" for seed in seeds for repetition in (0, 1)}
    for pair in pairs:
        if pair["control_fill"] != f"control_{pair['fill']}":
            raise ValueError("unexpected control identity")
        for name, role in ((pair["fill"], "candidate"), (pair["control_fill"], "matched_control")):
            for repetition in (0, 1):
                wanted_roles[(pair["seed"], name, repetition)] = role
    if len(tasks) != len(wanted_roles) or {identity(task) for task in tasks} != set(wanted_roles):
        raise ValueError("expected matched fill set does not match configuration")
    if len({Path(task['directory']).resolve() for task in tasks}) != len(tasks):
        raise ValueError('matched physical attempts share an evidence directory')
    if any(task["role"] != wanted_roles[identity(task)] for task in tasks):
        raise ValueError("invalid expected matched roles")
    expected = {identity(task): task for task in tasks}
    if len({identity(row) for row in records}) != len(records):
        raise ValueError("duplicated matched worker record")
    for row in records:
        task = expected.get(identity(row))
        if task is None or any(row[field] != task[field] for field in ("role", "directory", "input_sha256")):
            raise ValueError("worker record differs from expected matched task")
        if row["execution"] == "completed" and (
                row["hardware_mode"] != ("CGB" if args.cgb else "DMG") or
                row["comparison_boundary"]["rng_boundary"] != ("OakSpeech" if args.new_game else "SelectAndPatchLobbyExit")):
            raise ValueError("worker hardware/startup boundary differs from configuration")
    if len({key(row) for row in results}) != len(results) or any(key(row) not in wanted_pairs for row in results):
        raise ValueError("unexpected or duplicated initialization comparison")
    for row in results:
        if row["status"] not in ("equivalent", "divergent", "incomplete", "invalid_evidence", "confounded", "unstable"):
            raise ValueError("unknown matched comparison status")
        if row["status"] in ("equivalent", "divergent"):
            pair = next(pair for pair in pairs if key(pair) == key(row))
            recomputed = evaluate_matched_pair(pair, records)
            if recomputed["status"] != row["status"] or recomputed.get("event_index") != row.get("event_index"):
                raise ValueError("matched comparison disagrees with retained evidence")
    rows = []
    for seed in seeds:
        actual = [row for row in records if row["seed"] == seed]
        compared = [row for row in results if row["seed"] == seed]
        complete = (len(actual) == sum(task["seed"] == seed for task in tasks)
                    and all(row["execution"] == "completed" for row in actual)
                    and len(compared) == len(fills) and summary.get("comparison_errors") == []
                    and all(row["status"] in ("equivalent", "divergent") for row in compared))
        findings = [row for row in compared if row["status"] == "divergent"]
        findings += [row for row in summary.get("divergences", []) if row["seed"] == seed and row not in findings]
        findings += [finding for row in actual for finding in row.get("anomalies", [])]
        rows.append({"seed": seed, "outcome": "error" if any(row["execution"] == "error" for row in actual)
                     else "completed" if complete else "unreached", "anomalies": findings,
                     "sram_fills": sum(row["status"] == "equivalent" for row in compared) if complete else 0,
                     "detector_reports": [{"seed": row['seed'], 'fill': row['fill'],
                         'repetition': row['repetition'], 'role': row['role'],
                         'report': str(Path(row['directory']) / 'report.json')}
                         for row in actual]})
    return {"runs": rows}


def achieved_exposure(summary):
    if not isinstance(summary, dict) or not isinstance(summary.get("runs", []), list):
        raise ValueError("summary runs must be a list")
    counts = dict(completed_runs=0, stages=0, save_round_trips=0, power_cuts=0, purchase_cases=0, credit_cases=0, sram_fills=0, corpus_states=0)
    counts.update(directed_chains=0, directed_credit_chains=0, directed_trade_chains=0,
                  directed_teaching_empty_chains=0, directed_teaching_full_chains=0)
    corpus_hashes = set()
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
        counts["purchase_cases"] += sum(c.get("execution") == "completed" and c.get('family', 'purchase') == 'purchase' for c in row.get("cases", []))
        counts["credit_cases"] += sum(c.get("execution") == "completed" and c.get('family') == 'credit' for c in row.get("cases", []))
        for chain in row.get('cases', []):
            if chain.get('family') == 'directed' and chain.get('execution') == 'completed':
                key = 'directed_' + chain.get('chain_family', '') + '_chains'
                if key not in counts:
                    raise ValueError('unknown directed chain family')
                counts['directed_chains'] += 1
                counts[key] += 1
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
            retained = (data.get('branches') or {}).get('retained_snapshots', [])
            if not isinstance(retained, list):
                raise ValueError('retained snapshots must be a list')
            for record in retained:
                state, metadata_path = Path(record['state']), Path(record['metadata'])
                root = Path(row['report']).resolve().parent
                if any(path.is_symlink() or not path.resolve().is_relative_to(root) or not path.is_file()
                       for path in (state, metadata_path)):
                    raise ValueError('corpus evidence missing or outside report directory')
                if metadata_path.resolve() != state.with_suffix(state.suffix + '.json').resolve():
                    raise ValueError('corpus metadata is not paired with state')
                metadata = json.loads(metadata_path.read_text())
                if (not isinstance(metadata, dict) or type(metadata.get('schema_version')) is not int or
                        metadata['schema_version'] != 1 or not isinstance(metadata.get('origin'), dict) or
                        not isinstance(metadata['origin'].get('info'), dict)):
                    raise ValueError('unsupported or incomplete corpus provenance')
                if metadata != {key: value for key, value in record.items() if key not in ('state', 'metadata')}:
                    raise ValueError('corpus metadata differs from report')
                expected = {'rom_sha256': data['build_identity']['gbc'], 'sym_sha256': data['build_identity']['sym'],
                            'hardware_mode': data['hardware_mode']}
                if metadata['identity'] != expected or digest(state) != metadata['state_sha256']:
                    raise ValueError('corpus state/build identity mismatch')
                corpus_hashes.add(metadata['state_sha256'])
    counts['corpus_states'] = len(corpus_hashes)
    return counts


def evidence_inventory(attempt, summary):
    """Required evidence is immutable; screenshots alone are optional on resume.

    Inventory all worker artifacts, including unreferenced replay states. Reports
    named by the summary must exist inside this attempt, never another run.
    """
    artifacts = (attempt / "artifacts").resolve()
    for row in summary["runs"]:
        for physical in [row, *row.get('detector_reports', [])]:
            if physical.get("report"):
                report = Path(physical["report"]).resolve()
                if not report.is_relative_to(artifacts) or not report.is_file():
                    raise ValueError("referenced report missing or outside attempt")
    entries = []
    for path in sorted(artifacts.rglob("*")):
        if path.is_symlink():
            raise ValueError("artifact escapes attempt")
        if not path.is_file():
            continue
        if not path.resolve().is_relative_to(artifacts):
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
    try:
        from detector_health import assess
        health = assess(result['case'], normalize_summary(result['case'], json.loads(summary.read_text())))
        if any(row['status'] in ('error', 'incomplete') for row in health):
            return 'retained detector requirements failed'
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        return f'invalid retained detector evidence: {error}'
    return None


def validate_campaign_archive(output, manifest):
    build_root = output / manifest.get("preparation", ".") / "build"
    for name, expected in manifest["identity"]["builds"].items():
        path = build_root / name
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
            for rom in ("pokered", "pokeblue", "pokeblue_debug") for ext in ("gbc", "sym", "map")}


def validate_config(config):
    import run_autoplay
    cases = config["cases"]
    if not cases:
        raise ValueError("campaign has no cases")
    ids = set()
    for case in cases:
        from detector_health import validate_requirements, validate_schema
        validate_requirements(case.get('required_detectors', {}))
        validate_schema(case.get('required_detector_schema'))
        name = case["id"]
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}", name) or name in ids:
            raise ValueError(f"unsafe or duplicate case id: {name}")
        ids.add(name)
        args = case_parser(case).parse_args(case["args"])
        if case.get('scenario') == 'directed' and args.control_identity and args.case != 'trade':
            raise ValueError('identity control requires trade fixture')
        if case.get('scenario') == 'credit' and args.control_credit_balance and args.case != 'exact':
            raise ValueError('credit balance control requires exact fixture')
        expected_verdict = case.get("expected_verdict", "no_issue_detected")
        if expected_verdict not in ("no_issue_detected", "contract_violation"):
            raise ValueError("unsupported expected verdict")
        if expected_verdict == "contract_violation" and not (
                (case.get("scenario") == "purchase" and args.control_overcharge) or
                (case.get("scenario") == "credit" and args.control_credit_balance and args.case == 'exact') or
                (case.get('scenario') == 'directed' and args.control_identity and args.case == 'trade')):
            raise ValueError("an expected violation requires an isolated transaction detector control")
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
            if key.startswith('directed_') and case.get('scenario') != 'directed':
                raise ValueError('directed quotas require audited directed evidence')
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
    workers = {"purchase": "purchase_scenario.py", "credit": "credit_scenario.py", "directed": "directed_scenario.py", "sram": "sram_fuzz.py"}
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
    health = []
    if summary is not None:
        try:
            from detector_health import assess
            health = assess(case, summary)
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
            detail, summary = f'invalid detector evidence: {error}', None
    verdict = classify(code, summary, execution)
    if any(row['status'] == 'error' for row in health):
        verdict = 'harness_error'
    elif any(row['status'] == 'incomplete' for row in health) and verdict == 'no_issue_detected':
        verdict = 'incomplete'
    if missing and verdict == "no_issue_detected":
        verdict = "incomplete"
    peak_rss = None
    if memory_log.exists():
        lines = memory_log.read_text().splitlines()
        if lines and lines[-1].isdigit():
            peak_rss = int(lines[-1])
    result = {"schema_version": 1, "case": case, "execution": execution,
              "verdict": verdict, "exit": code, "achieved_exposure": exposure, "missing_exposure": missing,
              'evidence_valid': summary is not None,
              "detector_health": health,
              "worker_tree_peak_rss_kib": peak_rss,
              "seconds": round(time.monotonic() - started, 3), "detail": detail,
              "attempt": str(attempt), "command": command,
              "environment": {"REDROGUE_AUTOPLAY_ARTIFACTS": str(artifacts)},
              "summary": str(summaries[0]) if len(summaries) == 1 else None,
              "summary_sha256": digest(summaries[0]) if len(summaries) == 1 else None,
              "evidence_dependencies": dependencies,
              "expected_control_matched": control_matches(case, summary, execution, code, missing)
                  and not any(row['status'] in ('error', 'incomplete') for row in health)
                  if case.get("expected_verdict") == "contract_violation" else None,
              "artifact_bytes": sum(p.stat().st_size for p in attempt.rglob("*") if p.is_file())}
    from campaign_reporting import dimensions
    result['dimensions'] = dimensions(result, summary)
    atomic_json(directory / "result.json", result)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--case-budget", type=float, default=300)
    parser.add_argument("--campaign-budget", type=float, default=900)
    parser.add_argument("--storage-budget-mib", type=float, default=256)
    parser.add_argument("--rss-budget-mib", type=float, default=1024)
    args = parser.parse_args(argv)
    if os.name != "posix":
        parser.error("run under WSL; worker process groups require POSIX")
    budgets = (args.case_budget, args.campaign_budget, args.storage_budget_mib, args.rss_budget_mib)
    if any(not math.isfinite(value) or value <= 0 for value in budgets):
        parser.error("budgets must be finite and positive")
    output = args.output.resolve()
    if not native_storage(output):
        parser.error("campaign output must be on native Linux storage (for example /tmp); export evidence afterward")
    output.parent.mkdir(parents=True, exist_ok=True)
    import fcntl
    with (output.parent / f".{output.name}.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("another controller holds this campaign") from None
        from campaign_limits import supervise
        audit = supervise(controller_entry, args)
        output.mkdir(parents=True, exist_ok=True)
        atomic_json(output / "supervision.json", audit)
        atomic_json(output / "supervision_attempts" / f"{time.time_ns()}.json", audit)
        results_path = output / "results.json"
        try:
            results = json.loads(results_path.read_text()) if results_path.exists() else {"schema_version": 1, "cases": []}
        except (OSError, ValueError):
            results = {"schema_version": 1, "cases": [], "detail": "controller results unavailable"}
        results.update(campaign_execution=audit["execution"], campaign_verdict=audit["verdict"])
        atomic_json(results_path, results)
        with (output / "summary.md").open("a", encoding="utf-8") as summary:
            summary.write(f"\nCampaign supervision: {audit['execution']} / {audit['verdict']} ({audit['seconds']}s).\n")
        if audit["execution"] != "completed":
            print(f"campaign: {audit['execution']} / {audit['verdict']}; phase {audit['phase_at_stop']}", flush=True)
        return audit["exit"]


def native_storage(path):
    """Monitoring must not block on the filesystem that exhausted prep time."""
    mounts = []
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        fields, filesystem = line.split(" - ", 1)
        mount = Path(fields.split()[4].replace("\\040", " ").replace("\\134", "\\"))
        if path.is_relative_to(mount):
            mounts.append((len(str(mount)), filesystem.split()[0]))
    return max(mounts)[1] in ("ext4", "xfs", "btrfs", "tmpfs", "overlay", "zfs")


def controller_entry(args, notify):
    global _PHASE_SINK
    _PHASE_SINK = notify
    config = measured("configuration", lambda: json.loads(args.config.read_text()))
    cases = measured("configuration_validation", lambda: validate_config(config))
    return run_campaign(args, config, cases)


def run_campaign(args, config, cases):
    started = time.monotonic()
    output = args.output.resolve()
    manifest_path = output / "manifest.json"
    identity = {"source": measured("source_identity", source_identity), "builds": measured("build_identity", build_identity),
                "python": platform.python_version(), "pyboy": importlib.metadata.version("pyboy"),
                "platform": platform.platform(), "config": config, "case_budget": args.case_budget,
                "campaign_budget": args.campaign_budget,
                "storage_budget_mib": getattr(args, "storage_budget_mib", 256),
                "rss_budget_mib": getattr(args, "rss_budget_mib", 1024)}
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        if manifest["identity"] != identity:
            raise ValueError("source, build, runtime, or configuration changed; use a new campaign directory")
    else:
        output.mkdir(parents=True, exist_ok=True)
        if any((output / case["id"] / "result.json").exists() for case in cases):
            raise ValueError("manifest missing but case results exist; use a new campaign directory")
        if (output / "results.json").exists() and json.loads((output / "results.json").read_text()).get("cases"):
            raise ValueError("manifest missing but completed/partial case records remain")
        identity_path = output / "preparation_identity.json"
        if not identity_path.exists() and not (output / "supervision.json").exists():
            if any(output.iterdir()):
                raise ValueError("existing output is not an owned interrupted preparation")
        if identity_path.exists() and json.loads(identity_path.read_text()) != identity:
            raise ValueError("source/build/configuration changed after interrupted preparation")
        atomic_json(identity_path, identity)
        preparation = output / f"preparation-{time.time_ns()}"
        preparation.mkdir()
        manifest = {"schema_version": 1, "identity": identity, "created_unix": time.time(),
                    "preparation": preparation.name,
                    "replay": [sys.executable, str(Path(__file__).resolve()),
                               str(output / "config.json"), "--output", str(output),
                               "--case-budget", str(args.case_budget), "--campaign-budget", str(args.campaign_budget),
                               "--storage-budget-mib", str(getattr(args, "storage_budget_mib", 256)),
                               "--rss-budget-mib", str(getattr(args, "rss_budget_mib", 1024))]}
        atomic_json(output / "config.json", config)
        build_dir = preparation / "build"
        build_dir.mkdir()
        def archive_inputs():
            for name in identity["builds"]:
                shutil.copyfile(ROOT / name, build_dir / name)
            with tarfile.open(preparation / "source.tar.gz", "w:gz") as archive:
                for name, sha in identity["source"]["files"].items():
                    if sha is not None:
                        archive.add(ROOT / name, arcname=name, recursive=False)
            (preparation / "source.patch").write_bytes(b"" if (ROOT / "snapshot_identity.json").exists() else
                subprocess.check_output(["git", "diff", "HEAD", "--binary"], cwd=ROOT))
        measured("archive_inputs", archive_inputs)
        archive_names = [str(Path(preparation.name) / name) for name in ("source.tar.gz", "source.patch")] + ["config.json"]
        manifest["archive_hashes"] = {name: digest(output / name) for name in archive_names}
        atomic_json(manifest_path, manifest)
    measured("archive_validation", lambda: validate_campaign_archive(output, manifest))
    results = []
    for case in cases:
        if measured("source_before_case", source_identity) != identity["source"] or build_identity() != identity["builds"]:
            raise ValueError("source/build changed during campaign; stopped before next case")
        directory = output / case["id"]
        path = directory / "result.json"
        result = json.loads(path.read_text()) if path.exists() else None
        if result is not None and result["execution"] == "completed":
            evidence_error = validate_retained_evidence(result)
            if evidence_error:
                result.setdefault("original_verdict", result["verdict"])
                result.update(verdict="harness_error", detail=evidence_error)
                result['evidence_valid'] = False
                atomic_json(path, result)
        if result is None or result["execution"] != "completed":
            remaining = args.campaign_budget - (time.monotonic() - started)
            if remaining <= 0:
                result = {"case": case, "execution": "budget_exhausted", "verdict": "incomplete", "seconds": 0}
                atomic_json(path, result)
            else:
                result = measured(f"case:{case['id']}", lambda: execute_case(case, directory, min(args.case_budget, remaining)))
        if measured("source_after_case", source_identity) != identity["source"] or build_identity() != identity["builds"]:
            result.update(execution="invalidated", verdict="incomplete", detail="source/build changed during case")
            result['evidence_valid'] = False
            atomic_json(path, result)
        from campaign_reporting import dimensions, markdown
        recorded = None
        if result.get('evidence_valid', False) and result.get('summary'):
            try:
                recorded = normalize_summary(case, json.loads(Path(result['summary']).read_text()))
            except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
                result['evidence_valid'] = False
                result.update(verdict='harness_error', detail=f'final report validation failed: {error}')
        result['dimensions'] = dimensions(result, recorded)
        atomic_json(path, result)
        results.append(result)
        atomic_json(output / "results.json", {"schema_version": 1, "cases": results})
        (output / "summary.md").write_text(
            markdown(results),
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
