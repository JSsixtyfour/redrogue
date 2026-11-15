"""CODEBASE_SCAN_PLAN 2.2: wild-area load time through the real lobby door.

Per sample: lobby baseline -> tick k frames (varies the RNG) -> the ROM's own
lobby preload call (ProcPreloadAssignedWildArea, at a lobby-script boundary)
-> walk through door 1. Load = WarpFound2 -> first JoypadOverworld after the
EnterMap of the wild map. Finalizer hooks show which generator phases still
run on entry rather than in the preload.

Measured 2026-11-14 on 15ef8134 (CODEBASE_SCAN_PLAN_2026-11-14 2.2): cave 66,
forest 60, cemetery 48, facility 74 frames median. Not a test: smoke only
collects test_*.py. Pin the ROM (isolated build) when comparing two variants.

usage: python3 tools/pyboy_smoke/measure_wild_door_loads.py [samples] [cgb|dmg]
"""
from __future__ import annotations

import io
import json
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SAMPLES = int(sys.argv[1]) if len(sys.argv) > 1 else 10
CGB = (sys.argv[2] if len(sys.argv) > 2 else "cgb") == "cgb"
sys.path.insert(0, str(ROOT / "tools/pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
TYPES = {"cave": "PROCEDURAL_CAVE_1", "forest": "PROCEDURAL_FOREST",
         "cemetery": "PROCEDURAL_CEMETERY_1", "facility": "PROCEDURAL_FACILITY"}
PHASES = ["ProcPreloadAssignedWildArea", "PCFinalizeCave", "PCAutotilePass",
          "PFinalizeForest", "PFHuntAndKill", "PFacFinalize", "PCemFinalizeMap"]
MARKS = ["WarpFound2", "EnterMap", "JoypadOverworld", "RunMapScript.return"]


def main() -> None:
    results = {}
    for kind, map_name in TYPES.items():
        map_id = MAPS[map_name]
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts", cgb_mode=CGB)
        try:
            h.boot_to_lobby(encounter_kind=4, wild_type=kind)
            events: list[tuple[str, int]] = []
            for label in PHASES + MARKS:
                h.register_hook(label, lambda _c, label=label:
                                events.append((label, h.pyboy.frame_count)))
            h.tick(30)
            baseline = io.BytesIO()
            h.save_state(baseline)
            samples = []
            for i in range(SAMPLES):
                h.load_state(baseline)
                h.tick(1 + i * 7)
                events.clear()
                h.preload_and_enter_wild_area(map_id, kind)
                h.tick(120)
                samples.append(analyse(events, h))
            results[kind] = samples
        finally:
            h.close()
    report(results)


def analyse(events, h) -> dict:
    labels = [e[0] for e in events]
    # preload span: first preload entry -> the RunMapScript.return after it
    pre_start = next((f for l, f in events if l == "ProcPreloadAssignedWildArea"), None)
    pre_end = next((f for l, f in events
                    if l == "RunMapScript.return" and pre_start is not None and f >= pre_start), None)
    # entry span: last WarpFound2 that is followed by EnterMap, then first JoypadOverworld after it
    warp_idx = max(i for i, l in enumerate(labels) if l == "WarpFound2")
    enter_idx = next(i for i in range(warp_idx, len(events)) if labels[i] == "EnterMap")
    joy_idx = next(i for i in range(enter_idx, len(events)) if labels[i] == "JoypadOverworld")
    warp_f, enter_f, joy_f = events[warp_idx][1], events[enter_idx][1], events[joy_idx][1]
    on_entry = sorted({l for l, f in events[warp_idx:joy_idx + 1] if l in PHASES})
    in_preload = sorted({l for l, f in events[:warp_idx] if l in PHASES})
    return {
        "load": joy_f - warp_f, "fade_to_entermap": enter_f - warp_f,
        "entermap_to_control": joy_f - enter_f,
        "preload_frames": None if pre_end is None else pre_end - pre_start,
        "phases_on_entry": on_entry, "phases_in_preload": in_preload,
        "map": h.read8("hCurMap"),
        "phase_start_after_entermap": {l: f - enter_f for l, f in reversed(events[enter_idx:joy_idx + 1]) if l in PHASES},
    }


def report(results) -> None:
    print(f"mode={'CGB' if CGB else 'DMG'} samples={SAMPLES}")
    print(f"{'type':9} {'load med':>8} {'min':>4} {'max':>4} {'warp->EnterMap':>14} "
          f"{'EnterMap->ctl':>13} {'preload med/max':>16}  phases on entry | in preload")
    for kind, s in results.items():
        loads = [x["load"] for x in s]
        pre = [x["preload_frames"] for x in s if x["preload_frames"] is not None]
        print(f"{kind:9} {statistics.median(loads):8.0f} {min(loads):4} {max(loads):4} "
              f"{statistics.median(x['fade_to_entermap'] for x in s):14.0f} "
              f"{statistics.median(x['entermap_to_control'] for x in s):13.0f} "
              f"{(str(statistics.median(pre)) + '/' + str(max(pre))) if pre else 'n/a':>16}  "
              f"{sorted({p for x in s for p in x['phases_on_entry']})} | "
              f"{sorted({p for x in s for p in x['phases_in_preload']})}")
    for kind, s in results.items():
        offs = {}
        for x in s:
            for l, o in x["phase_start_after_entermap"].items():
                offs.setdefault(l, []).append(o)
        print(kind, {l: (min(v), max(v), len(v)) for l, v in offs.items()},
              "loads", [x["load"] for x in s])


if __name__ == "__main__":
    main()
