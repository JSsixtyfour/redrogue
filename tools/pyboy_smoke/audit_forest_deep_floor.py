"""Audit the Forest's deep-floor decision over many fresh forests (plan, Forest F8).

For each forest: the control pair after the first load must be decided (0/$FF, or
the deep magic and its complement); every deep forest must have its opening armed
(warps 31 and 3 aimed at this map's opening warps) on floor 1; the house must be
on floor 1 exactly when the coin did not give it to floor 2; and an encounter
assigned to the grotto must have moved to PROCEDURAL_FOREST in a deep forest and
stayed in the grotto in an ordinary one. Reports the deep rate against
the deep ramp's odds at battle count 11 (DeepRampRoll: 26 + 6 x 11 = 92/256,
~36%) and the coin's split.

usage (worktree tools/pyboy_smoke): python3 audit_forest_deep_floor.py [--forests N]
Exit 1 on any violation or a rate outside 36% +- 10.
"""
import argparse
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "tools/pyboy_smoke/artifacts"
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
FOREST, GROTTO = MAPS["PROCEDURAL_FOREST"], MAPS["PROCEDURAL_FOREST_GROTTO"]
CTRL = 400 + 102
MAGIC_MASK, MAGIC, HOUSE_2 = 0xE0, 0xC0, 0x04
FG_WARP, SECOND_WARP = 31, 3

ap = argparse.ArgumentParser()
ap.add_argument("--forests", type=int, default=300)
args = ap.parse_args()

h = RedRogueHarness(ROOT, ART)
h.allow_deep_forest_floor = True
problems, deep, demoted, house_on_2, moved, stayed = [], 0, 0, 0, 0, 0
try:
    h.boot_to_lobby(battle_count=11, encounter_kind=4)
    h.write8("wStageEvent", 0)
    # The harness boots through Debug 2, which forces every forest that can be
    # deep; production rolls the odds.
    h.write8("wStatusFlags6", h.read8("wStatusFlags6") & 0x7F)   # BIT_DEBUG2_MODE
    lobby = io.BytesIO()
    h.save_state(lobby)
    for n in range(args.forests):
        h.load_state(lobby)
        h.seed_rng((n & 255, (n >> 8) ^ 0x5A, n * 7 & 255, 1))
        h.preload_and_enter_wild_area(FOREST, "forest")
        ctrl, comp = h.read_sram_bytes("sProcCaveStagingBuffer", CTRL + 2, bank=0)[CTRL:]
        where = h.read8("wOptionalEncounterMap")
        has_encounter = h.read8("wOptionalEncounterSpecies") != 0
        house = h.read_sram_bytes("sProcForestItemGot", 1, bank=0)[0] & 0x1F
        if ctrl == 0x00 and comp == 0xFF:
            if where == FOREST:
                problems.append((n, "ordinary forest holds the encounter"))
            if has_encounter and where == GROTTO:
                stayed += 1
            continue
        if ctrl ^ comp != 0xFF or ctrl & MAGIC_MASK != MAGIC:
            problems.append((n, f"undecided or bad control {ctrl:02x} {comp:02x}"))
            continue
        deep += 1
        warps = h.warp_entries()
        if warps[FG_WARP][0] == 0xFF or warps[FG_WARP][2:] != [FG_WARP, FOREST] \
                or warps[SECOND_WARP][2:] != [SECOND_WARP, FOREST]:
            problems.append((n, f"deep without an opening aimed at itself: {warps[FG_WARP]} {warps[SECOND_WARP]}"))
        if ctrl & HOUSE_2:
            house_on_2 += 1
            if house:
                problems.append((n, f"the coin gave floor 2 the house, floor 1 kept site {house}"))
        if where == GROTTO and has_encounter:
            problems.append((n, "deep forest left the encounter in the grotto"))
        if where == FOREST and has_encounter:
            moved += 1
finally:
    h.close()

rate = 100.0 * deep / args.forests
print(f"forests {args.forests}, deep {deep} ({rate:.1f}%), house on floor 2 in {house_on_2}, "
      f"encounters moved to floor 2: {moved}, stayed in the grotto (ordinary): {stayed}")
for p in problems[:20]:
    print("PROBLEM", p)
ok = not problems and 26.0 <= rate <= 46.0
print("AUDIT", "OK" if ok else "FAILED", f"({len(problems)} problems)")
sys.exit(0 if ok else 1)
