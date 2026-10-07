#!/usr/bin/env python3
"""Generate data/trainers/band_pools.asm from data/trainers/PARTY_ROSTER.md.

PARTY_ROSTER.md is the source of truth for every banded trainer pool (gym
leaders today; mini-bosses, wild-area trainers, champions and gamblers as they
move onto the party spec system). Edit the markdown, then run

    python3 tools/gen_party_roster.py            # rewrite band_pools.asm
    python3 tools/gen_party_roster.py --check    # exit 1 if the asm is stale

`make audit` runs --check, so a hand edit to band_pools.asm, or a doc edit that
was never regenerated, fails the audit.

DOC FORMAT (see the doc's own "How to edit" section for the designer's view):

    ## <Section>                 only GENERATED_SECTIONS emit pools
    ### <Prefix> (anything)      Prefix = the asm label prefix, e.g. LtSurge
    <free prose>                 ignored
    **Band <n>...**              n = 1..NUM_BANDS
    - Aces: A, B (johto), C (warp)
    - Fodder: ...
    - Off-type: ...

An entry is a species name ("Nidoran M", "Mr Mime", "Porygon2") or a form name
("Hisuian Growlithe", "Espeon", "Aqua Tauros"), optionally tagged (johto) or
(warp) to put it in that run; untagged entries are the Kanto run. Listing an
entry twice doubles its odds. Within a run, doc order is asm order.

EMITTED SHAPE. Per character, band 1..n, lists in Ace / Fod / Off order, one
`band_pool <Prefix>_<Ace|Fod|Off><band>` each. Pool ORDER IS POOL IDS: pools.asm
numbers them in the order this file defines them, so reordering characters or
bands renumbers pools (harmless: specs refer to them by name).

A pool whose entries are identical to an EARLIER pool of the same character is
emitted as `band_same <new>, <earlier>`: an alias costing no bytes.

--from-asm is the one-time bootstrap (2026-10-07): it reads the shipping asm,
not LEADER_REVIEW.md, because the asm had been hand-edited since that sheet was
generated. --prose names a LEADER_REVIEW.md-style file whose per-leader headers
and notes are carried over.

Runs on Python 3.7+ (Git Bash's `py` is 3.7, and only it can read K:).
"""
import argparse
import difflib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "data", "trainers", "PARTY_ROSTER.md")
OUT = os.path.join(ROOT, "data", "trainers", "band_pools.asm")
POKEMON_CONSTANTS = os.path.join(ROOT, "constants", "pokemon_constants.asm")
FORMS_DIR = os.path.join(ROOT, "data", "pokemon", "forms")
STATS_DIR = os.path.join(ROOT, "data", "pokemon", "base_stats")
RARITY_ASM = os.path.join(ROOT, "engine", "pokemon", "rarity.asm")
EVOS_ASM = os.path.join(ROOT, "data", "pokemon", "evos_moves.asm")
BALANCE_ASM = os.path.join(ROOT, "constants", "balance_constants.asm")

NUM_BANDS = 4
GENERATED_SECTIONS = ("Gym leaders", "Mini-bosses", "Wild-area trainers",
                      "Champions", "Gamblers")
# doc bullet -> pool kind, in emitted order
LISTS = (("Aces", "Ace"), ("Fodder", "Fod"), ("Off-type", "Off"))
KIND_OF_BULLET = dict(LISTS)
BULLET_OF_KIND = {k: b for b, k in LISTS}
GROUPS = ("kanto", "johto", "warp")

# Form files whose display name is not "<Region> <Species>".
FORM_FILE_NAMES = {
    "ptaurosaqua": "Aqua Tauros",
    "ptaurosblaze": "Blaze Tauros",
    "ptauroscombat": "Combat Tauros",
    "sandyshocks": "Sandy Shocks",
    "screamtail": "Scream Tail",
}
REGION_PREFIX = {"a": "Alolan", "g": "Galarian", "h": "Hisuian", "p": "Paldean"}


