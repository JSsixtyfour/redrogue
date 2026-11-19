"""Deep-floor plan Phase 6 (Facility) Phase 0.3-0.6, one probe (from the Forest's).

0.3 load cost: lobby PFacPreload span, fresh PFacFinalize span, visible fresh
    entry (WarpFound2 -> first JoypadOverworld after EnterMap), an ordinary
    self-warp hop, and a regen hop (PFacPreload in place, then the hop: the
    nearest stand-in for a first descent); DMG single speed or CGB (--cgb).
0.4 seam order: the arrival seam routines on each load, the source map there,
    and every FollowerPrepareMap with the player's coordinates at that moment
    (the 2026-11-18 Forest follower bug: an InitMapSprites before the arrival
    is placed strands slot 15).
0.5 same-map warp: the Facility's warp 0 aimed at itself, scripted-warp path.
0.6 regen diff: every byte the second generation writes that an ordinary hop
    does not, by nearest symbol: the per-floor state a floor-2 swap must cover.

usage (worktree tools/pyboy_smoke): python3 probe_facility_deep_phase0.py [--cgb] [--seed N]
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
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
FAC = MAPS["PROCEDURAL_FACILITY"]
MAP_BYTES = 601

TRACE = ("LoadDestinationWarpPosition", "FGResolveArrival", "PFacResolveArrival",
         "ProcBossPatchStageSprite", "InitMapSprites", "FollowerPrepareMap", "LoadTileBlockMap",
         "ProcStageLoadDispatch", "PFacPreload", "PFacFinalize", "ProcGenerationEndDoubleSpeed",
         "WarpFound2", "EnterMap")

ap = argparse.ArgumentParser()
ap.add_argument("--cgb", action="store_true")
ap.add_argument("--seed", type=int, default=None)
args = ap.parse_args()

h = RedRogueHarness(ROOT, ART, cgb_mode=args.cgb)
events = []
state = {"want_joy": False, "on": True}


def note(label):
    def cb(_ctx):
        if not state["on"]:
            return
        events.append({"l": label, "f": h.pyboy.frame_count, "c": h.cycle_count(),
                       "map": h.read8("hCurMap"), "dw": h.read8("wDestinationWarpID"),
                       "from": h.read8("wWarpedFromWhichMap"), "last": h.read8("wLastMap"),
                       "yx": (h.read8("wYCoord"), h.read8("wXCoord")),
                       "key1": h.pyboy.memory[0xFF4D]})
        if label == "EnterMap":
            state["want_joy"] = True
    return cb


def joy(_ctx):
    if state["on"] and state["want_joy"]:
        state["want_joy"] = False
        events.append({"l": "JoypadOverworld", "f": h.pyboy.frame_count, "c": h.cycle_count(),
                       "map": h.read8("hCurMap"), "yx": (h.read8("wYCoord"), h.read8("wXCoord"))})


def span(evs, start_label, end_label="ProcGenerationEndDoubleSpeed"):
    for i, e in enumerate(evs):
        if e["l"] == start_label:
            for f in evs[i:]:
                if f["l"] == end_label:
                    return {"cycles": f["c"] - e["c"], "frames": f["f"] - e["f"], "key1": e["key1"]}
    return None


def summarize(tag, evs):
    out = {"tag": tag, "order": [e["l"] for e in evs if e["l"] not in ("WarpFound2", "EnterMap")]}
    out["preload"] = span(evs, "PFacPreload")
    out["finalize"] = span(evs, "PFacFinalize")
    w = next((i for i, e in enumerate(evs) if e["l"] == "WarpFound2"), None)
    if w is not None:
        j = next((i for i, e in enumerate(evs[w:], w) if e["l"] == "JoypadOverworld"), None)
        if j is not None:
            out["visible_load_frames"] = evs[j]["f"] - evs[w]["f"]
            out["arrival_yx"] = evs[j]["yx"]
    out["seam"] = [{k: e[k] for k in ("l", "map", "dw", "from", "last")}
                   for e in evs if e["l"] == "FGResolveArrival"]
    out["follower_prepare_yx"] = [e["yx"] for e in evs if e["l"] == "FollowerPrepareMap"]
    print("RESULT", json.dumps(out))


def hop(entrance):
    """A same-map warp to the Facility's warp 0, by the engine's scripted-warp
    path (BIT_WARP_FROM_CUR_SCRIPT -> WarpFound2); from WarpFound2 on, the load
    is the one a real pad warp takes."""
    h.write8("hWarpDestinationMap", FAC)
    h.write8("wDestinationWarpID", 0)
    h.write8("wStatusFlags3", h.read8("wStatusFlags3") | 1 << 3)   # BIT_WARP_FROM_CUR_SCRIPT
    seen = h.hook_flag("WarpFound2")
    h.wait_until(lambda: seen["count"] > 0, "the self-warp", 300)
    h.wait_until(lambda: h.read8("hCurMap") == FAC and (h.read8("wYCoord"), h.read8("wXCoord")) == entrance
                 and h.read8("hJoyIgnore") == 0, "back on the entrance", 1500)
    h.tick(120)


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


def spans(offsets):
    out = []
    for o in sorted(offsets):
        if out and o <= out[-1][1] + 1:
            out[-1][1] = o
        else:
            out.append([o, o])
    return out


def label(region, offset):
    bank, base = BASES[region]
    try:
        name = h.symbols.nearest(0 if region in ("wram", "hram") else bank, base + offset)
    except Exception:
        name = None
    return f"{base + offset:04x}", name


try:
    h.boot_to_lobby(battle_count=11, encounter_kind=4)
    h.write8("wStageEvent", 0)
    if args.seed is not None:
        h.seed_rng((args.seed, args.seed ^ 0xA5, 0, 1))
    for name in TRACE:
        try:
            h.register_hook(name, note(name))
        except Exception as e:
            print("NOHOOK", name, e)
    h.register_hook("JoypadOverworld", joy)

    h.preload_and_enter_wild_area(FAC, "facility")
    summarize("fresh_entry", events)
    h.wait_until(lambda: h.read8("hJoyIgnore") == 0, "settled", 900)
    h.tick(60)
    entrance = (h.read8("wYCoord"), h.read8("wXCoord"))
    print("ENTRANCE", entrance)
    base_map = h.read_bytes("wOverworldMap", MAP_BYTES)
    settled = io.BytesIO()
    h.save_state(settled)

    events.clear()
    hop(entrance)
    summarize("self_warp", events)
    print("SELFWARP", json.dumps({
        "map": h.read8("hCurMap"), "pos": (h.read8("wYCoord"), h.read8("wXCoord")),
        "map_unchanged": h.read_bytes("wOverworldMap", MAP_BYTES) == base_map,
        "baked": h.read_sram_bytes("sProcFacilityBaked", 1)[0]}))

    state["on"] = False
    h.load_state(settled)
    s0 = snap()
    hop(entrance)
    control = changed(s0, snap())
    h.load_state(settled)
    s0b = snap()
    state["on"] = True
    events.clear()
    h.park_before_hijack()
    h.call_routine("PFacPreload", limit=400000)
    pre = changed(s0b, snap())
    print("PRELOAD_IN_PLACE", json.dumps(span(list(events), "PFacPreload")))
    events.clear()
    hop(entrance)
    summarize("regen_hop", events)
    total = changed(s0b, snap())
    print("REGEN_MAP_CHANGED", h.read_bytes("wOverworldMap", MAP_BYTES) != base_map)
    for region in BASES:
        only = total[region] - control[region]
        print(f"== {region}: regen-only {len(only)} B, preload {len(pre[region])} B, control hop {len(control[region])} B")
        for a, b in spans(only):
            addr, name = label(region, a)
            where = "(preload)" if any(o in pre[region] for o in range(a, b + 1)) else "(finalize/hop)"
            print(f"   {addr} +{b - a + 1:<4} {name}  {where}")
finally:
    h.close()
