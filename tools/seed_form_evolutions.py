#!/usr/bin/env python3
"""
seed_form_evolutions.py - fills each FORM's own evolution block (Phase 1 of
FORM_EVOLUTION_LISTS_PLAN.md).

A form evolves through its OWN list (data/pokemon/form_evos_moves/<form>.asm),
and an empty block means it never evolves. Before this change a form used its
base species' list plus three implicit rules. This script writes the list each
form had under those rules, so behaviour is unchanged:

  * form-preserving: an entry into T keeps the form F if (T, F) has a form
    record, else it lands on the base form;
  * EvoStoneForms: a stone row (stone, T) sets that form instead;
  * FormEvoStones: a (species, form) answers to a different stone;
  * FormNoEvolve: a (species, form >= 1) row means an empty list.

The three tables are read from engine/pokemon/evos_moves.asm, so this script
has no copy of them to drift.

SAFE TO RE-RUN. A block that already holds any entry is hand-authored and left
alone; only empty blocks (a lone `db 0`) are written. --check reports what it
would write without touching anything, and exits 1 if a write is pending.

Run from the repo root:  python tools/seed_form_evolutions.py [--check]
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_form_evos_moves import (  # noqa: E402  (shared parsers)
    EVOS_MOVES_FILE, FORMS_DIR, FORM_RECORD_RE, OUT_DIR, OUT_TABLE_FILE,
    build_dw_list, build_species_index,
)

ROOT = Path(__file__).resolve().parent.parent
ENGINE_FILE = ROOT / "engine" / "pokemon" / "evos_moves.asm"

LABEL_RE = re.compile(r"^(\w+):\s*$")
ZERO_RE = re.compile(r"^\s*db\s+0\s*(?:;.*)?$")
ENTRY_RE = re.compile(r"^\s*db\s+(EVOLVE_LEVEL|EVOLVE_ITEM|EVOLVE_TRADE)\s*,([^;]*)(;.*)?$")
AUTHORED_RE = re.compile(r"^\s*(db\s+EVOLVE_|evo_\w+_form\b)")
POINTER_RE = re.compile(r"^\s*db\s+([A-Z_][A-Z0-9_]*)\s*,\s*(\d+)\s*$")
DW_RE = re.compile(r"^\s*dw\s+(\w+)\s*$")
OLD_COMMENT_FIRST = "; Evolutions - never read through this record."


def table_rows(label, width):
    """Rows of a `db a, b, c` table that follows `label:` in evos_moves.asm."""
    rows, inside = [], False
    for line in ENGINE_FILE.read_text(encoding="utf-8").splitlines():
        if line.startswith(label + ":"):
            inside = True
            continue
        if not inside:
            continue
        code = line.split(";")[0].strip()
        if not code:
            continue
        if not code.startswith("db"):
            break
        fields = [f.strip() for f in code[2:].split(",")]
        if fields == ["0"]:
            break
        assert len(fields) == width, (label, line)
        rows.append(tuple(fields))
    if not rows:
        sys.exit(f"FATAL: no rows under {label}:")
    return rows


def base_lists():
    """species label -> list of (type, params...) from its evolution block."""
    lines = EVOS_MOVES_FILE.read_text(encoding="utf-8").splitlines()
    lists, current = {}, None
    for line in lines:
        m = LABEL_RE.match(line)
        if m and m.group(1).endswith("EvosMoves"):
            current = m.group(1)
            lists[current] = []
            continue
        if current is None:
            continue
        if ZERO_RE.match(line):
            current = None
            continue
        e = ENTRY_RE.match(line)
        if e:
            lists[current].append((e.group(1), *[p.strip() for p in e.group(2).split(",")]))
        elif "EVOLVE_" in line.split(";")[0]:
            sys.exit(f"FATAL: unparsed evolution line under {current}: {line!r}")
    return lists


def form_records():
    recs = set()
    for path in FORMS_DIR.glob("*.asm"):
        for line in path.read_text(encoding="utf-8").splitlines():
            m = FORM_RECORD_RE.match(line)
            if m:
                recs.add((m.group(1), int(m.group(2))))
    return recs


def pointer_table():
    """record label -> (species, form) from FormEvosMovesPointers."""
    out, pending = {}, None
    for line in OUT_TABLE_FILE.read_text(encoding="utf-8").splitlines():
        m = POINTER_RE.match(line)
        if m:
            pending = (m.group(1), int(m.group(2)))
            continue
        d = DW_RE.match(line)
        if d and pending:
            out[d.group(1)] = pending
            pending = None
    return out


def seed_entries(species, form, base, recs, stone_forms, form_stones, no_evolve):
    if (species, str(form)) in no_evolve:
        return []
    swap = {(s, int(f)): stone for s, f, stone in form_stones}
    out = []
    for entry in base:
        kind = entry[0]
        if kind == "EVOLVE_ITEM":
            item, minlvl, target = entry[1], entry[2], entry[3]
            item = swap.get((species, form), item)
            result = next((int(n) for st, t, n in stone_forms if st == item and t == target), None)
            if result is None:
                result = form if (target, form) in recs else 0
            out.append(f"\tevo_item_form {result}, {item}, {minlvl}, {target}" if result
                       else f"\tdb EVOLVE_ITEM, {item}, {minlvl}, {target}")
        else:
            lvl, target = entry[1], entry[2]
            result = form if (target, form) in recs else 0
            macro = "evo_level_form" if kind == "EVOLVE_LEVEL" else "evo_trade_form"
            out.append(f"\t{macro} {result}, {lvl}, {target}" if result
                       else f"\tdb {kind}, {lvl}, {target}")
    return out


def main():
    check = "--check" in sys.argv[1:]
    index = build_species_index()
    by_index = {v: k for k, v in index.items()}
    dw = build_dw_list()
    label_of = {by_index[i + 1]: lab for i, lab in enumerate(dw) if (i + 1) in by_index}
    lists = base_lists()
    recs = form_records()
    stone_forms = table_rows("EvoStoneForms", 3)
    form_stones = table_rows("FormEvoStones", 3)
    no_evolve = set(table_rows("FormNoEvolve", 2))
    pointers = pointer_table()

    pending, kept = 0, 0
    for path in sorted(OUT_DIR.glob("*.asm")):
        text = path.read_text(encoding="utf-8")
        lines = text.split("\n")
        label = next(LABEL_RE.match(l).group(1) for l in lines if LABEL_RE.match(l))
        species, form = pointers[label]
        base_label = label_of[species]
        zero = next(i for i, l in enumerate(lines) if ZERO_RE.match(l))
        block = lines[1:zero]
        if any(AUTHORED_RE.match(l) for l in block):
            kept += 1
            continue
        entries = seed_entries(species, form, lists[base_label], recs,
                               stone_forms, form_stones, no_evolve)
        comment = [
            "; Evolutions - this FORM's own list (FORM_EVOLUTION_LISTS_PLAN.md). An",
            "; empty list means it never evolves, like any final Pokemon. Seeded by",
            f"; tools/seed_form_evolutions.py from {base_label}'s list with the old",
            "; implicit rules applied; hand-edit freely (a block with entries is never",
            "; re-seeded).",
        ]
        new_lines = [lines[0]] + comment + entries + lines[zero:]
        new_text = "\n".join(new_lines)
        if new_text == text:
            continue
        # a block that is ALREADY in the new shape but empty (never evolves) is
        # rewritten only if its comment is still the stale pre-plan one
        if not entries and OLD_COMMENT_FIRST not in text:
            continue
        pending += 1
        shown = ", ".join(e.strip() for e in entries) or "(never evolves)"
        print(f"{path.name}: {species} form {form} <- {base_label}: {shown}")
        if not check:
            path.write_text(new_text, encoding="utf-8", newline="")
    print(f"{pending} block(s) {'to write' if check else 'written'}, {kept} hand-authored left alone")
    if check and pending:
        sys.exit(1)


if __name__ == "__main__":
    main()
