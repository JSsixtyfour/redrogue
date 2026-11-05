"""Does a stage-event pair really seal a Procedural Cemetery floor in play?

The agent plays a real cemetery run with Jessie and James armed. On the hideout floor the
flood check predicts whether the pair cuts off the exit; the agent then shows what happens.
A predicted seal that the agent walks through means the flood check is wrong.

  wsl bash .../witch_probe.sh witch_probe_cem_drive.py [seeds] [jobs]
"""
import json
import multiprocessing
import sys
from pathlib import Path

import autoplay
from audit_stage_hideout_partner import passable_tiles, stage_const
from harness import RedRogueHarness
from source_constants import parse_map_constants
from witch_probe_cem_seal import BASE, ENTRY, EXITS, HEIGHT, STRIDE, WIDTH, flood, touches

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
BUDGET = 90000


def play(seed):
    maps = parse_map_constants(ROOT / "constants/map_constants.asm")
    floors = [maps[f"PROCEDURAL_CEMETERY_{n}"] for n in (1, 2, 3, 4)]
    blockset = (ROOT / "gfx/blocksets/cemetery.bst").read_bytes()
    passable = passable_tiles("Cemetery_Coll")
    h = RedRogueHarness(ROOT, ARTIFACTS)
    row = {"seed": seed}
    try:
        autoplay.boot(h, seed, 73, "VERY_EASY")
        h.write8("wStageEvent", stage_const("STAGE_EVENT_JESSIE_JAMES"))
        h.preload_and_enter_wild_area(floors[0], "Procedural Cemetery 1")
        agent = autoplay.AutoplayAgent(h, seed=seed, player="strong")
        rolled = h.read_sram_bytes("sStageEventHideoutFloor", 1, bank=0)[0]
        row["rolled_floor"] = rolled
        start = h.pyboy.frame_count
        predicted = None
        left = False
        while h.pyboy.frame_count - start < BUDGET and not h.hook_errors and not agent.checks.crash:
            agent.step()
            if not agent.game_world_reads_ready():
                continue
            current = h.read8("hCurMap")
            if rolled in (1, 2, 3) and current == floors[rolled] and predicted is None and agent.mode() == "overworld":
                origin = h.address("wOverworldMap") + BASE
                grid = [[h.pyboy.memory[origin + y * STRIDE + x] for x in range(WIDTH)] for y in range(HEIGHT)]
                walkable = [[blockset[grid[y // 2][x // 2] * 16 + (y % 2 * 2 + 1) * 4 + x % 2 * 2] in passable
                             for x in range(WIDTH * 2)] for y in range(HEIGHT * 2)]
                sprites = agent.sprites()
                pair = {(sprites[s]["x"], sprites[s]["y"]) for s in (2, 3) if s in sprites}
                exit_step = EXITS[rolled]
                free = flood(walkable, ENTRY[rolled], set())
                sealed = flood(walkable, ENTRY[rolled], pair)
                predicted = {"pair": sorted(pair), "free": touches(free, exit_step),
                             "sealed": touches(free, exit_step) and not touches(sealed, exit_step),
                             "frame": h.pyboy.frame_count}
                row["predicted"] = predicted
            if predicted and current == floors[rolled]:
                data1, data2 = h.address("wSpriteStateData1"), h.address("wSpriteStateData2")
                raw = [[slot, h.pyboy.memory[data1 + slot * 16], h.pyboy.memory[data2 + slot * 16 + 5] - 4,
                        h.pyboy.memory[data2 + slot * 16 + 4] - 4, h.pyboy.memory[data1 + slot * 16 + 2],
                        bool(agent.hidden.get(slot, False))] for slot in (2, 3)]
                if raw != row.get("raw_now"):
                    row["raw_now"] = raw
                    row.setdefault("raw_changes", []).append([h.pyboy.frame_count, agent.position(), raw,
                                                              h.read8("wStageEvent"), h.read8("hIsInBattle")])
                sprites = agent.sprites()
                now = sorted((slot, sprites[slot]["x"], sprites[slot]["y"]) for slot in (2, 3) if slot in sprites)
                if now != row.get("pair_now"):
                    row["pair_now"] = now
                    row.setdefault("pair_moves", []).append([h.pyboy.frame_count, agent.position(), now,
                                                             h.read8("wStageEvent"), h.read8("hIsInBattle")])
                spot = agent.position()
                if spot != row.get("spot"):
                    row["spot"] = spot
                    row.setdefault("path", []).append(spot)
            if predicted and current != floors[rolled] and h.read8("hCurMap") != floors[rolled - 1 if rolled else 0]:
                left = True
                row["left_to"] = agent.map_name(current)
                break
        row.update(left_floor=left, frames=h.pyboy.frame_count - start, map=agent.map_name(h.read8("hCurMap")),
                   position=agent.position(), crash=bool(agent.checks.crash), beaten=[h.read8("wStageEvent")],
                   blackouts=agent.report.blackouts, won=agent.report.battles_won)
        if predicted and predicted["sealed"]:
            h.write_failure_artifacts(f"cem_drive_{seed}")
    except Exception as error:
        row["error"] = f"{type(error).__name__}: {error}"[:300]
    finally:
        try:
            h.close()
        except Exception:
            pass
    return row


def main():
    seeds = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    first = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    with multiprocessing.Pool(jobs) as pool:
        rows = pool.map(play, range(first, first + seeds), chunksize=1)
    arrived = [r for r in rows if r.get("predicted")]
    sealed = [r for r in arrived if r["predicted"]["sealed"]]
    open_ = [r for r in arrived if not r["predicted"]["sealed"]]
    print(json.dumps({"seeds": len(rows), "errors": [r for r in rows if "error" in r][:2],
                      "reached_hideout_floor": len(arrived), "predicted_sealed": len(sealed),
                      "predicted_open": len(open_), "open_and_left": sum(1 for r in open_ if r["left_floor"]),
                      "sealed_and_left": sum(1 for r in sealed if r["left_floor"]),
                      "blackouts": sum(1 for r in rows if r.get("blackouts"))}), flush=True)
    for row in sealed:
        print(json.dumps(row, default=str), flush=True)
    for row in [r for r in open_ if not r["left_floor"]][:4]:
        print("OPEN BUT STAYED", json.dumps(row, default=str), flush=True)


if __name__ == "__main__":
    main()
