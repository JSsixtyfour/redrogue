"""Audit the cave's deep-floor decision over many fresh caves (plan Phase 2 #6).

For each cave: the control pair after the first load must be decided (0/$FF or
CAVE_DEEP_MAGIC and complement); every deep cave must have both dynamic ladders
(A = $FD, B = $FC) armed down to cave warps 0/1; an encounter assigned to the
premade B1F must have moved to PROCEDURAL_CAVE_1 in a deep cave. Reports the
deep rate against the deep ramp at battle count 11 (92/256, ~36%, times the ~92%
of caves with two dynamic ladders: ~33%).

usage (worktree tools/pyboy_smoke): python3 audit_cave_deep_floor.py [--caves N]
Exit 1 on any violation or a rate outside 33% +- 8.
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
CAVE, SUBROOM = MAPS["PROCEDURAL_CAVE_1"], MAPS["PROCEDURAL_CAVE_SUBROOM"]
TAIL = 81 + 19 * 26 + 20

ap = argparse.ArgumentParser()
ap.add_argument("--caves", type=int, default=300)
ap.add_argument("--debug2", action="store_true",
                help="keep Debug 2 mode on (it forces every cave that can be deep)")
args = ap.parse_args()

from collections import Counter  # noqa: E402
from test_optional_cold_moves import SPECIES  # noqa: E402
NAMES = {SPECIES["ONIX"]: "Onix", SPECIES["SNORLAX"]: "Snorlax"}

h = RedRogueHarness(ROOT, ART)
h.allow_deep_cave_floor = True
problems, deep, cold_moved, cold_seen = [], 0, 0, 0
found = {"deep": Counter(), "ordinary": Counter()}   # encounter species by cave kind
try:
    h.boot_to_lobby(battle_count=11, encounter_kind=4)
    h.write8("wStageEvent", 0)
    if not args.debug2:
        # The harness boots through Debug 2, whose cave forcing skips the odds;
        # production rolls them. (Its cold-encounter forcing goes too.)
        h.write8("wStatusFlags6", h.read8("wStatusFlags6") & 0x7F)   # BIT_DEBUG2_MODE
    lobby = io.BytesIO()
    h.save_state(lobby)
    for n in range(args.caves):
        h.load_state(lobby)
        h.seed_rng((n & 255, (n >> 8) ^ 0x5A, n * 7 & 255, 1))
        h.preload_and_enter_wild_area(CAVE, "cave")
        ctrl = h.read_sram_bytes("sProcFacilityGenScratch", 25, bank=1)[23:]
        tail = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 2, bank=0)
        a, b = tail[TAIL], tail[TAIL + 1]
        where = h.read8("wOptionalEncounterMap")
        species = h.read8("wOptionalEncounterSpecies") if where in (CAVE, SUBROOM) else 0
        kind = "deep" if ctrl == [0xA0, 0x5F] else "ordinary"
        found[kind][NAMES.get(species, "none" if not species else f"${species:02x}")] += 1
        if ctrl == [0x00, 0xFF]:
            if where == CAVE:
                problems.append((n, "ordinary cave holds the encounter"))
            continue
        if ctrl != [0xA0, 0x5F]:
            problems.append((n, f"undecided or bad control {ctrl}"))
            continue
        deep += 1
        if (a, b) != (0xFD, 0xFC):
            problems.append((n, f"deep without two dynamic ladders: {a:02x} {b:02x}"))
        warps = h.warp_entries()
        if warps[2][2:] != [0, CAVE] or warps[3][2:] != [1, CAVE]:
            problems.append((n, f"ladders not aimed down: {warps[2]} {warps[3]}"))
        if where == SUBROOM:
            problems.append((n, "deep cave left the encounter in the B1F"))
        if h.read8("wOptionalEncounterSpecies") and where == CAVE:
            cold_moved += 1
finally:
    h.close()

rate = 100.0 * deep / args.caves
print(f"caves {args.caves}, deep {deep} ({rate:.1f}%), encounters moved to floor 2: {cold_moved}")
# The cold encounter is rolled once per cave, before the deep decision, so its
# rate must not depend on the cave kind (design: 33% cold x 10/33 Onix, 5/33 Snorlax).
for kind, counts in found.items():
    total = sum(counts.values())
    shares = ", ".join(f"{name} {c} ({100.0 * c / total:.1f}%)" for name, c in sorted(counts.items()))
    print(f"  {kind:8s} {total:4d} caves: {shares}")
for p in problems[:20]:
    print("PROBLEM", p)
ok = not problems and (99.0 <= rate if args.debug2 else 25.0 <= rate <= 41.0)
print("AUDIT", "OK" if ok else "FAILED", f"({len(problems)} problems)")
sys.exit(0 if ok else 1)