# Gym leaders that only appear with Johto on, so they have no Kanto-only run to
# need a Kanto ace for. Measured 2026-10-07: custom_functions/random_stage_selection.asm
# GymLeaderPool indexes 8-15 (Falkner..Clair) are Johto-only, and Janine's coin flip
# only runs when the pool is NUM_GYM_POOL_ALL.
JOHTO_GATED = ("Falkner", "Bugsy", "Whitney", "Morty", "Chuck", "Jasmine", "Pryce",
               "Clair", "Janine")
# Pinned forms that may sit in the Johto run (band_pools.asm header rule): every
# other pinned form is Time Warp content.
JOHTO_FORMS = (("JOLTEON", 1), ("JOLTEON", 2))  # Espeon, Umbreon
# Minimum Ace base stat total per band (the old LEADER_REVIEW "weak here?" rule).
# Gym leaders only: the floors were set against gym levels.
WEAK_ACE_BST = {2: 360, 3: 430, 4: 470}

CURVE_BEGIN = "<!-- BEGIN GENERATED: gym curve -->"
CURVE_END = "<!-- END GENERATED: gym curve -->"


class RosterError(Exception):
    pass


# --- names ---------------------------------------------------------------------

def load_species():
    names = []
    with open(POKEMON_CONSTANTS, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"\s*const\s+([A-Z0-9_]+)", line)
            if m:
                names.append(m.group(1))
    return set(names)


def species_display(const):
    return const.replace("_", " ").title()


def load_forms(species):
    """{(SPECIES, index): display name} from data/pokemon/forms/*.asm."""
    out = {}
    for fn in sorted(os.listdir(FORMS_DIR)):
        if not fn.endswith(".asm"):
            continue
        stem = fn[:-4]
        with open(os.path.join(FORMS_DIR, fn), encoding="utf-8") as f:
            m = re.search(r"form_record\s+([A-Z0-9_]+)\s*,\s*(\d+)", f.read())
        if not m:
            continue
        key = (m.group(1), int(m.group(2)))
        base = m.group(1).replace("_", "").lower()
        if stem in FORM_FILE_NAMES:
            name = FORM_FILE_NAMES[stem]
        elif stem[1:] == base and stem[0] in REGION_PREFIX:
            name = "{} {}".format(REGION_PREFIX[stem[0]], species_display(m.group(1)))
        else:
            name = stem.title()
        if key in out:
            raise RosterError("two form files claim {}: {} and {}".format(key, out[key], name))
        out[key] = name
    return out


class Names:
    def __init__(self):
        self.species = load_species()
        self.forms = load_forms(self.species)
        self.by_name = {}
        for sp in self.species:
            self.by_name[self._key(species_display(sp))] = (sp, None)
        for (sp, idx), name in self.forms.items():
            k = self._key(name)
            if k in self.by_name:
                raise RosterError("form name {!r} collides with a species".format(name))
            self.by_name[k] = (sp, idx)

    @staticmethod
    def _key(name):
        return re.sub(r"[^a-z0-9]", "", name.lower())

    def lookup(self, name):
        hit = self.by_name.get(self._key(name))
        if hit is None:
            raise RosterError("unknown species or form {!r}".format(name))
        return hit

    def display(self, species, form):
        if form is None:
            return species_display(species)
        if (species, form) not in self.forms:
            raise RosterError("no form record {} {}".format(species, form))
        return self.forms[(species, form)]


# --- doc model -----------------------------------------------------------------
#
# characters: list of dicts {section, prefix, header, prose, bands}
# bands: {band: {kind: [(species, form, group), ...]}}

ENTRY_RE = re.compile(r"^(?P<name>.+?)(?:\s*\((?P<tag>johto|warp)\))?$")


