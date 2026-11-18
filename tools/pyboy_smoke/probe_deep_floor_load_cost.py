"""Deep-floor plan Phase 0.3 / 0.4 / 0.5 probe.

0.3 load cost: lobby PCPreloadCave span, fresh PCFinalizeCave span, and the
    player-visible fresh entry (WarpFound2 -> first JoypadOverworld after
    EnterMap), DMG single speed and CGB.
0.4 seam order: the order of LoadDestinationWarpPosition / FGResolveArrival /
    CaveResolveArrival / ProcBossPatchStageSprite / LoadTileBlockMap /
    ProcStageLoadDispatch / PCFinalizeCave on each load, and what identifies
    the source map at the seam.
0.5 same-map warp on PROCEDURAL_CAVE_1: the entrance retargeted at cave warp 0
    and at cave warp 2 (dynamic ladder A). Map unchanged, arrival tile, parity,
    view pointer, cost.

usage (worktree tools/pyboy_smoke): python3 phase0_probe.py [--cgb] [--seed N]
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
CAVE = MAPS["PROCEDURAL_CAVE_1"]
LADDER_BLOCK = 40
TAIL = 81 + 19 * 26 + 20

TRACE = ("LoadDestinationWarpPosition", "FGResolveArrival", "CaveResolveArrival",
         "ProcBossPatchStageSprite", "LoadTileBlockMap", "ProcStageLoadDispatch",
         "PCPreloadCave", "PCFinalizeCave", "ProcGenerationEndDoubleSpeed", "WarpFound2", "EnterMap")

ap = argparse.ArgumentParser()
ap.add_argument("--cgb", action="store_true")
ap.add_argument("--seed", type=int, default=None)
args = ap.parse_args()

h = RedRogueHarness(ROOT, ART, cgb_mode=args.cgb)
events = []
state = {"want_joy": False}


def note(label):
    def cb(_ctx):
        ev = {"l": label, "f": h.pyboy.frame_count, "c": h.cycle_count(),
              "map": h.read8("hCurMap"), "dw": h.read8("wDestinationWarpID"),
              "from": h.read8("wWarpedFromWhichMap"), "last": h.read8("wLastMap"),
              "key1": h.pyboy.memory[0xFF4D]}
        events.append(ev)
        if label == "EnterMap":
            state["want_joy"] = True
    return cb


def joy(_ctx):
    if state["want_joy"]:
        state["want_joy"] = False
        events.append({"l": "JoypadOverworld", "f": h.pyboy.frame_count, "c": h.cycle_count(),
                       "map": h.read8("hCurMap")})


def ladders():
    exit_y, exit_x = h.read_sram_bytes("sProcCaveStagingExitY", 2, bank=0)
    layout = h.read_bytes("wOverworldMap", 601)
    return [(x, y) for y in range(1, 19) for x in range(1, 19)
            if layout[81 + y * 26 + x] == LADDER_BLOCK and (x, y) != (exit_x, exit_y)]


def summarize(tag, evs):
    out = {"tag": tag, "order": [e["l"] for e in evs]}
    def first(label, after=0):
        for i, e in enumerate(evs[after:], after):
            if e["l"] == label:
                return i
        return None
    i_pre = first("PCPreloadCave")
    if i_pre is not None:
        j = first("ProcGenerationEndDoubleSpeed", i_pre)
        out["preload_cycles"] = evs[j]["c"] - evs[i_pre]["c"]
        out["preload_frames"] = evs[j]["f"] - evs[i_pre]["f"]
        out["preload_key1"] = evs[i_pre]["key1"]
    i_fin = first("PCFinalizeCave")
    if i_fin is not None:
        j = first("ProcGenerationEndDoubleSpeed", i_fin)
        out["finalize_cycles"] = evs[j]["c"] - evs[i_fin]["c"]
        out["finalize_frames"] = evs[j]["f"] - evs[i_fin]["f"]
        out["finalize_key1"] = evs[i_fin]["key1"]
    i_w = first("WarpFound2")
    if i_w is not None:
        j = first("JoypadOverworld", i_w)
        if j is not None:
            out["visible_load_frames"] = evs[j]["f"] - evs[i_w]["f"]
    seam = [e for e in evs if e["l"] in ("FGResolveArrival", "CaveResolveArrival")]
    out["seam"] = [{k: e[k] for k in ("l", "map", "dw", "from", "last")} for e in seam]
    print("RESULT", json.dumps(out))


try:
    h.boot_to_lobby(battle_count=11, encounter_kind=4)
    h.write8("wStageEvent", 0)
    if args.seed is not None:
        h.seed_rng((args.seed, args.seed ^ 0xA5, 0, 1))
    for label in TRACE:
        h.register_hook(label, note(label))
    h.register_hook("JoypadOverworld", joy)

    # --- fresh entry (preload in the lobby, then the warp) ---
    h.preload_and_enter_wild_area(CAVE, "cave")
    summarize("fresh_entry", events)
    raw = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 2, bank=0)
    print("LADDERS", json.dumps({"A": raw[TAIL], "B": raw[TAIL + 1], "drawn": ladders()}))
    h.write8("wProcCaveWildBudget", 0)
    base_map = h.read_bytes("wOverworldMap", 601)
    hop = io.BytesIO()
    h.wait_until(lambda: h.read8("wYCoord") == 39, "on the cave entrance", 600)
    h.save_state(hop)

    def self_warp(tag, dest_warp, expect_tile):
        h.load_state(hop)
        events.clear()
        state["want_joy"] = False
        h.write8("wWarpEntries", 39, offset=0)     # re-arm the entrance (disarmed on load)
        h.write8("wWarpEntries", dest_warp, offset=2)
        h.write8("wWarpEntries", CAVE, offset=3)
        h.pyboy.button_press("down")
        try:
            h.wait_until(lambda: any(e["l"] == "WarpFound2" for e in events), "self-warp start", 300)
            h.wait_until(lambda: any(e["l"] == "JoypadOverworld" for e in events), "self-warp settle", 600)
        finally:
            h.pyboy.button_release("down")
        h.tick(60)
        summarize(tag, events)
        pos = (h.read8("wXCoord"), h.read8("wYCoord"))
        parity = (h.read8("wXBlockCoord"), h.read8("wYBlockCoord"))
        ptr = h.read_bytes("wCurrentTileBlockMapViewPointer", 2)
        want_ptr = h.address("wOverworldMap") + 27 + (expect_tile[1] // 2) * 26 + expect_tile[0] // 2
        same = h.read_bytes("wOverworldMap", 601) == base_map
        print("SELFWARP", json.dumps({
            "tag": tag, "map": h.read8("hCurMap"), "pos": pos, "expect": expect_tile,
            "parity": parity, "ptr_ok": ptr == [want_ptr & 255, want_ptr >> 8],
            "map_unchanged": same, "baked": h.read_sram_bytes("sProcCaveBaked", 1, bank=0)[0],
            "warps": h.warp_entries()[:4]}))

    self_warp("self_warp_entrance", 0, (18, 39))
    drawn = ladders()
    if drawn:
        x, y = drawn[0]
        self_warp("self_warp_ladderA", 2, (2 * x + 1, 2 * y + 1))
finally:
    h.close()
