#!/usr/bin/env python3
"""Regenerate data/trainers/movesets.asm from the curated moveset corpus.

One-shot, by hand, output committed - the tools/gen_event_constants.py /
tools/reorder_move_ranks.py arrangement. `make` never invokes Python and the
K: drive is never a build dependency.

Source: K:\\Other computers\\My Laptop\\Red Rogue Files\\
  red_rogue_comprehensive_package_v3_1_2026-09-08_FIXED\\00_CURRENT\\
  red_rogue_gen1_moveset_reference_v76_low_level_layer_complete.txt

Every `db SPECIES, MOVE1, MOVE2, MOVE3, MOVE4` line in the whole file is one
record; there are exactly 1,946 of them, measured. The 307-record CUT SETS
ARCHIVE mentioned in the corpus's own changelog turns out to carry ZERO `db`
lines of its own (its sets are preserved as prose/metadata only, not as
runtime records), so no special-cased line-range exclusion is needed - a
plain whole-file scan for `db ` lines already returns exactly 1,946 and
already excludes the CUT archive. Verified by counting `db ` lines inside vs
outside the V71 CUT SETS ARCHIVE section before writing this script.

Filtering, measured against this tree's constants (not assumed):

  - Exactly ONE unknown move name appears anywhere in the corpus: `PSYCHIC`,
    250 times. Same fix as tools/reorder_move_ranks.py: PSYCHIC -> PSYCHIC_M.
  - 130 records (57 distinct names) name a species this tree has no constant
    for. 39 of those names are REGIONAL/EEVEELUTION FORMS this tree encodes
    as (base species, form index) via data/pokemon/forms/*.asm's
    `form_record` lines, not as separate species constants - see FORM_MAP
    below, built by cross-referencing every form_record in that directory
    against the corpus's unknown-species list, by hand (57 names is few
    enough that an automatic suffix-matcher would have bought nothing but a
    second place to get it wrong).
  - The remaining 14 distinct names (CLEFFA, DELIBIRD, ELEKID, HAPPINY,
    IGGLYBUFF, MAGBY, MIME_JR, MUNCHLAX, PICHU, SMEARGLE, SMOOCHUM, TYROGUE,
    UNOWN, WOBBUFFET; 31 records) do not exist in this tree under any name,
    species or form, confirmed by grep against constants/pokemon_constants.asm
    and every data/pokemon/forms/*.asm. Dropped, reported.

FORM RECORDS ARE DROPPED HERE TOO, DELIBERATELY, NOT MERGED INTO THE BASE
SPECIES' LIST. The 8-byte runtime record has no form field, and MSRC_SET's
species-only lookup (PartyGenApplyMoveset) has no way to ask for "the form
variant" of a set. Folding e.g. EXEGGUTOR_ALOLA's Fire-coverage set into
EXEGGUTOR's own list would make it reachable for a plain Kanto Exeggutor,
handing it a moveset that may not even be legal for that form (regional
forms can differ in type, which changes which moves make strategic sense as
a "set" at all). This is a real gap - form-aware curated sets are simply not
covered by this phase - and is called out again in the module docstring
below where MSRC_SET is wired up, plus in PARTY_SPEC_SPEC.md. Fixing it
properly needs the 8-byte record widened by a form byte and MSRC_SET made
form-aware; out of scope here. Counted and reported separately from the
truly-nonexistent species above so this decision is visible, not silent.

Two further corpus data-quality issues, worked around rather than reported as
count-dropped (the record is still used, just with a defaulted field):

  - 236 records carry BOTH `Final Strategic Rating` and `Generator Difficulty`
    and they DISAGREE. `Final Strategic Rating` is the later, more complete
    pass (see the corpus's own V50 "COMPLETE STRATEGIC DIFFICULTY... PASS"
    section) and wins. 32 records have NEITHER field; TIER_NORMAL is used and
    the count is reported.
  - 32 records have none of `Source Fixed Level` / `Recommended Level Min` /
    `Recommended Level Max` (empirically these three are always present
    together or absent together - no partial case exists). A default range
    of 1-100 is used for these, reported. Separately, a handful of records
    have `Recommended Level Min` > `Recommended Level Max` (a corpus data
    error - the source's own Stadium-rental sample shows Min 45 / Max 25 for
    one record), so the two are swapped into (min(a,b), max(a,b)) rather than
    trusted positionally.

`origin_id` indexes a deduped `MovesetOriginNames` string table built from the
`Suggested Loss Text` field. 1,115 of 1,946 records (mostly the Stadium rental
sets, which use a `Set Creator` field instead) have no `Suggested Loss Text`
at all; those all share one generic fallback entry rather than one invented
per record, which would be putting words about historical Pokemon sets'
provenance in the game's mouth that the corpus never actually said.

Usage:  python3 tools/gen_movesets.py [--check] [--source PATH]
"""

