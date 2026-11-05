"""Audit: a stage-event NPC standing at its hideout must not seal the way to the exit.

The pair stays standing after defeat, so a hand-over that found no room can be retried
(StageEventKeepSpriteOnDefeat). NPCs are solid. audit_stage_hideout_partner.py proves
the pair can be walked up to; it never asks whether the rest of the map is still reachable
with them there.

Measured by flood fill from the spawn over the engine's collision model, following warp
pads into the same map. A layout is SEALED when an exit is reachable with the NPCs ignored
and not reachable with them solid. Arrow tiles count as plain floor, which can only hide a
sealed layout, never invent one.

The rolled hideout alone is a weak test: most rolls land in open floor. --exhaustive also
stands the pair on every plain-floor block of each layout, which is the positive control
(it must find sealing blocks) and shows what a selection rule has to reject.

Self-check: a layout whose exit cannot be reached even with the NPCs ignored is counted as
"no exit in the model" and not as sealed.

Usage:
    python3 tools/pyboy_smoke/audit_stage_pair_blocks_exit.py [--layouts N] [--areas facility,forest,cave]
                                                              [--jobs N] [--exhaustive]
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import multiprocessing
import random
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from audit_stage_hideout_partner import (ARTIFACTS, AREAS, HIDEOUT_SRAM_BANK, GRID_BASE, GRID_SIZE, GRID_STRIDE,  # noqa: E402
                                         RNG_STATE_BYTES, STAGE_EVENT_NO_HIDEOUT, STEP_SIZE, passable_tiles,
                                         stage_const, walkable_grid)
from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

PFAC_FLOOR = 14  # procedural_facility_gen.asm


def flood(walkable, start, pads, solid) -> set:
    seen, stack = set(), [start]
    while stack:
        step = stack.pop()
        if step in seen:
            continue
        seen.add(step)
        if step in pads and pads[step] not in seen:
            stack.append(pads[step])
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nx, ny = step[0] + dx, step[1] + dy
            if 0 <= nx < STEP_SIZE and 0 <= ny < STEP_SIZE and walkable[ny][nx] and (nx, ny) not in solid:
                stack.append((nx, ny))
    return seen


def touches(seen, step) -> bool:
    x, y = step
    return step in seen or any((x + dx, y + dy) in seen for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)))


def around(grid, bx, by) -> list:
    """The 3x3 of block ids centred on (bx, by), -1 off the grid."""
    return [[grid[y][x] if 0 <= x < GRID_SIZE and 0 <= y < GRID_SIZE else -1 for x in (bx - 1, bx, bx + 1)]
            for y in (by - 1, by, by + 1)]


def measure(job):
    area, seed, exhaustive = job
    map_name, entry_name, blockset_name, coll_label, base_slot, sprite_slots = AREAS[area]
    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")[map_name]
    blockset = (REPO_ROOT / "gfx" / "blocksets" / blockset_name).read_bytes()
    passable = passable_tiles(coll_label)
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        rng = random.Random(seed)
        base = h.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            h.pyboy.memory[base + offset] = rng.randrange(1, 256)
        h.write8("wStageEvent", stage_const("STAGE_EVENT_JESSIE_JAMES") | (1 << stage_const("STAGE_EVENT_PHASE_SHIFT")))
        h.preload_and_enter_wild_area(map_id, entry_name)
        origin = h.address("wOverworldMap") + GRID_BASE
        grid = [[h.pyboy.memory[origin + y * GRID_STRIDE + x] for x in range(GRID_SIZE)] for y in range(GRID_SIZE)]
        player = (h.read8("wXCoord"), h.read8("wYCoord"))
        sprites = [tuple(p) for p in h.sprite_positions(sprite_slots)]
        hideout = h.read_sram_bytes("sStageEventHideoutX", 1, bank=HIDEOUT_SRAM_BANK)[0]
        hideout_y = h.read_sram_bytes("sStageEventHideoutY", 1, bank=HIDEOUT_SRAM_BANK)[0]
        warps = list(h.warp_entries())
    finally:
        try:
            h.close()
        except Exception:
            pass
    row = {"area": area, "seed": seed, "layout": hashlib.sha1(bytes(b for r in grid for b in r)).hexdigest()[:10],
           "hideout": (hideout, hideout_y)}
    if hideout == STAGE_EVENT_NO_HIDEOUT:
        row["result"] = "no_hideout"
        return row
    walkable = walkable_grid(grid, blockset, passable)
    in_grid = [(i, (x, y), target, dest) for i, (y, x, target, dest) in enumerate(warps)
               if x < STEP_SIZE and y < STEP_SIZE]
    by_index = {i + 1: step for i, step, _, _ in in_grid}
    pads = {step: by_index[target] for _, step, target, dest in in_grid if dest == map_id and target in by_index}
    exits = [step for _, step, _, dest in in_grid
             if dest != map_id and abs(step[0] - player[0]) + abs(step[1] - player[1]) > 2]
    leader, partner = sprites[base_slot - 1][::-1], sprites[base_slot][::-1]
    free = flood(walkable, player, pads, set())
    pair = flood(walkable, player, pads, {leader, partner})
    single = flood(walkable, player, pads, {leader})
    reachable = [step for step in exits if touches(free, step)]
    row.update(leader=leader, partner=partner, exits=exits, player=player, lost_floor=len(free) - len(pair))
    if not reachable:
        row["result"] = "no_exit_in_model"
    elif not any(touches(pair, step) for step in reachable):
        row["result"] = "sealed_by_pair"
    else:
        row["result"] = "open"
    row["sealed_by_leader_alone"] = bool(reachable) and not any(touches(single, step) for step in reachable)
    if exhaustive and reachable:
        candidates, sealing = 0, []
        for by in range(GRID_SIZE):
            for bx in range(GRID_SIZE):
                if grid[by][bx] != PFAC_FLOOR:
                    continue
                solid = {(bx * 2, by * 2), (bx * 2 + 1, by * 2)}
                if player in solid:
                    continue
                candidates += 1
                seen = flood(walkable, player, pads, solid)
                lost = len(free) - len(seen)
                cut = not any(touches(seen, step) for step in reachable)
                if cut or lost > 2:
                    sealing.append({"block": (bx, by), "exit_cut": cut, "floor_lost": lost,
                                    "around": around(grid, bx, by)})
        row.update(floor_blocks=candidates, sealing=sealing)
    return row


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=64)
    parser.add_argument("--areas", default="facility,forest,cave")
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--exhaustive", action="store_true")
    args = parser.parse_args()
    failed = 0
    for area in [a.strip() for a in args.areas.split(",") if a.strip()]:
        with multiprocessing.Pool(args.jobs) as pool:
            rows = pool.map(measure, [(area, seed, args.exhaustive) for seed in range(args.layouts)], chunksize=1)
        counts = collections.Counter(row["result"] for row in rows)
        sealed = [r for r in rows if r["result"] == "sealed_by_pair"]
        alone = [r for r in rows if r.get("sealed_by_leader_alone")]
        failed += len(sealed) + len(alone)
        print(f"{area}: {args.layouts} layouts, {len({r['layout'] for r in rows})} distinct, "
              f"{len({(r['layout'], r['hideout']) for r in rows})} distinct with hideout: {dict(counts)}; "
              f"sealed by the leader alone: {len(alone)}", flush=True)
        for row in sealed[:12]:
            print(f"  SEALED seed {row['seed']}: pair at {row['leader']} {row['partner']}, player {row['player']}, "
                  f"exits {row['exits']}, floor cut off {row['lost_floor']}", flush=True)
        for row in alone[:6]:
            print(f"  SEALED BY ONE seed {row['seed']}: leader at {row['leader']}", flush=True)
        if args.exhaustive:
            blocks = sum(r.get("floor_blocks", 0) for r in rows)
            sealing = [s for r in rows for s in r.get("sealing", [])]
            cuts = [s for s in sealing if s["exit_cut"]]
            if not blocks:
                raise SystemExit("exhaustive pass tested no blocks: the floor id is wrong")
            print(f"  exhaustive: {blocks} plain-floor blocks, {len(cuts)} would cut the exit, "
                  f"{len(sealing) - len(cuts)} would only cut off other floor", flush=True)
            shapes = collections.Counter(str(s["around"][0]) for s in cuts)
            print(f"  north row of the sealing blocks (NW, N, NE ids): {shapes.most_common(14)}", flush=True)
            for row in rows[:3]:
                for s in row.get("sealing", [])[:3]:
                    print(f"  e.g. seed {row['seed']}: {s}", flush=True)
    print("FAIL" if failed else "PASS")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
