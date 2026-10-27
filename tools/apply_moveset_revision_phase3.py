#!/usr/bin/env python3
"""Moveset revision Phase 3 (MOVESET_REVISION_IMPLEMENTATION_PLAN.md): apply the user's
decisions to tools/corpus/moveset_catalog.tsv, one idempotent step at a time.

    python tools/apply_moveset_revision_phase3.py --step N [--dry-run]

Every rule lives in tools/moveset_revision_rules.py; this file only walks the rows.
Packet inputs are read from the K: drive (Windows only). Re-running a step changes nothing.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_movesets as g
import moveset_revision_rules as rules

PACKET = r"K:\Other computers\My Laptop\Red Rogue Files\MOVESET_REVISION_PLAN_2026-10-23\proposals"
TODAY = "2026-10-27"
CREDIT_RANK = {"STADIUM": 0, "PERSON": 1, "SMOGON": 2, "ORIGINAL": 3, "CATEGORY": 4, "PENDING": 5}

_CACHE = {}


def packet(name):
    if name not in _CACHE:
        _CACHE[name] = json.load(open(os.path.join(PACKET, name), encoding="utf-8"))
    return _CACHE[name]


def worklist():
    return {r["logical_id"]: r for r in packet("R065_FULL_RANKING_WORKLIST.json")["rows"]}


def ledger():
    return packet("R065_CURRENT_PROPOSAL_LEDGER.json")


def stadium_memberships():
    return {m["proposal_logical_id"]: m for m in packet("S013_CURRENT_STADIUM_MEMBERSHIP.json")["memberships"]}


def key_of(row):
    """learnset_legality key: species name, or (base, form index) for a form row."""
    return g.form_key(row["species"]) if row["kind"] == "form" else row["species"]


def moveset(row):
    return frozenset(m for m in row["moves"] if m != "NO_MOVE")


def tier_text(segments):
    return g.format_segments(segments)


def new_id(identity, moves):
    return "RR-" + hashlib.sha1(f"{identity}|{','.join(sorted(moves))}".encode()).hexdigest()[:12]


def append_note(row, text):
    if text not in row["note"]:
        row["note"] = (row["note"] + " | " + text) if row["note"] else text


def set_status(row, status, note):
    row["status"] = status
    row["note"] = note


# --- Step 1: credits ----------------------------------------------------------------
# (creator, species, unordered moves). Decisions file, "Author lookup" table, plus the
# user-approved Sabelette/juoea credits and the three sets that stay Smogon's.
AUTHORS = [
    ("Beelzemon 2003", "ABRA", "PSYCHIC_M SEISMIC_TOSS COUNTER THUNDER_WAVE", "Side Format set"),
    ("Beelzemon 2003", "DRAGONAIR", "SURF WRAP DRAGON_RAGE AGILITY", None),
    ("Beelzemon 2003", "DRAGONAIR", "SURF THUNDERBOLT DRAGON_RAGE THUNDER_WAVE", None),
    ("Beelzemon 2003", "MACHOP", "LOW_KICK EARTHQUAKE ROCK_SLIDE SEISMIC_TOSS", "Side Format set"),
    ("Beelzemon 2003", "BULBASAUR", "RAZOR_LEAF BODY_SLAM SUBSTITUTE SWORDS_DANCE", "Side Format set"),
    ("Shellnuts", "EXEGGUTOR", "SLEEP_POWDER PSYCHIC_M EXPLOSION HYPER_BEAM", None),
    ("Mikon", "EXEGGUTOR", "PSYCHIC_M STUN_SPORE EXPLOSION REST", None),
    ("Mikon", "EXEGGUTOR", "PSYCHIC_M STUN_SPORE EXPLOSION DOUBLE_EDGE", None),
    ("Soda Eesti", "POLIWAG", "HYPNOSIS AMNESIA BLIZZARD HYDRO_PUMP", None),
    ("martinvtran", "STARMIE", "PSYCHIC_M SURF THUNDER_WAVE RECOVER", None),
    ("martinvtran", "SNORLAX", "AMNESIA BODY_SLAM EARTHQUAKE REST", None),
    ("martinvtran", "CHANSEY", "COUNTER THUNDER_WAVE SEISMIC_TOSS SOFTBOILED", None),
    ("martinvtran", "SNORLAX", "AMNESIA BLIZZARD BODY_SLAM REFLECT", None),
    ("martinvtran", "HYPNO", "AMNESIA PSYCHIC_M REST THUNDER_WAVE", None),
    ("martinvtran", "JOLTEON", "GROWTH THUNDERBOLT REST THUNDER_WAVE", None),
    ("gastlies", "MEW", "SWORDS_DANCE EARTHQUAKE HYPER_BEAM SOFTBOILED", None),
    ("gastlies", "MEWTWO", "AMNESIA BARRIER THUNDERBOLT RECOVER", None),
    ("juoea", "TENTACRUEL", "WRAP SURF SWORDS_DANCE HYPER_BEAM", None),
    ("juoea", "GYARADOS", "BODY_SLAM THUNDERBOLT SURF BLIZZARD", None),
    ("juoea", "HAUNTER", "HYPNOSIS PSYCHIC_M THUNDERBOLT EXPLOSION", None),
    ("juoea", "DRAGONITE", "THUNDER_WAVE WRAP BODY_SLAM BLIZZARD", None),
    ("juoea", "DRAGONITE", "BLIZZARD BODY_SLAM HYPER_BEAM THUNDER_WAVE", None),
    ("NotVeryCake", "ELECTABUZZ", "THUNDERBOLT THUNDER_WAVE BODY_SLAM HYPER_BEAM", None),
    ("NotVeryCake", "DRAGONITE", "THUNDER_WAVE BODY_SLAM BLIZZARD THUNDERBOLT", None),
    ("IronBullet", "GENGAR", "HYPNOSIS EXPLOSION CONFUSE_RAY NIGHT_SHADE", None),
    ("Sabelette", "KANGASKHAN", "BODY_SLAM HYPER_BEAM ROCK_SLIDE EARTHQUAKE", None),
    ("Smogon", "CLEFABLE", "BODY_SLAM BLIZZARD THUNDERBOLT THUNDER_WAVE", None),
    ("Smogon", "SCYTHER", "SLASH SWORDS_DANCE HYPER_BEAM AGILITY", None),
    ("Smogon", "SNORLAX", "BODY_SLAM THUNDER REST AMNESIA", None),
]
AUTHOR_INDEX = {(sp, frozenset(mv.split())): (who, name) for who, sp, mv, name in AUTHORS}


def person_name(heading, fallback=None):
    """Label name for a named person's set: the heading in the game font, ' set' appended
    unless it already ends in set/team/build/rental (gen_movesets.loss_label's rule)."""
    what = g.to_font(heading or "")
    what = re.sub(r"\bset \d+$", "set", what, flags=re.I)
    if not what:
        return fallback or "set"
    if not re.search(r"(set|team|build|rental)$", what, re.I):
        what += " set"
    return what


def smogon_source_name(row, profiles):
    """rules.smogon_set_name for a Smogon-credited row: the packet's standard-set name when
    the tuple has a profile, else the catalog heading ('Stadium OU - Substitute'), else OU."""
    prof = profiles.get(row["packet_id"])
    if prof and prof.get("standard_source_associations"):
        name = prof["standard_source_associations"][0].get("set_name") or ""
        if name:
            return rules.smogon_set_name(set_name=name)
    heading = (row["heading"] or "").replace(" \u2014 ", " ").strip()
    return rules.smogon_set_name(set_name=heading) if heading else "OU set"


def credit_person(row, who, name):
    row["credit_type"], row["creator"], row["set_name"] = "PERSON", who, name


def credit_smogon(row, name):
    row["credit_type"], row["creator"], row["set_name"] = "SMOGON", rules.SMOGON_CREATOR, name


def credit_original(row):
    row["credit_type"], row["creator"], row["set_name"] = "ORIGINAL", "", g.FIXED_LABELS[g.LOSS_ORIGIN_ORIGINAL]


def apply_author(r, profiles):
    """Credit a row that is in the author table; returns the creator."""
    who, name = AUTHOR_INDEX[(r["species"], moveset(r))]
    if who == "Smogon":
        credit_smogon(r, smogon_source_name(r, profiles))
    else:
        credit_person(r, who, name or person_name(r["heading"]))
    return who


def apply_credits(rows, only=None, quiet=False):
    """Credits for `only` (a predicate on rows; default: ACTIVE rows). Returns a Counter."""
    only = only or (lambda r: r["status"] == "ACTIVE")
    profiles = {p["logical_id"]: p for p in ledger()["baseline_standard_elite_profiles"]}
    members = stadium_memberships()
    c = Counter()
    for r in rows:
        if not only(r) or r["kind"] == "dropped":
            continue
        ident = (r["species"], moveset(r))
        before = (r["credit_type"], r["creator"], r["set_name"])
        # Required Stadium membership outranks every other credit.
        m = members.get(r["packet_id"])
        if m is not None and r["credit_type"] in ("SMOGON", "CATEGORY"):
            r["credit_type"], r["creator"] = "STADIUM", ""
            r["set_name"] = rules.stadium_set_name(current=rules.stadium_set_name(cup=m["source_occurrences"][0]["cup"]))
            c["stadium (outranks smogon)"] += 1
        elif ident in AUTHOR_INDEX:
            c["author " + apply_author(r, profiles)] += 1
        elif r["credit_type"] == "SMOGON":
            credit_smogon(r, smogon_source_name(r, profiles))
            c["smogon"] += 1
        elif r["credit_type"] == "CATEGORY":
            cat = r["set_name"]
            if cat == "a historical RBY team build":
                credit_person(r, "IronBullet", person_name(r["heading"]))
                c["category -> IronBullet"] += 1
            elif cat == "a GSC-inspired set":
                credit_original(r)
                c["gsc -> original"] += 1
            elif cat == "an RBY OU ladder jank set" or "Smogon" in r["source"] or "Smogon" in r["source_creator"]:
                credit_smogon(r, smogon_source_name(r, profiles))
                c["category -> smogon"] += 1
            elif cat == "a sourced Red/Blue-era set":
                # No source in the corpus. Headings that read "Level 15 Hard Trainer" are
                # the project's own naming; the rest are the Smogon Gen I Side Formats
                # thread's sets (the same thread as Beelzemon's), credited to Smogon.
                if r["heading"].startswith("Level ") or not r["heading"]:
                    credit_original(r)
                    append_note(r, f"credit {TODAY}: source blank, project-style name, assumed original")
                    c["blank category -> original"] += 1
                else:
                    credit_smogon(r, "Side Format set")
                    append_note(r, f"credit {TODAY}: source blank, Gen I side-format heading, assumed Smogon")
                    c["blank category -> smogon"] += 1
            else:
                c["category left"] += 1
        elif r["credit_type"] == "STADIUM":
            r["set_name"] = rules.stadium_set_name(current=r["set_name"])
            c["stadium wording"] += 1
        if (r["credit_type"], r["creator"], r["set_name"]) != before:
            c["changed"] += 1
    return c


def step1(rows):
    c = apply_credits(rows)
    for k, v in sorted(c.items()):
        print(f"  {k}: {v}")
    left = [r for r in rows if r["status"] == "ACTIVE" and r["credit_type"] == "CATEGORY"]
    if left:
        print(f"  CATEGORY rows still uncredited: {len(left)}")
        for r in left:
            print("   ", r["id"], r["species"], r["set_name"], "|", r["heading"], "|", r["source"][:50])


# --- Step 2: regrades and packet repairs ---------------------------------------------
def old_tier_for(seg, old_segments):
    """The catalog tier a packet segment re-grades: the old segment with the packet's
    original window, else the one overlapping it most, else the first."""
    window = tuple(seg.get("original_window") or seg.get("source_window") or ())
    for lo, hi, tier in old_segments:
        if (lo, hi) == window:
            return tier
    def overlap(o):
        return max(0, min(o[1], seg["max_level"]) - max(o[0], seg["min_level"]) + 1)
    best = max(old_segments, key=overlap, default=None)
    return best[2] if best else "TIER_NORMAL"


def step2(rows):
    wl = worklist()
    groups = defaultdict(list)
    for i, r in enumerate(rows):
        if r["status"] == "ACTIVE" and r["packet_id"]:
            groups[r["packet_id"]].append((i, r))
    c = Counter()
    for pid, grp in groups.items():
        old_segments = [s for _, r in grp for s in r["segments"]]
        win = min(grp, key=lambda ir: (CREDIT_RANK[ir[1]["credit_type"]], ir[0]))[1]
        for _, r in grp:
            if r is not win:
                set_status(r, "ARCHIVED", f"duplicate of {win['id']} (packet merge)")
                c["duplicate archived"] += 1
        if f"regraded {TODAY}" in win["note"]:
            continue
        w = wl.get(pid)
        if not w or not w["proposed_rating_segments"]:
            continue
        new_segments = []
        for s in w["proposed_rating_segments"]:
            expr = s.get("proposed_runtime_mask_expression") or "TIER_" + s["provisional_tier"]
            old = old_tier_for(s, old_segments)
            tier = rules.regrade(old, expr)
            rank = lambda e: max((rules.STRENGTH.index(t) for t in rules._tokens(e) if t in rules.STRENGTH), default=-1)
            c["promotion" if rank(expr) > rank(old) else "demotion" if rank(expr) < rank(old) else "same strength"] += 1
            new_segments.append((s["min_level"], s["max_level"], tier))
        new_segments = sorted(new_segments)
        if new_segments != sorted(win["segments"]):
            c["rows re-segmented"] += 1
        win["segments"] = new_segments
        append_note(win, f"regraded {TODAY}")
        c["rows regraded"] += 1
    # Packet repairs. Bulbasaur endpoints (45/25 -> 25/45, 40/25 -> 25/40): the window
    # becomes the proposed endpoints, keeping the regraded tier.
    for fix in ledger()["baseline_structural_range_repairs"]:
        for _, r in groups.get(fix["logical_id"], []):
            if r["status"] == "ACTIVE" and r["segments"]:
                lo, hi = fix["proposed_endpoints"]
                r["segments"] = [(lo, hi, r["segments"][0][2])]
                c["bulbasaur endpoints"] += 1
    # Interval proposals (Pidgeotto 15-20, Phanpy 1-8 + 9-24): each proposed segment is the
    # window of its own row, at that row's tier. Rows not yet ACTIVE are finished in step 3.
    by_id = {r["id"]: r for r in rows}
    for prop in ledger()["baseline_interval_proposals"]:
        for seg in prop["proposed_selection_segments"]:
            r = by_id.get(seg["logical_id"])
            if r and r["status"] == "ACTIVE" and r["segments"]:
                r["segments"] = [(seg["min_level"], seg["max_level"], r["segments"][0][2])]
                c["interval proposal"] += 1
    for k, v in sorted(c.items()):
        print(f"  {k}: {v}")


# --- Step 3: activate the pending rows -----------------------------------------------
REMOVED_STADIUM_MOVES = {"TELEPORT", "WHIRLWIND", "ROAR"}   # ROAR's id is now SUPER_TRANSFORM


def clip_segments(segments, lo, hi):
    out = [(max(a, lo), min(b, hi), t) for a, b, t in segments if max(a, lo) <= min(b, hi)]
    return out


def step3(rows):
    wl, members, led = worklist(), stadium_memberships(), ledger()
    learnable = g.load_learnable()
    profiles = {p["logical_id"]: p for p in led["baseline_standard_elite_profiles"]}
    community = {x["logical_id"]: x for x in led["community_sets_with_priority"]}
    adaptations = {x["logical_id"]: x for x in led["target_adaptations"]}
    user_sets = {x["logical_id"]: x for x in led["user_supplied_sets"]}
    clip = {seg["logical_id"]: (seg["min_level"], seg["max_level"])
            for prop in led["baseline_interval_proposals"] for seg in prop["proposed_selection_segments"]
            if seg["logical_id"] != prop["logical_id"]}
    c, no_points, illegal, tutor, activated = Counter(), [], [], [], []
    for r in rows:
        if r["status"] != "ARCHIVED" or not r["note"].startswith("PENDING_WINDOW"):
            continue
        w = wl[r["packet_id"]]
        decision = w["selection_disposition"]["decision"]
        key = key_of(r)
        moves = [m for m in r["moves"] if m != "NO_MOVE" and m not in REMOVED_STADIUM_MOVES]
        removed = [m for m in r["moves"] if m in REMOVED_STADIUM_MOVES]
        moves = moves + ["NO_MOVE"] * (4 - len(moves))
        if removed:
            c["removed-move slots -> NO_MOVE"] += 1
        moves, comment = g.salvage(moves, learnable[key], g.new_stats())
        r["moves"], r["asm_comment"] = moves, comment
        where = f"{r['id']} {r['species']} {'/'.join(moves)}"
        bad = [m for m in moves if m != "NO_MOVE" and m not in learnable[key]]
        if bad:
            set_status(r, "ARCHIVED", f"ILLEGAL: {', '.join(bad)} not learnable and no legal stand-in")
            illegal.append((where, bad, r["credit_type"]))
            continue
        need = rules.tutor_only_moves(key, moves)
        if need:
            set_status(r, "EXCLUDED", f"TUTOR: {', '.join(need)}")
            tutor.append((where, need, r["credit_type"]))
            continue
        floor = max([learnable[key][m] for m in moves if m != "NO_MOVE"] + [1])
        points = [p for ref in w["current_point_profile_refs"][:1] for p in ref["points"]]
        if not points:
            no_points.append(where)
        r["segments"] = rules.point_segments(points, floor)
        if r["id"] in clip:
            r["segments"] = clip_segments(r["segments"], *clip[r["id"]])
            c["interval proposal clip"] += 1
        if not r["segments"]:
            set_status(r, "ARCHIVED", "NO WINDOW: every graded point sits below the move floor")
            illegal.append((where, ["window"], r["credit_type"]))
            continue
        if r["id"] in members:                       # a Stadium membership
            r["credit_type"], r["creator"] = "STADIUM", ""
            r["set_name"] = rules.stadium_set_name(cup=members[r["id"]]["source_occurrences"][0]["cup"])
            r["source"] = "S013 Stadium membership"
        elif r["id"] in community:
            a = community[r["id"]]["source"]["associations"][0]
            who = community[r["id"]]["source"].get("individual_creator") or ""
            if who and not who.startswith("NOT_ESTABLISHED"):
                credit_person(r, who, person_name(a["set_name"]))
            else:
                credit_smogon(r, rules.smogon_set_name(pkmn_format=a["format"], role=a["set_name"]))
            r["source"] = "R065 community set (" + community[r["id"]]["source"]["dataset_url"] + ")"
            r["heading"] = a["set_name"]
        elif r["id"] in adaptations or r["id"] in user_sets:
            credit_original(r)
            r["source"] = "R065 " + ("user-supplied set" if r["id"] in user_sets else "target adaptation")
        else:
            sys.exit(f"{where}: pending row is in no credit list")
        if (r["species"], moveset(r)) in AUTHOR_INDEX:
            apply_author(r, profiles)
            c["author override"] += 1
        r["status"], r["origin"] = "ACTIVE", True
        r["note"] = f"activated {TODAY} ({decision})"
        activated.append(r)
        c["activated " + r["credit_type"]] += 1
    for k, v in sorted(c.items()):
        print(f"  {k}: {v}")
    print(f"  activated total: {len(activated)}")
    for title, items in (("no graded points (NORMAL 1-100)", no_points), ("ILLEGAL or no window", illegal),
                         ("EXCLUDED tutor", tutor)):
        print(f"  {title}: {len(items)}")
        for it in items[:60]:
            print("    ", it)


# --- Step 5: removals and the user's hand-picked sets ----------------------------------
HOPPIP_REPLACEMENTS = [
    # (species, old moves, new moves): the new set takes the old row's window and tier.
    ("HOPPIP", "SLEEP_POWDER REFLECT MEGA_DRAIN TOXIC", "SLEEP_POWDER LEECH_SEED MEGA_DRAIN REFLECT"),
    ("HOPPIP", "LEECH_SEED TOXIC REFLECT SLEEP_POWDER", "LEECH_SEED TOXIC SUBSTITUTE REFLECT"),
    ("SKIPLOOM", "LEECH_SEED TOXIC REFLECT SLEEP_POWDER", "LEECH_SEED TOXIC SUBSTITUTE MEGA_DRAIN"),
    ("JUMPLUFF", "LEECH_SEED TOXIC REFLECT SLEEP_POWDER", "LEECH_SEED TOXIC RECOVER SUBSTITUTE"),
    ("JUMPLUFF", "LEECH_SEED SLEEP_POWDER REFLECT STUN_SPORE", "SLEEP_POWDER LEECH_SEED MEGA_DRAIN SUBSTITUTE"),
]
# (species, moves, segments, why): new Red Rogue Original rows, approved 2026-10-27.
NEW_SETS = [
    ("JUMPLUFF", "RECOVER LEECH_SEED TOXIC MEGA_DRAIN", [(35, 100, "TIER_HARD")], "Hoppip rework: seed/Toxic + Recover + attack"),
    ("JUMPLUFF", "SLEEP_POWDER LEECH_SEED MEGA_DRAIN SOLARBEAM", [(45, 100, "TIER_NORMAL")], "Hoppip rework: attack"),
    ("GRAVELER", "ROCK_THROW DIG DEFENSE_CURL SELFDESTRUCT", [(25, 45, "TIER_NORMAL")], "hole fill (tutor Headbutt -> Selfdestruct)"),
    ("GROWLITHE", "EMBER LEER TAKE_DOWN BITE", [(30, 45, "TIER_NORMAL")], "hole fill (tutor Fire Spin -> Bite)"),
    ("ARCANINE", "EMBER LEER TAKE_DOWN BITE", [(30, 35, "TIER_NORMAL")], "hole fill (tutor Fire Spin -> Bite)"),
    ("DODRIO", "DRILL_PECK BODY_SLAM FURY_ATTACK RAGE", [(40, 55, "TIER_NORMAL")], "hole fill (tutor Swift -> Fury Attack)"),
    ("MACHOKE", "SEISMIC_TOSS SUBMISSION FOCUS_ENERGY LOW_KICK", [(25, 40, "TIER_NORMAL")], "hole fill (Meditate -> Low Kick)"),
    ("HITMONLEE", "ROLLING_KICK DOUBLE_KICK FOCUS_ENERGY MEDITATE", [(25, 100, "TIER_NORMAL")], "fighter fill for the revised Hitmon learnsets"),
    ("HITMONLEE", "JUMP_KICK ROLLING_KICK BODY_SLAM SEISMIC_TOSS", [(35, 100, "TIER_HARD")], "fighter fill for the revised Hitmon learnsets"),
    ("HITMONCHAN", "FIRE_PUNCH KARATE_CHOP BODY_SLAM AGILITY", [(25, 100, "TIER_NORMAL")], "fighter fill for the revised Hitmon learnsets"),
    ("HITMONCHAN", "ICE_PUNCH THUNDERPUNCH BODY_SLAM SEISMIC_TOSS", [(30, 100, "TIER_HARD")], "fighter fill for the revised Hitmon learnsets"),
]
ELITE_FILLS = [   # (species, moves): add TIER_ELITE to every segment
    ("ELECTIVIRE", "THUNDERBOLT THUNDER_WAVE EARTHQUAKE BODY_SLAM"),
    ("CLEFABLE", "BODY_SLAM BLIZZARD THUNDERBOLT THUNDER_WAVE"),
    ("HYPNO", "HYPNOSIS THUNDER_WAVE PSYCHIC_M SEISMIC_TOSS"),
]
ALOLAN_SANDSLASH = ("SANDSLASH_ALOLA", "SWORDS_DANCE BLIZZARD DEFENSE_CURL ICE_BEAM")


def find_active(rows, species, moves):
    ms = frozenset(moves.split())
    return [r for r in rows if r["status"] == "ACTIVE" and r["species"] == species and moveset(r) == ms]


def add_row(rows, species, moves, segments, why, species_ids):
    ms = moves.split()
    ident = species if species in species_ids else "%s#%d" % g.form_key(species)
    existing = [r for r in rows if r["species"] == species and moveset(r) == frozenset(ms)]
    if any(r["status"] == "ACTIVE" for r in existing):
        return "present"
    if existing:
        sys.exit(f"{species} {moves}: an inactive row already has this tuple ({existing[0]['id']}); decide by hand")
    row = {"id": new_id(ident, ms), "status": "ACTIVE", "kind": "species" if species in species_ids else "form",
           "species": species, "moves": ms, "segments": segments, "credit_type": "ORIGINAL", "creator": "",
           "set_name": g.FIXED_LABELS[g.LOSS_ORIGIN_ORIGINAL], "origin": True, "asm_comment": "",
           "note": f"added {TODAY}: {why}", "source": "Red Rogue original (user-approved 2026-10-27)",
           "source_creator": "", "heading": "", "packet_id": ""}
    assert all(r["id"] != row["id"] for r in rows), row["id"]
    rows.append(row)
    return "added"


def step5(rows):
    wl = worklist()
    species_ids = g.parse_species_constants(g.POKEMON_CONSTANTS)
    learnable = g.load_learnable()
    c = Counter()
    # 5.2 retirements first, so the note says why (before the tutor sweep reaches them)
    for r in rows:
        if r["status"] != "ACTIVE" or r["packet_id"] not in wl:
            continue
        d = wl[r["packet_id"]]["selection_disposition"]["decision"]
        if d.startswith("CARRY_FORWARD_EXISTING_RETIREMENT"):
            set_status(r, "ARCHIVED", f"retired {TODAY}: packet retirement/supersession proposal carried forward")
            c["retired (carry forward)"] += 1
        elif d.startswith("EXCLUDE_EXPLICITLY_REJECTED"):
            set_status(r, "REJECTED", f"rejected {TODAY}: user declined the tutor-dependent Chansey gimmick (R053)")
            c["rejected (Chansey)"] += 1
    for r in find_active(rows, *ALOLAN_SANDSLASH):
        set_status(r, "ARCHIVED", f"retired {TODAY}: Swords Dance with only special attacks; Blizzard/Defense Curl/Ice Beam/Slash covers it")
        c["retired (Alolan Sandslash)"] += 1
    # 5.1 tutor rule
    tutor_by_credit = Counter()
    for r in rows:
        if r["status"] != "ACTIVE":
            continue
        need = rules.tutor_only_moves(key_of(r), r["moves"])
        if need:
            set_status(r, "EXCLUDED", f"TUTOR: {', '.join(need)}")
            tutor_by_credit[r["credit_type"]] += 1
            c["excluded (tutor)"] += 1
    # 5.4 Hoppip replacements
    for species, old, new in HOPPIP_REPLACEMENTS:
        olds = find_active(rows, species, old)
        if not olds:
            if any(r["species"] == species and moveset(r) == frozenset(new.split()) and r["status"] == "ACTIVE" for r in rows):
                continue                      # already done
            sys.exit(f"Hoppip rework: no ACTIVE {species} {old}")
        segs = olds[0]["segments"]
        for r in olds:
            set_status(r, "ARCHIVED", f"replaced {TODAY} (Hoppip rework)")
        c["hoppip archived"] += len(olds)
        if add_row(rows, species, new, list(segs), "Hoppip rework", species_ids) == "added":
            c["hoppip added"] += 1
    # 5.5 elite fills (skip a segment that already has TIER_ELITE)
    for species, moves in ELITE_FILLS:
        for r in find_active(rows, species, moves):
            new = []
            for lo, hi, tier in r["segments"]:
                if "TIER_ELITE" not in tier:
                    tier = rules.join_mask(rules._tokens(tier) | {"TIER_ELITE"})
                new.append((lo, hi, tier))
            if species == "ELECTIVIRE":
                new = [(35, 100, "TIER_HARD | TIER_ELITE")]
            if new != r["segments"]:
                r["segments"] = new
                append_note(r, f"hole fill {TODAY}: Hard+Elite")
                c["elite fill"] += 1
    # 5.5 / 5.6 new sets
    for species, moves, segs, why in NEW_SETS:
        key = g.form_key(species) if species not in species_ids else species
        if add_row(rows, species, moves, list(segs), why, species_ids) == "added":
            c["new set"] += 1
    for k, v in sorted(c.items()):
        print(f"  {k}: {v}")
    print("  tutor exclusions by credit:", dict(tutor_by_credit))


# --- Step 6: the user's answers to the Step 6 coverage report (2026-10-27) ---------------
# Each excluded/retired set comes back with its one bad move swapped, same window and tier;
# the originals stay EXCLUDED/ARCHIVED. Jynx: the user's Lovely Kiss -> Sing learnset edit
# leaves 25-34 empty, so credited and rental sets are left alone and Sing variants are added.
HOLE_SWAPS = [  # (excluded row id, species, new moves)
    ("RRSET-686dba59b7fd783d", "KADABRA", "CONFUSION DISABLE PSYBEAM REFLECT"),
    ("RRSET-aefd7a2354fde2f9", "SHELLDER", "AURORA_BEAM BUBBLEBEAM SUPERSONIC WITHDRAW"),
    ("RRSET-45fb6e8eb7feac1f", "LAPRAS", "MIST AURORA_BEAM BODY_SLAM WATER_GUN"),
    ("RRSET-145d0917c9a227c6", "MR_MIME", "CONFUSION LIGHT_SCREEN REFLECT SUBSTITUTE"),
    ("RRSET-ae32874d1a714c1b", "DONPHAN", "EARTHQUAKE ROCK_SLIDE BODY_SLAM SUBSTITUTE"),  # Hyper Beam would duplicate an ACTIVE set
]
JYNX_VARIANTS = [
    ("PSYCHIC_M SING ICE_BEAM COUNTER", [(25, 34, "TIER_NORMAL | TIER_ELITE")], "Sing variant of GEPH 2007's Counter Lead (Lovely Kiss is level 35)"),
    ("SING BLIZZARD MEGA_PUNCH REFLECT", [(25, 34, "TIER_HARD")], "Sing variant of the Nintendo Cup '98 rental (Lovely Kiss is level 35)"),
]


def step6(rows):
    species_ids = g.parse_species_constants(g.POKEMON_CONSTANTS)
    by_id = {r["id"]: r for r in rows}
    c = Counter()
    for rid, species, moves in HOLE_SWAPS:
        old = by_id[rid]
        assert old["species"] == species, rid
        if add_row(rows, species, moves, list(old["segments"]), f"hole fill: {rid} with its tutor/retired move swapped", species_ids) == "added":
            c["swapped set"] += 1
    for moves, segs, why in JYNX_VARIANTS:
        if add_row(rows, "JYNX", moves, segs, why, species_ids) == "added":
            c["jynx variant"] += 1
    for k, v in sorted(c.items()):
        print(f"  {k}: {v}")


STEPS = {1: step1, 2: step2, 3: step3, 5: step5, 6: step6}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--step", type=int, required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    rows = g.read_catalog()
    before = open(g.CATALOG, encoding="utf-8").read()
    print(f"step {args.step}:")
    STEPS[args.step](rows)
    if args.dry_run:
        print("dry run: catalog not written")
        return
    tmp = g.CATALOG + ".new"
    g.write_catalog(rows, tmp)
    after = open(tmp, encoding="utf-8").read()
    os.remove(tmp)
    if after == before:
        print("catalog unchanged")
    else:
        g.write_catalog(rows)
        print(f"catalog written ({len(rows)} rows)")


if __name__ == "__main__":
    main()
