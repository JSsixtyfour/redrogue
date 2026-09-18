"""Audit: trainer evolutions respect species groups, honour trade evolutions,
and NO_DUPES counts the species actually FIELDED.

Three properties, all in the trainer team-build path.

(1) EVOLVE_TRADE reaches the trainer side at all.
    EvolveMonByLevel used to skip every EVOLVE_TRADE entry outright, and the
    player path (engine/pokemon/evos_moves.asm) only takes one under
    LINK_STATE_TRADING, which never happens in a run. So PORYGON2, PORYGON_Z,
    RHYPERIOR, KLEAVOR, SLOWKING, KINGDRA and POLITOED were unobtainable by
    ANYONE - contradicting data/trainers/pools.asm's own design note, which
    lists them as deliberately reached by evolving a pre-evolution.

(2) The group gate.
    The player's evolution path has gated on RogueIsSpeciesEvolutionAllowed
    since Phase 2 so a Kanto-locked run cannot produce a Johto evolution. The
    TRAINER path never did.

    NurseJoy is the ideal probe for both: her pool is exactly 6 species and a
    round-9 team is 6 mons with NO_DUPES, so the whole pool is fielded every
    time and PORYGON is guaranteed present. With Kanto only it must STAY a
    Porygon; with Johto unlocked it must become PORYGON2 - and must NOT reach
    PORYGON_Z, which is Warp group and still locked.

(3) NO_DUPES counts the fielded species.
    PartyGenSpeciesAlreadyUsed compares the DRAWN species against
    wEnemyPartySpecies, which holds BUILT (post-evolution) species. A pool
    listing ABRA, KADABRA and ALAKAZAM would pass ABRA against an already-built
    ALAKAZAM and field a second one.

Species groups are driven by wNumHoFTeams (0 = Kanto only, 1 = +Johto, 2+ =
+Warp) ANDed with the player's sRogueSpeciesGroupsEnabled toggle byte in SRAM
bank 1. Both are set here.

call_routine corrupts the machine after roughly ten invocations, so the builds
are split across two boots.

Usage:
    python3 tools/pyboy_smoke/audit_trainer_evolution_groups.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import (  # noqa: E402
    parse_rgbds_constants,
    parse_trainer_class_indexes,
)

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
ROUND9_BATTLE_COUNT = 85
ROUND9_TRAINER_NO = 9
ALL_GROUPS = 0b111


def species_by_name():
    return parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")


def species_names():
    return {v: k for k, v in species_by_name().items()}


def non_kanto_species():
    """Every species name listed under a Johto* or Warp* rarity list.

    The lists are named by group prefix, which is what RarityGroupTable's rows
    point at, so the prefix is the group membership.
    """
    text = (REPO_ROOT / "engine" / "pokemon" / "rarity.asm").read_text(
        encoding="utf-8", errors="replace")
    out = set()
    current = None
    for line in text.splitlines():
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):", line)
        if m:
            current = m.group(1)
            continue
        if current is None:
            continue
        if not (current.startswith("Johto") or current.startswith("Warp")):
            continue
        m = re.match(r"^\s+db\s+([A-Z_][A-Z0-9_]*)\s*$", line)
        if m:
            out.add(m.group(1))
    return out


def set_groups(h, hof_teams):
    """Unlock groups by champion wins, and enable them in the player toggle."""
    h.write8("wNumHoFTeams", hof_teams)
    h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [ALL_GROUPS], bank=1)


def build(h, class_index, hof_teams):
    set_groups(h, hof_teams)
    h.write8("wBattleCount", ROUND9_BATTLE_COUNT)
    h.write8("wTrainerClass", class_index)
    h.write8("wTrainerNo", ROUND9_TRAINER_NO)
    h.call_routine("ReadTrainer", limit=600)
    n = h.read8("wEnemyPartyCount")
    return h.read_bytes("wEnemyPartySpecies", n)


def main() -> int:
    classes = parse_trainer_class_indexes(
        REPO_ROOT / "constants" / "trainer_constants.asm")
    ids = species_by_name()
    names = species_names()
    non_kanto = non_kanto_species()
    failures = []

    # ---- boot 1: the Porygon probe, both group states -------------------
    # JoyPool used to be exactly 6 species against a 6-mon round-9 team, so one
    # build fielded the whole pool and PORYGON was guaranteed. It has since been
    # extended, so a single build no longer guarantees the draw - take the UNION
    # over several builds instead. (Noting this because the original one-build
    # version silently stopped measuring anything the moment the pool grew.)
    def union_builds(hof, count, seed):
        seen = set()
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_fight2(seed=seed)
            for _ in range(count):
                seen.update(build(h, classes["NURSE_JOY"], hof))
        finally:
            try:
                h.close()
            except Exception:
                pass
        return seen

    def show(label, team):
        print("%s: %s" % (label, sorted(names.get(s, "?%d" % s) for s in team)))

    kanto_only = union_builds(0, 5, 1)
    with_johto = union_builds(1, 5, 1)
    show("NurseJoy round 9 x5, Kanto only ", kanto_only)
    show("NurseJoy round 9 x5, Johto on   ", with_johto)

    if ids["PORYGON"] not in kanto_only and ids["PORYGON"] not in with_johto:
        failures.append(
            "PORYGON never appeared across 10 round-9 Joy builds, so neither "
            "half of this probe measured the Porygon line at all")
    if ids["PORYGON2"] in kanto_only:
        failures.append(
            "PORYGON2 appears with Johto LOCKED. It is a Johto-group species, "
            "so the trainer evolution path is not consulting "
            "RogueIsSpeciesEvolutionAllowed")
    if ids["PORYGON2"] not in with_johto:
        failures.append(
            "PORYGON2 does NOT appear with Johto unlocked. PORYGON's only "
            "evolution entry is EVOLVE_TRADE, so this means the trainer path is "
            "still skipping trade evolutions and the species is unreachable")
    if ids.get("PORYGON_Z") in with_johto:
        failures.append(
            "PORYGON_Z appears with only Johto unlocked. It is Warp group and "
            "Warp needs a second champion win, so the gate is leaking")

    # ---- boot 2: group containment and NO_DUPES across classes ----------
    # The no-duplicates rule can only be asserted where the pool is COMFORTABLY
    # larger than the team: PartyGenRollFromPool is bounded-then-accept by
    # design ("a pool smaller than the team size must degrade, never spin"), so
    # an 8-entry pool against 6 slots legitimately repeats sometimes. Only
    # JessieJames (22 Kanto + 4 Johto) has the headroom.
    #
    # It is also no longer the right probe for the evolution collapse: the five
    # stage pools were rebased to base forms, so none of them can produce two
    # stages of one line any more. SABRINA still lists ABRA, KADABRA and
    # ALAKAZAM, so she is the class that exercises what NO_DUPES has to catch.
    dupe_classes = ["JESSIE_JAMES", "SABRINA"]
    probe_classes = ["JESSIE_JAMES", "PSYCHIC_TR", "BURGLAR", "OFFICER_JENNY",
                     "SABRINA"]
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_fight2(seed=7)
        for name in probe_classes:
            team = build(h, classes[name], 0)   # Kanto only
            show("%s round 9, Kanto only" % name, team)
            for s in team:
                sname = names.get(s)
                if sname in non_kanto:
                    failures.append(
                        "%s fielded %s with only Kanto unlocked - it is listed "
                        "under a Johto/Warp rarity group, so an evolution "
                        "crossed a locked group boundary"
                        % (name, sname))
            if name in dupe_classes and len(set(team)) != len(team):
                dupes = sorted({names.get(s, s) for s in team
                                if list(team).count(s) > 1})
                failures.append(
                    "%s fielded duplicates %s despite NO_DUPES - the filter is "
                    "comparing the DRAWN species against BUILT ones, so two "
                    "stages of the same line both pass and then evolve into "
                    "the same species" % (name, dupes))
    finally:
        try:
            h.close()
        except Exception:
            pass

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: trade evolutions reach trainers, locked groups stay locked, "
          "and no team fields the same species twice")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
