#!/usr/bin/env python3
"""Regenerate data/moves/move_ranks.asm's MoveRankByID and MoveFlagsByID tables
from the CORRECTED move-rankings corpus.

One-shot, by hand, output committed - the same tools/gen_event_constants.py
arrangement. `make` never invokes Python and the K: drive is never a build
dependency; this script exists so the 167-row source can be re-pulled if the
corpus is ever revised, without re-deriving the two fixes below by hand.

Source (not shipped in the repo):
  K:\\Other computers\\My Laptop\\Red Rogue Files\\
    red_rogue_comprehensive_package_v3_1_2026-09-08_FIXED\\00_CURRENT\\
    red_rogue_gen1_move_rankings_v3_1_runtime_CORRECTED.asm

Two defects fixed here, both load-bearing and both invisible to a clean build:

1. ROW ORDER. The source file's own header calls MoveRuntimeRankTable
   "Move-ID-indexed", but its 167 rows are sorted by RANK DESCENDING, not by
   move id - row 1 is SUPER_TRANSFORM where move id 1 is POUND. Indexed
   in place it would return a wrong-but-plausible rank for essentially every
   move, and it would assemble and run without complaint. Every row carries
   its move name in a comment, so this script maps name -> id via
   constants/move_constants.asm and re-emits in id order.

2. FLAG BIT ASSIGNMENTS. The source's MOVEFLAG_* bit-index constants
   (MOVEFLAG_SLEEP EQU 3, MOVEFLAG_EXPLOSION EQU 7, ...) do NOT match this
   tree's already-shipped constants/party_spec_constants.asm
   (MOVEFLAG_SLEEP EQU 1<<0, MOVEFLAG_EXPLOSION EQU 1<<3, ...). Same 15 names,
   completely different bit positions - only MOVEFLAG_BUGGED happens to land
   on bit 10 in both, by coincidence. A byte-for-byte copy of the source's
   16-bit masks would silently scramble every other flag: `forbid_flags`
   would forbid the wrong move category with no build error and no crash,
   exactly the "misaligned table whose count assert passes" failure class
   this repo's Bibles document. This script decodes each source mask bit by
   bit, translates each SET bit through its NAME to this tree's bit position,
   and re-encodes. Verified 2026-09-10 by direct side-by-side diff of both
   DEF blocks; recorded in ROM_BIBLE.md.

Two name fixes, the only two of the 167 rows absent from this tree:
  PSYCHIC -> PSYCHIC_M ($5E). PSYCHIC is not a move constant here;
    PSYCHIC_TYPE is the type.
  DELETE the ROAR row. Slot $2E was repurposed as SUPER_TRANSFORM
    (constants/move_constants.asm:54), which the table already lists
    separately as its own row. Keeping both would double-count one id.

That leaves exactly NUM_ATTACKS + 1 rows, which this script asserts in
Python and the output file asserts again at build time.

Usage:  python3 tools/reorder_move_ranks.py [--check] [--source PATH]
        --check   re-derive and diff against the file on disk, write nothing
        --source  override the default K: drive source path
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "moves", "move_ranks.asm")
MOVE_CONSTANTS = os.path.join(ROOT, "constants", "move_constants.asm")
PARTY_SPEC_CONSTANTS = os.path.join(ROOT, "constants", "party_spec_constants.asm")

DEFAULT_SOURCE = (
    r"K:\Other computers\My Laptop\Red Rogue Files"
    r"\red_rogue_comprehensive_package_v3_1_2026-09-08_FIXED"
    r"\00_CURRENT\red_rogue_gen1_move_rankings_v3_1_runtime_CORRECTED.asm"
)

# Rank codes in the source file, 0-6. Symbolic names must match
# constants/party_spec_constants.asm's MOVE_RANK_* const_def order exactly.
RANK_NAMES = [
    "MOVE_RANK_F",
    "MOVE_RANK_D",
    "MOVE_RANK_C",
    "MOVE_RANK_B",
    "MOVE_RANK_A",
    "MOVE_RANK_S",
    "MOVE_RANK_OFFLIST",
]

# These six are forced to MOVE_RANK_OFFLIST regardless of what the corpus
# grades them - kept explicit and symbolic here (not "trust the source data"),
# because a randomizer must never hand out Splash, Whirlwind, Teleport or
# Struggle, and NO_MOVE/SUPER_TRANSFORM are not real battle moves at all.
# The corpus already grades all six as rank 6 (verified), so this is
# belt-and-braces, matching the placeholder table it replaces.
FORCED_OFFLIST = {
    "NO_MOVE",
    "SPLASH",
    "STRUGGLE",
    "SUPER_TRANSFORM",
    "TELEPORT",
    "WHIRLWIND",
}

NAME_FIXES = {
    "PSYCHIC": "PSYCHIC_M",
}
DROP_NAMES = {"ROAR"}

ROW_RE = re.compile(
    r"^\s*;\s*(\S+)\s*\n\s*db\s+(\d+),\s*LOW\(\$([0-9A-Fa-f]+)\),\s*HIGH\(\$([0-9A-Fa-f]+)\)",
    re.MULTILINE,
)


def parse_move_constants():
    """Returns (name -> id dict, NUM_ATTACKS)."""
    names = {}
    order = []
    with open(MOVE_CONSTANTS, encoding="utf-8") as f:
        text = f.read()
    idx = 0
    for line in text.splitlines():
        m = re.match(r"^\s*const\s+(\S+)", line)
        if m:
            name = m.group(1)
            names[name] = idx
            order.append(name)
            idx += 1
        m = re.search(r"DEF NUM_ATTACKS EQU const_value - 1", line)
        if m:
            break
    m = re.search(r"DEF NUM_ATTACKS EQU const_value - 1", text)
    if not m:
        sys.exit("could not find NUM_ATTACKS in constants/move_constants.asm")
    num_attacks = idx - 1
    return names, num_attacks


def parse_moveflag_bits(path, prefix_check=None):
    """Returns {flag_name: bit_index} from a file's DEF MOVEFLAG_* EQU lines.
    Accepts both `EQU <int>` (source file style) and `EQU 1 << <int>` (this
    tree's style)."""
    bits = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s*DEF\s+MOVEFLAG_(\S+)\s+EQU\s+1\s*<<\s*(\d+)", line)
            if m:
                bits[m.group(1)] = int(m.group(2))
                continue
            m = re.match(r"\s*DEF\s+MOVEFLAG_(\S+)\s+EQU\s+(\d+)\s*$", line)
            if m:
                bits[m.group(1)] = int(m.group(2))
    return bits


def remap_mask(raw_mask, source_bits, tree_bits):
    """Decode raw_mask against source_bits' bit positions, re-encode against
    tree_bits' bit positions. Every SET bit in raw_mask must correspond to a
    known source flag name, and every source flag name must have a matching
    tree flag name, or this fails loudly rather than silently dropping data."""
    out = 0
    for name, src_bit in source_bits.items():
        if raw_mask & (1 << src_bit):
            if name not in tree_bits:
                sys.exit(f"MOVEFLAG_{name} has no counterpart in party_spec_constants.asm")
            out |= 1 << tree_bits[name]
    return out


def parse_source_rows(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"MoveRuntimeRankTable::(.*?)\n; Grouped random-selection buckets", text, re.DOTALL)
    if not m:
        sys.exit("could not find MoveRuntimeRankTable block in source file")
    body = m.group(1)
    rows = []
    for name, rank_s, mask_lo_s, mask_hi_s in ROW_RE.findall(body):
        rank = int(rank_s)
        mask_lo = int(mask_lo_s, 16)
        mask_hi = int(mask_hi_s, 16)
        assert mask_lo == mask_hi, f"{name}: LOW/HIGH args differ ({mask_lo_s} vs {mask_hi_s})"
        rows.append((name, rank, mask_lo))
    return rows


def build(source_path):
    move_ids, num_attacks = parse_move_constants()
    source_bits = parse_moveflag_bits(source_path)
    tree_bits = parse_moveflag_bits(PARTY_SPEC_CONSTANTS)

    assert set(source_bits) == set(tree_bits), (
        "MOVEFLAG_* name sets differ between source and this tree: "
        f"source only={set(source_bits) - set(tree_bits)} "
        f"tree only={set(tree_bits) - set(source_bits)}"
    )

    rows = parse_source_rows(source_path)
    assert len(rows) == 167, f"expected 167 source rows, got {len(rows)}"

    by_id = {}
    for name, rank, raw_mask in rows:
        if name in DROP_NAMES:
            continue
        fixed_name = NAME_FIXES.get(name, name)
        if fixed_name not in move_ids:
            sys.exit(f"{name} (-> {fixed_name}) is not a move constant in this tree")
        move_id = move_ids[fixed_name]
        if move_id in by_id:
            sys.exit(f"move id {move_id} claimed by both {by_id[move_id][0]} and {name}")
        if fixed_name in FORCED_OFFLIST:
            rank = 6  # MOVE_RANK_OFFLIST, regardless of what the corpus graded it
        mask = remap_mask(raw_mask, source_bits, tree_bits)
        by_id[move_id] = (fixed_name, rank, mask)

    expected_ids = set(range(num_attacks + 1))
    got_ids = set(by_id)
    if got_ids != expected_ids:
        sys.exit(
            f"id coverage mismatch: missing={sorted(expected_ids - got_ids)} "
            f"extra={sorted(got_ids - expected_ids)}"
        )

    return by_id, num_attacks


def render(by_id, num_attacks):
    lines = []
    lines.append("; Per-move power grading for the party spec system's randomizers (Phase 2).")
    lines.append(";")
    lines.append("; Generated by tools/reorder_move_ranks.py from")
    lines.append(";   Red Rogue Files/red_rogue_comprehensive_package_v3_1_2026-09-08_FIXED/")
    lines.append(";     00_CURRENT/red_rogue_gen1_move_rankings_v3_1_runtime_CORRECTED.asm")
    lines.append("; NOT wired into `make` - re-run by hand and commit the output, the same")
    lines.append("; tools/gen_event_constants.py arrangement. Do not hand-edit MoveRankByID or")
    lines.append("; MoveFlagsByID below; MoveRankWeightTable and TMMovesForPartyGen are NOT")
    lines.append("; generated and are safe to hand-edit (Phase 5 tuning).")
    lines.append(";")
    lines.append("; Two fixes applied during generation, both load-bearing (see the script's")
    lines.append("; own header for the full explanation):")
    lines.append(";   1. The source's 167 rows are sorted by rank descending, not by move id")
    lines.append(";      despite its header's claim; re-emitted here in id order.")
    lines.append(";   2. The source's MOVEFLAG_* bit assignments do NOT match this tree's")
    lines.append(";      constants/party_spec_constants.asm (same 15 names, different bit")
    lines.append(";      positions - only MOVEFLAG_BUGGED coincides). Every mask below has been")
    lines.append(";      translated bit-by-bit through the flag NAME, not copied as a raw value.")
    lines.append(";   PSYCHIC -> PSYCHIC_M, and the ROAR row (repurposed as SUPER_TRANSFORM in")
    lines.append(";   this tree) is dropped, per constants/move_constants.asm:54.")
    lines.append("")
    lines.append("; Moves excluded from EVERY randomizer pool, permanently. MOVE_RANK_OFFLIST")
    lines.append("; is skipped before it is ever weighted, so none of these six can be selected")
    lines.append("; regardless of what a future corpus revision grades them - see FORCED_OFFLIST")
    lines.append("; in the generator script.")
    lines.append("")
    lines.append("MoveRankByID::")
    lines.append("\ttable_width 1, MoveRankByID")
    for i in range(num_attacks + 1):
        name, rank, _mask = by_id[i]
        lines.append(f"\tdb {RANK_NAMES[rank]} ; {name}")
    lines.append("\tassert_table_length NUM_ATTACKS + 1")
    lines.append("")
    lines.append("; Per-move MOVEFLAG_* mask (constants/party_spec_constants.asm), 2 bytes per")
    lines.append("; move id, little-endian - INPUT e = move id, OUTPUT de = mask is")
    lines.append("; PartyGenMoveFlags's contract (engine/battle/rogue_build_party.asm); every")
    lines.append("; caller already treats it that way.")
    lines.append("MoveFlagsByID::")
    lines.append("\ttable_width 2, MoveFlagsByID")
    for i in range(num_attacks + 1):
        name, _rank, mask = by_id[i]
        lines.append(f"\tdw ${mask:04X} ; {name}")
    lines.append("\tassert_table_length NUM_ATTACKS + 1")
    lines.append("")
    return "\n".join(lines) + "\n"


def load_preserved_tail():
    """Everything from the weight-table comment onward in the current file is
    hand-tuned (Phase 5) and NOT generated; carry it forward verbatim."""
    with open(OUT, encoding="utf-8") as f:
        text = f.read()
    marker = "; Selection weight per (difficulty row, move rank)"
    idx = text.find(marker)
    if idx == -1:
        sys.exit(f"could not find preserved-tail marker in {OUT}; has the file been hand-edited?")
    return text[idx:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--source", default=DEFAULT_SOURCE)
    args = ap.parse_args()

    if not os.path.exists(args.source):
        sys.exit(f"source not found: {args.source}")

    tail = load_preserved_tail()
    by_id, num_attacks = build(args.source)
    generated = render(by_id, num_attacks)
    full = generated + tail

    if args.check:
        with open(OUT, encoding="utf-8") as f:
            current = f.read()
        if current == full:
            print("up to date")
            return
        sys.exit("data/moves/move_ranks.asm is STALE relative to the source corpus")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(full)
    print(f"wrote {OUT}: {num_attacks + 1} moves")


if __name__ == "__main__":
    main()
