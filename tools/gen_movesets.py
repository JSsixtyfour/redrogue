#!/usr/bin/env python3
"""Regenerate data/trainers/movesets.asm from the curated moveset corpus.

One-shot, by hand, output committed - the tools/gen_event_constants.py /
tools/reorder_move_ranks.py arrangement. `make` never invokes Python and the
K: drive is never a build dependency.

Source: tools/corpus/red_rogue_gen1_moveset_reference_v76_low_level_layer_complete.txt
  (copied byte-identical on 2026-10-22 from Red Rogue Files\\
  red_rogue_comprehensive_package_v3_1_2026-09-08_FIXED\\00_CURRENT\\; the repo
  copy is now canonical, so it also runs from WSL).

Every `db SPECIES, MOVE1, MOVE2, MOVE3, MOVE4` line in the whole file is one
record; there are exactly 1,953 of them, measured. The 307-record CUT SETS
ARCHIVE mentioned in the corpus's own changelog turns out to carry ZERO `db`
lines of its own (its sets are preserved as prose/metadata only, not as
runtime records), so no special-cased line-range exclusion is needed - a
plain whole-file scan for `db ` lines returns exactly 1,953 (including the seven
2026-10-17 Umbreon additions) and
already excludes the CUT archive. Verified by counting `db ` lines inside vs
outside the V71 CUT SETS ARCHIVE section before writing this script.

Filtering, measured against this tree's constants (not assumed):

  - Exactly ONE unknown move name appears anywhere in the corpus: `PSYCHIC`,
    250 times. Same fix as tools/reorder_move_ranks.py: PSYCHIC -> PSYCHIC_M.
  - 137 records (57 distinct names) name a species this tree has no constant
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

FORM RECORDS (2026-10-17): now kept, in their own "Movesets Forms" section
found through MovesetFormIndex, keyed by (base species, form index) read from
each form's data/pokemon/forms/*.asm. PartyGenApplySetMovesetMask scans that
index for any mon whose form index is nonzero and NEVER falls back to the base
species' list (no form sets = the mix row's fallback, which already rolls from
the form's own learnset). The paragraph below is the original reasoning for not
MERGING form records into the base list, which still holds.

Original note: form records were dropped, deliberately, not merged into the
base species' list. The 8-byte runtime record has no form field, and MSRC_SET's
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

`origin_id` indexes `LossOriginLabels`, the "You were defeated by ..." label
printed on a blackout (engine/battle/loss_origin.asm). Indices 0-3 are fixed
engine labels (LOSS_ORIGIN_* in constants/party_spec_constants.asm, asserted in
the output); corpus labels follow, deduped. loss_label() derives one per record
from `Set Creator` plus the record's heading name ("; SPECIES - Set Name"): a
named person gives "Elo Bandit's Special Amnesia set", a Stadium rental gives
its cup name, Red Rogue originals all share fixed index 2 (their heading names
are internal design labels, not player-facing), and a record with no usable
creator falls back to its `Suggested Loss Text` category. Each label is a
(creator, name) pair of indices into two shared string tables, printed back to
back, so "Smogon's" and "BoltBeam set." are each stored once. Pre-wrapped for
the battle text box: the engine prints "by " in front, so line 1 holds 15
columns and later lines 18, joined by <CONT>. A creator-less label gets
LABEL_MAX_LINES lines; a creator owns line 1 (two lines if it wraps) and its
name gets NAME_LINES lines after it.

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

DEFAULT_SOURCE = os.path.join(
    ROOT, "tools", "corpus", "red_rogue_gen1_moveset_reference_v76_low_level_layer_complete.txt")

# NIGHTSHADE: the 2026-10-17 Umbreon additions spell it without the underscore.
NAME_FIXES = {"PSYCHIC": "PSYCHIC_M", "NIGHTSHADE": "NIGHT_SHADE"}

# Hand corrections to corpus records, applied before the legality check
# (2026-10-21, the user's edits to movesets.asm, moved here so a regenerate
# keeps them). Keyed on (corpus species name, the four corpus moves after
# NAME_FIXES); the value replaces all four moves.
CORPUS_FIXES = {
    # Poke Cup rental Seaking: the corpus had SURF/TOXIC/SMOKESCREEN/SWIFT.
    ("SEAKING", ("SURF", "TOXIC", "SMOKESCREEN", "SWIFT")):
        ("WATERFALL", "SUPERSONIC", "HORN_ATTACK", "ICE_BEAM"),
    # Poke Cup rental Charmeleon: Stun Spore was a corpus error.
    ("CHARMELEON", ("FLAMETHROWER", "COUNTER", "SEISMIC_TOSS", "STUN_SPORE")):
        ("FLAMETHROWER", "COUNTER", "SEISMIC_TOSS", "STRENGTH"),
}

# Salvage (2026-10-22): before a set is dropped as illegal, each move the mon
# cannot learn is swapped for the first legal, not-already-present move in its
# list - same type and role where Gen 1 has one (Slowbro's Waterfall -> Surf).
# A set with an illegal move that has no legal stand-in is still dropped.
SUBSTITUTES = {
    "BODY_SLAM": ["DOUBLE_EDGE", "TAKE_DOWN", "HEADBUTT", "STRENGTH", "SKULL_BASH"],
    "HEADBUTT": ["BODY_SLAM", "TAKE_DOWN", "DOUBLE_EDGE", "STOMP"],
    "STOMP": ["HEADBUTT", "BODY_SLAM", "TAKE_DOWN"],
    "TACKLE": ["POUND", "HEADBUTT", "BODY_SLAM"],
    "HYPER_BEAM": ["DOUBLE_EDGE", "BODY_SLAM", "TAKE_DOWN", "SKULL_BASH"],
    "REFLECT": ["LIGHT_SCREEN", "BARRIER", "ACID_ARMOR", "HARDEN", "DEFENSE_CURL", "WITHDRAW"],
    "AMNESIA": ["GROWTH"],  # Gen 1 Growth raises Special
    "AGILITY": ["DOUBLE_TEAM"],
    "THUNDER_WAVE": ["GLARE", "STUN_SPORE", "CONFUSE_RAY", "HYPNOSIS", "SUPERSONIC"],
    "SLEEP_POWDER": ["SPORE", "HYPNOSIS", "SING", "LOVELY_KISS"],
    "SMOKESCREEN": ["SAND_ATTACK", "FLASH", "KINESIS"],
    "EARTHQUAKE": ["DIG", "BONEMERANG", "BONE_CLUB"],
    "DIG": ["EARTHQUAKE", "BONEMERANG", "BONE_CLUB"],
    "PSYCHIC_M": ["PSYBEAM", "CONFUSION", "PSYWAVE"],
    "DRILL_PECK": ["FLY", "SKY_ATTACK", "WING_ATTACK", "PECK"],
    "WING_ATTACK": ["FLY", "GUST", "PECK"],
    "ICE_BEAM": ["BLIZZARD", "AURORA_BEAM", "ICE_PUNCH"],
    "THUNDERBOLT": ["THUNDER", "THUNDERPUNCH", "THUNDERSHOCK"],
    "THUNDERPUNCH": ["THUNDERBOLT", "THUNDER", "THUNDERSHOCK"],
    "FIRE_BLAST": ["FLAMETHROWER", "FIRE_PUNCH", "EMBER"],
    "FIRE_PUNCH": ["FLAMETHROWER", "FIRE_BLAST", "EMBER"],
    "WATERFALL": ["SURF", "HYDRO_PUMP", "BUBBLEBEAM", "CRABHAMMER", "WATER_GUN"],
    "SUBMISSION": ["DOUBLE_KICK", "JUMP_KICK", "HI_JUMP_KICK", "LOW_KICK", "ROLLING_KICK",
                   "SEISMIC_TOSS", "COUNTER"],
    "SMOG": ["SLUDGE", "ACID", "POISON_GAS"],
    "EXPLOSION": ["SELFDESTRUCT"],
    "NIGHT_SHADE": ["SEISMIC_TOSS", "PSYWAVE"],
}

# These legendaries keep the corpus level window (no level bump): a boss or
# event legendary is fielded below the level its line learns its signature
# moves (Mewtwo's Amnesia/Recover). Legality is still enforced for them.
LEVEL_BUMP_EXEMPT = {"MEW", "MEWTWO", "CELEBI", "LUGIA", "HO_OH"}

# Moves Red Rogue removed from every learnset (2026-04-05). A set naming one
# keeps its other moves and leaves that slot empty (NO_MOVE, moved last)
# instead of being dropped, so a Stadium rental such as Pidgey's survives.
REMOVED_MOVES = {"WHIRLWIND", "TELEPORT"}

# Corpus name -> the (base species, form index) it names, per data/pokemon/
# forms/*.asm's form_record lines. Built by hand 2026-09-10 against every
# form_record in that directory and every unknown-species name the corpus
# actually uses (see the module docstring). Records naming these are DROPPED
# (not merged - see the docstring), so this table is used only to tell a
# form apart from a genuinely nonexistent species in the drop report.
#
# 2026-10-17: form records are now KEPT. Each corpus form name maps to its
# data/pokemon/forms/<file>.asm, whose `form_record BASE, index` line supplies
# the (base, index) - read from the file, never restated here, so a renumbered
# form cannot silently desync. None = no such form in this tree (still dropped).
FORM_FILES = {
    "ARCANINE_HISUI": "harcanine", "ARTICUNO_GALAR": "garticuno",
    "DIGLETT_ALOLA": "adiglett", "DUGTRIO_ALOLA": "adugtrio",
    "ELECTRODE_HISUI": "helectrode", "ESPEON": "espeon",
    "EXEGGUTOR_ALOLA": "aexeggutor", "FARFETCHD_GALAR": "gfarfetchd",
    "GEODUDE_ALOLA": "ageodude", "GLACEON": "glaceon",
    "GOLEM_ALOLA": "agolem", "GRAVELER_ALOLA": "agraveler",
    "GRIMER_ALOLA": "agrimer", "GROWLITHE_HISUI": "hgrowlithe",
    "LEAFEON": "leafeon", "MAROWAK_ALOLA": "amarowak",
    "MEOWTH_ALOLA": "ameowth", "MEOWTH_GALAR": "gmeowth",
    "MOLTRES_GALAR": "gmoltres", "MR_MIME_GALAR": None,
    "MUK_ALOLA": "amuk", "NINETALES_ALOLA": "aninetales",
    "PERRSERKER": "perrserker", "PERSIAN_ALOLA": "apersian",
    "PONYTA_GALAR": "gponyta", "RAICHU_ALOLA": "araichu",
    "RAPIDASH_GALAR": "grapidash", "RATICATE_ALOLA": "araticate",
    "RATTATA_ALOLA": "arattata", "SANDSHREW_ALOLA": "asandshrew",
    "SANDSLASH_ALOLA": "asandslash", "SLOWBRO_GALAR": "gslowbro",
    "SLOWKING_GALAR": "gslowking", "SLOWPOKE_GALAR": "gslowpoke",
    "SYLVEON": "sylveon", "TAUROS_PALDEA_AQUA": "ptaurosaqua",
    "TAUROS_PALDEA_BLAZE": "ptaurosblaze", "TAUROS_PALDEA_COMBAT": "ptauroscombat",
    "UMBREON": "umbreon", "VOLTORB_HISUI": "hvoltorb",
    "VULPIX_ALOLA": "avulpix", "WEEZING_GALAR": "gweezing",
    "ZAPDOS_GALAR": "gzapdos",
    # 2026-10-27: forms with no corpus record, named for moveset_catalog.tsv's
    # rows (the user's Scream Tail and Toedscruel sets, the packet's additions).
    "SCREAM_TAIL": "screamtail", "SANDY_SHOCKS": "sandyshocks",
    "TOEDSCOOL": "toedscool", "TOEDSCRUEL": "toedscruel",
    "WIGLETT": "wiglett", "WUGTRIO": "wugtrio",
}
FORM_NAMES = set(FORM_FILES)
FORM_RECORD_RE = re.compile(r"^\s*form_record\s+([A-Z_][A-Z0-9_]*)\s*,\s*(\d+)", re.M)


def form_key(name):
    """(BASE, index) for a corpus form name, from its forms/*.asm, or None."""
    fname = FORM_FILES.get(name)
    if fname is None:
        return None
    text = open(os.path.join(FORMS_DIR, fname + ".asm"), encoding="utf-8").read()
    m = FORM_RECORD_RE.search(text)
    if not m:
        sys.exit(f"{fname}.asm has no form_record line (corpus form {name})")
    return m.group(1), int(m.group(2))

# Fixed engine labels, in LOSS_ORIGIN_* order (constants/party_spec_constants.asm).
FIXED_LABELS = [
    "a Basic Learnset",          # LOSS_ORIGIN_LEARNSET
    "a Generated set",           # LOSS_ORIGIN_GENERATED
    "a Red Rogue original set",  # LOSS_ORIGIN_ORIGINAL (also hand-authored moves)
    "your own Champion team",    # LOSS_ORIGIN_CHAMPION (FINAL_AI's archived team)
]
LOSS_ORIGIN_ORIGINAL = 2

# Set Creator values that are categories, not people.
CREATOR_CATEGORY = {
    "Red Rogue project original": FIXED_LABELS[LOSS_ORIGIN_ORIGINAL],
    "Smogon community standard/reference set — no single creator": "a Smogon standard set",
    "Smogon GSC adaptation": "a GSC-inspired set",
    "RBY OU Ladder / Jank Discussion": "an RBY OU ladder jank set",
    "My RBY OU Team — 2016 historical RMT": "a historical RBY team build",
}
# Set Creator values whose display name needs trimming.
CREATOR_NAME_FIXES = {
    "Boom — dsm77773 (2015)": "dsm77773",
    "Ctown6 + Chuva": "Ctown6 and Chuva",
}
LINE1_WIDTH = 15         # "by " takes the first 3 of the box's 18 columns
LINE_WIDTH = 18
LABEL_MAX_LINES = 3      # a creator-less label
NAME_LINES = 2           # a set name after its creator's line(s)
# Characters the game font has (constants/charmap.asm) besides letters/digits.
FONT_PUNCT = set(" ()[]:;'-?!.%/,é")


def to_font(text):
    """Map corpus text onto characters the game font can draw. The corpus
    carries one U+FFFD from an old encoding round-trip ("Pok? Cup"), meant
    to be an e-acute, which the font has."""
    text = (text.replace("�", "é").replace("’", "'")
            .replace("—", "-").replace("–", "-")
            .replace("+", "and").replace("&", "and").replace("_", " "))
    out = "".join(c for c in text if (c.isascii() and c.isalnum()) or c in FONT_PUNCT)
    return re.sub(r"\s+", " ", out).strip()


def article(word):
    return "an" if word[:1].lower() in "aeiou" else "a"


def loss_label(rec):
    """(creator, name) for the record's blackout label. creator is "" for a
    category label ("a Generated set"); display_text adds the possessive."""
    creator = rec.get("Set Creator") or ""
    name = rec.get("_name")
    if creator in CREATOR_CATEGORY:
        return ("", CREATOR_CATEGORY[creator])
    if creator.startswith("Official Pok"):
        # "Poke Cup Rentals" -> "a Poke Cup Rental"
        event = re.sub(r"Rentals$", "Rental", rec.get("Attribution Event") or "")
        event = re.sub(r"\bPoke\b", "Poké", event)  # the corpus spells it both ways
        rental = to_font(name or event or "Stadium rental")
        return ("", f"{article(rental)} {rental}")
    if creator and creator != "UNRESOLVED":
        who = to_font(CREATOR_NAME_FIXES.get(creator, creator))
        if not name:
            return (who, "set")
        what = to_font(name)
        if not re.search(r"(set|team|build|rental)$", what, re.I):
            what += " set"
        return (who, what)
    loss = rec.get("Suggested Loss Text") or ""
    loss = re.sub(r"^You (lost to|got caught by) ", "", loss).rstrip(".")
    return ("", to_font(loss) if loss else "a sourced RBY set")


def tiles(text):
    """Width in font tiles: 's 't 'd 'l 'v 'r 'm are single ligature tiles."""
    return len(re.sub(r"'[stdlvrm]", "x", text))


def wrap_creator(who):
    """Word-wrap "<who>'s" onto line 1 (15 tiles) and at most one more line,
    never trimming: a creator's name prints whole. A first word too wide for
    line 1 leaves line 1 empty ("by" alone), as wrap_label does."""
    widths = [LINE1_WIDTH, LINE_WIDTH]
    lines, cur = [], ""
    for w in f"{who}'s".split(" "):
        trial = f"{cur} {w}" if cur else w
        if tiles(trial) > widths[len(lines)]:
            lines.append(cur)
            cur = w
            assert len(lines) < len(widths), f"creator {who!r} needs more than 2 lines"
        else:
            cur = trial
    lines.append(cur)
    assert all(tiles(l) <= widths[i] for i, l in enumerate(lines)), (who, lines)
    return lines


def wrap_label(label, widths=None):
    """Word-wrap into the given line widths (default: all LABEL_MAX_LINES lines,
    15 tiles then 18), ending in '.', dropping trailing whole words that do not
    fit. A first word too wide for line 1 leaves line 1 empty ("by" alone)
    rather than splitting the word."""
    if widths is None:
        widths = [LINE1_WIDTH] + [LINE_WIDTH] * (LABEL_MAX_LINES - 1)
    words = label.split(" ")
    words[-1] += "."                     # the full stop travels with the last word
    lines, cur = [], ""
    for w in words:
        while True:
            if len(lines) == len(widths):
                break
            trial = f"{cur} {w}" if cur else w
            if tiles(trial) <= widths[len(lines)]:
                cur = trial
                break
            lines.append(cur)            # cur may be "" only on line 1
            cur = ""
        if len(lines) == len(widths):
            break
    else:
        lines.append(cur)
    if not lines[-1].endswith("."):      # ran out of lines: trim to fit a '.'
        last = lines[-1].rstrip(" '-/,")
        while tiles(last) + 1 > widths[len(lines) - 1]:
            last = last.rsplit(" ", 1)[0].rstrip(" '-/,")
        lines[-1] = last + "."
    assert all(tiles(l) <= widths[i] for i, l in enumerate(lines)), (label, lines)
    return lines


def display_text(label):
    """(creator text, name text) as the two strings PrintLossOrigin places one
    after the other. A creator fills line 1 (two lines if it must wrap) and
    the name always gets NAME_LINES full lines after it, so one name string
    serves every creator. label is a loss_label() pair or a plain category
    string (no creator). Also the origin dedupe key: equal pairs share an id."""
    creator, name = ("", label) if isinstance(label, str) else label
    if not creator:
        return ("", "<CONT>".join(wrap_label(name)))
    who = wrap_creator(creator)
    widths = [LINE_WIDTH] * NAME_LINES
    return ("<CONT>".join(who), "<CONT>" + "<CONT>".join(wrap_label(name, widths)))

# Keys may carry digits and hyphens ("Rental Species-Aware Score", "Level 15
# Legality Basis"). A key this rejects resets the block, dropping every field
# above it - which is how Stadium rentals once lost their Attribution Event.
FIELD_RE = re.compile(r"^;\s*([A-Za-z][A-Za-z0-9 /()-]*?):\s*(.*)$")
HEAD_RE = re.compile(r"^;\s*[A-Z0-9_' .-]+?\s+[—-]+\s+(.+)$")
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
    heading = None   # the "; SPECIES - Set Name" line that opens a block
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
            records.append({"species": parts[0], "moves": parts[1:], "_name": heading,
                            **current})
            current, heading = {}, None
            continue
        h = HEAD_RE.match(line)
        heading = h.group(1).strip() if h else None
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
        if form_key(name) is None:
            stats["dropped_form"] += 1
            stats["dropped_form_names"].add(name)
        return None                       # kept form records are handled by build()
    stats["dropped_unknown_species"] += 1
    stats["dropped_unknown_species_names"].add(name)
    return None


def resolve_moves(moves, move_names, stats, species=None):
    out = []
    for mv in moves:
        fixed = NAME_FIXES.get(mv, mv)
        if fixed not in move_names:
            stats["dropped_unknown_move"] += 1
            stats["dropped_unknown_move_names"].add(mv)
            return None
        out.append(fixed)
    fix = CORPUS_FIXES.get((species, tuple(out)))
    if fix is not None:
        stats["corpus_fixes"] += 1
        out = list(fix)
    if any(mv in REMOVED_MOVES for mv in out):
        stats["removed_move_slots"] += sum(mv in REMOVED_MOVES for mv in out)
        kept = [mv for mv in out if mv not in REMOVED_MOVES]
        out = kept + ["NO_MOVE"] * (4 - len(kept))
    return out


def bump_level(moves, learnable, lvl_min, lvl_max, stats):
    """Raise lvl_min to the level the line first learns every move, so a set
    never hands a mon a move early (2026-10-22). lvl_max follows if passed."""
    need = max((learnable[mv] for mv in moves if mv != "NO_MOVE"), default=0)
    if need > lvl_min:
        stats["level_bumped"] += 1
        lvl_min = min(need, 100)
        lvl_max = max(lvl_max, lvl_min)
    return lvl_min, lvl_max


def salvage(moves, learnable, stats):
    """Swap each illegal move for its first legal SUBSTITUTES entry not already
    in the set. Returns (moves, note); note is "" if nothing changed. Moves with
    no legal stand-in are left as they are, for is_illegal to reject."""
    out, swaps = list(moves), []
    for i, mv in enumerate(out):
        if mv == "NO_MOVE" or mv in learnable:
            continue
        sub = next((c for c in SUBSTITUTES.get(mv, ()) if c in learnable and c not in out), None)
        if sub:
            out[i] = sub
            swaps.append(f"{mv}->{sub}")
    bad = [mv for mv in out if mv != "NO_MOVE" and mv not in learnable]
    if swaps and not bad:
        stats["salvaged"] += 1
        return out, "salvaged " + ", ".join(swaps)
    return moves, ""


def is_illegal(moves, learnable, label, stats):
    """True (and counted) if any move is one this mon can never learn."""
    bad = [mv for mv in moves if mv != "NO_MOVE" and mv not in learnable]
    if bad:
        stats["dropped_illegal"] += 1
        stats["dropped_illegal_detail"].append(f"{label}: {', '.join(bad)}")
    return bool(bad)


def new_stats():
    stats = defaultdict(int)
    stats["dropped_unknown_species_names"] = set()
    stats["dropped_form_names"] = set()
    stats["dropped_unknown_move_names"] = set()
    stats["dropped_illegal_detail"] = []
    stats["roster_illegal_detail"] = []
    return stats


def load_learnable():
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import learnset_legality
    return learnset_legality.load()


def credit_type(rec):
    """Which kind of source a corpus record credits (catalog column)."""
    creator = rec.get("Set Creator") or ""
    if creator.startswith("Official Pok"):
        return "STADIUM"
    if creator == "Red Rogue project original":
        return "ORIGINAL"
    if creator.startswith("Smogon community standard"):
        return "SMOGON"
    if creator and creator != "UNRESOLVED" and creator not in CREATOR_CATEGORY:
        return "PERSON"
    return "CATEGORY"


def normalize(source_path, stats, learnable):
    """Stage A: every corpus record as one row, in corpus order. A row is what
    the catalog stores: kind ("species", "form", or "dropped"), the final moves
    (name fixes, CORPUS_FIXES, removed-move slots, salvage), the corpus window
    BEFORE the level bump, the tier, the label (creator, name), and `origin`:
    whether the record takes a loss-origin id. Status is ACTIVE for a record
    the game uses; a dropped one is ARCHIVED with the reason in `note`."""
    species_ids = parse_species_constants(POKEMON_CONSTANTS)
    move_names = parse_move_constants(MOVE_CONSTANTS)
    records = parse_records(source_path)
    # A floor, not an exact count: the corpus grows by hand (the 2026-10-17
    # Umbreon sets), and an exact assert broke on every addition. The floor
    # still catches a parser that silently stops matching `db` lines.
    assert len(records) >= 1946, f"only {len(records)} corpus records parsed"
    rows = []
    for rec in records:
        creator, name = loss_label(rec)
        row = {"species": rec["species"], "moves": list(rec["moves"]), "status": "ARCHIVED",
               "origin": False, "tier": "", "lo": "", "hi": "", "creator": creator,
               "set_name": name, "credit_type": credit_type(rec), "asm_comment": "", "note": "",
               "source": rec.get("Source") or "", "source_creator": rec.get("Set Creator") or "",
               "heading": rec.get("_name") or ""}
        rows.append(row)
        species = resolve_species(rec["species"], species_ids, stats)
        if species is None:
            if form_key(rec["species"]) is None:
                row.update(kind="dropped", note="DROPPED: species or form not in this tree")
                continue
            row["kind"] = "form"
            key = form_key(rec["species"])
        else:
            row["kind"] = "species"
            key = species
        moves = resolve_moves(rec["moves"], move_names, stats, rec["species"])
        if moves is None:
            row["note"] = "DROPPED: names a move not in this tree"
            continue
        row["tier"] = resolve_tier(rec, stats)
        row["lo"], row["hi"] = resolve_level_range(rec, stats)
        # The origin is taken BEFORE the legality drop: rental_origins.asm's
        # bitmap is keyed by origin_id, so a label keeps its index even when
        # every set carrying it is dropped.
        row["origin"] = True
        moves, comment = salvage(moves, learnable[key], stats)
        row["moves"], row["asm_comment"] = moves, comment
        if is_illegal(moves, learnable[key], rec["species"] if row["kind"] == "form" else species, stats):
            row["note"] = "DROPPED: a move this mon cannot learn"
            continue
        row["status"] = "ACTIVE"
    return species_ids, rows, len(records)


def assemble(species_ids, rows, total, stats, learnable):
    """Stage B: rows -> the tables render() writes. Origin ids are numbered in
    this order: the fixed engine labels, species rows, the PARTY_ROSTER.md
    character sets, then form rows, so a label keeps its id across runs. The
    level bump runs here, against the live learnsets, so a learnset edit moves
    a set's floor without touching the catalog. A row's `segments` (catalog)
    emit one record each; corpus rows have exactly one."""
    origin_order = []
    origin_index = {}

    def origin_id_for(text):
        if text not in origin_index:
            origin_index[text] = len(origin_order)
            origin_order.append(text)
        return origin_index[text]

    def emit(row, key, out):
        origin_id = origin_id_for(display_text((row["creator"], row["set_name"])))
        if row["status"] != "ACTIVE":
            return 0
        segments = row.get("segments") or [(row["lo"], row["hi"], row["tier"])]
        for lo, hi, tier in segments:
            if row["species"] not in LEVEL_BUMP_EXEMPT:
                if len(segments) > 1 and max(
                        (learnable[key][mv] for mv in row["moves"] if mv != "NO_MOVE"), default=0) > hi:
                    continue             # a later segment starts above this one's top
                lo, hi = bump_level(row["moves"], learnable[key], lo, hi, stats)
            out.append((row["moves"], tier, origin_id, lo, hi)
                       + ((row["asm_comment"],) if row["asm_comment"] else ()))
        return 1

    # Deduped on the DISPLAYED text: two labels that wrap/trim to the same
    # lines share one entry. Indices 0-3 are the engine's LOSS_ORIGIN_*.
    for label in FIXED_LABELS:
        origin_id_for(display_text(label))
    by_species = defaultdict(list)
    by_form = defaultdict(list)
    kept = 0
    for row in rows:
        if row["kind"] == "species" and row["origin"]:
            kept += emit(row, row["species"], by_species[row["species"]])

    # Character sets (party roster Phases 6-7): every "#### Sets: <tiers>" table in
    # data/trainers/PARTY_ROSTER.md, appended AFTER the corpus so every corpus
    # origin_id keeps its index. The heading's tiers are written as-is; levels are
    # 1-100, so the level window always passes. Each record is tagged
    # `; roster <Prefix>` so gen_party_roster.py --check can compare it to the doc.
    import gen_party_roster
    for table in gen_party_roster.load_signature_sets():
        origin = origin_id_for(display_text("a {} set".format(table["label"])))
        tiers = gen_party_roster.tier_expr(table["tiers"])
        for species, moves in table["sets"]:
            # Authored sets are never dropped, only reported: the doc is the
            # source of truth and gen_party_roster.py --check compares to it.
            bad = [mv for mv in moves if mv != "NO_MOVE" and mv not in learnable[species]]
            need = max((learnable[species].get(mv, 0) for mv in moves if mv != "NO_MOVE"), default=0)
            if need > 1:
                stats["roster_level_gated"] += 1
            if bad:
                stats["roster_illegal_detail"].append(f"{table['prefix']} {species}: {', '.join(bad)}")
            by_species[species].append((list(moves), tiers, origin, 1, 100, "roster " + table["prefix"]))
            stats["roster_sets"] += 1

    # Form rows go LAST so every origin_id assigned above keeps its index
    # (rental_origins.asm's bitmap is keyed by them). Keyed by corpus name;
    # render() emits them in their own section with MovesetFormIndex.
    for row in rows:
        if row["kind"] == "form" and row["origin"]:
            n = emit(row, form_key(row["species"]), by_form[row["species"]])
            stats["form_kept"] += n
            kept += n
    for name in [n for n, recs in by_form.items() if not recs]:
        del by_form[name]                # a form whose every row was dropped

    assert len(origin_order) <= 255, f"{len(origin_order)} labels overflow the 1-byte origin_id"
    return species_ids, by_species, origin_order, stats, kept, total, by_form


def build(source_path):
    stats = new_stats()
    learnable = load_learnable()
    species_ids, rows, total = normalize(source_path, stats, learnable)
    return assemble(species_ids, rows, total, stats, learnable)


# --- The moveset catalog (tools/corpus/moveset_catalog.tsv) -------------------
# Every set ever considered, one row each, ACTIVE or not (MOVESET_REVISION_
# IMPLEMENTATION_PLAN.md). Rows are normalize()'s rows plus an id and segments.
CATALOG = os.path.join(ROOT, "tools", "corpus", "moveset_catalog.tsv")
CATALOG_FIELDS = ["id", "status", "kind", "species", "move1", "move2", "move3", "move4",
                  "segments", "credit_type", "creator", "set_name", "origin", "asm_comment",
                  "note", "source", "source_creator", "heading", "packet_id"]
CATALOG_STATUSES = {"ACTIVE", "ARCHIVED", "REJECTED", "HELD", "EXCLUDED"}


def format_segments(segments):
    return ";".join(f"{lo}-{hi}:{tier}" for lo, hi, tier in segments)


def parse_segments(text):
    out = []
    for part in filter(None, text.split(";")):
        window, tier = part.split(":", 1)
        lo, hi = window.split("-")
        out.append((int(lo), int(hi), tier.strip()))
    return out


def write_catalog(rows, path=CATALOG):
    import csv
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n", quoting=csv.QUOTE_MINIMAL)
        w.writerow(CATALOG_FIELDS)
        for row in rows:
            segs = row.get("segments")
            if segs is None:
                segs = [(row["lo"], row["hi"], row["tier"])] if row["tier"] else []
            w.writerow([*(str(row.get(k, "")) for k in CATALOG_FIELDS[:4]), *row["moves"],
                        format_segments(segs), row["credit_type"], row["creator"], row["set_name"],
                        int(bool(row["origin"])), row["asm_comment"], row["note"], row["source"],
                        row["source_creator"], row["heading"], row.get("packet_id", "")])


def read_catalog(path=CATALOG):
    """Rows in file order, shaped like normalize()'s (segments parsed)."""
    import csv
    rows = []
    with open(path, encoding="utf-8", newline="") as f:
        for rec in csv.DictReader(f, delimiter="\t"):
            if rec["status"] not in CATALOG_STATUSES:
                sys.exit(f"catalog row {rec['id']}: unknown status {rec['status']!r}")
            segs = parse_segments(rec["segments"])
            lo, hi, tier = segs[0] if segs else ("", "", "")
            rows.append({**rec, "moves": [rec[f"move{i}"] for i in range(1, 5)],
                         "segments": segs, "lo": lo, "hi": hi, "tier": tier,
                         "origin": rec["origin"] == "1"})
    return rows


def build_from_catalog(path=CATALOG):
    stats = new_stats()
    learnable = load_learnable()
    rows = read_catalog(path)
    return assemble(parse_species_constants(POKEMON_CONSTANTS), rows, len(rows), stats, learnable)


def render(species_ids, by_species, origin_order, stats, kept, total, by_form):
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
    lines.append(f";   {stats['dropped_form']} named a FORM this tree does not have "
                 f"({', '.join(sorted(stats['dropped_form_names'])) or 'none'})")
    lines.append(f";   {stats['dropped_unknown_move']} named a move absent from this tree "
                 f"(after PSYCHIC->PSYCHIC_M: {sorted(stats['dropped_unknown_move_names'])})")
    lines.append(f";   {stats['dropped_illegal']} carried a move the mon cannot learn in this tree")
    lines.append(";     (tools/learnset_legality.py: own or pre-evolution level-1, level-up,")
    lines.append(";     TM/HM or tutor list). `gen_movesets.py --list-dropped` lists them.")
    lines.append(f"; Salvaged: {stats['salvaged']} records had each unlearnable move swapped for a legal")
    lines.append(";   stand-in (SUBSTITUTES), tagged `; salvaged OLD->NEW`.")
    lines.append(f"; Level-bumped: {stats['level_bumped']} kept records had lvl_min raised to the level")
    lines.append(";   the mon's line first learns all four moves (lvl_max raised to match if passed).")
    lines.append(";   Mew, Mewtwo, Celebi, Lugia and Ho-Oh are exempt (LEVEL_BUMP_EXEMPT).")
    lines.append(f"; Hand-corrected: {stats['corpus_fixes']} records (CORPUS_FIXES); "
                 f"{stats['removed_move_slots']} Whirlwind/Teleport slots left empty.")
    lines.append(f"; Defaulted rather than dropped: {stats['no_tier']} records had no tier rating "
                 "(-> TIER_NORMAL),")
    lines.append(f";   {stats['no_level']} had no level range (-> 1-100), "
                 f"{stats['inverted_level']} had an inverted range (swapped).")
    lines.append(f"; Plus {stats['roster_sets']} character sets (levels 1-100, tagged `; roster <Prefix>`)")
    lines.append(";   from the Sets tables in data/trainers/PARTY_ROSTER.md.")
    lines.append(f"; Plus {stats['form_kept']} regional/eeveelution FORM records in their own")
    lines.append(";   section, found through MovesetFormIndex. A form mon never reads its base")
    lines.append(";   species' sets: a base set can carry moves the form cannot learn.")
    lines.append("")
    lines.append('SECTION "Movesets Index", ROMX, BANK[$3D]')
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
        for moves, tier, origin_id, lvl_min, lvl_max, *note in by_species[name]:
            lines.append(
                f"\tdb {moves[0]}, {moves[1]}, {moves[2]}, {moves[3]}, "
                f"{tier}, {origin_id}, {lvl_min}, {lvl_max}"
                + (f" ; {note[0]}" if note else "")
            )
    lines.append("")
    lines.append('SECTION "Movesets 2", ROMX, BANK[$3B]')
    lines.append("")
    for name in part2:
        lines.append(f"Moveset_{name}::")
        for moves, tier, origin_id, lvl_min, lvl_max, *note in by_species[name]:
            lines.append(
                f"\tdb {moves[0]}, {moves[1]}, {moves[2]}, {moves[3]}, "
                f"{tier}, {origin_id}, {lvl_min}, {lvl_max}"
                + (f" ; {note[0]}" if note else "")
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
    # Aliases share an id with the real name and come after it in the file
    # (STARTER1 = CHARMANDER, RESTLESS_SOUL = MAROWAK), so a plain {id: name}
    # inversion kept the alias, which has no sets: Marowak and the three
    # starters indexed as empty and every set of theirs was unreachable
    # (found 2026-10-22 by test_gambler_fields_its_forced_sets). Keep the name
    # that has sets.
    species_by_id = {}
    for k, v in species_ids.items():
        if by_species.get(k) or v not in species_by_id:
            species_by_id[v] = k
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

    # Form sets: same 8-byte records, one run per corpus form name, then a
    # short list the runtime scans when the mon's form index is nonzero.
    forms = sorted(by_form, key=lambda n: (species_ids[form_key(n)[0]], form_key(n)[1]))
    keys = [form_key(n) for n in forms]
    assert len(set(keys)) == len(keys), f"two corpus names share a form: {keys}"
    lines.append('SECTION "Movesets Forms", ROMX, BANK[$3D]')
    lines.append("")
    for name in forms:
        lines.append(f"MovesetForm_{name}::")
        for moves, tier, origin_id, lvl_min, lvl_max, *note in by_form[name]:
            lines.append(
                f"\tdb {moves[0]}, {moves[1]}, {moves[2]}, {moves[3]}, "
                f"{tier}, {origin_id}, {lvl_min}, {lvl_max}"
                + (f" ; {note[0]}" if note else ""))
    lines.append("")
    lines.append("; Scanned linearly by PartyGenApplySetMovesetMask for a mon whose form index")
    lines.append("; is nonzero: db base species, form index; dw records; db count, bank. The")
    lines.append("; last four bytes have MovesetSpeciesIndex's layout. Ends at species 0.")
    lines.append("; MOVESET_FORM_ENTRY_SIZE lives in constants/party_spec_constants.asm.")
    lines.append("MovesetFormIndex::")
    for name, (base, idx) in zip(forms, keys):
        lines.append(f"\tdb {base}, {idx}")
        lines.append(f"\tdw MovesetForm_{name}")
        lines.append(f"\tdb {len(by_form[name])}, BANK(MovesetForm_{name})")
    lines.append("\tdb 0 ; end")
    lines.append(f"\tASSERT @ - MovesetFormIndex == {len(forms)} * MOVESET_FORM_ENTRY_SIZE + 1")
    lines.append("")

    lines.append('; Blackout labels: "You were defeated / by <label>" (engine/battle/loss_origin.asm,')
    lines.append("; pinned to this same bank and read with plain [hl]). A record's origin_id")
    lines.append("; indexes this table.")
    lines.append('SECTION "Loss Origin Labels", ROMX, BANK[$35]')
    lines.append("")
    for i, const in enumerate(("LEARNSET", "GENERATED", "ORIGINAL", "CHAMPION")):
        lines.append(f"ASSERT LOSS_ORIGIN_{const} == {i}")
    # Creator 0 is the empty string: category labels print their name alone.
    creators = [""] + sorted({c for c, _ in origin_order if c})
    names = sorted({n for _, n in origin_order})
    creator_id = {c: i for i, c in enumerate(creators)}
    name_id = {n: i for i, n in enumerate(names)}
    assert len(creators) <= 256 and len(names) <= 256, (len(creators), len(names))
    lines.append(f"DEF NUM_LOSS_ORIGINS EQU {len(origin_order)}")
    lines.append("; db creator, name: LossOriginCreators then LossOriginNames, printed back to back.")
    lines.append("LossOriginLabels::")
    lines.append("\ttable_width 2, LossOriginLabels")
    for i, (creator, name) in enumerate(origin_order):
        shown = (creator + name).replace("<CONT>", " / ").lstrip(" /")
        lines.append(f"\tdb {creator_id[creator]}, {name_id[name]} ; {i}: {shown}")
    lines.append("\tassert_table_length NUM_LOSS_ORIGINS")
    lines.append("")
    lines.append("LossOriginCreators::")
    lines.append("\ttable_width 2, LossOriginCreators")
    for i, _ in enumerate(creators):
        lines.append(f"\tdw .creator{i}")
    lines.append(f"\tassert_table_length {len(creators)}")
    for i, text in enumerate(creators):
        lines.append(f'.creator{i}: db "{text}@"')
    lines.append("")
    lines.append("LossOriginNames::")
    lines.append("\ttable_width 2, LossOriginNames")
    for i, _ in enumerate(names):
        lines.append(f"\tdw .name{i}")
    lines.append(f"\tassert_table_length {len(names)}")
    for i, text in enumerate(names):
        lines.append(f'.name{i}: db "{text}@"')
    lines.append("")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--list-dropped", action="store_true",
                    help="print every corpus set dropped as illegal, then exit")
    ap.add_argument("--source", default=DEFAULT_SOURCE)
    args = ap.parse_args()

    if not os.path.exists(args.source):
        sys.exit(f"source not found: {args.source}")

    built = build(args.source)
    species_ids, by_species, origin_order, stats, kept, total, by_form = built
    if args.list_dropped:
        for line in stats["dropped_illegal_detail"]:
            print(line)
        print(f"{stats['dropped_illegal']} illegal sets dropped")
        return
    full = render(*built)

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
          f"{len(by_form)} forms ({stats['form_kept']} records), "
          f"{len(origin_order)} loss labels")


if __name__ == "__main__":
    main()
