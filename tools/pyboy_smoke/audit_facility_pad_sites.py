#!/usr/bin/env python3
"""Measure where Facility warp-pad landing sites can live (PROCEDURAL_SUBROOMS_PLAN Phase 0).

Warp arrival coordinates are fixed in ROM (LoadDestinationWarpPosition reads
the def_warps_to table), so a pad can only land on one of K pre-declared
warp_events. Before choosing those K coordinates, this audit measures, per
block, how often that block would be a VALID pad site across a seed corpus.

A block is a valid site when all of these hold:
  1. all four quadrants are walkable floor;
  2. it lies inside the floor rect of a MIDDLE room (ids 1-10: not the entry
     room 0, not the exit/boss room 11);
  3. no real ball, fake ball or the boss stands on any of its quadrants;
  4. it is reachable from the entrance;
  5. treating the whole block as SOLID strands nothing else. A pad teleports
     whoever steps on it, so it is a wall for walking purposes, and a pad in
     a one-wide neck would cut the map.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/audit_facility_pad_sites.py [--seeds N] [--dump N]
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from itertools import combinations
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402
from audit_facility_stranded_quadrants import (  # noqa: E402
    BLOCKSET, ENTRANCE, flood, passable,
)
import io  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

ROOM_STRIDE = 6
ROOM_MAX = 12
ENTRY_ROOM = 0
EXIT_ROOM = 11
FAKE_BALL_OFFSET = 72  # sProcFacilityGenScratch bytes 72-79: fake-ball Y/X pairs


def block_cells(bx: int, by: int) -> set[tuple[int, int]]:
    return {(2 * bx + qx, 2 * by + qy) for qy in range(2) for qx in range(2)}


def layout(harness, seed, edge, baseline):
    harness.load_state(baseline)
    harness.write_sram_bytes("sProcFacilityExitEdge", [edge])
    harness.seed_rng(seed)
    harness.call_routine("PFacFinalize", limit=4000)
    buf = harness.read_bytes("wOverworldMap", 601)
    playable = tuple(buf[81 + r * 26 + c] for r in range(20) for c in range(20))
    scratch = harness.read_sram_bytes("sProcFacilityGenScratch", 81)
    balls = harness.read_sram_bytes("sProcFacilityBallXY", 8)
    boss = harness.read_bytes("wSprite01StateData2MapY", 2)
    return playable, scratch, balls, boss


def rooms_from(scratch):
    rooms = []
    for rid in range(ROOM_MAX):
        x, y, w, h, parent, typ = scratch[rid * ROOM_STRIDE: rid * ROOM_STRIDE + 6]
        rooms.append((rid, x, y, w, h, parent, typ))
    return rooms


def object_tiles(scratch, balls, boss):
    """Tile coords (no map border offset) of every ball and the boss."""
    tiles = set()
    for i in range(4):
        y, x = balls[2 * i], balls[2 * i + 1]
        tiles.add((x - 4, y - 4))
    for i in range(4):
        y, x = scratch[FAKE_BALL_OFFSET + 2 * i], scratch[FAKE_BALL_OFFSET + 2 * i + 1]
        tiles.add((x - 4, y - 4))
    tiles.add((boss[1] - 4, boss[0] - 4))
    return tiles


def valid_sites(blockset, playable, scratch, balls, boss):
    cells = passable(blockset, playable)
    reachable = flood(cells, ENTRANCE)
    occupied = object_tiles(scratch, balls, boss)
    sites = {}
    for rid, x, y, w, h, _parent, _typ in rooms_from(scratch):
        if rid in (ENTRY_ROOM, EXIT_ROOM) or w == 0:
            continue
        for by in range(y, y + h):
            for bx in range(x, x + w):
                if not (0 <= bx < 20 and 0 <= by < 20):
                    continue
                quads = block_cells(bx, by)
                if not quads <= cells or not quads <= reachable:
                    continue
                if quads & occupied:
                    continue
                rest = flood(cells - quads, ENTRANCE)
                if rest != reachable - quads:
                    continue
                sites[(bx, by)] = rid
    return sites  # block -> room id


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=200)
    parser.add_argument("--dump", type=int, default=0,
                        help="print raw room records / ball coords for N seeds and stop")
    parser.add_argument("--k", type=int, default=8, help="site-set size to evaluate")
    args = parser.parse_args()

    blockset = BLOCKSET.read_bytes()
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    harness.boot_to_lobby()
    harness.call_routine("PFacPreload", limit=60000)
    baseline = io.BytesIO()
    harness.save_state(baseline)

    state = 0x1234_5678
    per_layout_sites = []
    heat: Counter = Counter()
    count = args.dump or args.seeds
    for index in range(count):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        seed = [(state >> shift) & 0xFF for shift in (0, 8, 16, 24)]
        # Exit edge 0 (north) only: W/E are debug-only per sram.asm.
        playable, scratch, balls, boss = layout(harness, seed, 0, baseline)
        if args.dump:
            print(f"--- seed {' '.join(f'{b:02X}' for b in seed)}")
            for room in rooms_from(scratch):
                print("  room %2d x=%3d y=%3d w=%3d h=%3d parent=%3d type=%02X" % room)
            print("  balls YX", balls, " fake YX", scratch[72:80], " boss YX", boss)
            cells = passable(blockset, playable)
            print("  walkable", len(cells), " reachable", len(flood(cells, ENTRANCE)))
            continue
        sites = valid_sites(blockset, playable, scratch, balls, boss)
        per_layout_sites.append(sites)
        heat.update(sites.keys())  # a dict would add its values as counts
    if args.dump:
        return 0

    total = len(per_layout_sites)
    counts = [len(s) for s in per_layout_sites]
    print(f"layouts {total}")
    print(f"valid sites per layout: min {min(counts)} max {max(counts)} "
          f"mean {sum(counts) / total:.1f}")
    print("\nper-block validity % (rows 0-19, '.' = never valid):")
    for by in range(20):
        row = ""
        for bx in range(20):
            pct = 100 * heat[(bx, by)] // total
            row += " ." if pct == 0 else f"{min(pct, 99):2d}"
            row += " "
        print("   " + row)

    # Greedy pick of K sites, maximising the share of layouts whose valid
    # sites in the set span >=2 DISTINCT rooms (a pad pair inside one room is
    # not a shortcut), tie-broken by >=3 distinct rooms.
    candidates = [b for b, _ in heat.most_common()]
    chosen: list[tuple[int, int]] = []

    def rooms_hit(sites, site_set):
        return len({rid for block, rid in sites.items() if block in site_set})

    def score(site_set):
        ge2 = sum(1 for s in per_layout_sites if rooms_hit(s, site_set) >= 2)
        ge3 = sum(1 for s in per_layout_sites if rooms_hit(s, site_set) >= 3)
        return ge2, ge3

    for _ in range(args.k):
        best = max((c for c in candidates if c not in chosen),
                   key=lambda c: score(set(chosen) | {c}))
        chosen.append(best)
        ge2, ge3 = score(set(chosen))
        print(f"K={len(chosen)} add block {best}: >=2 rooms {100 * ge2 / total:.0f}%  "
              f">=3 rooms {100 * ge3 / total:.0f}%")
    print("chosen blocks:", chosen)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