import argparse
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Reuse the tested const_def/const_skip/const_next parser rather than a
# naive re-derivation: pokemon_constants.asm has one const_skip (a reserved
# slot at $1F), and a parser that just counted `const` lines sequentially
# would silently assign every species after it an id one too low - exactly
# the kind of misaligned-table bug this project's Bibles warn about. Found
# by that assert, not assumed: an early version of this script did exactly
# that and MovesetSpeciesIndex's assert_table_length failed with a
# byte count that wasn't a clean multiple of the entry width.
sys.path.insert(0, os.path.join(ROOT, "tools", "pyboy_smoke"))
from source_constants import parse_rgbds_constants
OUT = os.path.join(ROOT, "data", "trainers", "movesets.asm")
POKEMON_CONSTANTS = os.path.join(ROOT, "constants", "pokemon_constants.asm")
MOVE_CONSTANTS = os.path.join(ROOT, "constants", "move_constants.asm")
FORMS_DIR = os.path.join(ROOT, "data", "pokemon", "forms")

DEFAULT_SOURCE = (
    r"K:\Other computers\My Laptop\Red Rogue Files"
    r"\red_rogue_comprehensive_package_v3_1_2026-09-08_FIXED"
    r"\00_CURRENT\red_rogue_gen1_moveset_reference_v76_low_level_layer_complete.txt"
)

NAME_FIXES = {"PSYCHIC": "PSYCHIC_M"}

# Corpus name -> the (base species, form index) it names, per data/pokemon/
# forms/*.asm's form_record lines. Built by hand 2026-09-10 against every
# form_record in that directory and every unknown-species name the corpus
# actually uses (see the module docstring). Records naming these are DROPPED
# (not merged - see the docstring), so this table is used only to tell a
# form apart from a genuinely nonexistent species in the drop report.
FORM_NAMES = {
    "ARCANINE_HISUI", "ARTICUNO_GALAR", "DIGLETT_ALOLA", "DUGTRIO_ALOLA",
    "ELECTRODE_HISUI", "ESPEON", "EXEGGUTOR_ALOLA", "FARFETCHD_GALAR",
    "GEODUDE_ALOLA", "GLACEON", "GOLEM_ALOLA", "GRAVELER_ALOLA",
    "GRIMER_ALOLA", "GROWLITHE_HISUI", "LEAFEON", "MAROWAK_ALOLA",
    "MEOWTH_ALOLA", "MEOWTH_GALAR", "MOLTRES_GALAR", "MR_MIME_GALAR",
    "MUK_ALOLA", "NINETALES_ALOLA", "PERRSERKER", "PERSIAN_ALOLA",
    "PONYTA_GALAR", "RAICHU_ALOLA", "RAPIDASH_GALAR", "RATICATE_ALOLA",
    "RATTATA_ALOLA", "SANDSHREW_ALOLA", "SANDSLASH_ALOLA", "SLOWBRO_GALAR",
    "SLOWKING_GALAR", "SLOWPOKE_GALAR", "SYLVEON", "TAUROS_PALDEA_AQUA",
    "TAUROS_PALDEA_BLAZE", "TAUROS_PALDEA_COMBAT", "UMBREON",
    "VOLTORB_HISUI", "VULPIX_ALOLA", "WEEZING_GALAR", "ZAPDOS_GALAR",
}

