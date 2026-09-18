"""Audit: stage-event pools list base forms, so round 1 has no final evolutions.

The reported symptom was a level-5 ARCANINE on Officer Jenny and a level-5
EXEGGUTOR + STARMIE on Nurse Joy. Cause: the five stage-event pools listed
fully-evolved species (and in three cases listed BOTH a base and its evolution,
which also wasted pool slots and defeated NO_DUPES).

The fix is the convention data/trainers/pools.asm already documents for its
other 18 pools: list the lowest stage of each line and let
ScaleTrainer_evolution promote it. This audit holds that line.

  round 1 (wBattleCount 5, 2 mons at levels 5-6, Kanto only)
      no team member may be a species that has a pre-evolution
  round 9 (wBattleCount 85, 6 mons at levels 52-57, all groups)
      evolved forms MUST appear, or the pools have simply been weakened
      rather than rebased - this half is the negative control for the first

"Has a pre-evolution" is derived from data/pokemon/evos_moves.asm by collecting
every species that appears as an evolution TARGET, so it cannot drift from the
data.

Known and deliberate exception: JoyPool's Time Warp run pins VAPOREON form 2
(Sylveon), which is an evolved species - Sylveon has no pre-evolution that
reaches it. Round 1 is therefore run with Kanto only, where that run is not
eligible.

call_routine corrupts the machine after roughly ten invocations, so the two
rounds are split across two boots.

Usage:
    python3 tools/pyboy_smoke/audit_stage_pool_base_forms.py
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
STAGE_CLASSES = ["JESSIE_JAMES", "PSYCHIC_TR", "BURGLAR", "NURSE_JOY", "OFFICER_JENNY"]
ALL_GROUPS = 0b111


def evolution_targets():
    """Every species that something else evolves INTO."""
    text = (REPO_ROOT / "data" / "pokemon" / "evos_moves.asm").read_text(
        encoding="utf-8", errors="replace")
    out = set()
    for line in text.splitlines():
        m = re.match(r"^\s+db\s+EVOLVE_(LEVEL|TRADE),\s*[^,]+,\s*([A-Z_][A-Z0-9_]*)", line)
        if m:
            out.add(m.group(2))
            continue
        m = re.match(r"^\s+db\s+EVOLVE_ITEM,\s*[^,]+,\s*[^,]+,\s*([A-Z_][A-Z0-9_]*)", line)
        if m:
            out.add(m.group(1))
    return out


def build(h, class_index, battle_count, trainer_no, hof_teams):
    h.write8("wNumHoFTeams", hof_teams)
    h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [ALL_GROUPS], bank=1)
    h.write8("wBattleCount", battle_count)
    h.write8("wTrainerClass", class_index)
    h.write8("wTrainerNo", trainer_no)
    h.call_routine("ReadTrainer", limit=600)
    n = h.read8("wEnemyPartyCount")
    return h.read_bytes("wEnemyPartySpecies", n)


def main() -> int:
    classes = parse_trainer_class_indexes(
        REPO_ROOT / "constants" / "trainer_constants.asm")
    names = {v: k for k, v in
             parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm").items()}
    evolved = evolution_targets()
    failures = []

    print("ROUND 1 (levels 5-6, Kanto only) - nothing may be a final evolution")
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_fight2(seed=3)
        for name in STAGE_CLASSES:
            team = build(h, classes[name], 5, 1, 0)
            shown = [names.get(s, "?%d" % s) for s in team]
            bad = [n for n in shown if n in evolved]
            print("  %-14s %s%s" % (name, shown, "   <-- %s" % bad if bad else ""))
            if bad:
                failures.append(
                    "%s fields %s at level 5-6. Those species have a "
                    "pre-evolution, so the pool is still listing an evolved "
                    "form where it should list the base and let "
                    "ScaleTrainer_evolution promote it." % (name, bad))
    finally:
        try:
            h.close()
        except Exception:
            pass

    print()
    print("ROUND 9 (levels 52-57, all groups) - evolved forms MUST come back")
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_fight2(seed=3)
        for name in STAGE_CLASSES:
            team = build(h, classes[name], 85, 9, 2)
            shown = [names.get(s, "?%d" % s) for s in team]
            n_evolved = sum(1 for n in shown if n in evolved)
            print("  %-14s %s   (%d evolved)" % (name, shown, n_evolved))
            if n_evolved == 0:
                failures.append(
                    "%s fields NO evolved species at level 52-57. Rebasing the "
                    "pool to base forms is only correct because the evolution "
                    "scaler puts them back - if it does not, the pool has just "
                    "been made weaker." % name)
    finally:
        try:
            h.close()
        except Exception:
            pass

    # ---- Sylveon: the one pinned form, and the one thing gating it ------
    # JoyPool's _Warp run holds `pool_mon VAPOREON, 2`. A pinned form index is
    # passed through UNGATED by PartyGenResolveForm, so the run sublist is the
    # ONLY thing keeping Sylveon out of a Kanto game. If someone later "tidies"
    # that entry into the Kanto run to match VAPOREON's own rarity group, this
    # is what catches it.
    print()
    print("SYLVEON (VAPOREON form 2) - must be Warp-run only")
    vaporeon = parse_rgbds_constants(
        REPO_ROOT / "constants" / "pokemon_constants.asm")["VAPOREON"]
    for label, hof, want_possible in (("Kanto only", 0, False),
                                      ("Warp unlocked", 2, True)):
        drawn = 0
        as_sylveon = 0
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_fight2(seed=11)
            for _ in range(4):
                team = build(h, classes["NURSE_JOY"], 85, 9, hof)
                base = h.address("wEnemyMon1")
                stride = h.address("wEnemyMon2") - base
                cr_off = h.address("wEnemyMon1CatchRate") - base
                for i, s in enumerate(team):
                    if s != vaporeon:
                        continue
                    drawn += 1
                    form = (h.pyboy.memory[base + i * stride + cr_off] >> 5) & 0x03
                    if form == 2:
                        as_sylveon += 1
        finally:
            try:
                h.close()
            except Exception:
                pass
        print("  %-14s vaporeon drawn %d, of which Sylveon %d"
              % (label, drawn, as_sylveon))
        if not want_possible and drawn:
            failures.append(
                "Joy fielded VAPOREON %d times with Time Warp LOCKED. Sylveon "
                "is Warp content and a pinned form is ungated, so the _Warp "
                "run sublist is the only gate - that entry must not move into "
                "the Kanto run." % drawn)
        if want_possible and drawn and as_sylveon != drawn:
            failures.append(
                "Joy fielded %d VAPOREON but only %d carried form 2 - the pin "
                "is not landing, so she is getting plain Vaporeon instead of "
                "Sylveon" % (drawn, as_sylveon))
        if want_possible and drawn == 0:
            failures.append(
                "Joy never drew VAPOREON across 4 round-9 builds with Warp "
                "unlocked - the _Warp run is not being reached at all, so the "
                "Kanto-only half of this check proves nothing")

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: round-1 stage teams are all base forms, round-9 teams evolve "
          "back, and Sylveon is Warp-only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
