"""Run the Red Rogue PyBoy smoke suite in parallel worker processes.

Whole modules are packed into batches (two per worker, balanced on the last
run's durations) and run in parallel (--jobs, default: every CPU). A worker is
a process because importing pyboy costs ~2s, so one process per module would
spend ~5 minutes of CPU on imports alone (measured 2026-10-14).

Each test runs under a watchdog (--test-timeout): a test that hangs, e.g. an
illegal opcode that freezes pyboy.tick() for good, dumps its Python stack and
is reported as TIMEOUT, and the rest of its batch continues in a fresh worker.
A hang costs one test, never the whole run.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import faulthandler
import fnmatch
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest


SUITE_DIR = Path(__file__).resolve().parent
REPO_ROOT = SUITE_DIR.parents[1]
# Last run's per-module test time, used to balance the batches.
DURATIONS_CACHE = REPO_ROOT / "builds" / "smoke_durations.json"
SLOWEST_SHOWN = 10
DEFAULT_TEST_TIMEOUT_S = 180
BATCHES_PER_JOB = 2
# Modules that never start an emulator: they check source files or shell out to
# a static audit script. `make audit` runs them (--source-only), `make smoke`
# skips them. Only the slow ones live here; sub-second source checks stay in
# smoke, where moving them would buy nothing.
SOURCE_ONLY_MODULES = frozenset({
    "test_static_map_audits",        # ~45s: map text-id / object-const audits
    "test_party_roster",             # ~10s: PARTY_ROSTER.md lint and curve rules
    "test_bridge_gift_roll_range",   # ~6s
    "test_follower_sprite_budget",   # ~6s
})
# Unknown modules are scheduled as if each test took this long.
GUESS_PER_TEST_S = 0.3


# --------------------------------------------------------------------------
# Worker: runs the test IDs it is handed, recording each result as it lands.
# --------------------------------------------------------------------------

class WorkerResult(unittest.TextTestResult):
    """Arms the hang watchdog per test and appends one JSON line per result."""

    results_path: Path
    test_timeout_s: int

    def startTest(self, test):
        self._status = "ok"
        os.environ["REDROGUE_CURRENT_TEST"] = test.id()
        self._started_at = time.perf_counter()
        super().startTest(test)
        self.stream.flush()
        # A C thread, so it fires even while pyboy.tick() never returns.
        faulthandler.dump_traceback_later(self.test_timeout_s, exit=True)

    def stopTest(self, test):
        faulthandler.cancel_dump_traceback_later()
        super().stopTest(test)
        record = {"id": test.id(), "status": self._status,
                  "seconds": time.perf_counter() - self._started_at}
        self._status = None
        write_record(self.results_path, record)

    def addFailure(self, test, err):
        self._status = "fail"
        super().addFailure(test, err)

    def addError(self, test, err):
        # setUpClass/module fixture errors arrive outside start/stopTest; the
        # parent reports their tests as errors via the worker's "done" marker.
        if getattr(self, "_status", None) is not None:
            self._status = "error"
        super().addError(test, err)

    def addSubTest(self, test, subtest, err):
        if err is not None:
            self._status = "fail" if issubclass(err[0], test.failureException) else "error"
        super().addSubTest(test, subtest, err)

    def addSkip(self, test, reason):
        self._status = "skip"
        super().addSkip(test, reason)

    def addUnexpectedSuccess(self, test):
        self._status = "fail"
        super().addUnexpectedSuccess(test)


def write_record(results_path: Path, record: dict) -> None:
    with results_path.open("a", encoding="utf-8") as results:
        results.write(json.dumps(record) + "\n")


class ModuleSuite(unittest.TestSuite):
    """One module's tests, with its hardware mode set before ANY of its code.

    The mode must be in place before setUpClass builds a class-shared harness,
    which runs before the first startTest; set there, it leaked from whichever
    module the worker ran previously (a test_cgb_* one broke the next DMG class).
    """

    def __init__(self, module_name: str, tests):
        super().__init__(tests)
        self.mode = "CGB" if module_name.startswith("test_cgb_") else "DMG"

    def run(self, result, debug=False):
        os.environ["REDROGUE_PYBOY_EXPECTED_MODE"] = self.mode
        return super().run(result, debug)


def run_worker(results_path: Path, test_timeout_s: int) -> int:
    ids = json.load(sys.stdin)
    sys.path.insert(0, str(SUITE_DIR))
    by_module: dict[str, list[str]] = {}
    for test_id in ids:
        by_module.setdefault(test_id.split(".", 1)[0], []).append(test_id)
    suite = unittest.TestSuite(
        ModuleSuite(module, unittest.defaultTestLoader.loadTestsFromNames(module_ids))
        for module, module_ids in by_module.items()
    )
    WorkerResult.results_path = results_path
    WorkerResult.test_timeout_s = test_timeout_s
    result = unittest.TextTestRunner(
        stream=sys.stdout, verbosity=2, resultclass=WorkerResult
    ).run(suite)
    # The worker reached the end: any unrecorded ID failed in a class or
    # module fixture, not a hang, and retrying it would fail the same way.
    write_record(results_path, {"done": True})
    return 0 if result.wasSuccessful() else 1


# --------------------------------------------------------------------------
# Parent: packs modules into batches, runs them, aggregates the results.
# --------------------------------------------------------------------------

class Batch:
    """Whole modules run by one worker process (one pyboy import, ~2s)."""

    def __init__(self):
        self.modules: list[str] = []
        self.ids: list[str] = []
        self.estimate = 0.0
        self.records: dict[str, dict] = {}
        self.output: list[str] = []
        self.seconds = 0.0

    @property
    def failed(self) -> list[dict]:
        return [r for r in self.records.values()
                if r["status"] in ("fail", "error", "timeout", "crash")]


def run_batch(batch: Batch, test_timeout_s: int) -> Batch:
    started = time.perf_counter()
    remaining = list(batch.ids)
    with tempfile.TemporaryDirectory(prefix="smoke_") as scratch:
        attempt = 0
        while remaining:
            attempt += 1
            results_path = Path(scratch) / f"results_{attempt}.jsonl"
            results_path.touch()
            command = [sys.executable, str(Path(__file__).resolve()), "--worker",
                       "--results", str(results_path),
                       "--test-timeout", str(test_timeout_s)]
            # Backstop only; the per-test watchdog normally fires first.
            backstop_s = test_timeout_s * (len(remaining) + 1)
            try:
                completed = subprocess.run(
                    command, input=json.dumps(remaining), capture_output=True,
                    text=True, cwd=REPO_ROOT, timeout=backstop_s,
                )
                output, killed = completed.stdout + completed.stderr, False
            except subprocess.TimeoutExpired as expired:
                output = expired.stdout or ""
                if isinstance(output, bytes):
                    output = output.decode(errors="replace")
                killed = True
            batch.output.append(output)
            done, finished = set(), False
            for line in results_path.read_text(encoding="utf-8").splitlines():
                record = json.loads(line)
                if record.get("done"):
                    finished = True
                    continue
                batch.records[record["id"]] = record
                done.add(record["id"])
            remaining = [test_id for test_id in remaining if test_id not in done]
            if not remaining:
                break
            if finished:
                for test_id in remaining:
                    batch.records[test_id] = {"id": test_id, "status": "error", "seconds": 0.0}
                break
            # The worker died mid-test (tests run in the order handed over), so
            # the first unrecorded ID is the culprit. Respawn for the rest.
            culprit = remaining.pop(0)
            status = "timeout" if (killed or "Timeout (" in output) else "crash"
            batch.records[culprit] = {"id": culprit, "status": status,
                                      "seconds": float(test_timeout_s)}
    batch.seconds = time.perf_counter() - started
    return batch


def plan_batches(by_module: dict[str, list[str]], durations: dict[str, float],
                 count: int) -> list[Batch]:
    """Longest-processing-time-first packing of modules into `count` batches."""
    def estimate(module: str) -> float:
        return durations.get(module, GUESS_PER_TEST_S * len(by_module[module]))

    batches = [Batch() for _ in range(count)]
    for module in sorted(by_module, key=estimate, reverse=True):
        lightest = min(batches, key=lambda batch: batch.estimate)
        lightest.modules.append(module)
        lightest.ids.extend(by_module[module])
        lightest.estimate += estimate(module)
    return sorted((b for b in batches if b.ids), key=lambda b: b.estimate, reverse=True)


def failure_report(output: str) -> str:
    """The parts of a worker's output that explain a failure."""
    lines = output.splitlines()
    for index, line in enumerate(lines):
        if "Timeout (" in line:
            return "\n".join(lines[index:])
    separator = "=" * 70
    start = next((i for i, line in enumerate(lines) if line == separator), None)
    if start is None:
        return output.rstrip()
    end = next((i for i in range(len(lines) - 1, start, -1)
                if lines[i].startswith("Ran ")), len(lines))
    return "\n".join(lines[start:end]).rstrip()