GENERIC_ORIGIN = "an old team someone once ran"

# The corpus text file carries at least one mangled character from an earlier
# encoding round-trip (U+FFFD in "Pok� Cup rental set", clearly meant to
# be an e), not something introduced here. Strings are ASCII-sanitized before
# being written as `db "...", 0` since nothing here declares a CHARMAP for
# this file's INCLUDE context and RGBDS's default charmap is not guaranteed
# to have a tile for arbitrary Unicode.
def sanitize_ascii(text):
    text = text.replace("�", "e").replace("’", "'").replace("–", "-")
    return "".join(c if ord(c) < 128 else "?" for c in text)

FIELD_RE = re.compile(r"^;\s*([A-Za-z ]+?):\s*(.*)$")
DB_RE = re.compile(r"^db\s+([A-Za-z0-9_]+)(?:\s*,\s*([A-Za-z0-9_]+)){4}\s*$")


def parse_species_constants(path):
    return parse_rgbds_constants(Path(path))


def parse_move_constants(path):
    # Only membership matters here (resolve_moves just checks "does this name
    # exist"), but this still goes through the real const_def/const_skip
    # parser rather than a naive line-count, for the same reason species ids
    # do: cheap insurance against a future const_skip silently breaking a
    # simpler parser's assumptions.
    return set(parse_rgbds_constants(Path(path)))


def parse_records(path):
    """One dict per `db` line, with every `; Field: value` comment line that
    immediately precedes it (contiguous, no blank/prose line in between) - a
    genuine metadata block, not a stray prose paragraph mentioning the same
    field name elsewhere in the document (the corpus has at least one such
    paragraph, a documentation example, which this must not pick up)."""
    records = []
    current = {}
    for line in open(path, encoding="utf-8").read().splitlines():
        m = FIELD_RE.match(line)
        if m:
            current[m.group(1).strip()] = m.group(2).strip()
            continue
        if line.startswith("db "):
            m2 = DB_RE.match(line)
            if not m2:
                sys.exit(f"malformed db line, expected SPECIES + 4 moves: {line!r}")
            parts = [p.strip() for p in line[3:].split(",")]
            records.append({"species": parts[0], "moves": parts[1:], **current})
            current = {}
            continue
        current = {}
    return records


TIER_BITS = {
    "BAD": "TIER_BAD", "EASY": "TIER_EASY", "NORMAL": "TIER_NORMAL",
    "HARD": "TIER_HARD", "ELITE": "TIER_ELITE",
}


def resolve_tier(rec, stats):
    value = rec.get("Final Strategic Rating") or rec.get("Generator Difficulty")
    if not value:
        stats["no_tier"] += 1
        return "TIER_NORMAL"
    bit = TIER_BITS.get(value)
    if bit is None:
        sys.exit(f"unknown tier value {value!r} on {rec['species']}")
    return bit


def resolve_level_range(rec, stats):
    lo = rec.get("Recommended Level Min")
    hi = rec.get("Recommended Level Max")
    if not lo or not hi:
        stats["no_level"] += 1
        return 1, 100
    lo, hi = int(lo), int(hi)
    if lo > hi:
        stats["inverted_level"] += 1
        lo, hi = hi, lo
    return max(1, min(lo, 100)), max(1, min(hi, 100))


def resolve_species(name, species_ids, stats):
    if name in species_ids:
        return name
    if name in FORM_NAMES:
        stats["dropped_form"] += 1
        return None
    stats["dropped_unknown_species"] += 1
    stats["dropped_unknown_species_names"].add(name)
    return None


def resolve_moves(moves, move_names, stats):
    out = []
    for mv in moves:
        fixed = NAME_FIXES.get(mv, mv)
        if fixed not in move_names:
            stats["dropped_unknown_move"] += 1
            stats["dropped_unknown_move_names"].add(mv)
            return None
        out.append(fixed)
    return out


