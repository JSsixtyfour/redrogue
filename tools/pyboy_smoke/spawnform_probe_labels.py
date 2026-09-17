"""Insert or strip temporary probe labels before every `ld [wSpawnForm], a`.

Companion to `probe_spawnform_writers.py`, which needs to hook each writer
individually. PyBoy hooks take a symbol, not a source line, and there is no
line-to-address mapping available - so the writers get labels. Labels emit no
bytes, so no address moves and no RNG stream shifts.

LOCAL labels (".name") on purpose. A new GLOBAL label mid-routine ends the
current local scope, so a later `jr .someLocal` referring to a local defined
before the probe would either fail to assemble or, worse, silently bind to a
same-named label in the new scope. Locals attach to the enclosing routine and
appear in the .sym as "Routine.name", which is exactly what register_hook wants.

Kept as a tool rather than a throwaway because Phase 7 makes `wSpawnForm` bugs
much more likely (it puts forms in pools and copies them into durable SRAM
records), and being able to re-instrument every writer in one command is worth
more than the tidiness of not having the script.

Usage:
    python3 tools/pyboy_smoke/spawnform_probe_labels.py           # insert
    python3 tools/pyboy_smoke/spawnform_probe_labels.py --remove  # strip
Rebuild after either.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MARKER = ".spawnFormProbe"
PATTERN = re.compile(r"^\s*ld\s+\[wSpawnForm\]\s*,\s*a\s*(;.*)?$")
INDEX_PATH = REPO_ROOT / "tools" / "pyboy_smoke" / "spawnform_probes.json"

# Vendored upstream copies and build scratch, never the live tree.
SKIP_DIRS = {"tmp", ".git"}


def source_files() -> list[Path]:
    out = []
    for path in sorted(REPO_ROOT.rglob("*.asm")):
        parts = path.relative_to(REPO_ROOT).parts
        if SKIP_DIRS & set(parts):
            continue
        out.append(path)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--remove", action="store_true")
    args = parser.parse_args()

    index: list[dict] = []
    counter = 0
    touched = 0

    for path in source_files():
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        lines = text.splitlines(keepends=True)

        if args.remove:
            kept = [line for line in lines if not line.strip().startswith(MARKER)]
            if len(kept) != len(lines):
                path.write_text("".join(kept), encoding="utf-8")
                touched += 1
                print("stripped %d label(s) from %s"
                      % (len(lines) - len(kept), path.relative_to(REPO_ROOT)))
            continue

        if any(line.strip().startswith(MARKER) for line in lines):
            print("already instrumented, skipping: %s" % path.relative_to(REPO_ROOT))
            continue

        out = []
        for number, line in enumerate(lines, start=1):
            if PATTERN.match(line):
                counter += 1
                name = "%s%02d" % (MARKER, counter)
                out.append(name + "\n")
                index.append(
                    {
                        "probe": name.lstrip("."),
                        "file": str(path.relative_to(REPO_ROOT)).replace("\\", "/"),
                        "line": number,
                    }
                )
            out.append(line)
        if len(out) != len(lines):
            path.write_text("".join(out), encoding="utf-8")
            touched += 1

    if args.remove:
        if INDEX_PATH.exists():
            INDEX_PATH.unlink()
        print("stripped probes from %d file(s)" % touched)
        return 0

    INDEX_PATH.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    print("inserted %d probe(s) across %d file(s)" % (counter, touched))
    for entry in index:
        print("  %-22s %s:%d" % (entry["probe"], entry["file"], entry["line"]))
    print()
    print("now rebuild, then run probe_spawnform_writers.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
