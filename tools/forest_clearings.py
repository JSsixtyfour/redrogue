#!/usr/bin/env python3
"""Build and prove the Procedural Forest clearings (PROCEDURAL_SUBROOMS_PLAN Phase F).

A clearing is a hand-drawn piece (maps/*.blk, W x H forest blocks) that
PFPlaceClearing stamps over an aligned patch of the 9x9-cell maze. Its sidecar,
data/maps/forest_clearings/*.clear, names the payload and its size, and may
name the block whose top-left tile holds the clearing's pokeball (forest balls
always stand on a block's top-left tile); without one, the tool picks the
valid block nearest the piece's centre.

WHY STAMPING ANYWHERE IS SAFE. The maze is a spanning tree, so any maze path
that reaches the patch's edge must stay connected to every other one. That
holds when (proved here, per piece, with the ball's tile counted as solid):
  1. every walkable tile on the piece's edge connects to every other one
     inside the piece;
  2. every edge block has at least one walkable quadrant on its outer side,
     so a passage arriving at any edge block gets in;
  3. a tile next to the ball is walkable and connected to the edge.

Usage (from the repo root):
    python3 tools/forest_clearings.py           # prove every piece, write the asm
    python3 tools/forest_clearings.py --check   # exit 1 if a piece fails or the asm is stale
    python3 tools/forest_clearings.py --show    # draw each piece
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PIECE_DIR = ROOT / "data" / "maps" / "forest_clearings"
BLOCKSET = ROOT / "gfx" / "blocksets" / "forest.bst"
COLLISION = ROOT / "data" / "tilesets" / "collision_tile_ids.asm"
OUT = ROOT / "data" / "maps" / "forest_clearing_pieces.asm"
COUNT_OUT = ROOT / "constants" / "forest_clearing_constants.asm"
QUADRANT_TILES = (4, 6, 12, 14)   # the collision tile of each quadrant: its BOTTOM-LEFT tile
PAIRS = ROOT / "data" / "tilesets" / "pair_collision_tile_ids.asm"
MAZE_FLOOR_TILE = 0x20            # the collision tile of every maze floor quadrant
MAX_SIZE = 7                      # odd offsets 1.. leave the far edge <= block 17


def forest_tile_pairs() -> set[frozenset[int]]:
    """FOREST's land tile pairs: the player can never step between the two
    tiles of a pair (Gen 1's elevation rule, e.g. raised ground $2E)."""
    text = PAIRS.read_text(encoding="utf-8").split("TilePairCollisionsWater::")[0]
    return {frozenset((int(a, 16), int(b, 16)))
            for a, b in re.findall(r"db FOREST, \$([0-9A-Fa-f]+), \$([0-9A-Fa-f]+)", text)}


class PieceError(Exception):
    pass


def walkable_tiles() -> set[int]:
    text = COLLISION.read_text(encoding="utf-8")
    match = re.search(r"^Forest_Coll::\s*\n\s*coll_tiles\s+([^\n;]+)", text, re.M)
    if not match:
        raise SystemExit("Forest_Coll not found")
    return {int(t.strip().lstrip("$"), 16) for t in match.group(1).split(",")}


class Piece:
    def __init__(self, path: Path, blockset: bytes, walk_tiles: set[int]):
        self.path = path
        self.name = path.stem
        size = blk = ball = None
        for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = raw.split("#", 1)[0].split()
            if not line:
                continue
            key, args = line[0], line[1:]
            try:
                if key == "blk":
                    blk = args[0]
                elif key == "size":
                    size = (int(args[0]), int(args[1]))
                elif key == "ball":
                    ball = (int(args[0]), int(args[1]))
                else:
                    raise PieceError(f"unknown key {key!r}")
            except (IndexError, ValueError) as exc:
                raise PieceError(f"{path.name}:{n}: {raw.strip()!r}: {exc}") from exc
        if not (blk and size):
            raise PieceError(f"{path.name}: needs blk and size")
        self.blk_path = blk
        self.w, self.h = size
        if not (2 <= self.w <= MAX_SIZE and 2 <= self.h <= MAX_SIZE):
            raise PieceError(f"{path.name}: size must be 2..{MAX_SIZE}")
        data = (ROOT / blk).read_bytes()
        if len(data) != self.w * self.h:
            raise PieceError(f"{path.name}: {blk} is {len(data)} bytes, size says {self.w * self.h}")
        self.blocks = list(data)
        self.coll = {
            (tx, ty): blockset[self.blocks[(ty // 2) * self.w + tx // 2] * 16
                               + QUADRANT_TILES[(ty % 2) * 2 + tx % 2]]
            for ty in range(2 * self.h) for tx in range(2 * self.w)
        }
        self.walk = {t for t, c in self.coll.items() if c in walk_tiles}
        self.pairs = forest_tile_pairs()
        self._prove_edges(None)
        self.ball = ball if ball is not None else self._pick_ball()
        why = self._prove_edges((2 * self.ball[0], 2 * self.ball[1]))
        if why:
            raise PieceError(f"{self.name}: ball block {self.ball}: {why}")

    def passable(self, a: int, b: int) -> bool:
        return frozenset((a, b)) not in self.pairs

    def _edge_tiles(self):
        return {(x, y) for y in range(2 * self.h) for x in range(2 * self.w)
                if x in (0, 2 * self.w - 1) or y in (0, 2 * self.h - 1)}

    def _prove_edges(self, ball_tile) -> str | None:
        walk = self.walk - ({ball_tile} if ball_tile else set())
        if ball_tile and ball_tile not in self.walk:
            return "its top-left tile is not walkable"
        # Open from outside: walkable and enterable from maze floor.
        edge = {t for t in self._edge_tiles() & walk if self.passable(MAZE_FLOOR_TILE, self.coll[t])}
        if not edge:
            raise PieceError(f"{self.name}: no walkable edge")
        start = next(iter(edge))
        seen, todo = {start}, [start]
        while todo:
            x, y = todo.pop()
            for nxt in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if nxt in walk and nxt not in seen and self.passable(self.coll[(x, y)], self.coll[nxt]):
                    seen.add(nxt)
                    todo.append(nxt)
        if not edge <= seen:
            return f"edge tiles {sorted(edge - seen)} are cut off from the rest of the edge"
        for side, blocks, outer in (
            ("top", [(bx, 0) for bx in range(self.w)], lambda bx, by: [(2 * bx, 0), (2 * bx + 1, 0)]),
            ("bottom", [(bx, self.h - 1) for bx in range(self.w)],
             lambda bx, by: [(2 * bx, 2 * by + 1), (2 * bx + 1, 2 * by + 1)]),
            ("left", [(0, by) for by in range(self.h)], lambda bx, by: [(0, 2 * by), (0, 2 * by + 1)]),
            ("right", [(self.w - 1, by) for by in range(self.h)],
             lambda bx, by: [(2 * bx + 1, 2 * by), (2 * bx + 1, 2 * by + 1)]),
        ):
            for bx, by in blocks:
                if not any(t in edge for t in outer(bx, by)):
                    return f"{side} edge block {(bx, by)} has no open outer side"
        if ball_tile:
            bx, by = ball_tile
            if not any((bx + dx, by + dy) in seen
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                return "the ball cannot be reached"
        return None

    def _pick_ball(self):
        centre = ((self.w - 1) / 2, (self.h - 1) / 2)
        options = sorted(
            ((bx, by) for by in range(self.h) for bx in range(self.w)),
            key=lambda b: (abs(b[0] - centre[0]) + abs(b[1] - centre[1]), b[1], b[0]),
        )
        for block in options:
            if not self._prove_edges((2 * block[0], 2 * block[1])):
                return block
        raise PieceError(f"{self.name}: no block can hold the ball without cutting a path")

    def label(self) -> str:
        return "PFClear" + "".join(p.capitalize() for p in re.split(r"[^A-Za-z0-9]+", self.name))

    def show(self) -> str:
        lines = [f"{self.name} ({self.w}x{self.h} blocks), ball block {self.ball}  o = ball tile"]
        for ty in range(2 * self.h):
            row = ""
            for tx in range(2 * self.w):
                row += "o" if (tx, ty) == (2 * self.ball[0], 2 * self.ball[1]) else (
                    "." if (tx, ty) in self.walk else "#")
            lines.append("    " + row)
        return "\n".join(lines)


def load() -> tuple[list[Piece], list[str]]:
    blockset, walk_tiles = BLOCKSET.read_bytes(), walkable_tiles()
    pieces, errors = [], []
    for path in sorted(PIECE_DIR.glob("*.clear")):
        try:
            pieces.append(Piece(path, blockset, walk_tiles))
        except PieceError as exc:
            errors.append(str(exc))
    return pieces, errors


def build() -> tuple[str, str, list[str]]:
    pieces, errors = load()
    lines = [
        "; GENERATED by tools/forest_clearings.py from data/maps/forest_clearings/*.clear.",
        "; Do not edit by hand; rerun the tool. Descriptor, PF_CLEAR_STRIDE bytes:",
        ";   +0/+1 piece W/H (blocks), +2/+3 ball block (piece-local), +4/+5 payload.",
        "PFClearingPieces:",
    ]
    for p in pieces:
        lines.append(f"\tdb {p.w}, {p.h}, {p.ball[0]}, {p.ball[1]} ; {p.path.relative_to(ROOT).as_posix()}")
        lines.append(f"\tdw {p.label()}")
    lines += ["PFClearingPiecesEnd:", ""]
    for p in pieces:
        lines += [f"{p.label()}:", f'\tINCBIN "{p.blk_path}"']
    counts = "\n".join([
        "; GENERATED by tools/forest_clearings.py. Do not edit by hand.",
        f"DEF NUM_FOREST_CLEARINGS EQU {len(pieces)}",
    ]) + "\n"
    return "\n".join(lines) + "\n", counts, errors


def main() -> int:
    if "--show" in sys.argv[1:]:
        pieces, errors = load()
        for p in pieces:
            print(p.show())
        for e in errors:
            print("ERROR:", e)
        return 1 if errors else 0
    text, counts, errors = build()
    for e in errors:
        print("ERROR:", e)
    if "--check" in sys.argv[1:]:
        for path, want in ((OUT, text), (COUNT_OUT, counts)):
            current = path.read_text(encoding="utf-8") if path.exists() else ""
            if current != want:
                print(f"{path.relative_to(ROOT)} is stale: run tools/forest_clearings.py")
                return 1
        return 1 if errors else 0
    if errors:
        return 1
    OUT.write_text(text, encoding="utf-8", newline="\n")
    COUNT_OUT.write_text(counts, encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)} and {COUNT_OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
