#!/usr/bin/env python3
"""Audit: every generated forest stands its rest house, reachable and armed.

PROCEDURAL_SUBROOMS_PLAN Phase 4. PFPlaceHouse puts a two-block house over
trees on one of the door spots in constants/forest_house_site_constants.asm.
For each forest (real warp-in, one fresh boot each, like
audit_forest_clearings.py) this checks:

  * a house was placed (the spot is in sProcForestItemGot bits 0-4) and both
    of its blocks are in the map;
  * exactly that spot's door warp is armed;
  * the cell in front of the door is reachable from the entrance under the
    full collision model (walkable quadrants plus FOREST's elevation pairs),
    and no object stands on the tile the player steps out onto;
  * every ball and the exit are still reachable (the house cut nothing).

Usage:
    python3 tools/pyboy_smoke/audit_forest_house.py [--seeds 200]
"""

from __future__ import annotations

import argparse
import random
import re
from collections import Counter
from pathlib import Path

from audit_forest_clearings import ENTRANCE_TILE, fc, flood, walkable_cells
from harness import RedRogueHarness
from source_constants import parse_map_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
SITE_MASK = 0x1F
HOUSE = (0x19, 0x1C)
FIRST_HOUSE_WARP = 3


def house_sites() -> list[tuple[int, int]]:
    text = (REPO_ROOT / "constants/forest_house_site_constants.asm").read_text(encoding="utf-8")
    return [(int(x), int(y)) for x, y in re.findall(r"^\s*house_site\s+(\d+),\s*(\d+)", text, re.M)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=200)
    args = parser.parse_args()

    sites = house_sites()
    blockset, walk_tiles = fc.BLOCKSET.read_bytes(), fc.walkable_tiles()
    forest = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_FOREST"]
    used: Counter = Counter()
    problems = errors_run = 0
    for seed in range(args.seeds):
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby()
            rng = random.Random(seed)
            base = h.address("wRandomTable")
            for offset in range(10):
                h.pyboy.memory[base + offset] = rng.randrange(1, 256)
            h.preload_and_enter_wild_area(forest, "Procedural Forest")
        except Exception as exc:
            errors_run += 1
            print(f"seed {seed}: harness {type(exc).__name__}: {exc}")
            h.close()
            continue
        buf = h.read_bytes("wOverworldMap", 601)
        playable = tuple(buf[81 + r * 26 + c] for r in range(20) for c in range(20))
        got = h.read_sram_bytes("sProcForestItemGot", 1, bank=0)[0]
        balls = h.read_sram_bytes("sProcForestBallXY", 8, bank=0)
        exit_i = h.read_sram_bytes("sProcForestExitI", 1, bank=0)[0]
        warps = h.warp_entries()
        objects = set()
        for slot in range(1, 16):
            objects.add((h.read8("wSprite01StateData2MapX", offset=16 * (slot - 1)) - 4,
                         h.read8("wSprite01StateData2MapY", offset=16 * (slot - 1)) - 4))
        h.close()

        found = []
        ball_tiles = [(balls[2 * i + 1] - 4, balls[2 * i] - 4) for i in range(4)]
        cells = walkable_cells(playable, blockset, walk_tiles)
        for tile in ball_tiles:
            cells.pop(tile, None)
        reach = flood(cells, ENTRANCE_TILE)

        site = (got & SITE_MASK) - 1
        if site < 0:
            used["(none)"] += 1
            found.append("no house")
        else:
            used[site] += 1
            x, y = sites[site]
            if (playable[y * 20 + x], playable[y * 20 + x + 1]) != HOUSE:
                found.append(f"site {site} {(x, y)} holds {playable[y * 20 + x]:02X} {playable[y * 20 + x + 1]:02X}")
            front = (2 * x + 1, 2 * y + 2)
            if front not in reach:
                found.append(f"door front {front} unreachable")
            if front in objects:
                found.append(f"an object stands on the door front {front}")
        for n in range(len(sites)):
            armed = warps[FIRST_HOUSE_WARP + n][0] != 0xFF
            if armed != (n == site):
                found.append(f"door warp {n} armed={armed}")
        for i, (bx, by) in enumerate(ball_tiles):
            if not any((bx + dx, by + dy) in reach for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                found.append(f"ball {i} at {(bx, by)} unreachable")
        exit_tiles = {(2 * (2 * exit_i + 1) + qx, qy) for qx in range(2) for qy in range(2)}
        if not exit_tiles & reach:
            found.append("exit unreachable")
        for line in found:
            print(f"seed {seed}: {line}")
        problems += len(found)

    housed = args.seeds - errors_run - used["(none)"]
    print(f"forests {args.seeds}: with a house {housed}, problems {problems}, harness errors {errors_run}")
    print(f"sites used {len([k for k in used if k != '(none)'])}/{len(sites)}:",
          dict(sorted((k, v) for k, v in used.items() if k != "(none)")))
    return 1 if problems or errors_run else 0


if __name__ == "__main__":
    raise SystemExit(main())
