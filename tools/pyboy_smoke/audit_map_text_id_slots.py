"""Audit: no map script fires a text constant that DisplayTextID will reroute.

DisplayTextID (home/text_script.asm) takes its `.spriteHandling` branch
whenever hTextID <= wNumSprites, and that branch does NOT print text id N. It
REPLACES the id with wMapSpriteData[N-1] - the text id declared by the object
in slot N - and prints that instead. The indirection is what makes talking to
a sprite find the sprite's own line, and for that purpose it is always right,
however the table is ordered.

The trap is the other caller. When a MAP SCRIPT sets hTextID to a constant by
name and that constant's value is <= the object count, the same indirection
fires and reroutes it to whatever the object in that slot declares. Nothing
warns, nothing crashes, the wrong box simply appears.

So a mismatch matters only when BOTH are true:
  1. text entry N is not the text id that object slot N declares, and
  2. something outside the object list fires entry N's constant by name.
This script tests both, which is the difference between an actionable list and
152 harmless permutations.

MEASURED 2026-09-17: Phase 7 appended two stage-event NPC slots to all seven
procedural maps, which grew wNumSprites past ids that had been out of range
without touching the text tables. On a live cave, BOSS_OFFER printed the stage
NPC's line and CALMED printed its partner's; the four cemetery floors
misrouted CALMED the same way. Read from wMapSpriteData on a running ROM, not
inferred. Fixed by moving the two NPC entries up to their slots' positions.

Appending an object is the move that causes this, and it never looks like it
touches text - which is why this guard is static and cheap rather than a boot.

Usage:
    python3 tools/pyboy_smoke/audit_map_text_id_slots.py [--scope procedural|all]
                                                         [--verbose]

`--scope all` surveys the whole game. It reports the pre-existing cases outside
the procedural maps but does not fail on them; those are recorded in
`FOLLOWUPS.md` rather than fixed here, because they are a mod-wide ordering
convention rather than this change's business.

NEGATIVE CONTROL: move a SCRIPT-FIRED entry (CALMED, say) up into the object
block and this must name that map and slot. Swapping two of the objects' OWN
entries is not a control and must NOT fail - verified 2026-09-17, and the
reason is the point of this script: the indirection follows the slot's declared
id, so a permutation confined to entries nothing fires by name still lands on
the right text. An audit that failed on those would be crying wolf on 152
harmless cases and would have buried the two real ones.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
OBJECTS = REPO_ROOT / "data" / "maps" / "objects"

PROCEDURAL = {
    "ProceduralCave1", "ProceduralForest", "ProceduralFacility",
    "ProceduralCemetery1", "ProceduralCemetery2", "ProceduralCemetery3",
    "ProceduralCemetery4",
}

OBJECT_RE = re.compile(r"^\s*object_event\s+(.*)$")
DW_CONST_RE = re.compile(r"^\s*dw_const\s+[^,]+,\s*([A-Za-z_][A-Za-z0-9_]*)")
TEXT_ID_RE = re.compile(r"\bTEXT_[A-Z0-9_]+\b")


def strip_comment(line: str) -> str:
    # Neither macro's arguments contain string literals, so splitting at the
    # first ';' is safe here.
    return line.split(";")[0].rstrip()


def object_text_ids(path: Path):
    """The text-id constant each object_event declares, in slot order."""
    out = []
    for raw in path.read_text(encoding="utf-8", errors="ignore").split("\n"):
        m = OBJECT_RE.match(strip_comment(raw))
        if not m:
            continue
        argv = [a.strip() for a in m.group(1).split(",")]
        out.append(argv[5] if len(argv) > 5 else None)
    return out


def text_table(path: Path):
    """The text-id constants in def_text_pointers order (index 0 == id 1)."""
    text = path.read_text(encoding="utf-8", errors="ignore")
    if "def_text_pointers" not in text:
        return None
    out = []
    started = False
    for raw in text.split("\n"):
        line = strip_comment(raw)
        if "def_text_pointers" in line:
            started = True
            continue
        if not started:
            continue
        m = DW_CONST_RE.match(line)
        if m:
            out.append(m.group(1))
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith("EXPORT"):
            continue
        break           # any other directive ends the table
    return out


def fired_by_name():
    """Every TEXT_* constant referenced anywhere but an object list or a
    def_text_pointers entry - i.e. every one something could set hTextID to."""
    fired = set()
    for path in REPO_ROOT.rglob("*.asm"):
        parts = path.parts
        if "tmp" in parts or ".git" in parts:
            continue
        if path.parent == OBJECTS:
            continue        # a declaration, not a firing
        for raw in path.read_text(encoding="utf-8", errors="ignore").split("\n"):
            line = strip_comment(raw)
            if DW_CONST_RE.match(line):
                continue    # the table entry itself
            fired.update(TEXT_ID_RE.findall(line))
    return fired


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scope", choices=("procedural", "all"),
                        default="procedural")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    fired = fired_by_name()
    failures = []
    survey = []
    checked = 0

    for obj_path in sorted(OBJECTS.glob("*.asm")):
        name = obj_path.stem
        if args.scope == "procedural" and name not in PROCEDURAL:
            continue
        script_path = SCRIPTS / obj_path.name
        if not script_path.exists():
            continue
        table = text_table(script_path)
        if table is None:
            continue
        objects = object_text_ids(obj_path)
        if not objects:
            continue
        checked += 1

        for slot, declared in enumerate(objects, start=1):
            if declared is None:
                failures.append((name, "slot %d: object_event has no text-id "
                                       "argument" % slot))
                continue
            if slot > len(table):
                failures.append((
                    name,
                    "slot %d declares %s but the table has only %d entries, so "
                    "hTextID = %d has nothing to reroute TO"
                    % (slot, declared, len(table), slot)))
                continue
            victim = table[slot - 1]
            if victim == declared:
                continue
            # A permutation inside the object block is harmless for TALKING -
            # the indirection still lands on the sprite's own line. It is only
            # a bug if something fires the displaced constant by name.
            entry = (name,
                     "slot %d declares %s, so firing %s by name prints %s "
                     "instead" % (slot, declared, victim, declared))
            if victim in fired:
                (failures if name in PROCEDURAL else survey).append(entry)
            elif args.verbose:
                print("  (harmless) %s: %s" % entry)
        if args.verbose:
            print("%-34s %2d objects, %2d text entries"
                  % (name, len(objects), len(table)))

    print()
    print("%d maps checked (scope=%s)" % (checked, args.scope))

    if survey:
        others = sorted({n for n, _ in survey})
        print()
        print("PRE-EXISTING, outside the procedural maps - reported, not failed "
              "(%d on %d maps): %s" % (len(survey), len(others), ", ".join(others)))
        for n, msg in survey[:12]:
            print("    %s: %s" % (n, msg))
        if len(survey) > 12:
            print("    ... and %d more" % (len(survey) - 12))
        print("  These are the Rogue reward-pokeball and trade-NPC objects "
              "appended to vanilla maps, the same move Phase 7 made. Recorded "
              "in FOLLOWUPS.md.")

    print()
    if failures:
        for n, msg in failures:
            print("  %s: %s" % (n, msg))
        print()
        print("FAIL: %d script-fired constants are rerouted by DisplayTextID"
              % len(failures))
        return 1
    print("PASS: no script-fired text constant on these maps is rerouted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
