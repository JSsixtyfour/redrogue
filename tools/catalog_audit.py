#!/usr/bin/env python3
"""Source-only checks on tools/corpus/moveset_catalog.tsv (Moveset revision Phase 2).

Errors (exit 1):
  - ids unique, statuses known, segments well-formed (1 <= lo <= hi <= 100,
    TIER_* tokens only, no overlap inside a row);
  - every ACTIVE row: species/form exists, every move is a move constant
    (so a historical ROAR, now SUPER_TRANSFORM's id, can never slip in) or
    NO_MOVE, no move twice, every move learnable (tools/learnset_legality.py),
    a credit (credit_type not PENDING, set_name not empty) whose label fits;
  - tutor rule (user decision 2026-10-27): no ACTIVE row needs a move its line
    can only get from a move tutor. TUTOR_RULE_ENFORCED is True since Phase 3
    marked the tutor-dependent sets EXCLUDED (False downgrades it to a warning);
  - data/trainers/movesets.asm and rental_origins.asm match the catalog;
  - coverage: no (species/form, level, requested tier mask) that has a curated
    set in COVERAGE_BASELINE loses its last one, apart from ACCEPTED_HOLES.
    "Requested" = the set_tier_mask of every party_specs.asm mix row that draws
    MSRC_SET, the same exact-then-widened-by-SET_LEVEL_SLACK_BELOW window test
    the selector uses (rogue_build_party.asm .recordPasses).

Usage:  python3 tools/catalog_audit.py [--write-coverage-baseline]
"""
import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_movesets as g
import gen_rental_origins

ROOT = g.ROOT
COVERAGE_BASELINE = os.path.join(ROOT, "tools", "corpus", "moveset_coverage_baseline.json")
TUTOR_RULE_ENFORCED = True
# (species or corpus form name, requested mask name, first level, last level): holes the
# user accepted (MOVESET_REVISION_DECISIONS_2026-10-27.md), so the generated fallback is fine.
ACCEPTED_HOLES = [
    ("ARCANINE", "TIER_GAMBLER", 1, 100),     # Gambler Arcanine (tutor Fire Spin) removed
    ("SHELLDER", "TIER_NORMAL | TIER_HARD", 31, 42),
    # Kakuna and Metapod: the retired sets were their only moves anyway (user 2026-10-27).
    *[(sp, m, 25, 100) for sp in ("KAKUNA", "METAPOD")
      for m in ("TIER_EASY | TIER_NORMAL", "TIER_NORMAL", "TIER_NORMAL | TIER_HARD")],
    ("GENGAR", "TIER_EASY | TIER_NORMAL", 25, 28),
    ("GENGAR", "TIER_NORMAL", 25, 28),
]
TIER_VALUES = {name: 1 << int(bit) for name, bit in re.findall(
    r"^DEF\s+(TIER_\w+)\s+EQU\s+1\s*<<\s*(\d+)",
    open(os.path.join(ROOT, "constants", "party_spec_constants.asm"), encoding="utf-8").read(), re.M)}
assert {"TIER_BAD", "TIER_ELITE", "TIER_GAMBLER"} <= set(TIER_VALUES), TIER_VALUES


def mask_value(expr):
    expr = str(expr).strip()
    if expr in ("", "0"):
        return 0
    return sum(TIER_VALUES[t.strip()] for t in expr.split("|"))


def requested_masks():
    """{mask expression: value} for every mix row whose MSRC_SET quota is nonzero."""
    text = open(os.path.join(ROOT, "data", "trainers", "party_specs.asm"), encoding="utf-8").read()
    out = {}
    for line in text.splitlines():
        m = re.match(r"^\s+mix\s+(.*?)(;|$)", line)
        if not m:
            continue
        cols = [c.strip() for c in m.group(1).split(",")]
        if int(cols[5]) and cols[6] != "0":
            out[cols[6]] = mask_value(cols[6])
    return out


def slack():
    text = open(os.path.join(ROOT, "constants", "balance_constants.asm"), encoding="utf-8").read()
    return int(re.search(r"SET_LEVEL_SLACK_BELOW\s+EQU\s+(\d+)", text).group(1))


def coverage(by_species, by_form):
    """{"SPECIES|mask expr": sorted covered levels} over the emitted records."""
    masks, sl = requested_masks(), slack()
    out = {}
    for table in (by_species, by_form):
        for name, recs in table.items():
            for expr, want in masks.items():
                levels = [lvl for lvl in range(1, 101)
                          if any(mask_value(r[1]) & want and r[3] <= lvl <= r[4] + sl for r in recs)]
                if levels:
                    out[f"{name}|{expr}"] = levels
    return out


def ranges(levels):
    out, start = [], levels[0]
    for a, b in zip(levels, levels[1:] + [None]):
        if b != a + 1:
            out.append(f"{start}-{a}" if start != a else str(start))
            start = b
    return ",".join(out)


