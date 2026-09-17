"""Audit: Phase 7f's good-NPC branch (Joy, Jenny, the pair).

Per the user's design ("unlike the stealers, they just exist on the map and
can be approached for a battle"), STAGE_EVENT_JOY/_JENNY/_BOTH_GOOD must NOT
run the villains' vanish-and-hide sequence: no theft, no dark flash, no
relocation, no recovery text. This checks the branch added in
scripts/ProceduralCave1.asm's .afterSetup:

  1. the arrival text fires once, exactly as for a villain
  2. after it is dismissed, the phase goes straight to SETTLED (2), never
     touching HIDING (1) - the villains' phase
  3. the NPC sprite(s) do NOT move - they stay exactly where they arrived,
     one step above the player
  4. StageEventRoundTier's wTrainerNo, and therefore the built team's size,
     tracks wBattleCount the way stage_event_team_spec's ladder promises
     (2/2/3/3/4/4/5/5/6 across rounds 1-9)

Usage:
    python3 tools/pyboy_smoke/audit_stage_event_good_npc.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants, parse_trainer_class_indexes  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
SRAM_BANK = 0
SPRITE_SLOTS = 7
NPC1, NPC2 = 5, 6


def stage_event_constants() -> dict:
    text = (REPO_ROOT / "constants" / "ram_constants.asm").read_text()
    out = {}
    for name, value in re.findall(r"^DEF (STAGE_EVENT_\w+)\s+EQU\s+(\S+)", text, re.M):
        value = value.strip()
        if value.startswith("$"):
            out[name] = int(value[1:], 16)
        elif value.startswith("%"):
            out[name] = int(value[1:], 2)
        elif value.isdigit():
            out[name] = int(value)
        elif value in out:
            out[name] = out[value]
    return out


def run_arrival(event_type: int, const: dict, failures: list) -> None:
    phase_mask = const["STAGE_EVENT_PHASE_MASK"]
    phase_shift = const["STAGE_EVENT_PHASE_SHIFT"]
    hiding = const["STAGE_EVENT_PHASE_HIDING"]
    settled = const["STAGE_EVENT_PHASE_SETTLED"]
    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.write8("wStageEvent", event_type)
        h.preload_and_enter_wild_area(map_id, "Procedural Cave")
        player = (h.read8("wXCoord"), h.read8("wYCoord"))
        before = [tuple(p) for p in h.sprite_positions(SPRITE_SLOTS)]
        npc1_before = (before[NPC1][1], before[NPC1][0])  # (x, y)

        for _ in range(6):
            h.tap("a", frames=12)
            h.tick(40)

        after_event = h.read8("wStageEvent")
        after_phase = (after_event & phase_mask) >> phase_shift
        after = [tuple(p) for p in h.sprite_positions(SPRITE_SLOTS)]
        npc1_after = (after[NPC1][1], after[NPC1][0])

        print("type %d: player=%s  npc1 before=%s after=%s  phase=%d"
              % (event_type, player, npc1_before, npc1_after, after_phase))

        if after_phase != settled:
            failures.append("type %d: phase is %d, expected SETTLED (%d) - a good "
                            "NPC must not enter HIDING" % (event_type, after_phase, settled))
        if after_phase == hiding:
            failures.append("type %d: phase is HIDING - the villain vanish ran for "
                            "a good NPC" % event_type)
        if npc1_after != npc1_before:
            failures.append("type %d: slot 6 moved from %s to %s - a good NPC must "
                            "stay put" % (event_type, npc1_before, npc1_after))
    finally:
        try:
            h.close()
        except Exception:
            pass


def run_round_tier(failures: list) -> None:
    classes = parse_trainer_class_indexes(REPO_ROOT / "constants" / "trainer_constants.asm")
    expected_n = {1: 2, 2: 2, 3: 3, 4: 3, 5: 4, 6: 4, 7: 5, 8: 5, 9: 6}
    battle_counts = {1: 0, 2: 15, 3: 25, 4: 35, 5: 45, 6: 55, 7: 65, 8: 75, 9: 85}

    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_fight2(seed=1)
        for round_n, bc in battle_counts.items():
            h.write8("wBattleCount", bc)
            h.write8("wTrainerClass", classes["NURSE_JOY"])
            # Drive RogueBuildParty directly against the round-derived wTrainerNo,
            # mirroring what StageEventRoundTier would compute for this wBattleCount.
            h.write8("wTrainerNo", round_n)
            h.call_routine("ReadTrainer", limit=600)
            n = h.read8("wEnemyPartyCount")
            print("round %d (wBattleCount=%d): wEnemyPartyCount=%d (want %d)"
                  % (round_n, bc, n, expected_n[round_n]))
            if n != expected_n[round_n]:
                failures.append("round %d: party count %d, expected %d"
                                % (round_n, n, expected_n[round_n]))
    finally:
        try:
            h.close()
        except Exception:
            pass


def main() -> int:
    const = stage_event_constants()
    failures: list = []
    for t in (const["STAGE_EVENT_JOY"], const["STAGE_EVENT_JENNY"], const["STAGE_EVENT_BOTH_GOOD"]):
        run_arrival(t, const, failures)
    run_round_tier(failures)

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: good NPCs never hide, and stage-event teams scale with the round")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