def parse_doc(text, names):
    chars, section, cur, band = [], None, None, None
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()

        def fail(msg):
            raise RosterError("PARTY_ROSTER.md:{}: {}".format(lineno, msg))

        if line.startswith("## "):
            section, cur, band = line[3:].strip(), None, None
            continue
        if line.startswith("### "):
            if section not in GENERATED_SECTIONS:
                cur = None
                continue
            m = re.match(r"###\s+([A-Za-z][A-Za-z0-9]*)\b", line)
            if not m:
                fail("character header must start with an asm prefix: {!r}".format(line))
            if any(c["prefix"] == m.group(1) for c in chars):
                fail("character {} defined twice".format(m.group(1)))
            cur = {"section": section, "prefix": m.group(1), "bands": {}}
            chars.append(cur)
            band = None
            continue
        if cur is None:
            continue
        m = re.match(r"\*\*Band\s+(\d+)\b", line)
        if m:
            band = int(m.group(1))
            if not 1 <= band <= NUM_BANDS:
                fail("band {} out of range 1-{}".format(band, NUM_BANDS))
            if band in cur["bands"]:
                fail("{} band {} defined twice".format(cur["prefix"], band))
            cur["bands"][band] = {}
            continue
        m = re.match(r"-\s+([A-Za-z-]+):\s*(.*)$", line)
        if m:
            if band is None:
                fail("list outside a **Band n** block")
            bullet, body = m.group(1), m.group(2)
            if bullet not in KIND_OF_BULLET:
                fail("unknown list {!r} (expected {})".format(
                    bullet, ", ".join(b for b, _ in LISTS)))
            kind = KIND_OF_BULLET[bullet]
            if kind in cur["bands"][band]:
                fail("{} band {} lists {} twice".format(cur["prefix"], band, bullet))
            entries = []
            for item in [p.strip() for p in body.split(",") if p.strip()]:
                em = ENTRY_RE.match(item)
                try:
                    species, form = names.lookup(em.group("name"))
                except RosterError as e:
                    fail(str(e))
                entries.append((species, form, em.group("tag") or "kanto"))
            if not entries:
                fail("{} band {} {} is empty; delete the line instead".format(
                    cur["prefix"], band, bullet))
            cur["bands"][band][kind] = entries
    for c in chars:
        for b, lists in c["bands"].items():
            if "Fod" not in lists:
                raise RosterError("{} band {} has no Fodder list".format(c["prefix"], b))
    return chars


# --- asm emit --------------------------------------------------------------------

ASM_HEADER = """\
; GENERATED by tools/gen_party_roster.py from data/trainers/PARTY_ROSTER.md.
; DO NOT EDIT: change the doc and rerun the tool. `make audit` fails when this
; file and the doc disagree.
;
; Banded trainer pools (BALANCE_PHASE5_PLAN.md workstream F, 2026-09-29; moved
; onto the roster doc 2026-10-07). Per character, per band of GYM_BAND_ROUNDS
; rounds (gyms 1-2, 3-4, 5-6, 7-8):
;   Ace<n>  the last slot's pool. `band_ace` entries are used AS WRITTEN (never
;           evolved), so write the form you want at that band's levels. Listing
;           a species twice doubles its odds.
;   Fod<n>  every other slot. `band_mon` entries are evolved by level, so list
;           base forms.
;   Off<n>  ONE slot per team, and the fallback when a fodder slot finds every
;           on-type species already on the team (see PARTY_GEN_OFFTYPE_SLOT).
;           Also evolved by level.
;
; Each pool has a Kanto run, then `band_johto`, then `band_warp`, then
; `band_end`. A run only takes part when its species group is on. A form entry
; without an index (e.g. `band_mon GEODUDE`) may still ROLL a form when Time
; Warp is on, exactly like any procedural mon.
;
; `band_same <new>, <earlier>` is an alias for an identical pool: no bytes.
;
; Every list but Fod is optional per band: a band without Ace has no ace slot
; (every slot is fodder), and one without Off has no off-type slot. See
; banded_round_spec in party_specs.asm.
;
; This file is INCLUDEd four times: by party_specs.asm with BAND_POOL_PASS 3
; (which pools exist), then by pools.asm with 0/1/2 (ids, table rows, lists),
; so each pool is written exactly once. Macros: band_pool_macros.asm.
"""