def needs_tutor(key, moves, full, no_tutor):
    return [m for m in moves if m != "NO_MOVE" and m in full.get(key, {}) and m not in no_tutor.get(key, {})]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write-coverage-baseline", action="store_true",
                    help="record today's coverage as the baseline (only when the user accepts it)")
    args = ap.parse_args()
    errors, warnings = [], []
    rows = g.read_catalog()
    species_ids = g.parse_species_constants(g.POKEMON_CONSTANTS)
    move_names = g.parse_move_constants(g.MOVE_CONSTANTS) | {"NO_MOVE"}
    import learnset_legality as ll
    full = ll.load()
    real_records = ll._records
    ll._records = lambda p, s: {k: (e, lv, set(), raw) for k, (e, lv, _t, raw) in real_records(p, s).items()}
    no_tutor = ll.load()
    ll._records = real_records

    for rid, n in Counter(r["id"] for r in rows).items():
        if n > 1:
            errors.append(f"id {rid} used {n} times")
    tutor_rows = []
    for r in rows:
        where = f"{r['id']} {r['species']} {'/'.join(r['moves'])}"
        segs = r["segments"]
        for lo, hi, tier in segs:
            if not 1 <= lo <= hi <= 100:
                errors.append(f"{where}: bad window {lo}-{hi}")
            try:
                mask_value(tier)
            except KeyError:
                errors.append(f"{where}: bad tier {tier!r}")
        for (a, b, _), (c, d, _) in zip(sorted(segs), sorted(segs)[1:]):
            if c <= b:
                errors.append(f"{where}: segments {a}-{b} and {c}-{d} overlap")
        if r["status"] != "ACTIVE":
            if r["status"] in ("EXCLUDED", "REJECTED", "HELD") and not r["note"]:
                errors.append(f"{where}: {r['status']} row needs a note saying why")
            continue
        if r["kind"] == "species":
            key = r["species"]
            if key not in species_ids:
                errors.append(f"{where}: no such species")
                continue
        elif r["kind"] == "form":
            key = g.form_key(r["species"])
            if key is None:
                errors.append(f"{where}: no such form")
                continue
        else:
            errors.append(f"{where}: ACTIVE row of kind {r['kind']!r}")
            continue
        if not segs:
            errors.append(f"{where}: ACTIVE with no segments")
        bad = [m for m in r["moves"] if m not in move_names]
        if bad:
            errors.append(f"{where}: not a move constant: {bad}")
            continue
        occupied = [m for m in r["moves"] if m != "NO_MOVE"]
        if len(set(occupied)) != len(occupied):
            errors.append(f"{where}: a move appears twice")
        unlearnable = [m for m in occupied if m not in full[key]]
        if unlearnable:
            errors.append(f"{where}: cannot learn {unlearnable}")
        tutor = needs_tutor(key, occupied, full, no_tutor)
        if tutor:
            tutor_rows.append(f"{where}: tutor-only {tutor}")
        if r["credit_type"] == "PENDING" or not r["set_name"]:
            errors.append(f"{where}: ACTIVE without a credit (credit_type/set_name)")
        try:
            g.display_text((r["creator"], r["set_name"]))
        except AssertionError as e:
            errors.append(f"{where}: label does not fit the text box: {e}")
    if tutor_rows:
        (errors if TUTOR_RULE_ENFORCED else warnings).append(
            f"{len(tutor_rows)} ACTIVE rows need a tutor-only move (mark them EXCLUDED):\n    "
            + "\n    ".join(tutor_rows[:10]) + ("\n    ..." if len(tutor_rows) > 10 else ""))

    text, built = g.render_catalog()
    if open(g.OUT, encoding="utf-8").read() != text:
        errors.append("data/trainers/movesets.asm is stale: run tools/gen_movesets.py")
    else:
        try:
            if gen_rental_origins.OUT.read_text(encoding="utf-8") != gen_rental_origins.render(g.CATALOG):
                errors.append("rental_origins.asm is stale: run tools/gen_rental_origins.py")
        except ValueError as e:
            errors.append(f"rental origins: {e}")

    _, by_species, _, _, _, _, by_form = built
    cov = coverage(by_species, by_form)
    if args.write_coverage_baseline:
        with open(COVERAGE_BASELINE, "w", encoding="utf-8", newline="\n") as f:
            json.dump({k: ranges(v) for k, v in sorted(cov.items())}, f, indent=0)
            f.write("\n")
        print(f"wrote {COVERAGE_BASELINE}: {len(cov)} covered (species, mask) pairs")
    else:
        base = json.load(open(COVERAGE_BASELINE, encoding="utf-8"))
        accepted = defaultdict(set)
        for sp, expr, lo, hi in ACCEPTED_HOLES:
            accepted[f"{sp}|{expr}"].update(range(lo, hi + 1))
        lost = []
        for k, rng in base.items():
            levels = {int(x) for part in rng.split(",") for x in
                      (range(int(part.split("-")[0]), int(part.split("-")[-1]) + 1))}
            gone = sorted(levels - set(cov.get(k, [])) - accepted[k])
            if gone:
                lost.append(f"{k}: levels {ranges(gone)}")
        if lost:
            errors.append(f"coverage lost on {len(lost)} (species, mask) pairs:\n    " + "\n    ".join(lost))

    for w in warnings:
        print("WARNING:", w)
    for e in errors:
        print("ERROR:", e)
    active = sum(r["status"] == "ACTIVE" for r in rows)
    print(f"catalog audit: {len(rows)} rows, {active} ACTIVE, {len(errors)} errors, {len(warnings)} warnings")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
