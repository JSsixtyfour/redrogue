"""Audit: a stage NPC's MAP position and its SCREEN PIXEL position agree.

A sprite carries its position twice. CheckSpriteAvailability decides the
on-screen window test from SPRITESTATEDATA2_MAPY/MAPX, but the text-box test
(GetTileSpriteStandsOn) and TrainerEngage both read
SPRITESTATEDATA1_YPIXELS/XPIXELS. The only routine that resyncs them is
InitializeSpriteScreenPosition, and UpdateNPCSprite does `ret c` on an
invisible sprite BEFORE reaching it - so once the two disagree, the sprite
cannot repair itself.

Every stage-event placement writes MAP coords and never pixels. Harmless on an
ordinary load, where LoadMapHeader just zeroed the sprite state - but NOT after
a battle, where LoadMapHeader skips the object-list load entirely
("battles don't destroy this data") while the generator still slams the map
coords back to the hideout. The sprite then reads as offscreen (IMAGEINDEX
$ff), which also makes DetectCollisionBetweenSprites skip it: the reported
"they flicker on and off, no longer block you, and the location can change".

This audit asserts the two agree at the two moments the placement runs, on all
four wild areas:
  1. on arrival, right after entering the wild area
  2. after the dark-flash vanish has relocated the pair to the hideout

The formula is InitializeSpriteScreenPosition's own arithmetic, and it must be
reproduced literally rather than as "times 16":
    YPIXELS = (swap_nibbles((MAPY - wYCoord) & $ff) - 4) & $ff
    XPIXELS =  swap_nibbles((MAPX - wXCoord) & $ff)
`swap a` exchanges the nibbles; it only behaves like *16 when the difference is
0..15. For a sprite ABOVE or LEFT of the player the difference is negative, and
e.g. $ff swaps to $ff, not $f0. Writing this as *16 makes a correctly synced
sprite look off by 15. Note also the Y has a -4 and the X does not.

Also asserts wYCoord/wXCoord are already populated when the placement runs,
since the whole derivation is relative to the player.

THE CEMETERY IS THE INTERESTING CASE. Its pair lives on whichever floor the
hideout rolled onto, so the post-vanish state on floor 1 is usually the
PARK path - MapY/MapX both written to 0 to get the villain out of the face of
the player it just robbed. That path had no pixel sync at all until
2026-09-17, and it is the one most likely to regress, because "the sprite is
parked off-map anyway" reads like a reason not to bother. It is not: the
collision and text-box tests read the pixel pair, so an unsynced park leaves a
ghost blocking and talking from the cell the villain used to stand on.

NEGATIVE CONTROL (how to trust a pass): comment out the
`farcall StageEventSyncPairScreenPos` at the end of the area's placement
routine and rebuild. Every map must then FAIL its hideout check while still
passing its arrival check - arrival happens on a fresh LoadMapHeader, which
zeroes the sprite state and re-derives pixels for free, so a sync bug is
invisible there. Verified 2026-09-17 on the cave.

Usage:
    python3 tools/pyboy_smoke/audit_stage_npc_pixel_sync.py [--areas cave,forest,...]
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

# name -> (map constant, the string preload_and_enter_wild_area wants, slots)
# The facility is the one stage that cannot reuse slots 6-7: they are already
# its four fake item balls, so its pair lives at 10-11.
AREAS = {
    "cave": ("PROCEDURAL_CAVE_1", "Procedural Cave", (6, 7)),
    "forest": ("PROCEDURAL_FOREST", "Procedural Forest", (6, 7)),
    "facility": ("PROCEDURAL_FACILITY", "Procedural Facility", (10, 11)),
    "cemetery": ("PROCEDURAL_CEMETERY_1", "Procedural Cemetery 1", (2, 3)),
}


def stage_const(name):
    text = (REPO_ROOT / "constants" / "ram_constants.asm").read_text()
    m = re.search(r"^DEF %s\s+EQU\s+(%%[01]+|\$[0-9a-fA-F]+|\d+)" % name, text, re.M)
    if m is None:
        raise SystemExit("could not find DEF %s" % name)
    raw = m.group(1)
    if raw.startswith("%"):
        return int(raw[1:], 2)
    if raw.startswith("$"):
        return int(raw[1:], 16)
    return int(raw)


def swap_nibbles(v):
    """The Game Boy `swap a` instruction, which is NOT a multiply by 16."""
    return ((v << 4) | (v >> 4)) & 0xFF


def slot_state(h, slot):
    """(mapy, mapx, ypixels, xpixels) for one sprite slot."""
    # Named fields, not offsets: YPixels and XPixels are NOT adjacent
    # (YStepVector and XStepVector sit between them in StateData1).
    mapy = h.read8("wSprite%02dStateData2MapY" % slot)
    mapx = h.read8("wSprite%02dStateData2MapX" % slot)
    ypix = h.read8("wSprite%02dStateData1YPixels" % slot)
    xpix = h.read8("wSprite%02dStateData1XPixels" % slot)
    return mapy, mapx, ypix, xpix


def check(h, area, label, slots, failures):
    py = h.read8("wYCoord")
    px = h.read8("wXCoord")
    print("  %s: player step (x=%d, y=%d)" % (label, px, py))
    for slot in slots:
        mapy, mapx, ypix, xpix = slot_state(h, slot)
        want_y = (swap_nibbles((mapy - py) & 0xFF) - 4) & 0xFF
        want_x = swap_nibbles((mapx - px) & 0xFF)
        ok = (ypix == want_y) and (xpix == want_x)
        print("    slot %d: map=(%3d,%3d) pixels=($%02x,$%02x) want=($%02x,$%02x) %s"
              % (slot, mapx, mapy, xpix, ypix, want_x, want_y,
                 "ok" if ok else "DESYNC"))
        if not ok:
            failures.append(
                "%s/%s slot %d: map (%d,%d) implies pixels ($%02x,$%02x) but the "
                "sprite holds ($%02x,$%02x). CheckSpriteAvailability windows on "
                "the map pair while the collision and sight-line tests read the "
                "pixel pair, so this slot will flicker and stop blocking."
                % (area, label, slot, mapx, mapy, want_x, want_y, xpix, ypix))


def run_area(area, failures):
    map_name, entry_name, slots = AREAS[area]
    map_id = parse_map_constants(
        REPO_ROOT / "constants" / "map_constants.asm")[map_name]

    print()
    print("=== %s (slots %d-%d) ===" % (area.upper(), slots[0], slots[1]))

    # A fresh harness per area: boot_to_lobby is not re-entrant, and the second
    # call on one PyBoy instance always fails.
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        h.write8("wStageEvent", stage_const("STAGE_EVENT_JESSIE_JAMES"))
        h.preload_and_enter_wild_area(map_id, entry_name)
        h.tick(40)

        # The derivation is relative to the player, so the placement is only
        # meaningful if the player's own coords are already live by then.
        py = h.read8("wYCoord")
        px = h.read8("wXCoord")
        if (py, px) == (0, 0):
            failures.append(
                "%s: wYCoord/wXCoord are both 0 on arrival - the placement runs "
                "inside LoadMapData via ProcStageLoadDispatch and derives "
                "pixels relative to the player, so a zero here means the sync "
                "is computed against a position the player does not have yet"
                % area)

        print("ARRIVAL")
        check(h, area, "arrival", slots, failures)

        # Dismiss the greeting; the dark flash relocates the pair to the
        # hideout and re-runs the same placement routine.
        for _ in range(4):
            h.tap("a", frames=12)
            h.tick(40)
        phase_mask = stage_const("STAGE_EVENT_PHASE_MASK")
        shift = stage_const("STAGE_EVENT_PHASE_SHIFT")
        phase = (h.read8("wStageEvent") & phase_mask) >> shift
        print("HIDEOUT (phase=%d)" % phase)
        if phase == 0:
            failures.append(
                "%s: the event is still in phase WAITING after the greeting - "
                "the vanish never ran, so the hideout half of this audit proved "
                "nothing" % area)
        check(h, area, "hideout", slots, failures)
    finally:
        try:
            h.close()
        except Exception:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--areas", default=",".join(AREAS),
                        help="comma-separated subset of: " + ", ".join(AREAS))
    args = parser.parse_args()

    wanted = [a.strip() for a in args.areas.split(",") if a.strip()]
    for a in wanted:
        if a not in AREAS:
            raise SystemExit("unknown area %r; known: %s" % (a, ", ".join(AREAS)))

    failures = []
    for area in wanted:
        run_area(area, failures)

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: on %s, both NPC slots' screen pixels agree with their map "
          "position, on arrival and at the hideout" % ", ".join(wanted))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
