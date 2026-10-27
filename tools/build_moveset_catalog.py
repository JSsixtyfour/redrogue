#!/usr/bin/env python3
"""Seed tools/corpus/moveset_catalog.tsv (Moveset revision Phase 1, 2026-10-27).

One-shot, by hand, output committed. After this the catalog is the file people
edit; the v76 corpus .txt stays as frozen history.

Rows, in this order:
  1. Every corpus record, through gen_movesets.normalize(): the game's current
     sets as ACTIVE, records the generator drops as ARCHIVED with the reason.
     Stage B (assemble) of this catalog reproduces today's movesets.asm data.
  2. Every R065 packet tuple not already a row (the active additions, the new
     Stadium memberships, the held Japanese Tentacool), as ARCHIVED with note
     PENDING_WINDOW (HELD for Tentacool), origin 0: present for Phase 3 to
     activate, invisible to the game until then.

Each row's id is the packet's logical id (RRSET-...) when the packet has the
same tuple (species or form, unordered occupied moves), else a hash of that
identity (RR-...); a second row with the same tuple gets a -2 suffix.

Usage:  python tools/build_moveset_catalog.py [--packet DIR] [--check]
"""
import argparse
import hashlib
import json
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_movesets as g

PACKET = r"K:\Other computers\My Laptop\Red Rogue Files\MOVESET_REVISION_PLAN_2026-10-23"
OCCUPIED_SKIP = {"NO_MOVE"}
PENDING = {
    "KEEP_ACTIVE_PROPOSAL_AS_PROPOSED_ADDITION_WITH_EXISTING_GATES": ("ARCHIVED", "PENDING_WINDOW: packet addition"),
    "KEEP_REQUIRED_STADIUM_MEMBERSHIPS_WITH_NATIVE_EXCEPTIONS": ("ARCHIVED", "PENDING_WINDOW: packet Stadium membership"),
    "HOLD_USER_DISPUTED_TENTACOOL_SOURCE_NOT_SELECTED": ("HELD", "Japanese Gym Tentacool: user-held, evidence only"),
}


def identity(row):
    """The packet's identity string: SPECIES, or BASE#form for a form row."""
    if row["kind"] == "form":
        base, idx = g.form_key(row["species"])
        return f"{base}#{idx}"
    return row["species"]


def tuple_key(ident, moves):
    return ident, frozenset(m for m in moves if m not in OCCUPIED_SKIP)


def make_rows(packet_dir):
    stats = g.new_stats()
    learnable = g.load_learnable()
    _, rows, _ = g.normalize(g.DEFAULT_SOURCE, stats, learnable)
    sel = json.load(open(os.path.join(packet_dir, "proposals", "R065_SELECTION_DISPOSITIONS.json"),
                         encoding="utf-8"))["selection_dispositions"]
    packet_ids = {}
    for x in sel:
        packet_ids.setdefault(tuple_key(x["identity"], x["moves"]), (x["logical_id"], x["decision"]))

    form_name = {g.form_key(n): n for n in g.FORM_FILES if g.form_key(n) is not None}
    seen = Counter()
    for row in rows:
        ident = identity(row) if row["kind"] != "dropped" else row["species"]
        key = tuple_key(ident, row["moves"])
        pid = packet_ids.get(key)
        row["packet_id"] = pid[0] if pid else ""
        base = pid[0] if pid else "RR-" + hashlib.sha1(
            f"{ident}|{','.join(sorted(key[1]))}".encode()).hexdigest()[:12]
        seen[base] += 1
        row["id"] = base if seen[base] == 1 else f"{base}-{seen[base]}"
    present = {tuple_key(identity(r), r["moves"]) for r in rows if r["kind"] != "dropped"}

    added = Counter()
    for x in sel:
        if x["decision"] not in PENDING:
            continue
        key = tuple_key(x["identity"], x["moves"])
        if key in present:
            continue
        present.add(key)
        status, note = PENDING[x["decision"]]
        if "#" in x["identity"]:
            base, idx = x["identity"].split("#")
            species, kind = form_name.get((base, int(idx))), "form"
            if species is None:
                species, kind, note = x["identity"], "dropped", "DROPPED: form not in this tree; " + note
        else:
            species, kind = x["identity"], "species"
        moves = list(x["moves"]) + ["NO_MOVE"] * (4 - len(x["moves"]))
        is_stadium = "STADIUM" in x["decision"]
        rows.append({"id": x["logical_id"], "status": status, "kind": kind, "species": species,
                     "moves": moves, "segments": [], "credit_type": "STADIUM" if is_stadium else "PENDING",
                     "creator": "", "set_name": "", "origin": False, "asm_comment": "", "note": note,
                     "source": "R065 packet", "source_creator": "", "heading": "",
                     "packet_id": x["logical_id"]})
        added[status, note] += 1
    return rows, added


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--packet", default=PACKET)
    ap.add_argument("--check", action="store_true", help="compare with the committed catalog")
    args = ap.parse_args()
    rows, added = make_rows(args.packet)
    if args.check:
        tmp = g.CATALOG + ".check"
        g.write_catalog(rows, tmp)
        same = open(tmp, encoding="utf-8").read() == open(g.CATALOG, encoding="utf-8").read()
        os.remove(tmp)
        sys.exit(0 if same else "moveset_catalog.tsv differs from a fresh import")
    g.write_catalog(rows)
    status = Counter(r["status"] for r in rows)
    print(f"wrote {g.CATALOG}: {len(rows)} rows {dict(status)}")
    for (s, note), n in sorted(added.items()):
        print(f"  + {n} {s} ({note})")


if __name__ == "__main__":
    main()
