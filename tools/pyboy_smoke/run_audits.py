#!/usr/bin/env python3
"""Run the registered standalone audits (audits.json) and summarize pass/fail.

These are the slower regression guards that are not part of `make smoke`: most
boot PyBoy and sweep many generated layouts. `make audits_long` runs every
'guard' not already covered by smoke.

    python3 tools/pyboy_smoke/run_audits.py                 # guards not in smoke
    python3 tools/pyboy_smoke/run_audits.py --only '*cave*'
    python3 tools/pyboy_smoke/run_audits.py --kind probe    # the one-off probes
    python3 tools/pyboy_smoke/run_audits.py --list

Each audit runs against the pokeblue_debug.gbc already built; rebuilding while
this runs mixes ROMs between audits.
"""
from __future__ import annotations

from pathlib import Path
import argparse
import fnmatch
import json
import subprocess
import sys
import time


SUITE_DIR = Path(__file__).resolve().parent
REPO_ROOT = SUITE_DIR.parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--kind", choices=["guard", "probe", "all"], default="guard")
    parser.add_argument("--only", action="append", default=[], metavar="PATTERN",
                        help="script name glob; may be repeated")
    parser.add_argument("--include-smoke", action="store_true",
                        help="also run guards that make smoke already covers")
    parser.add_argument("--timeout", type=int, default=900, help="seconds per audit")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()

    registry = json.loads((SUITE_DIR / "audits.json").read_text(encoding="utf-8"))["audits"]
    missing = [a["script"] for a in registry if not (SUITE_DIR / a["script"]).exists()]
    if missing:
        print(f"audits.json lists missing scripts: {', '.join(missing)}", file=sys.stderr)
        return 2
    selected = [
        a for a in registry
        if (args.kind == "all" or a["kind"] == args.kind)
        and (args.include_smoke or not a.get("in_smoke"))
        and (not args.only or any(fnmatch.fnmatchcase(a["script"], p) for p in args.only))
    ]
    if not selected:
        parser.error("no audits selected")
    if args.list:
        for a in selected:
            print(f"{a['kind']:<6} {a['script']:<40} {a['guards']}")
        return 0

    results = []
    for a in selected:
        command = [sys.executable, str(SUITE_DIR / a["script"]), *a["args"]]
        print(f"--- {a['script']} {' '.join(a['args'])}", flush=True)
        started = time.perf_counter()
        try:
            proc = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True,
                                  timeout=args.timeout)
            status = "PASS" if proc.returncode == 0 else f"FAIL({proc.returncode})"
            tail = (proc.stdout + proc.stderr).strip().splitlines()[-3:]
        except subprocess.TimeoutExpired:
            status, tail = "TIMEOUT", []
        seconds = time.perf_counter() - started
        results.append((a["script"], status, seconds))
        print(f"    {status} in {seconds:.1f}s")
        if status != "PASS":
            for line in tail:
                print(f"    | {line}")

    failed = [r for r in results if r[1] != "PASS"]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed, "
          f"{sum(r[2] for r in results):.0f}s total")
    for script, status, _ in failed:
        print(f"  {status:<10} {script}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