def pool_lines(kind, entries):
    """The body lines of one pool, kanto/johto/warp runs in doc order."""
    macro = "band_ace" if kind == "Ace" else "band_mon"
    lines = []
    for group in GROUPS:
        if group == "johto":
            lines.append("\tband_johto")
        elif group == "warp":
            lines.append("\tband_warp")
        for species, form, g in entries:
            if g == group:
                lines.append("\t{} {}".format(macro, species) if form is None
                             else "\t{} {}, {}".format(macro, species, form))
    lines.append("\tband_end")
    return lines


def emit_asm(chars):
    out = [ASM_HEADER]
    for c in chars:
        out.append("; --- {} {}".format(c["prefix"], "-" * max(3, 72 - len(c["prefix"]))))
        seen = {}  # body tuple -> first pool name, this character only
        for band in sorted(c["bands"]):
            for _, kind in LISTS:
                entries = c["bands"][band].get(kind)
                if entries is None:
                    continue
                name = "{}_{}{}".format(c["prefix"], kind, band)
                body = tuple(pool_lines(kind, entries))
                if body in seen:
                    out.append("\tband_same {}, {}".format(name, seen[body]))
                    continue
                seen[body] = name
                out.append("\tband_pool {}".format(name))
                out.extend(body)
        out.append("")
    return "\n".join(out)


# --- asm -> doc bootstrap ---------------------------------------------------------

def parse_asm(text):
    """{prefix: {band: {kind: [(species, form, group)]}}}, in file order."""
    pools, order, cur, group = {}, [], None, None
    for raw in text.splitlines():
        code = raw.split(";", 1)[0].strip()
        if not code:
            continue
        op, _, arg = code.partition(" ")
        args = [a.strip() for a in arg.split(",")] if arg else []
        if op in ("band_pool", "band_same"):
            m = re.match(r"([A-Za-z0-9]+)_(Ace|Fod|Off)(\d)$", args[0])
            if not m:
                raise RosterError("unexpected pool name {}".format(args[0]))
            prefix, kind, band = m.group(1), m.group(2), int(m.group(3))
            if prefix not in pools:
                pools[prefix] = {}
                order.append(prefix)
            slot = pools[prefix].setdefault(band, {})
            if op == "band_same":
                m2 = re.match(r"([A-Za-z0-9]+)_(Ace|Fod|Off)(\d)$", args[1])
                slot[kind] = list(pools[m2.group(1)][int(m2.group(3))][m2.group(2)])
                cur = None
            else:
                cur, group = slot.setdefault(kind, []), "kanto"
        elif op == "band_johto":
            group = "johto"
        elif op == "band_warp":
            group = "warp"
        elif op == "band_end":
            cur = None
        elif op in ("band_ace", "band_mon"):
            form = int(args[1]) if len(args) > 1 else None
            cur.append((args[0], form, group))
        else:
            raise RosterError("unexpected asm line {!r}".format(raw))
    return [(p, pools[p]) for p in order]


def parse_prose(path):
    """{prefix: (header line, [prose lines])} from a LEADER_REVIEW.md-style file."""
    out, cur = {}, None
    with open(path, encoding="utf-8") as f:
        for raw in f.read().splitlines():
            if raw.startswith("### "):
                m = re.match(r"###\s+([A-Za-z][A-Za-z0-9]*)", raw)
                cur = m.group(1)
                out[cur] = (raw.rstrip(), [])
                continue
            if raw.startswith("## ") or raw.startswith("**"):
                cur = None
                continue
            if cur is not None:
                out[cur][1].append(raw.rstrip())
    return {k: (h, _trim(p)) for k, (h, p) in out.items()}


def _trim(lines):
    while lines and not lines[0]:
        lines = lines[1:]
    while lines and not lines[-1]:
        lines = lines[:-1]
    return lines


def entry_text(names, e):
    species, form, group = e
    text = names.display(species, form)
    return text if group == "kanto" else "{} ({})".format(text, group)