def load_durations() -> dict[str, float]:
    try:
        return json.loads(DURATIONS_CACHE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_durations(durations: dict[str, float], records: list[dict]) -> None:
    per_module: dict[str, float] = {}
    for record in records:
        module = record["id"].split(".", 1)[0]
        per_module[module] = per_module.get(module, 0.0) + record["seconds"]
    durations.update({module: round(seconds, 2) for module, seconds in per_module.items()})
    try:
        DURATIONS_CACHE.parent.mkdir(parents=True, exist_ok=True)
        DURATIONS_CACHE.write_text(json.dumps(durations, indent=1, sort_keys=True) + "\n",
                                   encoding="utf-8")
    except OSError:
        pass


def iter_tests(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from iter_tests(test)
        else:
            yield test


def discover_ids() -> list[str]:
    sys.path.insert(0, str(SUITE_DIR))
    suite = unittest.defaultTestLoader.discover(
        str(SUITE_DIR), pattern="test_*.py", top_level_dir=str(SUITE_DIR)
    )
    ids = []
    for test in iter_tests(suite):
        # A module that fails to import shows up as a loader error "test".
        if type(test).__name__ == "_FailedTest":
            raise SystemExit(f"cannot import {test.id()}:\n{test._exception}")
        ids.append(test.id())
    return ids


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Red Rogue PyBoy smoke tests")
    parser.add_argument(
        "--test", action="append", default=[], metavar="PATTERN",
        help="run test IDs matching a shell-style pattern; may be repeated",
    )
    parser.add_argument("--list", action="store_true", help="list selected test IDs")
    parser.add_argument("--jobs", "-j", type=int, default=os.cpu_count() or 1,
                        help="parallel worker processes (default: CPU count)")
    parser.add_argument("--test-timeout", type=int, default=DEFAULT_TEST_TIMEOUT_S,
                        metavar="SECONDS", help="per-test hang watchdog")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="print every worker's full output, not only failures")
    parser.add_argument("--source-only", action="store_true",
                        help="run only the source-only modules (make audit), "
                             "which a normal run skips")
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--results", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()

    if args.worker:
        return run_worker(args.results, args.test_timeout)

    ids = discover_ids()
    modules = {test_id.split(".", 1)[0] for test_id in ids}
    unknown = SOURCE_ONLY_MODULES - modules
    if unknown:
        parser.error(f"SOURCE_ONLY_MODULES names missing modules: {', '.join(sorted(unknown))}")
    # The split applies to whole-suite runs; an explicit --test reaches any module.
    if args.source_only or not args.test:
        ids = [test_id for test_id in ids
               if (test_id.split(".", 1)[0] in SOURCE_ONLY_MODULES) == args.source_only]
    if args.test:
        ids = [test_id for test_id in ids
               if any(fnmatch.fnmatchcase(test_id, pattern) for pattern in args.test)]
        if not ids:
            parser.error(f"no tests matched: {', '.join(args.test)}")
    if args.list:
        for test_id in ids:
            print(test_id)
        return 0

    by_module: dict[str, list[str]] = {}
    for test_id in ids:
        by_module.setdefault(test_id.split(".", 1)[0], []).append(test_id)
    durations = load_durations()
    jobs = max(1, min(args.jobs, len(by_module)))
    # Two batches per worker: few pyboy imports, yet a slow batch can still be
    # absorbed by the others when the cached durations are off.
    batches = plan_batches(by_module, durations, min(len(by_module), jobs * BATCHES_PER_JOB))
    print(f"Running {len(ids)} tests ({len(by_module)} modules) in {len(batches)} batches "
          f"on {jobs} workers, per-test timeout {args.test_timeout}s", flush=True)

    started = time.perf_counter()
    finished = 0
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [pool.submit(run_batch, batch, args.test_timeout) for batch in batches]
        for future in as_completed(futures):
            batch = future.result()
            finished += 1
            verdict = f"FAILED ({len(batch.failed)})" if batch.failed else "ok"
            print(f"[{finished:2}/{len(batches)}] {len(batch.modules):3} modules "
                  f"{len(batch.ids):4} tests {batch.seconds:6.1f}s  {verdict}", flush=True)
            if args.verbose:
                for chunk in batch.output:
                    print(chunk.rstrip(), flush=True)
            elif batch.failed:
                for chunk in batch.output:
                    report = failure_report(chunk)
                    if report and ("FAIL" in report or "ERROR" in report
                                   or "Timeout (" in report or "Traceback" in report):
                        print(report, flush=True)
                print("-" * 70, flush=True)
    wall = time.perf_counter() - started

    records = [record for batch in batches for record in batch.records.values()]
    save_durations(durations, records)
    counts: dict[str, int] = {}
    for record in records:
        counts[record["status"]] = counts.get(record["status"], 0) + 1
    busy = sum(batch.seconds for batch in batches)

    print(f"\nSlowest {min(SLOWEST_SHOWN, len(records))} tests:")
    for record in sorted(records, key=lambda r: r["seconds"], reverse=True)[:SLOWEST_SHOWN]:
        print(f"  {record['seconds']:7.2f}s  {record['id']}")
    print(f"\nRan {len(records)} tests in {wall:.1f}s wall "
          f"({busy:.1f}s of worker time on {jobs} workers)")
    print("  " + ", ".join(f"{status}={count}" for status, count in sorted(counts.items())))

    failed = [record for batch in batches for record in batch.failed]
    missing = len(ids) - len(records)
    if failed or missing:
        print(f"\nFAILED ({len(failed)} failing, {missing} not run):")
        for record in sorted(failed, key=lambda r: r["id"]):
            print(f"  {record['status'].upper():8} {record['id']}")
        return 1
    print("\nOK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
