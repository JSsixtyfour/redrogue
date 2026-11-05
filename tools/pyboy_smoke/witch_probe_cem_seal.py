"""Can the stage-event pair seal a Procedural Cemetery floor?

For floors 2-4 (the only hideout floors), generate the real floor, then stand the pair on the
top row of every block PCemStageHideoutCellOk's block rules accept, and flood from the entrance
stair to the exit. Reports the cell the game actually rolled too.

  wsl bash .../witch_probe.sh witch_probe_cem_seal.py [layouts] [jobs]
"""
import json
import multiprocessing
import random
import sys
from pathlib import Path

from audit_stage_hideout_partner import passable_tiles, stage_const
from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]
WIDTH, HEIGHT, STRIDE, BASE = 10, 9, 16, 51
FLOORS = (14, 54)
ENTRY = {1: (18, 9), 2: (3, 9), 3: (18, 9)}
EXITS = {1: (3, 9), 2: (18, 9), 3: (9, 16)}
EXCLUDED = {1: {(1, 4), (9, 4)}, 2: {(1, 4), (9, 4)}, 3: {(1, 4), (9, 4), (4, 7), (5, 8), (4, 8)}}
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"


def flood(walkable, start, solid):
    seen, stack = set(), [start]
    while stack:
        step = stack.pop()
        if step in seen:
            continue
        seen.add(step)
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            x, y = step[0] + dx, step[1] + dy
            if 0 <= x < WIDTH * 2 and 0 <= y < HEIGHT * 2 and walkable[y][x] and (x, y) not in solid:
                stack.append((x, y))
    return seen


def touches(seen, step):
    x, y = step
    return step in seen or any((x + dx, y + dy) in seen for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)))


def measure(seed):
    maps = parse_map_constants(ROOT / "constants/map_constants.asm")
    blockset = (ROOT / "gfx/blocksets/cemetery.bst").read_bytes()
    passable = passable_tiles("Cemetery_Coll")
    h = RedRogueHarness(ROOT, ARTIFACTS)
    rows = []
    try:
        h.boot_to_lobby()
        rng = random.Random(seed)
        for offset in range(10):
            h.write8("wRandomTable", rng.randrange(1, 256), offset=offset)
        h.write8("wStageEvent", stage_const("STAGE_EVENT_JESSIE_JAMES") | (1 << stage_const("STAGE_EVENT_PHASE_SHIFT")))
        h.preload_and_enter_wild_area(maps["PROCEDURAL_CEMETERY_1"], "Procedural Cemetery 1")
        h.tick(60)
        rolled = h.read_sram_bytes("sStageEventHideoutFloor", 1, bank=0)[0]
        for index in (1, 2, 3):
            h.park_before_hijack()
            h.write8("hCurMap", maps[f"PROCEDURAL_CEMETERY_{index + 1}"])
            h.call_routine("PCemFinalizeMap", limit=200000)
            origin = h.address("wOverworldMap") + BASE
            grid = [[h.pyboy.memory[origin + y * STRIDE + x] for x in range(WIDTH)] for y in range(HEIGHT)]
            walkable = [[blockset[grid[y // 2][x // 2] * 16 + (y % 2 * 2 + 1) * 4 + x % 2 * 2] in passable
                         for x in range(WIDTH * 2)] for y in range(HEIGHT * 2)]
            free = flood(walkable, ENTRY[index], set())
            ok_exit = touches(free, EXITS[index])
            candidates, cuts, loses = 0, [], 0
            for by in range(HEIGHT):
                for bx in range(WIDTH):
                    if grid[by][bx] not in FLOORS or (bx, by) in EXCLUDED[index]:
                        continue
                    solid = {(bx * 2, by * 2), (bx * 2 + 1, by * 2)}
                    candidates += 1
                    seen = flood(walkable, ENTRY[index], solid)
                    if ok_exit and not touches(seen, EXITS[index]):
                        cuts.append((bx, by))
                    elif len(free - solid - seen) > 0:
                        loses += 1
            cell = None
            if rolled == index:
                cell = tuple(h.read_sram_bytes("sStageEventHideoutX", 1, bank=0)
                             + h.read_sram_bytes("sStageEventHideoutY", 1, bank=0))
            rows.append({"seed": seed, "index": index, "exit_reachable": ok_exit, "candidates": candidates,
                         "cuts": cuts, "only_floor_lost": loses, "rolled_cell": cell,
                         "rolled_seals": cell in [tuple(c) for c in cuts] if cell else False,
                         "tiles_walkable": sum(map(sum, walkable))})
    except Exception as error:
        rows.append({"seed": seed, "error": str(error)[:200]})
    finally:
        try:
            h.close()
        except Exception:
            pass
    return rows


def main():
    layouts = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    with multiprocessing.Pool(jobs) as pool:
        rows = [r for batch in pool.map(measure, range(layouts), chunksize=1) for r in batch]
    errors = [r for r in rows if "error" in r]
    rows = [r for r in rows if "error" not in r]
    distinct = len({(r["index"], r["tiles_walkable"], tuple(map(tuple, r["cuts"]))) for r in rows})
    candidates = sum(r["candidates"] for r in rows)
    cuts = sum(len(r["cuts"]) for r in rows)
    print(json.dumps({"floors": len(rows), "errors": len(errors), "first_error": errors[0] if errors else None,
                      "roughly_distinct": distinct, "floors_exit_unreachable_even_free":
                      sum(1 for r in rows if not r["exit_reachable"]), "candidates": candidates,
                      "would_cut_exit": cuts, "would_only_lose_floor": sum(r["only_floor_lost"] for r in rows),
                      "floors_with_any_cut": sum(1 for r in rows if r["cuts"]),
                      "rolled_cells": sum(1 for r in rows if r["rolled_cell"]),
                      "rolled_cells_sealing": sum(1 for r in rows if r["rolled_seals"]),
                      "rolled_with_no_hideout": sum(1 for r in rows if r["rolled_cell"] == (255, 255)),
                      "examples": [r for r in rows if r["cuts"]][:3]}), flush=True)


if __name__ == "__main__":
    main()
