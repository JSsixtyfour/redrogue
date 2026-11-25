"""Run the three menu fuzzers (Bill's PC, START menu, slots) and write one summary.

    python3 tools/pyboy_smoke/menu_fuzz.py --seeds random:120 --jobs 6

Each tool gets the same seed list (the slot machine the first half of it) and runs in its own
process; a tool that crashes, exits without its report, or tests nothing is itself a finding.
nightly.py reads artifacts/menu_fuzz.json.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import run_autoplay

HERE = Path(__file__).resolve().parent
ARTIFACTS = Path(os.environ.get("REDROGUE_AUTOPLAY_ARTIFACTS", HERE / "artifacts"))
TOOLS = ("bills_pc_fuzz", "start_menu_fuzz", "slot_fuzz")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Bill's PC, START menu and slot machine fuzzers in one go.")
    parser.add_argument("--seeds", default="random:60")
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    parser.add_argument("--timeout", type=float, default=600, help="seconds per tool")
    args = parser.parse_args(argv)
    seeds = run_autoplay.parse_seeds(args.seeds)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    findings: dict[str, list[int]] = {}
    tools: dict[str, dict[str, object]] = {}
    for tool in TOOLS:
        share = seeds[:max(1, len(seeds) // 2)] if tool == "slot_fuzz" else seeds
        report = ARTIFACTS / f"{tool}.json"
        report.unlink(missing_ok=True)
        started = time.monotonic()
        try:
            code: object = subprocess.run(
                [sys.executable, str(HERE / f"{tool}.py"), "--seeds", ",".join(map(str, share)), "--jobs", str(args.jobs)],
                timeout=args.timeout).returncode
        except subprocess.TimeoutExpired:
            code = "timeout"
        data = json.loads(report.read_text(encoding="utf-8")) if report.exists() else None
        for what, hit in (data or {}).get("findings", {}).items():
            findings[f"{tool}: {what}"] = hit
        if data is None or code not in (0, 1) or code == 1 and not data["findings"]:
            findings[f"{tool}: no result (exit {code})"] = share[:1]
        tools[tool] = {"exit": code, "seeds": len(share), "seconds": round(time.monotonic() - started),
                       "outcomes": (data or {}).get("outcomes", {})}
        print(f"{tool}: exit {code}, {tools[tool]}", flush=True)
    (ARTIFACTS / "menu_fuzz.json").write_text(json.dumps(
        {"seeds": seeds, "tools": tools, "findings": findings}, indent=1) + "\n", encoding="utf-8")
    for what, hit in findings.items():
        print(f"  {what}  seeds {hit[:6]}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
