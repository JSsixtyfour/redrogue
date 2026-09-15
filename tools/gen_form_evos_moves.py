#!/usr/bin/env python3
"""
gen_form_evos_moves.py - Phase 2 one-shot generator (Species Groups form learnsets).

RUN ONCE, THEN NEVER AGAIN. This seeds each of the 52 form records with a
VERBATIM COPY of its base species' level-up learnset, so the user can hand-edit
each one afterwards. Re-running this script would silently discard every hand
edit made since the first run.

What it does:
  1. Reads constants/pokemon_constants.asm to build species-name -> internal
     index (const_skip slots count toward the index but bind no name).
  2. Reads the dw list under EvosMovesPointerTable: in data/pokemon/evos_moves.asm
     (index 1 = first entry, since index 0 is NO_MON and is never listed there).
  3. Reads data/pokemon/forms.asm for its INCLUDE order (52 files), and each
     data/pokemon/forms/<shortname>.asm for its `form_record <SPECIES>, <n>` line.
  4. For each form, looks up its base species' EvosMoves label, locates that
     label's definition, and extracts the text strictly between its first and
     second zero-terminator lines (i.e. the learnset block, "; Learnset" comment
     and all - NOT the evolution block, NOT the tutor block).
  5. Emits data/pokemon/form_evos_moves/<shortname>.asm: a `<Shortname>FormEvosMoves:`
     label, an empty (`db 0`) evolution block, then the copied learnset verbatim.
  6. Emits data/pokemon/form_evos_moves.asm: FormEvosMovesPointers with one
     (species, form, record pointer) entry per form, a `db 0` terminator, then
     one INCLUDE per emitted file.

Run from the repo root:  py tools/gen_form_evos_moves.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONSTANTS_FILE = ROOT / "constants" / "pokemon_constants.asm"
EVOS_MOVES_FILE = ROOT / "data" / "pokemon" / "evos_moves.asm"
FORMS_FILE = ROOT / "data" / "pokemon" / "forms.asm"
FORMS_DIR = ROOT / "data" / "pokemon" / "forms"
OUT_DIR = ROOT / "data" / "pokemon" / "form_evos_moves"
OUT_TABLE_FILE = ROOT / "data" / "pokemon" / "form_evos_moves.asm"

CONST_RE = re.compile(r"^\s*const\s+([A-Z_][A-Z0-9_]*)\s*(?:;.*)?$")
CONST_SKIP_RE = re.compile(r"^\s*const_skip\s*(?:;.*)?$")
END_MARKER_RE = re.compile(r"^\s*DEF\s+NUM_POKEMON_INDEXES\b")

DW_ENTRY_RE = re.compile(r"^\s*dw\s+(\w+)\s*(?:;.*)?$")
POINTER_TABLE_START_RE = re.compile(r"^EvosMovesPointerTable:\s*$")
POINTER_TABLE_END_RE = re.compile(r"^\s*assert_table_length\b")

FORM_INCLUDE_RE = re.compile(r'^\s*INCLUDE\s+"data/pokemon/forms/(\w+)\.asm"\s*$')
FORM_RECORD_RE = re.compile(r"^\s*form_record\s+([A-Z_][A-Z0-9_]*)\s*,\s*(\d+)\s*(?:;.*)?$")

LABEL_RE = re.compile(r"^(\w+EvosMoves):\s*$")
ZERO_TERM_RE = re.compile(r"^[ \t]*db\s+0\s*(?:;.*)?$")


def build_species_index():
    """species constant name -> 1-based internal index (const_skip counts, unnamed)."""
    text = CONSTANTS_FILE.read_text(encoding="utf-8").splitlines()
    name_to_index = {}
    index = 0
    for line in text:
        if END_MARKER_RE.match(line):
            break
        m = CONST_RE.match(line)
        if m:
            name_to_index[m.group(1)] = index
            index += 1
            continue
        if CONST_SKIP_RE.match(line):
            index += 1
            continue
    if "NO_MON" not in name_to_index or name_to_index["NO_MON"] != 0:
        sys.exit("FATAL: NO_MON not found at index 0 - const parsing is wrong")
    return name_to_index


def build_dw_list():
    """0-based list of EvosMoves labels; dw_list[0] is species index 1's record."""
    lines = EVOS_MOVES_FILE.read_text(encoding="utf-8").splitlines()
    dw_list = []
    in_table = False
    for line in lines:
        if POINTER_TABLE_START_RE.match(line):
            in_table = True
            continue
        if not in_table:
            continue
        if POINTER_TABLE_END_RE.match(line):
            break
        m = DW_ENTRY_RE.match(line)
        if m:
            dw_list.append(m.group(1))
    if not dw_list:
        sys.exit("FATAL: found no dw entries under EvosMovesPointerTable:")
    return dw_list


def build_label_offsets(lines):
    """label name -> line index of its 'Label:' line, for every *EvosMoves: label."""
    offsets = {}
    for i, line in enumerate(lines):
        m = LABEL_RE.match(line)
        if m:
            offsets[m.group(1)] = i
    return offsets


