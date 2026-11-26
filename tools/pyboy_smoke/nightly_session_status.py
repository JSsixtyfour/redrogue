"""Print the nightly's state for an agent's SessionStart hook (.claude, .codex).

A new regression is listed with its findings and replay commands at the start of every session until
`--seen` marks that night; other nights give one line.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path

import nightly

REPORTS = Path(os.environ.get("USERPROFILE", Path.home())) / "redrogue_nightly_reports"
RECENT = 4  # nights looked back over for unseen problems
SHOWN = 8  # regressions, and findings, listed before "more"


def history(reports: Path):
    """(folder, report) newest first. --quick runs only check the runner."""
    for path in sorted(reports.glob("*/report.json"), reverse=True):
        try:
            report = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not report.get("quick"):
            yield path.parent, report


def seen(reports: Path) -> str:
    try:
        return (reports / "seen.txt").read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def mark_seen(reports: Path) -> str:
    latest = next(history(reports), None)
    if latest is None:
        return "no nightly report to mark"
    (reports / "seen.txt").write_text(latest[0].name + "\n", encoding="utf-8")
    return f"{latest[0].name} marked seen"


def capped(lines: list[str], where: Path) -> list[str]:
    more = len(lines) - SHOWN
    return lines[:SHOWN] + ([f"- {more} more in {where}"] if more > 0 else [])


def message(reports: Path) -> str:
    try:
        attempt = (reports / "latest_attempt.txt").read_text(encoding="utf-8-sig").strip()
    except OSError:
        attempt = "No Windows runner status yet."
    marked = seen(reports)
    if marked and marked in attempt:
        attempt += " (seen)"
    nights = list(history(reports))
    full =next((folder for folder, report in nights if nightly.is_full_report(report)), None)
    if full is None:
        headline = f"Red Rogue nightly: no complete report. {attempt}"
    else:
        age = dt.datetime.now().timestamp() - (full / "report.json").stat().st_mtime
        overdue = "OVERDUE. " if age > 30 * 3600 else ""
        headline = f"Red Rogue nightly: {overdue}{attempt} Dashboard: {reports / 'index.html'}"
    if not nights:
        return headline
    unseen = [(folder, report) for folder, report in nights[:RECENT]
              if report.get("status") == "NEW regression" and folder.name > marked]
    if not unseen:
        return headline
    # A blocked attempt has no suites: do not let it hide the run before it.
    folder, report = next((row for row in unseen if row[1]["suites"]), unseen[0])
    others = [f"Also unseen: {other / 'report.md'}" for other, _ in unseen if other != folder]
    new = [f"- {line}" for line in report.get("regressions", [])]
    if report.get("runner_error"):
        new.insert(0, f"- runner failure: {report['runner_error']}")
    found = [f"- {name}: {what}" + (f" | replay: {replay}" if replay else "")
             for name, what, replay in nightly.finding_rows(report)]
    return "\n".join([
        headline,
        f"NEW nightly problems, commit {report['sha'][:8]}, not yet seen. Raise them in the first reply, "
        "before other work. Once they have been acknowledged, run "
        "`python tools/pyboy_smoke/nightly_session_status.py --seen`.",
        "New since last night:", *capped(new, folder / "report.md"),
        "Findings (replay at that commit; the text comes from test output):", *capped(found, folder / "report.md"), *others])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seen", action="store_true", help="stop listing the latest night's problems")
    args = parser.parse_args()
    print(mark_seen(REPORTS) if args.seen else message(REPORTS))