def emit_doc_characters(names, parsed, prose):
    out = []
    for prefix, bands in parsed:
        header, notes = prose.get(prefix, ("### " + prefix, []))
        out.append(header)
        out.append("")
        if notes:
            out.extend(notes)
            out.append("")
        for band in sorted(bands):
            out.append("**Band {}: rounds {}-{}**".format(band, 2 * band - 1, 2 * band))
            for _, kind in LISTS:
                if kind in bands[band]:
                    out.append("- {}: {}".format(BULLET_OF_KIND[kind], ", ".join(
                        entry_text(names, e) for e in bands[band][kind])))
            out.append("")
    return "\n".join(out)


# --- lint -------------------------------------------------------------------------

def load_rarity_groups():
    """{SPECIES: 'kanto'|'johto'|'warp'}: first group whose rarity lists hold it
    (RogueClassifySpecies; mirrors tools/balance/parse.py load_rarity/classify)."""
    lists, cur = {}, None
    with open(RARITY_ASM, encoding="utf-8") as f:
        for raw in f:
            code = raw.split(";", 1)[0].strip()
            m = re.match(r"^((?:Kanto|Johto|Warp)[A-Za-z]+?)(_Evos|_End)?:$", code)
            if m:
                cur = None if m.group(2) == "_End" else m.group(1)
                if cur:
                    lists.setdefault(cur, [])
                continue
            if cur and code.startswith("db "):
                lists[cur].append(code[3:].strip())
    out = {}
    for group in GROUPS:
        for label, species in sorted(lists.items()):
            if label.lower().startswith(group):
                for sp in species:
                    out.setdefault(sp, group)
    if sum(1 for g in out.values() if g == "kanto") != 151:
        raise RosterError("rarity.asm Kanto lists do not hold 151 species")
    return out


def load_evolution_targets():
    """Every species something else evolves INTO."""
    out = set()
    with open(EVOS_ASM, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r"^\s+db\s+EVOLVE_(?:LEVEL|TRADE),\s*[^,]+,\s*([A-Z_][A-Z0-9_]*)", line)
            if m:
                out.add(m.group(1))
                continue
            m = re.match(r"^\s+db\s+EVOLVE_ITEM,\s*[^,]+,\s*[^,]+,\s*([A-Z_][A-Z0-9_]*)", line)
            if m:
                out.add(m.group(1))
    return out


STAT_LINE = re.compile(r"^\s*db\s+(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:;.*)?$")


def base_stat_total(species, form):
    """Sum of the first five-number `db` line of the species (or form) file."""
    if form is None:
        fn = None
        for stem in (species.replace("_", "").lower(), species.lower()):  # PORYGON_Z keeps its _
            if os.path.exists(os.path.join(STATS_DIR, stem + ".asm")):
                fn = os.path.join(STATS_DIR, stem + ".asm")
        if fn is None:
            raise RosterError("no base stats file for " + species)
    else:
        fn = None
        for name_fn in sorted(os.listdir(FORMS_DIR)):
            if not name_fn.endswith(".asm"):
                continue
            with open(os.path.join(FORMS_DIR, name_fn), encoding="utf-8") as f:
                m = re.search(r"form_record\s+([A-Z0-9_]+)\s*,\s*(\d+)", f.read())
            if m and (m.group(1), int(m.group(2))) == (species, form):
                fn = os.path.join(FORMS_DIR, name_fn)
        if fn is None:
            raise RosterError("no form file for {} {}".format(species, form))
    with open(fn, encoding="utf-8") as f:
        for line in f:
            m = STAT_LINE.match(line)
            if m:
                return sum(int(g) for g in m.groups())
    raise RosterError("no base stat line in " + os.path.relpath(fn, ROOT))


LIST_NAME = {"Ace": "Aces", "Fod": "Fodder", "Off": "Off-type"}


