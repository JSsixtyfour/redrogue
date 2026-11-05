"""Print one or more witch result.json files: status, failing checks, notes.

    python3 witch_show.py <result.json>... [--notes N]   (N = characters of each note, default 600)
Paths may be globs. Passing results print one line.
"""
import glob
import json
import sys

args = sys.argv[1:]
limit = 600
if "--notes" in args:
    at = args.index("--notes")
    limit = int(args[at + 1])
    del args[at:at + 2]
for pattern in args:
    for path in sorted(glob.glob(pattern)):
        result = json.load(open(path, encoding="utf-8"))
        label = f"{result['rom']} {result['case']} {result['branch']}"
        print(f"== {label}: {result['status']} {str(result.get('detail', ''))[-300:]}")
        for check in result.get("checks", []):
            if not check["ok"]:
                print(f"   FAIL {check['name']}: expected {str(check['expected'])[:80]}, observed {str(check['observed'])[:80]}")
        for note in result.get("notes", []):
            print(f"   note: {note[:limit]}")
        if result.get("anomalies"):
            print(f"   anomalies: {result['anomalies'][:3]}")
