import datetime as dt
import json
import os
from pathlib import Path

reports = Path(os.environ["USERPROFILE"]) / "redrogue_nightly_reports"
latest = reports / "latest_attempt.txt"
try:
    attempt = latest.read_text(encoding="utf-8-sig").strip()
except OSError:
    attempt = "No Windows runner status yet."
last_full = None
for path in sorted(reports.glob("*/report.json"), reverse=True):
    try:
        run = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        continue
    if (not run.get("quick") and not run.get("runner_error") and
            len(run["suites"]) == 8):
        last_full = path
        break
if last_full is None:
    print(f"Red Rogue nightly: no complete report. {attempt}")
else:
    age = dt.datetime.now().timestamp() - last_full.stat().st_mtime
    overdue = "OVERDUE. " if age > 30 * 3600 else ""
    print(f"Red Rogue nightly: {overdue}{attempt} Dashboard: {reports / 'index.html'}")
