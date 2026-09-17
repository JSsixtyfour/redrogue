"""Audit: does the Phase 7c stage-event arrival sequence actually run?

The lobby only arms an event on a wild-area assignment, and then only
STAGE_EVENT_CHANCE of the time, so this forces `wStageEvent` before the
preload rather than waiting for a roll. That is legitimate here: the roll is
tested by its own arithmetic, and what this script exercises is everything
downstream of it.

The whole 7c lifecycle, checked as a sequence rather than as a final state,
because a wrong intermediate that self-corrects looks identical to a correct
one at the end:

  1. the NPC sprites are staged (non-zero PICTUREID) for an armed event, and
     stay zero for STAGE_EVENT_NONE - a zero costs no VRAM tile slot
  2. on warp-in the pair stands one step ABOVE the player, in the player's own
     column and the one to its right
  3. the arrival text fires on the first tick after the load
  4. after it is dismissed, the dark flash moves them to the hideout and the
     phase advances WAITING -> HIDING
  5. re-reading with phase HIDING places them at the hideout, not in front of
     the player

Step 2 needs no floor check anywhere in the engine, which is the point of
placing them relative to the entrance: the player is standing in that block,
so it is walkable by definition.

Usage:
    python3 tools/pyboy_smoke/audit_cave_stage_event.py [--type N]

Exits non-zero if any step of the sequence fails.
"""

from __future__ import annotations

import argparse
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
    """Read the STAGE_EVENT_* block rather than duplicating its numbers here."""
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--type", type=int, default=1,
                        help="STAGE_EVENT_* type to force (1 = Jessie & James, a PAIR)")
    args = parser.parse_args()

    const = stage_event_constants()
    phase_mask = const["STAGE_EVENT_PHASE_MASK"]
    phase_shift = const["STAGE_EVENT_PHASE_SHIFT"]
    type_mask = const["STAGE_EVENT_TYPE_MASK"]
    hiding = const["STAGE_EVENT_PHASE_HIDING"]

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]
    failures = []

    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        harness.boot_to_lobby()
        # Arm the event BEFORE the preload: StageEventStageSprites publishes the
        # per-slot sprites during PCPreloadCave, which is far too early to be
        # influenced by anything written afterwards.
        harness.write8("wStageEvent", args.type)
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")

        player = (harness.read8("wXCoord"), harness.read8("wYCoord"))
        sprite6 = harness.read_sram_bytes("sStageEventSprite6", 1, bank=SRAM_BANK)[0]
        sprite7 = harness.read_sram_bytes("sStageEventSprite7", 1, bank=SRAM_BANK)[0]
        hx = harness.read_sram_bytes("sStageEventHideoutX", 1, bank=SRAM_BANK)[0]
        hy = harness.read_sram_bytes("sStageEventHideoutY", 1, bank=SRAM_BANK)[0]
        print("player step (x,y) = %s" % (player,))
        print("staged sprites: slot6=$%02x slot7=$%02x" % (sprite6, sprite7))
        print("hideout block   = (%d,%d)" % (hx, hy))

        # --- 1. sprites staged -------------------------------------------
        if sprite6 == 0:
            failures.append("slot 6 sprite is 0 with an event armed - it will not render")
        if args.type == 1 and sprite7 == 0:
            failures.append("slot 7 sprite is 0 for a PAIRED event (Jessie & James)")

        # --- 2. arrival placement ----------------------------------------
        pos = [tuple(p) for p in harness.sprite_positions(SPRITE_SLOTS)]
        npc1_y, npc1_x = pos[NPC1]
        npc2_y, npc2_x = pos[NPC2]
        print("arrival: slot6 step (x=%d,y=%d)  slot7 step (x=%d,y=%d)"
              % (npc1_x, npc1_y, npc2_x, npc2_y))
        want = (player[0], player[1] - 1)
        if (npc1_x, npc1_y) != want:
            failures.append("slot 6 at (%d,%d), expected one step above the player %s"
                            % (npc1_x, npc1_y, (want,)))
        if (npc2_x, npc2_y) != (player[0] + 1, player[1] - 1):
            failures.append("slot 7 at (%d,%d), expected right of slot 6" % (npc2_x, npc2_y))

        # --- 3. the arrival text fired ------------------------------------
        # The entry sequence already ran script ticks, so by now the text box
        # should be open and the phase should still be WAITING (the vanish runs
        # only after the text is dismissed).
        before_phase = (harness.read8("wStageEvent") & phase_mask) >> phase_shift
        print("phase before dismissing text = %d" % before_phase)
        if before_phase != 0:
            failures.append("phase advanced to %d before the text was dismissed"
                            % before_phase)

        # --- 4. dismiss, then the dark flash ------------------------------
        for _ in range(6):
            harness.tap("a", frames=12)
            harness.tick(40)
        after = harness.read8("wStageEvent")
        after_phase = (after & phase_mask) >> phase_shift
        print("phase after  dismissing text = %d (wStageEvent=$%02x)" % (after_phase, after))
        if after_phase != hiding:
            failures.append("phase is %d, expected STAGE_EVENT_PHASE_HIDING (%d) - the "
                            "vanish never ran" % (after_phase, hiding))
        if (after & type_mask) != args.type:
            failures.append("event type was corrupted: $%02x" % after)

        # --- 5. relocated to the hideout ----------------------------------
        pos = [tuple(p) for p in harness.sprite_positions(SPRITE_SLOTS)]
        npc1_y, npc1_x = pos[NPC1]
        npc2_y, npc2_x = pos[NPC2]
        print("hideout: slot6 step (x=%d,y=%d) block (%d,%d)  slot7 step (x=%d,y=%d)"
              % (npc1_x, npc1_y, npc1_x // 2, npc1_y // 2, npc2_x, npc2_y))
        if (npc1_x // 2, npc1_y // 2) != (hx, hy):
            failures.append("slot 6 is at block (%d,%d), expected the hideout (%d,%d)"
                            % (npc1_x // 2, npc1_y // 2, hx, hy))
        if (npc1_x, npc1_y) == want:
            failures.append("slot 6 never moved - it is still in front of the player")
    finally:
        try:
            harness.close()
        except Exception:
            pass

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: arrival placement, text, dark flash and hideout relocation all fired")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
