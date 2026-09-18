"""Audit: the Phase 7 rollout of stage events onto the Cemetery.

The cemetery is the only wild area whose arrival and hideout are on DIFFERENT
MAPS, so this audit checks two things the other three stages' audits cannot:

  Part A, floor 1 (the arrival floor):
    1. a hideout FLOOR was rolled, and it is 1-3 (never 0 - floor 1 is the
       arrival floor and must be excluded by construction)
    2. the pair stands in the corridor east of the entrance
    3. StageEventApplyTrainers (d=2) wrote a class into slot 2, NOT slot 1
       (slot 1 is the floor's pokeball)
    4. dismissing the text advances to HIDING and PARKS both slots off-grid -
       on the cemetery the villain leaves the map entirely rather than
       relocating on it
    5. forced Nurse Joy instead: settles in place, never moves

  Part B, floors 2-4 (the possible hideouts):
    For each floor, drive PCemFinalizeMap for that floor and assert the
    placement gate: the pair is at the SRAM hideout on the rolled floor and
    parked off-grid on every other one. That gate is what stops the phantom
    NPCs the forest once grew, which here would fire on three floors of four.

Usage:
    python3 tools/pyboy_smoke/audit_cemetery_stage_event.py
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
SPRITE_SLOTS = 4
NPC1, NPC2 = 1, 2  # 0-based indices of object slots 2 and 3

# Floor 1's entrance is warp 1 at player step (3,9), on the WEST wall, so the
# pair stands in the corridor east of it rather than "one step above".
ARRIVAL_NPC1 = (4, 9)
ARRIVAL_NPC2 = (4, 8)
OFF_GRID = (-4, -4)  # sprite_positions subtracts 4, and parking writes 0


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

    maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
    floor_ids = [maps["PROCEDURAL_CEMETERY_%d" % n] for n in (1, 2, 3, 4)]
    failures = []

    # ---- Part A: the arrival on floor 1 --------------------------------
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.write8("wStageEvent", const["STAGE_EVENT_JESSIE_JAMES"])
        h.preload_and_enter_wild_area(floor_ids[0], "Procedural Cemetery 1")

        floor = h.read_sram_bytes("sStageEventHideoutFloor", 1, bank=0)[0]
        print("rolled hideout floor index = %s (want 1-3)" % floor)
        if floor not in (1, 2, 3):
            failures.append(
                "hideout floor is %s, expected 1-3 - floor 1 (index 0) is the "
                "arrival floor and must never be rolled" % floor)

        pos = [tuple(p) for p in h.sprite_positions(SPRITE_SLOTS)]
        npc1 = (pos[NPC1][1], pos[NPC1][0])  # (x, y)
        npc2 = (pos[NPC2][1], pos[NPC2][0])
        print("arrival: slot2 %s slot3 %s" % (npc1, npc2))
        if npc1 != ARRIVAL_NPC1:
            failures.append("slot 2 at %s, expected the corridor cell %s"
                            % (npc1, ARRIVAL_NPC1))
        if npc2 != ARRIVAL_NPC2:
            failures.append("slot 3 at %s, expected %s" % (npc2, ARRIVAL_NPC2))

        base = h.address("wMapSpriteExtraData")
        cls2 = h.pyboy.memory[base + (2 - 1) * 2]
        cls1 = h.pyboy.memory[base + (1 - 1) * 2]
        print("slot 2 trainer class=%d  slot 1 (pokeball) class=%d" % (cls2, cls1))
        if cls2 == 0:
            failures.append("slot 2 has no trainer class - StageEventApplyTrainers "
                            "did not write, or wrote to the wrong slot (d != 2)")
        if cls1 != 0:
            failures.append("slot 1 (the pokeball) got a trainer class written "
                            "into it - the base slot is wrong")

        for _ in range(6):
            h.tap("a", frames=12)
            h.tick(40)
        after_phase = (h.read8("wStageEvent") & phase_mask) >> phase_shift
        print("phase after dismissing text = %d" % after_phase)
        if after_phase != hiding:
            failures.append("phase is %d, expected HIDING (%d) - "
                            "PCemStageEventVanish never ran" % (after_phase, hiding))

        pos = [tuple(p) for p in h.sprite_positions(SPRITE_SLOTS)]
        npc1 = (pos[NPC1][1], pos[NPC1][0])
        print("after vanish: slot2 %s (want off-grid %s)" % (npc1, OFF_GRID))
        if npc1 == ARRIVAL_NPC1:
            failures.append("slot 2 never moved - the villain is still standing "
                            "in front of the player after the vanish")
        elif npc1 != OFF_GRID:
            failures.append("slot 2 at %s after the vanish, expected off-grid %s - "
                            "the cemetery villain leaves the MAP, it does not "
                            "relocate on it" % (npc1, OFF_GRID))
    finally:
        try:
            h.close()
        except Exception:
            pass

    # ---- Part A2: a good NPC is FOUND on the hideout floor -------------
    # CHANGED 2026-09-17. This used to assert "a good NPC settles in place",
    # meaning it stayed standing in floor 1's entrance corridor. That was the
    # cemetery's version of the reported ambush: Joy and Jenny are supposed to
    # be something you find. PCemStageEventFloor now sends a good NPC to the
    # hideout floor in EVERY phase, so the contract is:
    #
    #   floor 1              parked off-grid, and SETTLED on arrival with no
    #                        input - no greeting was ever shown
    #   the hideout floor    standing on the hideout cell, ready to be found
    #
    # Asserting only the first half would pass on a build where the good NPC
    # exists nowhere at all, which is the exact shape of
    # project_fixture_hides_missing_production_code.
    h2 = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h2.boot_to_lobby()
        h2.write8("wStageEvent", const["STAGE_EVENT_JOY"])
        h2.preload_and_enter_wild_area(floor_ids[0], "Procedural Cemetery 1")

        entry_phase = (h2.read8("wStageEvent") & phase_mask) >> phase_shift
        rolled = h2.read_sram_bytes("sStageEventHideoutFloor", 1, bank=0)[0]
        before = [tuple(p) for p in h2.sprite_positions(SPRITE_SLOTS)]
        npc1_before = (before[NPC1][1], before[NPC1][0])
        print("good NPC: floor 1 slot2=%s, entry phase=%d, rolled floor idx=%s"
              % (npc1_before, entry_phase, rolled))

        if entry_phase != settled:
            failures.append(
                "good NPC: phase is %d on arrival with NO input, expected "
                "SETTLED (%d). The type gate must run before the DisplayTextID "
                "so no greeting is ever shown." % (entry_phase, settled))
        if npc1_before != OFF_GRID:
            failures.append(
                "good NPC: slot 2 is at %s on floor 1 instead of off-grid %s - "
                "this is the ambush, they belong on the hideout floor"
                % (npc1_before, OFF_GRID))
        if rolled == no_hideout:
            failures.append(
                "good NPC: no hideout floor was rolled, so Joy exists nowhere. "
                "PCemRollStageHideoutFloor must roll for good types too - its "
                "own header says why.")
        else:
            h2.write8("hCurMap", floor_ids[rolled])
            h2.call_routine("PCemFinalizeMap", limit=200000)
            hx = h2.read_sram_bytes("sStageEventHideoutX", 1, bank=0)[0]
            hy = h2.read_sram_bytes("sStageEventHideoutY", 1, bank=0)[0]
            pos = [tuple(p) for p in h2.sprite_positions(SPRITE_SLOTS)]
            npc1 = (pos[NPC1][1], pos[NPC1][0])
            want = (hx * 2, hy * 2)
            print("  good NPC on floor idx %d: cell=(%d,%d) slot2=%s"
                  % (rolled, hx, hy, npc1))
            if hx == no_hideout or hy == no_hideout:
                failures.append(
                    "good NPC: floor idx %d rolled but no cell was picked"
                    % rolled)
            elif npc1 != want:
                failures.append(
                    "good NPC: slot 2 at %s on its hideout floor, expected %s "
                    "for block (%d,%d). PCPlaceStageEventNpcs must test TYPE "
                    "before PHASE, or a good NPC in phase SETTLED still takes "
                    "the arrival branch." % (npc1, want, hx, hy))
    finally:
        try:
            h2.close()
        except Exception:
            pass

    # ---- Part B: the per-floor placement gate --------------------------
    h3 = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h3.boot_to_lobby()
        h3.write8("wStageEvent", const["STAGE_EVENT_JESSIE_JAMES"])
        h3.preload_and_enter_wild_area(floor_ids[0], "Procedural Cemetery 1")
        rolled = h3.read_sram_bytes("sStageEventHideoutFloor", 1, bank=0)[0]
        # Advance past the arrival so the phase is HIDING, which is the state
        # the hideout placement actually runs in.
        for _ in range(6):
            h3.tap("a", frames=12)
            h3.tick(40)
        print("\npart B: rolled floor index = %s" % rolled)

        for index in (1, 2, 3):
            h3.write8("hCurMap", floor_ids[index])
            h3.call_routine("PCemFinalizeMap", limit=200000)
            hx = h3.read_sram_bytes("sStageEventHideoutX", 1, bank=0)[0]
            hy = h3.read_sram_bytes("sStageEventHideoutY", 1, bank=0)[0]
            pos = [tuple(p) for p in h3.sprite_positions(SPRITE_SLOTS)]
            npc1 = (pos[NPC1][1], pos[NPC1][0])
            npc2 = (pos[NPC2][1], pos[NPC2][0])
            if index == rolled:
                want1 = (hx * 2, hy * 2)
                want2 = (hx * 2 + 1, hy * 2)
                print("  floor idx %d (THE hideout): cell=(%d,%d) slot2=%s slot3=%s"
                      % (index, hx, hy, npc1, npc2))
                if hx == no_hideout or hy == no_hideout:
                    failures.append(
                        "floor idx %d is the rolled hideout but no cell was "
                        "picked - PCemPickStageHideoutCell never fired" % index)
                elif npc1 != want1 or npc2 != want2:
                    failures.append(
                        "floor idx %d: pair at %s/%s, expected %s/%s for hideout "
                        "block (%d,%d)" % (index, npc1, npc2, want1, want2, hx, hy))
            else:
                print("  floor idx %d (not the hideout): slot2=%s slot3=%s"
                      % (index, npc1, npc2))
                if npc1 != OFF_GRID or npc2 != OFF_GRID:
                    failures.append(
                        "floor idx %d is NOT the hideout but the pair is at "
                        "%s/%s instead of off-grid - this is the phantom-NPC "
                        "gate failing" % (index, npc1, npc2))
    finally:
        try:
            h3.close()
        except Exception:
            pass

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: cemetery stage events - floor roll, arrival, trainer slot 2, "
          "cross-floor vanish, the good-NPC no-vanish branch, and the "
          "per-floor placement gate all work")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
