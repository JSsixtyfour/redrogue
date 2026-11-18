"""Deep-floor plan Phase 0 (risk list): every byte a second generation writes.

From a settled cave: (control) a plain self-warp hop, and (regen) PCPreloadCave
run in place with sProcCaveBaked forced 0, followed by the same self-warp hop
(which then takes the fresh PCFinalizeCave path). Diffs WRAM, HRAM and SRAM
banks 0-3, and reports the regions the regen path changes that the control hop
does not, labelled with the nearest symbol.

usage (worktree tools/pyboy_smoke): python3 regen_diff_probe.py [--cgb] [--seed N]
"""
import argparse
import io
import json
import sys
from pathlib import Path

sys.path.insert(0, ".")
from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ROOT = Path(".").resolve().parents[1]
ART = ROOT / "tools/pyboy_smoke/artifacts"
CAVE = parse_map_constants(ROOT / "constants/map_constants.asm")["PROCEDURAL_CAVE_1"]

ap = argparse.ArgumentParser()
ap.add_argument("--cgb", action="store_true")
ap.add_argument("--seed", type=int, default=None)
args = ap.parse_args()

h = RedRogueHarness(ROOT, ART, cgb_mode=args.cgb)


def snap():
    m = h.pyboy.memory
    out = {"wram": bytes(m[0xC000:0xE000]), "hram": bytes(m[0xFF80:0xFFFF])}
    for b in range(4):
        out[f"sram{b}"] = bytes(m[b, 0xA000:0xBFFF]) + bytes([m[b, 0xBFFF]])
    return out


BASES = {"wram": (0, 0xC000), "hram": (0, 0xFF80), "sram0": (0, 0xA000),
         "sram1": (1, 0xA000), "sram2": (2, 0xA000), "sram3": (3, 0xA000)}


def changed(a, b):
    return {k: {i for i in range(len(a[k])) if a[k][i] != b[k][i]} for k in a}


def label(region, offset):
    bank, base = BASES[region]
    addr = base + offset
    sym_bank = 0 if region in ("wram", "hram") else bank
    try:
        name = h.symbols.nearest(sym_bank, addr)
    except Exception:
        name = None
    return f"{addr:04x}", name


def spans(offsets):
    out = []
    for o in sorted(offsets):
        if out and o <= out[-1][1] + 1:
            out[-1][1] = o
        else:
            out.append([o, o])
    return out


def hop():
    h.write8("wWarpEntries", 39, offset=0)
    h.write8("wWarpEntries", 0, offset=2)
    h.write8("wWarpEntries", CAVE, offset=3)
    seen = h.hook_flag("WarpFound2")
    h.pyboy.button_press("down")
    try:
        h.wait_until(lambda: seen["count"] > 0, "hop start", 300)
        h.tick(30)
    finally:
        h.pyboy.button_release("down")
    h.tick(200)
    if h.read8("hCurMap") != CAVE or (h.read8("wXCoord"), h.read8("wYCoord")) != (18, 39):
        raise AssertionError(f"hop landed at map {h.read8('hCurMap')} {h.read8('wXCoord'), h.read8('wYCoord')}")


try:
    h.boot_to_lobby(battle_count=11, encounter_kind=4)
    h.write8("wStageEvent", 0)
    if args.seed is not None:
        h.seed_rng((args.seed, args.seed ^ 0xA5, 0, 1))
    h.preload_and_enter_wild_area(CAVE, "cave")
    h.write8("wProcCaveWildBudget", 0)
    h.wait_until(lambda: h.read8("wYCoord") == 39, "on the cave entrance", 600)
    h.tick(30)
    base = io.BytesIO()
    h.save_state(base)

    s0 = snap()
    hop()
    control = changed(s0, snap())

    h.load_state(base)
    s0b = snap()
    h.park_before_hijack()
    h.call_routine("PCPreloadCave", limit=60000)
    s1 = snap()
    pre = changed(s0b, s1)
    h.write_sram_bytes("sProcCaveBaked", [0], bank=0)   # already 0 after preload; explicit
    hop()
    s2 = snap()
    total = changed(s0b, s2)

    for region in BASES:
        only = total[region] - control[region]
        print(f"== {region}: regen-only {len(only)} B, preload {len(pre[region])} B, "
              f"control hop {len(control[region])} B")
        for a, b in spans(only):
            addr, name = label(region, a)
            in_pre = any(o in pre[region] for o in range(a, b + 1))
            print(f"   {addr} +{b - a + 1:<4} {name}  {'(preload)' if in_pre else '(finalize/hop)'}")
finally:
    h.close()
