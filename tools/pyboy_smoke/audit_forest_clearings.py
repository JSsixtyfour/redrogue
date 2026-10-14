#!/usr/bin/env python3
"""Corpus check of Procedural Forest clearings (PROCEDURAL_SUBROOMS_PLAN Phase F).

For each generated forest (north exit, the normal-play edge):
  * a live clearing record (sProcForestGenScratch 72-78) matches the map: the
    piece is stamped block for block at its rect, which avoids the entrance
    block (9,17), the sign block (9,16) and the boss cell;
  * ball 0 stands on the piece's ball block; balls 1-3 and the stage-event
    hideout are outside the clearing;
  * with every ball counted as solid, each ball has a reachable neighbour and
    the exit is reachable from the entrance (the maze stays connected).
Prints how often a forest gets a clearing and which pieces were used.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/audit_forest_clearings.py [--seeds N]
"""

from __future__ import annotations

import argparse
import random
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402
import forest_clearings as fc  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
ENTRANCE_TILE = (18, 35)   # block (9,17), the warp_event tile the player arrives on
NO_HIDEOUT = 0xFF


def walkable_cells(playable, blockset, walk_tiles):
    """{tile: its collision tile} for every walkable quadrant."""
    cells = {}
    for by in range(20):
        for bx in range(20):
            block = playable[by * 20 + bx]
            for qy in range(2):
                for qx in range(2):
                    tile = blockset[block * 16 + fc.QUADRANT_TILES[qy * 2 + qx]]
                    if tile in walk_tiles:
                        cells[(2 * bx + qx, 2 * by + qy)] = tile
    return cells


PAIRS = fc.forest_tile_pairs()


def flood(cells, start):
    """Reachable tiles, honouring FOREST's elevation pairs (no step between
    the two tiles of a pair, e.g. raised ground $2E and floor $20)."""
    seen = {start} if start in cells else set()
    todo = list(seen)
    while todo:
        x, y = todo.pop()
        for nxt in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if nxt in cells and nxt not in seen and frozenset((cells[(x, y)], cells[nxt])) not in PAIRS:
                seen.add(nxt)
                todo.append(nxt)
    return seen


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=200)
    args = parser.parse_args()

    pieces, errors = fc.load()
    assert not errors, errors
    blockset, walk_tiles = fc.BLOCKSET.read_bytes(), fc.walkable_tiles()

    forest = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_FOREST"]
    used: Counter = Counter()
    problems = 0
    errors_run = 0
    for seed in range(args.seeds):
        # The real warp-in path, one fresh boot per forest, exactly like
        # audit_boss_ball_overlap.py: the maze is carved into the forest map's
        # own tree fill, so calling PFinalizeForest from the lobby generates on
        # top of the lobby's blocks instead (measured: every such layout found
        # no dead ends at all).
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
        rec = h.read_sram_bytes("sProcForestGenScratch", 81, bank=0)[72:79]
        balls = h.read_sram_bytes("sProcForestBallXY", 8, bank=0)
        exit_i = h.read_sram_bytes("sProcForestExitI", 1, bank=0)[0]
        hideout = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
        found = []
        ball_tiles = [(balls[2 * i + 1] - 4, balls[2 * i] - 4) for i in range(4)]

        key, x, y, w, hh, bbx, bby = rec
        if key & 0x80:
            piece = pieces[key & 0x7F]
            used[piece.name] += 1
            if (w, hh) != (piece.w, piece.h):
                found.append(f"record size {(w, hh)} != piece {(piece.w, piece.h)}")
            for py in range(piece.h):
                for px in range(piece.w):
                    got = playable[(y + py) * 20 + x + px]
                    want = piece.blocks[py * piece.w + px]
                    if got != want:
                        found.append(f"block ({px},{py}) is {got:02X}, piece has {want:02X}")

            def inside(block):
                return x <= block[0] < x + w and y <= block[1] < y + hh

            for block in ((9, 17), (9, 16), (2 * exit_i + 1, 1)):
                if inside(block):
                    found.append(f"clearing covers {block}")
            if (bbx, bby) != (x + piece.ball[0], y + piece.ball[1]):
                found.append(f"record ball {(bbx, bby)} is not the piece's")
            if ball_tiles[0] != (2 * bbx, 2 * bby):
                found.append(f"ball 0 at {ball_tiles[0]}, clearing wants {(2 * bbx, 2 * bby)}")
            for i in (1, 2, 3):
                if inside((ball_tiles[i][0] // 2, ball_tiles[i][1] // 2)):
                    found.append(f"ball {i} inside the clearing")
            if hideout[0] != NO_HIDEOUT and inside((hideout[0], hideout[1])):
                found.append("hideout inside the clearing")
        else:
            used["(none)"] += 1

        cells = walkable_cells(playable, blockset, walk_tiles)
        for tile in ball_tiles:
            cells.pop(tile, None)
        reach = flood(cells, ENTRANCE_TILE)
        for i, (bx, by) in enumerate(ball_tiles):
            if not any((bx + dx, by + dy) in reach for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                found.append(f"ball {i} at {(bx, by)} unreachable")
        exit_tiles = {(2 * (2 * exit_i + 1) + qx, qy) for qx in range(2) for qy in range(2)}
        if not exit_tiles & reach:
            found.append("exit unreachable")
        h.close()
        for line in found:
            print(f"seed {seed}: {line}")
        problems += len(found)
    with_clearing = args.seeds - used["(none)"]
    print(f"forests {args.seeds}: with a clearing {with_clearing} "
          f"({100 * with_clearing / args.seeds:.0f}%), problems {problems}, harness errors {errors_run}")
    print("pieces:", dict(sorted(used.items())))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
