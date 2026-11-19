"""Facility SPEC X3 input: what PFacFinalize's fresh path alone rewrites.

From a settled Facility, a hop with sProcFacilityBaked cleared (the first
descent's generation, without PFacPreload) against an ordinary hop. Every WRAM
and SRAM byte only the regeneration writes, by nearest symbol, minus the
Facility's own bank-1 section (that is the per-floor state the exchange swaps).
Run twice (two seeds) so a byte a seed happens to rewrite to the same value is
less likely to hide.

usage (worktree tools/pyboy_smoke): python3 probe_facility_deep_finalize_diff.py [--seed N]
"""
import argparse
import io
import sys
from pathlib import Path

sys.path.insert(0, ".")
from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ROOT = Path(".").resolve().parents[1]
ART = ROOT / "tools/pyboy_smoke/artifacts"
FAC = parse_map_constants(ROOT / "constants/map_constants.asm")["PROCEDURAL_FACILITY"]

ap = argparse.ArgumentParser()
ap.add_argument("--seed", type=int, default=7)
args = ap.parse_args()
h = RedRogueHarness(ROOT, ART)


def hop(entrance):
    h.write8("hWarpDestinationMap", FAC)
    h.write8("wDestinationWarpID", 0)
    h.write8("wStatusFlags3", h.read8("wStatusFlags3") | 1 << 3)
    seen = h.hook_flag("WarpFound2")
    h.wait_until(lambda: seen["count"] > 0, "the self-warp", 300)
    h.wait_until(lambda: h.read8("hCurMap") == FAC and (h.read8("wYCoord"), h.read8("wXCoord")) == entrance
                 and h.read8("hJoyIgnore") == 0, "back on the entrance", 1500)
    h.tick(120)


def snap():
    m = h.pyboy.memory
    out = {"wram": bytes(m[0xC000:0xE000])}
    for b in range(4):
        out[f"sram{b}"] = bytes(m[b, 0xA000:0xBFFF]) + bytes([m[b, 0xBFFF]])
    return out


BASES = {"wram": (0, 0xC000), "sram0": (0, 0xA000), "sram1": (1, 0xA000),
         "sram2": (2, 0xA000), "sram3": (3, 0xA000)}
try:
    h.boot_to_lobby(battle_count=11, encounter_kind=4)
    h.write8("wStageEvent", 0)
    h.seed_rng((args.seed, args.seed ^ 0xA5, 0, 1))
    h.preload_and_enter_wild_area(FAC, "facility")
    h.wait_until(lambda: h.read8("hJoyIgnore") == 0, "settled", 900)
    h.tick(60)
    entrance = (h.read8("wYCoord"), h.read8("wXCoord"))
    settled = io.BytesIO()
    h.save_state(settled)
    s0 = snap()
    hop(entrance)
    s1 = snap()
    control = {k: {i for i in range(len(s0[k])) if s0[k][i] != s1[k][i]} for k in s0}
    h.load_state(settled)
    h.write_sram_bytes("sProcFacilityBaked", [0], bank=1)
    s0 = snap()
    hop(entrance)
    s2 = snap()
    fac0 = h.address("sProcFacilityStagingBuffer") - 0xA000
    fac1 = h.address("sProcFacilityGenScratch") + 81 - 0xA000
    for k in s0:
        only = sorted(i for i in range(len(s0[k])) if s0[k][i] != s2[k][i] and i not in control[k])
        if k == "sram1":
            only = [i for i in only if not fac0 <= i < fac1]
        if k == "wram":   # the map, tilemaps, OAM and the stack: per-load, not state
            only = [i for i in only if not (0xC300 <= 0xC000 + i < 0xC9F0 or 0xDF00 <= 0xC000 + i)]
        runs = []
        for o in only:
            if runs and o <= runs[-1][1] + 1:
                runs[-1][1] = o
            else:
                runs.append([o, o])
        print(f"== {k}: {len(only)} B")
        bank, base = BASES[k]
        for a, b in runs:
            try:
                name = h.symbols.nearest(0 if k == "wram" else bank, base + a)
            except Exception:
                name = None
            print(f"   {base + a:04x} +{b - a + 1:<3} {name}  {s0[k][a:b + 1].hex()} -> {s2[k][a:b + 1].hex()}")
finally:
    h.close()
