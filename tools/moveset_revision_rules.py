#!/usr/bin/env python3
"""The fixed rules for Moveset revision Phase 3 (MOVESET_REVISION_IMPLEMENTATION_PLAN.md),
as functions, so applying them to catalog rows is transcription, not judgement.
Every rule cites the user decision it implements (MOVESET_REVISION_DECISIONS_2026-10-27.md).

    python tools/moveset_revision_rules.py     # self-test, prints worked examples
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

STRENGTH = ["TIER_BAD", "TIER_EASY", "TIER_NORMAL", "TIER_HARD", "TIER_ELITE"]
GRADE = {g[5:]: g for g in STRENGTH}               # "HARD" -> "TIER_HARD"


def _tokens(expr):
    return {t.strip() for t in str(expr).split("|") if t.strip() and t.strip() != "0"}


def join_mask(tokens):
    """Non-strength bits first, then strength low to high: 'TIER_GAMBLER | TIER_HARD'."""
    special = sorted(t for t in tokens if t not in STRENGTH)
    return " | ".join(special + [t for t in STRENGTH if t in tokens])


def regrade(old_expr, new_expr):
    """Decision 'middle' (2026-10-27): a promotion ADDS the packet's strength bit to
    the set's old ones (Hard -> Hard+Elite); a demotion REPLACES them (Hard -> Normal).
    Non-strength bits (Gambler, Legendary Boss, Signature) are always kept."""
    old, new = _tokens(old_expr), _tokens(new_expr)
    old_s, new_s = old & set(STRENGTH), new & set(STRENGTH)
    top = lambda s: max((STRENGTH.index(t) for t in s), default=-1)
    strength = old_s | new_s if top(new_s) > top(old_s) else new_s
    return join_mask((old - set(STRENGTH)) | strength)


def point_segments(points, floor=1):
    """Approved tier rule (2026-10-27) for a set graded only at points, e.g. AIPOM
    HARD@5, NORMAL@15/30/50: each grade covers its level up to the next point's
    level - 1, the first starts at `floor`, the last ends at 100 (ceiling 100: user,
    'floor, no ceiling'), adjacent equal grades merge. Returns [(lo, hi, TIER_X)].
    The generator's level bump still raises the first lo to the move floor."""
    pts = sorted((p["evaluation_level"], GRADE[p["provisional_tier"]]) for p in points)
    if not pts:
        return [(floor, 100, "TIER_NORMAL")]
    segs = []
    for i, (lvl, tier) in enumerate(pts):
        lo = floor if i == 0 else max(floor, lvl)
        hi = pts[i + 1][0] - 1 if i + 1 < len(pts) else 100
        if hi < lo:
            continue
        if segs and segs[-1][2] == tier:
            segs[-1] = (segs[-1][0], hi, tier)
        else:
            segs.append((lo, hi, tier))
    return segs


# --- Smogon labels: decision 2026-10-27 option 2 (option 1 is the fallback) ---------
# A Smogon-credited set (no individual credited) prints "by Smogon's / <name>".
# <name> is its ROLE for the 25 commonest roles, its FORMAT otherwise; "Standard" keeps
# the format ("OU Standard"). Sized so the loss-label table stays near 233 of 255 ids.
# Fallback (option 1) if the generator's 255 assert ever fires: SMOGON_ROLES = set().
SMOGON_CREATOR = "Smogon"
SMOGON_ROLES = {
    "Mixed Attacker", "Swords Dance", "Offensive", "Standard", "Support", "Special Attacker",
    "Bulky Attacker", "Amnesia", "Sleeper", "Double Powder", "Agility Sweeper", "Explosion",
    "Physical Attacker", "Agility", "Wallbreaker", "Wrap", "Reflect + Rest", "Counter",
    "Reflect", "Status Spreader", "All-Out Attacker", "Defensive", "Slash", "Substitute",
    "Double Team + Rest",
}
FORMATS = ["LC Level 100", "Tradebacks OU", "Stadium OU", "Pika Cup", "Petit Cup", "Middle Cup",
           "1v1", "LC", "OU", "UU", "NU", "PU", "ZU", "Ubers", "NC1997", "NC1999", "Monotype"]
FORMAT_RE = re.compile(r"^(%s)\b\s*" % "|".join(re.escape(f) for f in FORMATS))
# data.pkmn.cc format ids (the packet's community_sets_with_priority associations).
PKMN_FORMAT = {"petitcup": "Petit Cup", "pikacup": "Pika Cup", "stadiumou": "Stadium OU",
               "lclevel100": "LC Level 100", "nc1997": "NC1997", "nc1999": "NC1999",
               "monotype": "Monotype", "ou": "OU", "middlecup": "Middle Cup"}


def smogon_set_name(set_name=None, pkmn_format=None, role=None):
    """Label name for a Smogon set. Give either the packet's standard set_name
    ('OU Swords Dance') or a community set's pkmn_format + role."""
    if set_name is not None:
        m = FORMAT_RE.match(set_name)
        fmt, role = (m.group(1), set_name[m.end():]) if m else ("OU", set_name)
    else:
        fmt = PKMN_FORMAT.get(pkmn_format, pkmn_format)
    role = (role or "").strip()
    if role == "Standard":
        return f"{fmt} Standard set"
    if role in SMOGON_ROLES:
        return f"{role} set"
    return f"{fmt} set"


