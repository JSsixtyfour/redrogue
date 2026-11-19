"""Audit the Facility's deep-floor decision over many fresh Facilities (plan, Facility X8).

For each Facility, after its first load:
  * the control pair is decided: 0/$FF, or the deep magic and its complement;
  * a deep floor 1 has its marker pad armed at its own warp (the seam's trigger),
    holds no resident (slot 12 picture 0) and no floor-2 encounter (slot 13 picture 0);
  * an encounter rolled for the subroom stands on PROCEDURAL_FACILITY with the
    floor-2 state bit in a deep Facility, and is never left on the subroom map;
  * an ordinary Facility keeps the state bit clear.
Reports the deep rate against FACILITY_DEEP_ODDS (128/256 = 50%) and how often the
no-pad demotion fired. For the first --descend deep Facilities it also takes the pad
down and checks floor 2: the resident stands on a plain-floor block that no ball,
encounter or other object occupies, is shown, and floor 2 carries a way back up.

usage (worktree tools/pyboy_smoke): python3 audit_facility_deep_floor.py [--facilities N] [--descend M]
Exit 1 on any violation or a deep rate outside 50% +- 10.
"""
import argparse
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_facility_deep_floor as t  # noqa: E402
from harness import RedRogueHarness  # noqa: E402

ROOT, ART, FAC, SUBROOM = t.ROOT, t.ARTIFACTS, t.FAC, t.SUBROOM

ap = argparse.ArgumentParser()
ap.add_argument("--facilities", type=int, default=300)
ap.add_argument("--descend", type=int, default=40)
args = ap.parse_args()

h = RedRogueHarness(ROOT, ART)
h.allow_deep_facility_floor = True
case = t.FacilityDeepFloorTest("test_lobby_decides_and_the_default_is_ordinary")
case.h = h                                   # the test's trip(), spot() and ctrl() helpers
demotions = [h.hook_flag("FDFDemote"), h.hook_flag("FDF2Demote")]
problems, deep, descended, encounters_deep, encounters_ordinary = [], 0, 0, 0, 0
spots = {}                                    # the resident's tile -> how many floors 2
try:
    h.boot_to_lobby(battle_count=11, encounter_kind=4)
    h.write8("wStageEvent", 0)
    h.write8("wStatusFlags6", h.read8("wStatusFlags6") & 0x7F)   # BIT_DEBUG2_MODE: production odds
    lobby = io.BytesIO()
    h.save_state(lobby)
    for n in range(args.facilities):
        h.load_state(lobby)
        h.seed_rng((n & 255, (n >> 8) ^ 0x5A, n * 7 & 255, 1))
        h.preload_and_enter_wild_area(FAC, "facility")
        h.write8("wProcFacilityWildBudget", 0)
        ctrl, comp = case.ctrl()
        where = h.read8("wOptionalEncounterMap")
        has_encounter = h.read8("wOptionalEncounterSpecies") != 0
        state_bit = bool(h.read8("wOptionalEncounterState") & t.ENC_STATE_BIT)
        if ctrl == 0x00 and comp == 0xFF:
            if state_bit:
                problems.append((n, "ordinary Facility with the floor-2 encounter bit"))
            if has_encounter:
                encounters_ordinary += 1
            continue
        if ctrl ^ comp != 0xFF or ctrl & t.MAGIC_MASK != t.MAGIC:
            problems.append((n, f"undecided or bad control {ctrl:02x} {comp:02x}"))
            continue
        deep += 1
        pad = case.subroom_pad()
        warps = h.warp_entries()
        if pad >= t.NUM_PAD_SITES:
            problems.append((n, f"deep floor 1 without a subroom pad (byte 7 = {pad})"))
        elif warps[t.FIRST_PAD + pad][2:] != [t.FIRST_PAD + pad, FAC]:
            problems.append((n, f"marker pad not armed at its own warp: {warps[t.FIRST_PAD + pad]}"))
        if case.picture(t.NERD_SLOT):
            problems.append((n, "deep floor 1 shows the resident"))
        if has_encounter:
            encounters_deep += 1
            if where == SUBROOM:
                problems.append((n, "deep Facility left the encounter on the subroom map"))
            if bool(ctrl & t.ENC_2) != state_bit:
                problems.append((n, "ENC_2 and the encounter state bit disagree"))
            if state_bit and case.picture(t.ENC_SLOT):
                problems.append((n, "a floor-2 encounter shows on floor 1"))
        if descended < args.descend:
            descended += 1
            try:
                case.trip("down")
            except AssertionError as error:
                problems.append((n, f"descent failed: {error}"))
                continue
            x, y = case.spot(t.NERD_SLOT)
            if not case.picture(t.NERD_SLOT):
                problems.append((n, "floor 2 has no resident"))
                continue
            spots[(x, y)] = spots.get((x, y), 0) + 1
            layout = h.read_bytes("wOverworldMap", 601)
            if (x % 2, y % 2) != (1, 1) or layout[81 + (y - 5) // 2 * 26 + (x - 5) // 2] != 0x0E:
                problems.append((n, f"resident not on a plain-floor block: {x},{y}"))
            for slot in range(1, 14):
                if slot != t.NERD_SLOT and case.picture(slot):
                    sx, sy = case.spot(slot)
                    if slot != t.ENC_SLOT and (sx, sy) == (x, y):
                        problems.append((n, f"slot {slot} stands on the resident"))
                    if slot == t.ENC_SLOT and abs(sx - x) + abs(sy - y) == 0:
                        problems.append((n, "the encounter stands on the resident"))
            if warps and h.warp_entries()[t.FIRST_PAD + case.subroom_pad()][2:] != \
                    [t.FIRST_PAD + case.subroom_pad(), FAC]:
                problems.append((n, "floor 2 has no marker pad back up"))
finally:
    h.close()

rate = 100.0 * deep / args.facilities
print(f"facilities {args.facilities}, deep {deep} ({rate:.1f}%), demotions {sum(f['count'] for f in demotions)}, "
      f"descended {descended}, encounters in deep {encounters_deep}, ordinary {encounters_ordinary}")
commonest = max(spots.values()) if spots else 0
bands = [0, 0, 0, 0]                           # block rows 3-6, 7-10, 11-14, 15-18
for (x, y), count in spots.items():
    bands[min(3, max(0, ((y - 5) // 2 - 3) // 4))] += count
print(f"resident block-row bands 3-6/7-10/11-14/15-18: {bands}")
print(f"resident tiles: {len(spots)} distinct in {sum(spots.values())} floors 2, the commonest on {commonest}")
# Variety (2026-11-19): his spot is seeded by floor 2's own ball cells, so it
# must not collapse onto a few tiles.
if sum(spots.values()) >= 30 and min(bands) * 8 < sum(spots.values()):
    problems.append(("-", f"the resident favours part of the map: row bands {bands}"))
if sum(spots.values()) >= 30 and len(spots) * 3 < sum(spots.values()):
    problems.append(("-", f"the resident stands on only {len(spots)} tiles in {sum(spots.values())} floors 2"))
for p in problems[:20]:
    print("PROBLEM", p)
ok = not problems and 40.0 <= rate <= 60.0
print("AUDIT", "OK" if ok else "FAILED", f"({len(problems)} problems)")
sys.exit(0 if ok else 1)