def build(source_path):
    species_ids = parse_species_constants(POKEMON_CONSTANTS)
    move_names = parse_move_constants(MOVE_CONSTANTS)
    records = parse_records(source_path)
    assert len(records) == 1946, f"expected 1946 corpus records, got {len(records)}"

    stats = defaultdict(int)
    stats["dropped_unknown_species_names"] = set()
    stats["dropped_unknown_move_names"] = set()

    origin_order = []
    origin_index = {}

    def origin_id_for(text):
        if text not in origin_index:
            origin_index[text] = len(origin_order)
            origin_order.append(text)
        return origin_index[text]

    by_species = defaultdict(list)
    kept = 0
    for rec in records:
        species = resolve_species(rec["species"], species_ids, stats)
        if species is None:
            continue
        moves = resolve_moves(rec["moves"], move_names, stats)
        if moves is None:
            continue
        tier = resolve_tier(rec, stats)
        lvl_min, lvl_max = resolve_level_range(rec, stats)
        loss_text = sanitize_ascii(rec.get("Suggested Loss Text") or GENERIC_ORIGIN)
        origin_id = origin_id_for(loss_text)
        by_species[species].append((moves, tier, origin_id, lvl_min, lvl_max))
        kept += 1

    return species_ids, by_species, origin_order, stats, kept, len(records)