def lint(chars, names, groups=None, evo_targets=None, bst=None):
    """[(severity, message)], severity 'error' or 'warning'. Errors fail the tool."""
    groups = load_rarity_groups() if groups is None else groups
    evo_targets = load_evolution_targets() if evo_targets is None else evo_targets
    bst = bst or base_stat_total
    out = []
    for c in chars:
        who = c["prefix"]
        for band in sorted(c["bands"]):
            lists = c["bands"][band]
            # Every kind, not only gym leaders: an Ace pool with no eligible
            # entry does NOT drop the ace. PartyGenRollFromPool's .giveUp takes
            # the pool's first entry UNFILTERED, so a Kanto-only run would field
            # Johto/Warp content (rogue_build_party.asm, read 2026-10-07).
            if (who not in JOHTO_GATED
                    and "Ace" in lists
                    and not any(g == "kanto" for _, _, g in lists["Ace"])):
                out.append(("error", "{} band {} Aces: no Kanto (untagged) ace, "
                            "so a Kanto-only run has none".format(who, band)))
            for kind in ("Ace", "Fod", "Off"):
                entries = lists.get(kind)
                if not entries:
                    continue
                where = "{} band {} {}".format(who, band, LIST_NAME[kind])
                counts = {}
                for sp, form, g in entries:
                    counts[(sp, form)] = counts.get((sp, form), 0) + 1
                    shown = names.display(sp, form)
                    if form is not None:
                        ok = g == "warp" or (g == "johto" and (sp, form) in JOHTO_FORMS)
                        if not ok:
                            out.append(("error", "{}: {} is a pinned form, so it must be "
                                        "tagged (warp)".format(where, shown)))
                    else:
                        sg = groups.get(sp)
                        if sg == "johto" and g == "kanto":
                            out.append(("error", "{}: {} is a Johto-group species and "
                                        "needs (johto) or (warp)".format(where, shown)))
                        elif sg == "warp" and g != "warp":
                            out.append(("error", "{}: {} is a Warp-group species and "
                                        "needs (warp)".format(where, shown)))
                    if kind in ("Fod", "Off") and sp in evo_targets:
                        out.append(("warning", "{}: {} is not a base form".format(where, shown)))
                    if kind == "Ace" and band in WEAK_ACE_BST and c["section"] == "Gym leaders":
                        total = bst(sp, form)
                        if total < WEAK_ACE_BST[band]:
                            out.append(("warning", "{}: {} BST {} is under {} (weak here?)".format(
                                where, shown, total, WEAK_ACE_BST[band])))
                for (sp, form), n in sorted(counts.items(), key=lambda kv: str(kv[0])):
                    if n > 2:
                        out.append(("warning", "{}: {} is listed {} times".format(
                            where, names.display(sp, form), n)))
    return out


# --- generated curve block ----------------------------------------------------------

def load_curve(text=None):
    """{round: (mons, base, step)} from GYM_R<n>_MONS/BASE/STEP literals."""
    if text is None:
        text = read(BALANCE_ASM)
    vals = {}
    for m in re.finditer(r"^DEF\s+GYM_R(\d+)_(MONS|BASE|STEP)\s+EQU\s+(.*?)\s*(?:;.*)?$",
                         text, re.M):
        if not re.match(r"^\d+$", m.group(3)):
            raise RosterError("GYM_R{}_{} is {!r}, not a literal; teach "
                              "gen_party_roster.py before using an expression".format(
                                  m.group(1), m.group(2), m.group(3)))
        vals[(int(m.group(1)), m.group(2))] = int(m.group(3))
    rounds = {}
    for r in range(1, 2 * NUM_BANDS + 1):
        try:
            rounds[r] = tuple(vals[(r, k)] for k in ("MONS", "BASE", "STEP"))
        except KeyError:
            raise RosterError("GYM_R{}_MONS/BASE/STEP missing from "
                              "balance_constants.asm".format(r))
    return rounds


def curve_block(rounds):
    def span(vals):
        return "{}-{}".format(min(vals), max(vals))
    rows = [CURVE_BEGIN,
            "<!-- Rewritten by tools/gen_party_roster.py from GYM_R<n>_MONS/BASE/STEP in "
            "constants/balance_constants.asm. Do not edit by hand. -->",
            "",
            "| Band | Rounds | Team size | Slot 0 L | Ace L |",
            "|---|---|---|---|---|"]
    for band in range(1, NUM_BANDS + 1):
        rs = [2 * band - 1, 2 * band]
        mons = [rounds[r][0] for r in rs]
        base = [rounds[r][1] for r in rs]
        ace = [rounds[r][1] + (rounds[r][0] - 1) * rounds[r][2] for r in rs]
        rows.append("| {} | {}-{} | {} | {} | {} |".format(
            band, rs[0], rs[1], span(mons), span(base), span(ace)))
    rows += ["", CURVE_END]
    return "\n".join(rows)


