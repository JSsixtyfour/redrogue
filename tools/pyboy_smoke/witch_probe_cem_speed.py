"""What the cemetery hideout rule costs: emulated cycles for the placement scan, and frames from the
warp to the first input poll for each floor load. Run once per snapshot and compare.

  WITCH_SNAPSHOT=<id> wsl bash .../witch_probe.sh witch_probe_cem_speed.py [seeds] [jobs]
"""
import json
import multiprocessing
import statistics
import sys
from pathlib import Path

import autoplay
from audit_stage_hideout_partner import stage_const
from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
BUDGET = 60000


def play(seed):
    maps = parse_map_constants(ROOT / "constants/map_constants.asm")
    floors = {maps[f"PROCEDURAL_CEMETERY_{n}"]: n - 1 for n in (1, 2, 3, 4)}
    h = RedRogueHarness(ROOT, ARTIFACTS)
    row = {"seed": seed, "scan_cycles": [], "loads": []}
    try:
        autoplay.boot(h, seed, 73, "VERY_EASY")
        h.write8("wStageEvent", stage_const("STAGE_EVENT_JESSIE_JAMES"))
        h.preload_and_enter_wild_area(min(floors), "Procedural Cemetery 1")
        agent = autoplay.AutoplayAgent(h, seed=seed, player="strong")
        row["rolled"] = h.read_sram_bytes("sStageEventHideoutFloor", 1, bank=0)[0]
        state = {"scan": None, "warp": None, "seen": set()}

        def scan_start(_context):
            state["scan"] = h.cycle_count()

        def scan_found(_context):
            if state["scan"] is not None:
                row["scan_cycles"].append(h.cycle_count() - state["scan"])
                state["scan"] = None

        def warp(_context):
            state["warp"] = h.pyboy.frame_count

        h.register_hook("PCemPickStageHideoutCell.scan", scan_start)
        h.register_hook("PCemPickStageHideoutCell.found", scan_found)
        h.register_hook("WarpFound2", warp)
        start = h.pyboy.frame_count
        while h.pyboy.frame_count - start < BUDGET and not agent.checks.crash and not h.hook_errors:
            agent.step()
            if not agent.game_world_reads_ready():
                continue
            current = h.read8("hCurMap")
            if state["warp"] is not None and agent.last_overworld_frame > state["warp"] and current in floors:
                index = floors[current]
                row["loads"].append({"floor": index, "first": index not in state["seen"],
                                     "hideout_floor": index == row["rolled"],
                                     "frames": agent.last_overworld_frame - state["warp"]})
                state["seen"].add(index)
                state["warp"] = None
            if current == maps["INDIGO_PLATEAU_LOBBY"]:
                break
    except Exception as error:
        row["error"] = f"{type(error).__name__}: {error}"[:200]
    finally:
        try:
            h.close()
        except Exception:
            pass
    return row


def spread(values):
    if not values:
        return None
    ordered = sorted(values)
    return {"n": len(values), "mean": round(statistics.mean(values), 1), "median": statistics.median(values),
            "p90": ordered[int(len(ordered) * 0.9)], "max": ordered[-1]}


def main():
    seeds = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    with multiprocessing.Pool(jobs) as pool:
        rows = pool.map(play, range(1, seeds + 1), chunksize=1)
    loads = [load for row in rows for load in row["loads"]]
    print(json.dumps({"snapshot": sys.argv[1].rstrip("/").split("/")[-1], "errors": [r["error"] for r in rows if "error" in r][:2],
                      "scan_cycles": spread([c for r in rows for c in r["scan_cycles"]]),
                      "hideout_floor_first_load_frames": spread([l["frames"] for l in loads if l["first"] and l["hideout_floor"]]),
                      "other_floor_first_load_frames": spread([l["frames"] for l in loads if l["first"] and not l["hideout_floor"]]),
                      "repeat_load_frames": spread([l["frames"] for l in loads if not l["first"]])}), flush=True)


if __name__ == "__main__":
    main()