def extract_learnset_block(lines, label, label_offsets):
    start = label_offsets[label]
    # Find the next label's start (or EOF) to bound the search.
    later = sorted(off for off in label_offsets.values() if off > start)
    end_bound = later[0] if later else len(lines)

    term_indices = []
    for i in range(start + 1, end_bound):
        if ZERO_TERM_RE.match(lines[i]):
            term_indices.append(i)
            if len(term_indices) == 2:
                break

    if len(term_indices) < 2:
        sys.exit(
            f"FATAL: {label} has only {len(term_indices)} zero-terminator(s) "
            f"before the next label - cannot isolate its learnset block"
        )

    t1, t2 = term_indices
    block_lines = lines[t1 + 1 : t2 + 1]

    # Sanity check: every non-comment, non-blank line in the extracted block
    # should be either the leading comment(s) or a `db <level>, <MOVE>` entry,
    # or the trailing `db 0` we already matched via ZERO_TERM_RE.
    entry_re = re.compile(r"^\s*db\s+\d+\s*,\s*\w+.*$")
    comment_or_blank_re = re.compile(r"^\s*(;.*)?$")
    for bl in block_lines[:-1]:  # last line is the terminator itself
        if not (entry_re.match(bl) or comment_or_blank_re.match(bl)):
            sys.exit(
                f"FATAL: {label} learnset block has an unrecognised line: {bl!r}"
            )

    return block_lines


def main():
    name_to_index = build_species_index()
    dw_list = build_dw_list()
    evos_lines = EVOS_MOVES_FILE.read_text(encoding="utf-8").splitlines()
    label_offsets = build_label_offsets(evos_lines)

    existing_labels = set(label_offsets.keys())

    # Canonical form order: as INCLUDEd by forms.asm.
    forms_text = FORMS_FILE.read_text(encoding="utf-8").splitlines()
    shortnames = []
    for line in forms_text:
        m = FORM_INCLUDE_RE.match(line)
        if m:
            shortnames.append(m.group(1))
    if len(shortnames) != 52:
        sys.exit(f"FATAL: expected 52 form includes in forms.asm, found {len(shortnames)}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    entries = []  # (species_const, form_index, record_label, shortname)
    total_bytes = 0

    for shortname in shortnames:
        form_file = FORMS_DIR / f"{shortname}.asm"
        text = form_file.read_text(encoding="utf-8")
        m = None
        for line in text.splitlines():
            m = FORM_RECORD_RE.match(line)
            if m:
                break
        if not m:
            sys.exit(f"FATAL: no form_record line found in {form_file}")
        species, form_index = m.group(1), int(m.group(2))

        if species not in name_to_index:
            sys.exit(f"FATAL: unknown species constant {species!r} in {form_file}")
        idx = name_to_index[species]
        if idx < 1 or idx > len(dw_list):
            sys.exit(f"FATAL: species {species} index {idx} out of dw_list range")
        base_label = dw_list[idx - 1]
        if base_label not in label_offsets:
            sys.exit(f"FATAL: base label {base_label} (for {species}) not found in evos_moves.asm")

        learnset_lines = extract_learnset_block(evos_lines, base_label, label_offsets)

        record_label = f"{shortname.capitalize()}FormEvosMoves"
        if record_label in existing_labels:
            sys.exit(f"FATAL: label collision - {record_label} already exists in evos_moves.asm")

        out_file = OUT_DIR / f"{shortname}.asm"
        out_lines = [f"{record_label}:"]
        out_lines.append(
            "; Evolutions - never read through this record. Evolution stays"
        )
        out_lines.append(
            "; species-keyed (the form's own bits ride along in the block-copied"
        )
        out_lines.append(
            "; party struct), so it already evolves correctly through the"
        )
        out_lines.append(
            "; species-keyed EvosMovesPointerTable. This terminator exists only"
        )
        out_lines.append(
            "; because every consumer skips this block before reading the learnset."
        )
        out_lines.append("\tdb 0")
        out_lines.append(f"; Learnset - verbatim copy of {species}'s ({base_label})")
        out_lines.append(
            "; learnset, seeded by tools/gen_form_evos_moves.py. Hand-edit freely;"
        )
        out_lines.append("; this file is never regenerated.")
        out_lines.extend(learnset_lines)
        out_lines.append("")

        content = "\n".join(out_lines)
        with open(out_file, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        total_bytes += sum(
            1
            for bl in learnset_lines
            if re.match(r"^\s*db\s+\d+\s*,\s*\w+", bl)
        ) * 2 + 1  # 2 bytes/entry + 1 terminator byte for the learnset block
        total_bytes += 1  # the empty evolution terminator

        entries.append((species, form_index, record_label, shortname))

    # FormEvosMovesPointers table + includes.
    table_lines = [
        "FormEvosMovesPointers::",
        "; Entry layout, 4 bytes:",
        ";     db <base species>, <form index>",
        ";     dw <record>",
        ";",
        "; Generated by tools/gen_form_evos_moves.py (Phase 2). Each record below is",
        "; a verbatim copy of its base species' level-up learnset at generation time -",
        "; hand-edit the individual data/pokemon/form_evos_moves/<name>.asm files",
        "; freely; this table itself only needs an edit if a form is added or removed.",
    ]
    for species, form_index, record_label, _ in entries:
        table_lines.append(f"\tdb {species}, {form_index}")
        table_lines.append(f"\tdw {record_label}")
    table_lines.append("\tdb 0 ; terminator")
    table_lines.append("")
    for _, _, _, shortname in entries:
        table_lines.append(f'\tINCLUDE "data/pokemon/form_evos_moves/{shortname}.asm"')
    table_lines.append("")

    with open(OUT_TABLE_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(table_lines))

    entry_table_bytes = len(entries) * 4 + 1  # 4 bytes/entry + 1 terminator
    total_bytes += entry_table_bytes

    print(f"Emitted {len(entries)} form learnset records under {OUT_DIR}")
    print(f"Rewrote {OUT_TABLE_FILE}")
    print(f"Approx total bytes added to bank $31: {total_bytes}")


if __name__ == "__main__":
    main()