# --- Stadium labels -----------------------------------------------------------------
# A membership's label comes from its FIRST source occurrence's cup, worded like the
# labels already in the game. STADIUM_LABEL_MERGES folds today's inconsistent variants
# into one wording each (same credit, fewer label ids).
STADIUM_CUP_LABEL = {
    "PRIME_ALT": "a Prime Cup Rental", "POKE_INTL": "a Poké Cup Rental",
    "GYM_INTL_ALT": "a Gym Leader Castle Rental", "GYM_JP": "a Gym Leader Castle Rental",
    "PIKA_INTL": "a Pika Cup Rental", "PIKA_JP": "a Japanese Pokémon Stadium Pika Cup Rental",
    "PETIT_INTL": "a Petit Cup Rental", "PETIT_JP": "a Japanese Petit Cup Rental",
    "NC97": "a Nintendo Cup '97 Rental", "NC98": "a Nintendo Cup '98 Rental",
    "NC99": "a Nintendo Cup '99 Rental",
    "STADIUM0_FREE_BATTLE": "a Japanese Pokémon Stadium Rental",
    "STADIUM0_LEVEL30": "a Japanese Pokémon Stadium Rental",
    "STADIUM0_LEVEL55": "a Japanese Pokémon Stadium Rental",
    "BATTLE_NOW_PRESET": "a Stadium Battle Now Rental",
}
STADIUM_LABEL_MERGES = {
    "a Nintendo Cup 1997 Rental": "a Nintendo Cup '97 Rental",
    "a Nintendo Cup 1999 Rental": "a Nintendo Cup '99 Rental",
    "a NC 97 Rental - Fast OHKO": "a Nintendo Cup '97 Rental",
    "a Nintendo Cup 1997 Swords Dance": "a Nintendo Cup '97 Rental",
}
STADIUM_LABEL_PREFIX_MERGES = {"a Poké Cup Rental - ": "a Poké Cup Rental"}


def stadium_set_name(current=None, cup=None):
    if cup is not None:
        return STADIUM_CUP_LABEL[cup]
    for prefix, to in STADIUM_LABEL_PREFIX_MERGES.items():
        if current.startswith(prefix):
            return to
    return STADIUM_LABEL_MERGES.get(current, current)


# --- Tutor rule (user decision 2026-10-27) --------------------------------------------
_LEARN = {}


def _learnsets():
    if not _LEARN:
        import learnset_legality as ll
        _LEARN["full"] = ll.load()
        real = ll._records
        ll._records = lambda p, s: {k: (e, lv, set(), raw) for k, (e, lv, _t, raw) in real(p, s).items()}
        try:
            _LEARN["no_tutor"] = ll.load()
        finally:
            ll._records = real
    return _LEARN["full"], _LEARN["no_tutor"]


def tutor_only_moves(key, moves):
    """Moves of `moves` that `key` (species, or (base, form)) can get only from a tutor.
    A row with any is EXCLUDED, note 'TUTOR: <moves>'."""
    full, no_tutor = _learnsets()
    return [m for m in moves if m != "NO_MOVE" and m in full.get(key, {}) and m not in no_tutor.get(key, {})]


def _selftest():
    assert regrade("TIER_HARD", "TIER_ELITE") == "TIER_HARD | TIER_ELITE"
    assert regrade("TIER_HARD", "TIER_NORMAL") == "TIER_NORMAL"
    assert regrade("TIER_GAMBLER | TIER_HARD", "TIER_ELITE") == "TIER_GAMBLER | TIER_HARD | TIER_ELITE"
    assert regrade("TIER_NORMAL", "TIER_NORMAL") == "TIER_NORMAL"
    aipom = [{"evaluation_level": 5, "provisional_tier": "HARD"},
             {"evaluation_level": 15, "provisional_tier": "NORMAL"},
             {"evaluation_level": 30, "provisional_tier": "NORMAL"},
             {"evaluation_level": 50, "provisional_tier": "NORMAL"}]
    assert point_segments(aipom) == [(1, 14, "TIER_HARD"), (15, 100, "TIER_NORMAL")], point_segments(aipom)
    assert point_segments(aipom, floor=20) == [(20, 100, "TIER_NORMAL")], point_segments(aipom, 20)
    assert smogon_set_name("OU Swords Dance") == "Swords Dance set"
    assert smogon_set_name("OU Standard") == "OU Standard set"
    assert smogon_set_name("ZU Showdown Usage") == "ZU set"
    assert smogon_set_name(pkmn_format="petitcup", role="Revenge Killer") == "Petit Cup set"
    assert stadium_set_name("a Poké Cup Rental - Sleeper") == "a Poké Cup Rental"
    assert stadium_set_name(cup="NC98") == "a Nintendo Cup '98 Rental"
    import gen_movesets as g
    for name in [smogon_set_name(f"{f} {r}") for f in FORMATS for r in SMOGON_ROLES | {"x"}]:
        g.display_text((SMOGON_CREATOR, name))        # every Smogon label fits the box
    for name in set(STADIUM_CUP_LABEL.values()):
        g.display_text(("", name))
    print("moveset_revision_rules self-test OK")
    print("  regrade Hard->Elite:", regrade("TIER_HARD", "TIER_ELITE"),
          "| AIPOM:", point_segments(aipom), "| 'OU Swords Dance' ->", smogon_set_name("OU Swords Dance"))


if __name__ == "__main__":
    _selftest()