def render(species_ids, by_species, origin_order, stats, kept, total):
    max_id = max(species_ids.values())
    lines = []
    lines.append("; Curated moveset corpus for MSRC_SET, generated by tools/gen_movesets.py.")
    lines.append("; NOT wired into `make` - re-run by hand and commit the output, the same")
    lines.append("; tools/gen_event_constants.py / tools/reorder_move_ranks.py arrangement.")
    lines.append(";")
    lines.append(f"; Source corpus: {total} records. Kept {kept}, dropped {total - kept}:")
    lines.append(f";   {stats['dropped_unknown_species']} named a species absent from this tree entirely")
    lines.append(f";     ({len(stats['dropped_unknown_species_names'])} distinct: "
                 + ", ".join(sorted(stats["dropped_unknown_species_names"])) + ")")
    lines.append(f";   {stats['dropped_form']} named a regional/eeveelution FORM - dropped rather than")
    lines.append(";     merged into the base species (see this script's module docstring: the 8-byte")
    lines.append(";     record has no form field, and a form's moveset can be illegal for its base)")
    lines.append(f";   {stats['dropped_unknown_move']} named a move absent from this tree "
                 f"(after PSYCHIC->PSYCHIC_M: {sorted(stats['dropped_unknown_move_names'])})")
    lines.append(f"; Defaulted rather than dropped: {stats['no_tier']} records had no tier rating "
                 "(-> TIER_NORMAL),")
    lines.append(f";   {stats['no_level']} had no level range (-> 1-100), "
                 f"{stats['inverted_level']} had an inverted range (swapped).")
    lines.append("")
    lines.append('SECTION "Movesets Index", ROMX, BANK[$3D]')
    lines.append("")
    lines.append("MovesetOriginNames::")
    lines.append("\ttable_width 2, MovesetOriginNames")
    for i, _ in enumerate(origin_order):
        lines.append(f"\tdw .origin{i}")
    lines.append(f"\tassert_table_length {len(origin_order)}")
    for i, text in enumerate(origin_order):
        escaped = text.replace('"', '\\"')
        lines.append(f'.origin{i}: db "{escaped}", 0')
    lines.append("")
    lines.append("; One record per curated set: db move1, move2, move3, move4, tier, origin_id,")
    lines.append("; lvl_min, lvl_max. Species is NOT stored per-record - it is implied by which")
    lines.append("; species' run of records this is, addressed via MovesetSpeciesIndex.")
    lines.append("DEF MOVESET_RECORD_SIZE EQU 8")
    lines.append("")

    populated = sorted((n for n in by_species if by_species[n]), key=lambda n: species_ids[n])

    # Split the records across two ROMX banks (a single SECTION cannot span a
    # bank boundary). The split point is chosen by cumulative BYTE size, not
    # by species id, so it balances the two banks regardless of how the
    # corpus's per-species record counts happen to be distributed - a fixed
    # id-range split (e.g. "$01-$7F") could put most of the data in one half
    # if sets cluster among low or high species ids, which they do (Kanto's
    # low ids carry far more Smogon/tournament coverage than the Johto tail).
    sizes = [(name, len(by_species[name]) * 8) for name in populated]
    total_bytes = sum(sz for _, sz in sizes)
    running = 0
    split_index = len(sizes)
    for i, (_, sz) in enumerate(sizes):
        if running + sz > total_bytes // 2:
            split_index = i
            break
        running += sz
    part1, part2 = populated[:split_index], populated[split_index:]

    lines.append('SECTION "Movesets 1", ROMX, BANK[$3A]')
    lines.append("")
    for name in part1:
        lines.append(f"Moveset_{name}::")
        for moves, tier, origin_id, lvl_min, lvl_max in by_species[name]:
            lines.append(
                f"\tdb {moves[0]}, {moves[1]}, {moves[2]}, {moves[3]}, "
                f"{tier}, {origin_id}, {lvl_min}, {lvl_max}"
            )
    lines.append("")
    lines.append('SECTION "Movesets 2", ROMX, BANK[$3B]')
    lines.append("")
    for name in part2:
        lines.append(f"Moveset_{name}::")
        for moves, tier, origin_id, lvl_min, lvl_max in by_species[name]:
            lines.append(
                f"\tdb {moves[0]}, {moves[1]}, {moves[2]}, {moves[3]}, "
                f"{tier}, {origin_id}, {lvl_min}, {lvl_max}"
            )
    lines.append("")
    lines.append('SECTION "Movesets Index Tail", ROMX, BANK[$3D]')
    lines.append("")

    lines.append("; Dense, indexed directly by internal species id (0 = no sets for this species).")
    lines.append("; dw offset, db count, db bank - bank is explicit because the two Movesets")
    lines.append("; sections are pinned in different ROMX banks; MSRC_SET's reader is a farcall")
    lines.append("; and must switch to it before reading a record.")
    lines.append("MovesetSpeciesIndex::")
    lines.append(f"\ttable_width 4, MovesetSpeciesIndex")
    # `dw a, b, c` emits THREE WORDS (6 bytes), not word+byte+byte - `db`
    # takes the count/bank fields separately, one directive each, or they
    # silently double in size. Found by this exact table's own
    # assert_table_length: 254 entries came out as 1,524 bytes instead of
    # 1,016, and 1524 / 254 = 6 pointed straight at it.
    lines.append("\tdw 0 ; species id 0 does not exist")
    lines.append("\tdb 0, 0")
    species_by_id = {v: k for k, v in species_ids.items()}
    for sid in range(1, max_id + 1):
        name = species_by_id.get(sid)
        if name is None or name not in by_species or not by_species[name]:
            lines.append("\tdw 0")
            lines.append("\tdb 0, 0")
            continue
        count = len(by_species[name])
        lines.append(f"\tdw Moveset_{name}")
        lines.append(f"\tdb {count}, BANK(Moveset_{name})")
    lines.append(f"\tassert_table_length {max_id + 1}")
    lines.append("")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--source", default=DEFAULT_SOURCE)
    args = ap.parse_args()

    if not os.path.exists(args.source):
        sys.exit(f"source not found: {args.source}")

    species_ids, by_species, origin_order, stats, kept, total = build(args.source)
    full = render(species_ids, by_species, origin_order, stats, kept, total)

    if args.check:
        with open(OUT, encoding="utf-8") as f:
            current = f.read()
        if current == full:
            print("up to date")
            return
        sys.exit("data/trainers/movesets.asm is STALE relative to the source corpus")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(full)
    populated_species = sum(1 for s in by_species if by_species[s])
    print(f"wrote {OUT}: {kept}/{total} records kept, {populated_species} species, "
          f"{len(origin_order)} distinct origins")


if __name__ == "__main__":
    main()