def splice_curve(doc_text, block):
    """doc_text with the text between (and including) the markers replaced."""
    b, e = doc_text.find(CURVE_BEGIN), doc_text.find(CURVE_END)
    if b < 0 or e < b:
        raise RosterError("PARTY_ROSTER.md has no '{}' ... '{}' block".format(
            CURVE_BEGIN, CURVE_END))
    return doc_text[:b] + block + doc_text[e + len(CURVE_END):]


# --- main ----------------------------------------------------------------------

def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if band_pools.asm differs from what the doc generates")
    ap.add_argument("--warnings", action="store_true",
                    help="with --check: list every lint warning instead of a count")
    ap.add_argument("--from-asm", metavar="ASM",
                    help="bootstrap: print the doc's character blocks for this asm")
    ap.add_argument("--prose", metavar="MD",
                    help="with --from-asm: carry headers/notes over from this file")
    args = ap.parse_args()
    try:
        names = Names()
        if args.from_asm:
            prose = parse_prose(args.prose) if args.prose else {}
            sys.stdout.write(emit_doc_characters(names, parse_asm(read(args.from_asm)), prose))
            return 0
        doc_text = read(DOC)
        chars = parse_doc(doc_text, names)
        asm = emit_asm(chars)
        findings = lint(chars, names)
        new_doc = splice_curve(doc_text, curve_block(load_curve()))
    except RosterError as e:
        print("gen_party_roster: " + str(e), file=sys.stderr)
        return 1
    warnings = [m for sev, m in findings if sev == "warning"]
    # The designer-facing warnings run to ~200 lines on today's doc, so the audit
    # (--check) prints a count unless --warnings asks for the list.
    if not args.check or args.warnings:
        for sev, msg in findings:
            print("gen_party_roster: {}: {}".format(sev, msg), file=sys.stderr)
    elif warnings:
        print("gen_party_roster: {} lint warning(s); run without --check (or with "
              "--warnings) to list them".format(len(warnings)), file=sys.stderr)
    for sev, msg in findings:
        if sev == "error" and args.check and not args.warnings:
            print("gen_party_roster: error: " + msg, file=sys.stderr)
    errors = sum(1 for sev, _ in findings if sev == "error")
    if errors:
        print("gen_party_roster: {} lint error(s); nothing written".format(errors),
              file=sys.stderr)
        return 1
    if args.check:
        bad = False
        current = read(OUT) if os.path.exists(OUT) else ""
        if current != asm:
            sys.stdout.writelines(difflib.unified_diff(
                current.splitlines(True), asm.splitlines(True),
                "band_pools.asm (committed)", "band_pools.asm (from PARTY_ROSTER.md)", n=1))
            print("gen_party_roster: band_pools.asm is stale; run "
                  "`python3 tools/gen_party_roster.py`", file=sys.stderr)
            bad = True
        if new_doc != doc_text:
            sys.stdout.writelines(difflib.unified_diff(
                doc_text.splitlines(True), new_doc.splitlines(True),
                "PARTY_ROSTER.md (committed)", "PARTY_ROSTER.md (regenerated)", n=1))
            print("gen_party_roster: the generated curve block in PARTY_ROSTER.md is stale; "
                  "rerun `python3 tools/gen_party_roster.py`", file=sys.stderr)
            bad = True
        if bad:
            return 1
        print("gen_party_roster: band_pools.asm and the curve block match PARTY_ROSTER.md")
        return 0
    write(OUT, asm)
    if new_doc != doc_text:
        write(DOC, new_doc)
    print("gen_party_roster: wrote " + os.path.relpath(OUT, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
