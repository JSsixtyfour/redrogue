"""Audit: every map's object constants are in the same order as its objects.

`object_const_def` numbers a map's `const_export` names 1, 2, 3... and those
numbers are SLOT numbers: `toggle_object_state <CONST>, ON` in
data/maps/toggleable_objects.asm keys a toggle on "sprite slot <CONST>", and
scripts use the same consts for sprite indices (hSpriteIndex, movement, facing).
Nothing ties the const list to the `object_event` list below it, so the two
can drift apart silently.

MEASURED 2026-09-23: SS Anne B1F declared SSANNEB1F_CAPTAIN first (= slot 1)
while the captain's object_event was slot 11. HideObject on
TOGGLE_SS_ANNE_B1F_CAPTAIN hid an invisible padding trainer in slot 1 and the
real captain never disappeared.

How a const is matched to its object: by name. Const `X` belongs to the
object_event whose text id is `TEXT_X` (the convention every map follows). A
const whose `TEXT_X` sits at a different slot is MISPLACED. A const with no
matching text id cannot be checked and is listed with --verbose only.

A misplaced const FAILS only if something outside its objects file uses it
(toggle table, a script). An unused misplaced const is reported, not failed:
its number is never read, so it is harmless until someone starts using it.

Usage:
    python3 tools/pyboy_smoke/audit_map_object_const_order.py [--verbose]
    python3 tools/pyboy_smoke/audit_map_object_const_order.py --objects-file F
        (audit one file, e.g. an old revision from `git show`, as a control)

NEGATIVE CONTROL (2026-09-23): `git show 584de52d:data/maps/objects/SSAnneB1F.asm`
fed through --objects-file must FAIL naming SSANNEB1F_CAPTAIN (slot 1 vs 11).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
OBJECTS = REPO_ROOT / "data" / "maps" / "objects"
SCAN_DIRS = ("scripts", "data", "engine", "custom_functions", "home", "constants")

CONST_RE = re.compile(r"^\s*const(?:_export)?\s+(\w+)", re.M)
OBJECT_RE = re.compile(r"^\s*object_event\s+([^;\n]*)", re.M)


def parse(text: str):
    """Return (consts, object text ids) or None if the file has no const block."""
    start = text.find("object_const_def")
    label = re.search(r"^\w+_Object:", text[start:], re.M) if start >= 0 else None
    if label is None:
        return None
    consts = CONST_RE.findall(text[start:start + label.start()])
    body = text[start + label.start():]
    texts = []
    for args in OBJECT_RE.findall(body):
        parts = [a.strip() for a in args.split(",")]
        texts.append(parts[5] if len(parts) > 5 else "")
    return consts, texts


WORD_RE = re.compile(r"\w+")
COMMENT_RE = re.compile(r";[^\n]*")


def word_index(exclude: Path | None) -> dict[str, set[str]]:
    """word -> set of files (repo-relative) that contain it."""
    index: dict[str, set[str]] = {}
    for d in SCAN_DIRS:
        for p in (REPO_ROOT / d).rglob("*.asm"):
            if exclude is not None and p.resolve() == exclude.resolve():
                continue
            rel = str(p.relative_to(REPO_ROOT))
            code = COMMENT_RE.sub("", p.read_text(errors="replace"))  # a comment is not a use
            for w in set(WORD_RE.findall(code)):
                index.setdefault(w, set()).add(rel)
    return index


def audit(name: str, text: str, index: dict, own: str, verbose: bool):
    parsed = parse(text)
    if parsed is None:
        return [], []
    consts, texts = parsed
    fails, notes = [], []
    if len(consts) != len(texts):
        notes.append(f"{name}: {len(consts)} consts for {len(texts)} objects")
    for i, c in enumerate(consts):
        want = "TEXT_" + c
        if want not in texts:
            if verbose:
                notes.append(f"{name}: {c} (slot {i + 1}) has no {want} object; unchecked")
            continue
        j = texts.index(want)
        if j == i:
            continue
        used = bool(index.get(c, set()) - {own})
        msg = (f"{name}: {c} = slot {i + 1}, but its object ({want}) is slot {j + 1}"
               + ("" if used else " [unused: harmless for now]"))
        (fails if used else notes).append(msg)
    return fails, notes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--objects-file", type=Path)
    args = ap.parse_args()

    if args.objects_file:
        files = [args.objects_file]
        # a control file stands in for its tree copy, so drop that copy's uses
        index = word_index(OBJECTS / args.objects_file.name)
    else:
        files = sorted(OBJECTS.glob("*.asm"))
        index = word_index(None)

    all_fails, all_notes = [], []
    for p in files:
        own = str((OBJECTS / p.name).relative_to(REPO_ROOT))
        f, n = audit(p.stem, p.read_text(errors="replace"), index, own, args.verbose)
        all_fails += f
        all_notes += n

    print(f"{len(files)} object files checked")
    for n in all_notes:
        print("  note: " + n)
    if all_fails:
        print(f"\nFAIL: {len(all_fails)} used object const(s) do not match their object's slot:")
        for f in all_fails:
            print("    " + f)
        return 1
    print("PASS: every used object const matches its object's slot")
    return 0


if __name__ == "__main__":
    sys.exit(main())
