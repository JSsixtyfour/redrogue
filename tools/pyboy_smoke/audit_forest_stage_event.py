"""Audit: the Phase 7 rollout of stage events onto the Forest.

Mirrors audit_cave_stage_event.py and audit_stage_event_good_npc.py, but
drives the forest's own routines (PFPickForestHideout via PFScanForBall,
PFPlaceStageEventNpcs/PFPlaceStageEventArrival, PFStageEventVanish,
PFApplyStageEventTrainers) instead of the cave's. The forest's own risk: the
hideout is picked from a candidate list that a later step in the SAME
function (PFScanForBall's ball-XY copy) partially overwrites, so a wrong
insertion point would either read garbage or silently disarm the hideout.

Checks, forced type 1 (Jessie & James, a villain pair):
  1. sStageEventHideoutX/Y != STAGE_EVENT_NO_HIDEOUT (a real cell was found)
  2. arrival: NPC pair stands one step above the player, in front of them
  3. dismiss -> dark flash -> phase HIDING, NPCs relocated to the hideout
  4. the team-building/trainer-slot plumbing (StageEventApplyTrainers with
     d=6) actually wrote a class into wMapSpriteExtraData slot 6/7

Then, forced type 4 (Nurse Joy, a good NPC), over the same map:
  5. after dismissing the arrival text, phase is SETTLED (not HIDING), and
     the NPC's position is unchanged (no vanish)

Usage:
    python3 tools/pyboy_smoke/audit_forest_stage_event.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
SRAM_BANK = 0
SPRITE_SLOTS = 7
NPC1, NPC2 = 5, 6  # 0-based indices of object slots 6 and 7


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


def main() -> int:
    const = stage_event_constants()
    phase_mask = const["STAGE_EVENT_PHASE_MASK"]
    phase_shift = const["STAGE_EVENT_PHASE_SHIFT"]
    hiding = const["STAGE_EVENT_PHASE_HIDING"]
    settled = const["STAGE_EVENT_PHASE_SETTLED"]
    no_hideout = const["STAGE_EVENT_NO_HIDEOUT"]

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_FOREST"]
    failures = []

    # --- villain pair: hideout, arrival, vanish, trainer slots -------------
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.write8("wStageEvent", const["STAGE_EVENT_JESSIE_JAMES"])
        h.preload_and_enter_wild_area(map_id, "Procedural Forest")

        player = (h.read8("wXCoord"), h.read8("wYCoord"))
        hx = h.read_sram_bytes("sStageEventHideoutX", 1, bank=SRAM_BANK)[0]
        hy = h.read_sram_bytes("sStageEventHideoutY", 1, bank=SRAM_BANK)[0]
        print("player step (x,y) = %s" % (player,))
        print("hideout block = (%d,%d)" % (hx, hy))
        if hx == no_hideout:
            failures.append("hideout disarmed (STAGE_EVENT_NO_HIDEOUT) on a normal "
                            "forest - PFPickForestHideout never fired or the "
                            "fallback-no-deadends path was wrongly taken")

        pos = [tuple(p) for p in h.sprite_positions(SPRITE_SLOTS)]
        npc1_y, npc1_x = pos[NPC1]
        npc2_y, npc2_x = pos[NPC2]
        print("arrival: slot6 (x=%d,y=%d) slot7 (x=%d,y=%d)" % (npc1_x, npc1_y, npc2_x, npc2_y))
        want = (player[0], player[1] - 1)
        if (npc1_x, npc1_y) != want:
            failures.append("slot 6 at (%d,%d), expected one step above the player %s"
                            % (npc1_x, npc1_y, want))
        if (npc2_x, npc2_y) != (player[0] + 1, player[1] - 1):
            failures.append("slot 7 at (%d,%d), expected right of slot 6" % (npc2_x, npc2_y))

        class6 = h.address("wMapSpriteExtraData")
        cls = h.pyboy.memory[class6 + (6 - 1) * 2]
        team = h.pyboy.memory[class6 + (6 - 1) * 2 + 1]
        print("slot 6 trainer: class=%d team=%d" % (cls, team))
        if cls == 0:
            failures.append("slot 6 has no trainer class - StageEventApplyTrainers "
                            "did not write, or wrote to the wrong slot (d != 6)")

        for _ in range(6):
            h.tap("a", frames=12)
            h.tick(40)
        after = h.read8("wStageEvent")
        after_phase = (after & phase_mask) >> phase_shift
        print("phase after dismissing text = %d" % after_phase)
        if after_phase != hiding:
            failures.append("phase is %d, expected HIDING (%d) - PFStageEventVanish "
                            "never ran" % (after_phase, hiding))

        pos = [tuple(p) for p in h.sprite_positions(SPRITE_SLOTS)]
        npc1_y, npc1_x = pos[NPC1]
        if (npc1_x // 2, npc1_y // 2) != (hx, hy):
            failures.append("slot 6 at block (%d,%d), expected the hideout (%d,%d)"
                            % (npc1_x // 2, npc1_y // 2, hx, hy))
        if (npc1_x, npc1_y) == want:
            failures.append("slot 6 never moved - it is still in front of the player")
    finally:
        try:
            h.close()
        except Exception:
            pass

    # --- good NPC: no vanish ------------------------------------------------
    h2 = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h2.boot_to_lobby()
        h2.write8("wStageEvent", const["STAGE_EVENT_JOY"])
        h2.preload_and_enter_wild_area(map_id, "Procedural Forest")
        before = [tuple(p) for p in h2.sprite_positions(SPRITE_SLOTS)]
        npc1_before = (before[NPC1][1], before[NPC1][0])
        for _ in range(6):
            h2.tap("a", frames=12)
            h2.tick(40)
        after_event = h2.read8("wStageEvent")
        after_phase = (after_event & phase_mask) >> phase_shift
        after = [tuple(p) for p in h2.sprite_positions(SPRITE_SLOTS)]
        npc1_after = (after[NPC1][1], after[NPC1][0])
        print("good NPC: before=%s after=%s phase=%d" % (npc1_before, npc1_after, after_phase))
        if after_phase != settled:
            failures.append("good NPC phase is %d, expected SETTLED (%d)"
                            % (after_phase, settled))
        if npc1_after != npc1_before:
            failures.append("good NPC moved from %s to %s - it should stay put"
                            % (npc1_before, npc1_after))
    finally:
        try:
            h2.close()
        except Exception:
            pass

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: forest stage events - hideout, arrival, vanish, trainer slots, "
          "and the good-NPC no-vanish branch all work")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
