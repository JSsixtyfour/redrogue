"""Where a Facility warp's frames go (measurement only, nothing changed).

Trips, each from WarpFound2 to the first JoypadOverworld after EnterMap (the
player-visible load, reference_load_time_measurement), on a deep Facility:
  pad      an ordinary warp pad on floor 1 (another pad on the same map)
  down 1   the first descent to floor 2 (generates it)
  up       floor 2 back to floor 1
  down 2   the second descent (floor 2 already made)
  pad 2    an ordinary pad on floor 2

Each trip is broken into segments between the load path's labels. Real frames
come from cycles: 70224 per frame at single speed, 140448 inside a double-speed
span (FACILITY_LOAD_TIME_2026-11-10.md, "Unit conversion"), judged by KEY1 at
the segment's start.

usage (worktree tools/pyboy_smoke): python3 probe_facility_warp_time.py [--cgb] [--repeat N]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_facility_deep_floor as deep  # noqa: E402
from harness import RedRogueHarness  # noqa: E402

MILESTONES = ["WarpFound2", "FacilityDeepSeam", "EnterMap", "LoadMapData", "ProcBossPatchStageSprite",
              "InitMapSprites", "LoadTileBlockMap", "ProcStageLoadDispatch", "PFacFinalize",
              "ProcGenerationEndDoubleSpeed", "FacilityDeepAfterFinalize",
              "LoadTilesetTilePatternData", "LoadCurrentMapView", "_LeaveMapAnim", "EnterMapAnim",
              "PlayerSpinWhileMovingUpOrDown", "PlayerSpinInPlace", "JoypadOverworld"]

ap = argparse.ArgumentParser()
ap.add_argument("--cgb", action="store_true")
ap.add_argument("--repeat", type=int, default=3, help="Facilities (different lobbies) to average over")
args = ap.parse_args()

results: dict[str, list[dict]] = {}


def run_one(n: int) -> None:
    t = deep.FacilityDeepFloorTest("test_lobby_decides_and_the_default_is_ordinary")
    t.h = RedRogueHarness(deep.ROOT, deep.ARTIFACTS, cgb_mode=args.cgb)
    t.h.allow_deep_facility_floor = True
    h = t.h
    events: list[tuple[str, int, int, bool]] = []
    armed = {"on": False}

    def mark(label):
        def cb(_ctx):
            if label == "WarpFound2":
                events.clear()
                armed["on"] = True
            if armed["on"]:
                events.append((label, h.pyboy.frame_count, h.cycle_count(),
                               bool(h.pyboy.memory[0xFF4D] & 0x80)))
        return cb

    try:
        h.boot_to_lobby(battle_count=11 + n, encounter_kind=4)
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(deep.FAC, "facility")
        h.wait_until(lambda: h.read8("hJoyIgnore") == 0, "settled", 900)
        h.tick(60)
        h.write8("wProcFacilityWildBudget", 0)
        for m in MILESTONES:
            h.register_hook(m, mark(m))

        def finish(name: str) -> None:
            armed["on"] = False
            try:
                w = next(i for i, e in enumerate(events) if e[0] == "EnterMap")
                j = next(i for i, e in enumerate(events) if e[0] == "JoypadOverworld" and i > w)
            except StopIteration:
                print("incomplete trace for", name, [e[0] for e in events])
                return
            evs = events[:j + 1]
            segs = []
            for a, b in zip(evs, evs[1:]):
                real = (b[2] - a[2]) / (140448 if a[3] else 70224)
                segs.append((f"{a[0]} -> {b[0]}", real))
            results.setdefault(name, []).append({
                "visible_frames": evs[-1][1] - evs[0][1],
                "real_frames": sum(s[1] for s in segs),
                "segments": segs})

        def pad_hop(name: str) -> None:
            pad = t.subroom_pad()
            entries = h.warp_entries()
            pick = next(i for i in range(deep.FIRST_PAD, deep.FIRST_PAD + deep.NUM_PAD_SITES)
                        if i != deep.FIRST_PAD + pad and entries[i][3] == deep.FAC and entries[i][0] != 0xFF)
            script = h.hook_flag("ProceduralFacility_Script")
            h.wait_until(lambda: script["count"] > 0, f"{name}: script", 300)
            h.write8("hWarpDestinationMap", deep.FAC)
            h.write8("wDestinationWarpID", entries[pick][2])
            h.write8("wStatusFlags3", h.read8("wStatusFlags3") | 1 << 3)
            joy = h.hook_flag("JoypadOverworld")
            h.wait_until(lambda: armed["on"], f"{name}: the warp", 300)
            h.wait_until(lambda: any(e[0] == "EnterMap" for e in events) and joy["count"] > 0
                         and events[-1][0] == "JoypadOverworld", f"{name}: control back", 1500)
            finish(name)
            h.tick(120)
            h.write8("wProcFacilityWildBudget", 0)

        def trip(name: str) -> None:
            t.trip(name)
            finish(name)

        pad_hop("pad (floor 1)")
        trip("down 1 (generates floor 2)")
        trip("up (floor 2 -> 1)")
        trip("down 2 (floor 2 made)")
        pad_hop("pad (floor 2)")
    finally:
        h.close()


for n in range(args.repeat):
    run_one(n)

print("hardware", "CGB" if args.cgb else "DMG", "facilities", args.repeat)
for name, runs in results.items():
    vis = [r["visible_frames"] for r in runs]
    real = [round(r["real_frames"], 1) for r in runs]
    print(f"\n== {name}: visible frames {vis}, real frames {real}")
    agg: dict[str, list[float]] = {}
    for r in runs:
        seen = {}
        for label, f in r["segments"]:
            seen[label] = seen.get(label, 0) + f
        for label, f in seen.items():
            agg.setdefault(label, []).append(f)
    for label, fs in sorted(agg.items(), key=lambda kv: -sum(kv[1]) / len(kv[1])):
        mean = sum(fs) / len(fs)
        if mean >= 0.5:
            print(f"   {mean:6.1f}  {label}")
out = deep.ARTIFACTS / f"facility_warp_time_{'cgb' if args.cgb else 'dmg'}.json"
out.write_text(json.dumps(results, indent=1))
print("\nraw:", out)
