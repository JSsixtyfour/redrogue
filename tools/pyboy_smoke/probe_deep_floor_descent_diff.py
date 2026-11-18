"""Deep floor S3 measurement: every byte a REAL first descent changes that an
ordinary same-map hop does not. Snapshot WRAM/HRAM/SRAM 0-3 on floor 1's ladder A;
(control) hop onto ladder A again through the entrance and diff; (descent) from
the same state, down ladder A to a freshly generated floor 2 and diff.
Labels each changed span with the nearest symbol.

usage (worktree tools/pyboy_smoke): python3 probe_deep_floor_descent_diff.py [--cgb]
"""
import argparse
import io
import sys

sys.path.insert(0, ".")
import test_cave_deep_floor as T  # noqa: E402
from harness import RedRogueHarness  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--cgb", action="store_true")
args = ap.parse_args()

BASES = {"wram": (0, 0xC000, 0x2000), "hram": (0, 0xFF80, 0x7F)}
for b in range(4):
    BASES[f"sram{b}"] = (b, 0xA000, 0x2000)


def snap(h):
    m = h.pyboy.memory
    out = {"wram": bytes(m[0xC000:0xE000]), "hram": bytes(m[0xFF80:0xFFFF])}
    for b in range(4):
        out[f"sram{b}"] = bytes(m[b, 0xA000:0xBFFF]) + bytes([m[b, 0xBFFF]])
    return out


def changed(a, b):
    return {k: {i for i in range(len(a[k])) if a[k][i] != b[k][i]} for k in a}


def spans(offsets):
    out = []
    for o in sorted(offsets):
        if out and o <= out[-1][1] + 1:
            out[-1][1] = o
        else:
            out.append([o, o])
    return out


class Probe(T.CaveDeepFloorTest):
    def runTest(self):
        pass


t = Probe()
t.h = RedRogueHarness(T.ROOT, T.ARTIFACTS, cgb_mode=args.cgb)
h = t.h
try:
    t.deep_cave()
    base = io.BytesIO()
    h.save_state(base)
    s0 = snap(h)
    # Control: off the ladder and back on, aimed at the subroom ladder's own
    # destination replaced by cave warp 2 (a same-map hop that is no way down).
    t.ladder_warp(2, 2)
    control = changed(s0, snap(h))
    h.load_state(base)
    s0b = snap(h)
    t.ladder_warp(2, 0)
    descent = changed(s0b, snap(h))
    skip_names = ("wOverworldMap", "wTileMap", "wShadowOAM", "wTempPic", "wSurroundingTiles",
                  "wTileMapBackup", "wSprite", "wSpriteState", "wChannel", "wStack", "wEndlessDebugOverride")
    for region, (bank, base_addr, _n) in BASES.items():
        only = descent[region] - control[region]
        print(f"== {region}: descent-only {len(only)} B (control hop {len(control[region])} B)")
        for a, b in spans(only):
            addr = base_addr + a
            try:
                name = h.symbols.nearest(0 if region in ("wram", "hram") else bank, addr)
            except Exception:
                name = None
            if region == "wram" and name and name.startswith(skip_names):
                continue
            print(f"   {addr:04x} +{b - a + 1:<4} {name}")
finally:
    h.close()
