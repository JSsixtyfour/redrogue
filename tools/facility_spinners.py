#!/usr/bin/env python3
"""Build and prove the Facility spinner decor (PROCEDURAL_SUBROOMS_PLAN Phase 3).

A spinner piece is large decor: an interior-only payload (maps/*.blk, W x H
blocks, no wall ring) that the generator centres inside an item room's generic
interior. Its sidecar, data/maps/facility_spinners/*.spin, names only the
payload, its size and the tile the pokeball stands on. Everything else is read
from the art:

ARROWS AND STOPPERS (measured 2026-10-13 against vanilla Rocket Hideout B2F and
B3F: this rule reproduces the exact move list of all 59 vanilla slides).
  * a walkable quadrant drawn 21 31/21 31 is an UP arrow, 20 30/20 30 DOWN,
    21 21/20 20 LEFT, 31 31/30 30 RIGHT (each a pair of chevrons);
  * a quadrant drawn 5E 5E/5E 5E is a STOPPER;
  * 21 31/20 30 is the warp-pad diamond, not an arrow, and is refused.
  Stepping onto an arrow slides the player one tile at a time; passing over
  another arrow turns the slide, entering a stopper ends it, and so does the
  next tile being solid, the pokeball, or outside the piece. Slides are
  computed inside the piece only, so they are identical in every room size
  (the engine replays a fixed step count).

PROOFS. The piece is placed, centred, in every interior size from its own size
up to 7x7, inside the generic one-block wall ring with plain floor around it.
The ring's inner quadrants form a closed walkable BASEBOARD loop, and every
opening into the room, wherever a corridor meets the ring, joins that loop, so
the proofs are stated against the baseboard and hold for any doorways:
  1. every slide moves at least one tile and does not loop;
  2. a tile next to the pokeball is reachable from the baseboard;
  3. no trap: from every tile reachable from the baseboard, the baseboard is
     reachable again, both with the ball in place and after it is taken.
The ROM checks, before stamping, that the room's interior is all plain floor
and that every ring block keeps its inner (baseboard) quadrants walkable.
The descriptor records the largest interior size range that passes
everywhere; the generator only uses rooms inside it.

Usage (from the repo root):
    python3 tools/facility_spinners.py           # prove every piece, write the asm
    python3 tools/facility_spinners.py --check   # exit 1 if a piece fails or the asm is stale
    python3 tools/facility_spinners.py --show    # draw each piece
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROOM_DIR = ROOT / "data" / "maps" / "facility_spinners"
MASKS = ROOT / "data" / "tilesets" / "facility_quad_masks.asm"
BLOCKSET = ROOT / "gfx" / "blocksets" / "facility.bst"
OUT = ROOT / "data" / "maps" / "facility_spinner_rooms.asm"
COUNT_OUT = ROOT / "constants" / "facility_spinner_constants.asm"

DIRS = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}
PAD = {"up": "PAD_UP", "down": "PAD_DOWN", "left": "PAD_LEFT", "right": "PAD_RIGHT"}
GLYPH = {"up": "^", "down": "v", "left": "<", "right": ">"}
ARROW_ART = {
    (0x21, 0x31, 0x21, 0x31): "up",
    (0x20, 0x30, 0x20, 0x30): "down",
    (0x21, 0x21, 0x20, 0x20): "left",
    (0x31, 0x31, 0x30, 0x30): "right",
}
STOPPER_ART = (0x5E, 0x5E, 0x5E, 0x5E)
PAD_ART = (0x21, 0x31, 0x20, 0x30)
QUADRANT_TILES = ((0, 1, 4, 5), (2, 3, 6, 7), (8, 9, 12, 13), (10, 11, 14, 15))
MAX_INTERIOR = 7          # PFacRollRoomDim: interiors roll 1..7
MAX_SLIDE = 64
MAX_PER_BUILD = 3         # two room-Type bits hold (index + 1)

# Generic room ring, by position: block id (the ROM verifies every spinner
# room's ring has exactly these quadrant masks before stamping).
RING = {"T": 0x41, "B": 0x49, "L": 0x44, "R": 0x46,
        "TL": 0x40, "TR": 0x42, "BL": 0x48, "BR": 0x4A}
FLOOR = 0x0E


class RoomError(Exception):
    pass


def quad_masks() -> list[int]:
    return [int(m, 2) for m in re.findall(r"%([01]{4})", MASKS.read_text(encoding="utf-8"))]


class Piece:
    def __init__(self, path: Path, masks: list[int], blockset: bytes):
        self.path = path
        self.name = path.stem
        self.debug = False
        size = blk = reward = None
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
                elif key == "reward":
                    reward = (int(args[0]), int(args[1]))
                elif key == "debug":
                    self.debug = True
                else:
                    raise RoomError(f"unknown key {key!r}")
            except (IndexError, ValueError) as exc:
                raise RoomError(f"{path.name}:{n}: {raw.strip()!r}: {exc}") from exc
        if not (blk and size and reward):
            raise RoomError(f"{path.name}: needs blk, size and reward")
        self.blk_path = blk
        self.w, self.h = size
        if not (1 <= self.w <= MAX_INTERIOR and 1 <= self.h <= MAX_INTERIOR):
            raise RoomError(f"{path.name}: size must be 1..{MAX_INTERIOR}")
        data = (ROOT / blk).read_bytes()
        if len(data) != self.w * self.h:
            raise RoomError(f"{path.name}: {blk} is {len(data)} bytes, size says {self.w * self.h}")
        self.blocks = list(data)
        self.masks = masks
        self.ball = reward
        self.walk: set[tuple[int, int]] = set()
        self.arrows: dict[tuple[int, int], str] = {}
        self.stoppers: set[tuple[int, int]] = set()
        for ty in range(2 * self.h):
            for tx in range(2 * self.w):
                block = self.blocks[(ty // 2) * self.w + tx // 2]
                quad = (ty % 2) * 2 + tx % 2
                if not masks[block] >> quad & 1:
                    continue
                self.walk.add((tx, ty))
                art = tuple(blockset[block * 16 + k] for k in QUADRANT_TILES[quad])
                if art in ARROW_ART:
                    self.arrows[(tx, ty)] = ARROW_ART[art]
                elif art == STOPPER_ART:
                    self.stoppers.add((tx, ty))
                elif art == PAD_ART:
                    raise RoomError(f"{path.name}: tile {(tx, ty)} is warp-pad art, not an arrow")
        if not self.arrows:
            raise RoomError(f"{path.name}: no arrow art found")
        if self.ball not in self.walk or self.ball in self.arrows or self.ball in self.stoppers:
            raise RoomError(f"{path.name}: reward tile {self.ball} must be plain walkable floor")
        self.slides = {a: self._slide(a) for a in self.arrows}

    def _slide(self, start) -> tuple[tuple[int, int], list[str]]:
        pos, moves, seen = start, [], set()
        direction = self.arrows[start]
        while True:
            if (pos, direction) in seen or len(moves) > MAX_SLIDE:
                raise RoomError(f"{self.name}: arrow {start} slides in a loop")
            seen.add((pos, direction))
            dx, dy = DIRS[direction]
            nxt = (pos[0] + dx, pos[1] + dy)
            if nxt not in self.walk or nxt == self.ball:
                break
            pos = nxt
            moves.append(direction)
            if pos in self.stoppers:
                break
            if pos in self.arrows:
                direction = self.arrows[pos]
        if not moves:
            raise RoomError(f"{self.name}: arrow {start} points straight into a wall")
        if pos in self.arrows:
            raise RoomError(f"{self.name}: arrow {start} stops on arrow {pos}")
        return pos, moves

    # --- a placed room ---------------------------------------------------------
    def room(self, iw: int, ih: int):
        """Tile-level model of the piece centred in an iw x ih generic room.
        Returns (piece offset in tiles, walkable(tile, open, ball_gone),
        doorway tile sets, room size in tiles)."""
        fw, fh = iw + 2, ih + 2
        ox = 2 * (1 + (iw - self.w) // 2)
        oy = 2 * (1 + (ih - self.h) // 2)
        doors = {"N": (1 + iw // 2, 0), "S": (1 + iw // 2, fh - 1),
                 "W": (0, 1 + ih // 2), "E": (fw - 1, 1 + ih // 2)}

        def block_at(bx, by):
            if bx == 0 and by == 0:
                return RING["TL"]
            if bx == fw - 1 and by == 0:
                return RING["TR"]
            if bx == 0 and by == fh - 1:
                return RING["BL"]
            if bx == fw - 1 and by == fh - 1:
                return RING["BR"]
            if by == 0:
                return RING["T"]
            if by == fh - 1:
                return RING["B"]
            if bx == 0:
                return RING["L"]
            if bx == fw - 1:
                return RING["R"]
            return FLOOR

        def walkable(tile, open_doors, ball_gone):
            tx, ty = tile
            if not (0 <= tx < 2 * fw and 0 <= ty < 2 * fh):
                return False
            local = (tx - ox, ty - oy)
            if 0 <= local[0] < 2 * self.w and 0 <= local[1] < 2 * self.h:
                if local == self.ball and not ball_gone:
                    return False
                return local in self.walk
            block = (tx // 2, ty // 2)
            if any(block == doors[side] for side in open_doors):
                return True
            return bool(self.masks[block_at(*block)] >> ((ty % 2) * 2 + tx % 2) & 1)

        door_tiles = {side: {(2 * bx + qx, 2 * by + qy) for qy in range(2) for qx in range(2)}
                      for side, (bx, by) in doors.items()}
        return (ox, oy), walkable, door_tiles, (2 * fw, 2 * fh)

    def prove(self, iw: int, ih: int) -> str | None:
        (ox, oy), walkable, _doors, (tw, th) = self.room(iw, ih)
        ends = {(ox + x, oy + y): (ox + e[0], oy + e[1]) for (x, y), (e, _m) in self.slides.items()}
        # Baseboard: the walkable quadrants of the ring blocks (outer tile ring
        # of the room is solid, so these are the inner ones).
        baseboard = {(tx, ty) for ty in range(th) for tx in range(tw)
                     if (tx < 2 or ty < 2 or tx >= tw - 2 or ty >= th - 2)
                     and walkable((tx, ty), (), False)}

        def edges(ball_gone):
            graph = {}
            for ty in range(th):
                for tx in range(tw):
                    t = (tx, ty)
                    if t in ends or not walkable(t, (), ball_gone):
                        continue
                    out = set()
                    for dx, dy in DIRS.values():
                        nxt = (tx + dx, ty + dy)
                        if walkable(nxt, (), ball_gone):
                            out.add(ends.get(nxt, nxt))
                    graph[t] = out
            return graph

        def reach(graph, starts):
            seen = set(s for s in starts if s in graph)
            todo = list(seen)
            while todo:
                for nxt in graph[todo.pop()]:
                    if nxt not in seen:
                        seen.add(nxt)
                        todo.append(nxt)
            return seen

        graph = edges(False)
        if reach(graph, {next(iter(baseboard))}) & baseboard != baseboard:
            return "the baseboard loop is broken"
        got = reach(graph, baseboard)
        bx, by = ox + self.ball[0], oy + self.ball[1]
        if not any((bx + dx, by + dy) in got for dx, dy in DIRS.values()):
            return "the pokeball cannot be reached"
        for node in got:
            if not reach(graph, {node}) & baseboard:
                return f"trap at piece tile {(node[0] - ox, node[1] - oy)}"
        gone = edges(True)
        for node in reach(gone, baseboard):
            if not reach(gone, {node}) & baseboard:
                return f"trap after the ball is taken, at piece tile {(node[0] - ox, node[1] - oy)}"
        return None

    def size_range(self) -> tuple[int, int]:
        """Largest (max interior W, max interior H) such that every size from the
        piece's own up to it passes."""
        why = self.prove(self.w, self.h)
        if why:
            raise RoomError(f"{self.name}: unsafe even in an exact-fit room: {why}")
        passing = {(iw, ih) for iw in range(self.w, MAX_INTERIOR + 1)
                   for ih in range(self.h, MAX_INTERIOR + 1) if not self.prove(iw, ih)}
        best = (self.w, self.h)
        for mw in range(self.w, MAX_INTERIOR + 1):
            for mh in range(self.h, MAX_INTERIOR + 1):
                if all((iw, ih) in passing for iw in range(self.w, mw + 1)
                       for ih in range(self.h, mh + 1)):
                    if (mw - self.w + 1) * (mh - self.h + 1) > (best[0] - self.w + 1) * (best[1] - self.h + 1):
                        best = (mw, mh)
        return best

    # --- output ---------------------------------------------------------------
    def label(self) -> str:
        return "PFacSpin" + "".join(p.capitalize() for p in re.split(r"[^A-Za-z0-9]+", self.name))

    def descriptor(self, max_size) -> list[str]:
        lab = self.label()
        out = [f"; {self.path.relative_to(ROOT).as_posix()}: fits interiors "
               f"{self.w}x{self.h} .. {max_size[0]}x{max_size[1]}"]
        if self.debug:
            out.append("IF DEF(_DEBUG)")
        out += [f"\tdb {self.w}, {self.h}, {max_size[0]}, {max_size[1]}, {self.ball[0]}, {self.ball[1]}",
                f"\tdw {lab}Blocks, {lab}Arrows"]
        if self.debug:
            out.append("ENDC")
        return out

    def data(self) -> list[str]:
        lab = self.label()
        out = ["IF DEF(_DEBUG)"] if self.debug else []
        out += [f"{lab}Blocks:", f'\tINCBIN "{self.blk_path}"', f"{lab}Arrows:"]
        order = sorted(self.arrows, key=lambda t: (t[1], t[0]))
        for tile in order:
            out.append(f"\tmap_coord_movement {tile[0]}, {tile[1]}, {lab}Slide_{tile[0]}_{tile[1]}")
        out.append("\tdb -1 ; end")
        for tile in order:
            end, moves = self.slides[tile]
            runs: list[list] = []
            for move in moves:
                if runs and runs[-1][0] == move:
                    runs[-1][1] += 1
                else:
                    runs.append([move, 1])
            out.append(f"{lab}Slide_{tile[0]}_{tile[1]}: ; {GLYPH[self.arrows[tile]]} ends at {end}")
            for move, count in reversed(runs):  # replayed last entry first
                out.append(f"\tdb {PAD[move]}, {count}")
            out.append("\tdb -1 ; end")
        if self.debug:
            out.append("ENDC")
        return out

    def show(self) -> str:
        lines = [f"{self.name} ({self.w}x{self.h} blocks)  ^v<> arrow  S stopper  o ball"]
        lines.append("      x " + "".join(str(x % 10) for x in range(2 * self.w)))
        for ty in range(2 * self.h):
            row = ""
            for tx in range(2 * self.w):
                t = (tx, ty)
                row += ("o" if t == self.ball else GLYPH[self.arrows[t]] if t in self.arrows
                        else "S" if t in self.stoppers else "." if t in self.walk else "#")
            lines.append(f"  y{ty:<3} {row}")
        for tile in sorted(self.arrows, key=lambda t: (t[1], t[0])):
            end, moves = self.slides[tile]
            lines.append(f"  {GLYPH[self.arrows[tile]]} at {tile} -> {end} in {len(moves)}")
        return "\n".join(lines)


def load() -> tuple[list[Piece], list[str]]:
    masks, blockset = quad_masks(), BLOCKSET.read_bytes()
    pieces, errors = [], []
    for path in sorted(ROOM_DIR.glob("*.spin")):
        try:
            pieces.append(Piece(path, masks, blockset))
        except RoomError as exc:
            errors.append(str(exc))
    return pieces, errors


def count_text(pieces) -> str:
    shipped = sum(1 for p in pieces if not p.debug)
    return "\n".join([
        "; GENERATED by tools/facility_spinners.py. Do not edit by hand.",
        "; Spinner pieces assembled into this build (debug-only pieces count in the debug ROM).",
        "IF DEF(_DEBUG)",
        f"DEF NUM_FACILITY_SPINNER_ROOMS EQU {len(pieces)}",
        "ELSE",
        f"DEF NUM_FACILITY_SPINNER_ROOMS EQU {shipped}",
        "ENDC",
    ]) + "\n"


def build() -> tuple[str, str, list[str]]:
    pieces, errors = load()
    proven = []
    for piece in pieces:
        try:
            proven.append((piece, piece.size_range()))
        except RoomError as exc:
            errors.append(str(exc))
    if len(proven) > MAX_PER_BUILD:
        errors.append(f"{len(proven)} spinner pieces: at most {MAX_PER_BUILD} (two Type bits)")
    lines = [
        "; GENERATED by tools/facility_spinners.py from data/maps/facility_spinners/*.spin.",
        "; Do not edit by hand; rerun the tool. Descriptor, PFAC_SPIN_STRIDE bytes:",
        ";   +0/+1 piece W/H (blocks), +2/+3 largest interior W/H it is proven in,",
        ";   +4/+5 ball tile (piece-local), +6/+7 payload, +8/+9 arrow table (piece-local tiles).",
        "; Index in this table + 1 is stored in the room's Type bits 2-3.",
        "PFacSpinnerRooms:",
    ]
    for piece, size in proven:
        lines += piece.descriptor(size)
    lines += ["PFacSpinnerRoomsEnd:", ""]
    for piece, _ in proven:
        lines += piece.data()
    return "\n".join(lines) + "\n", count_text([p for p, _ in proven]), errors


def main() -> int:
    if "--show" in sys.argv[1:]:
        pieces, errors = load()
        for piece in pieces:
            print(piece.show())
            try:
                print("  proven in interiors up to %dx%d" % piece.size_range())
            except RoomError as exc:
                print("  NOT SAFE:", exc)
        for error in errors:
            print("ERROR:", error)
        return 1 if errors else 0
    text, counts, errors = build()
    for error in errors:
        print("ERROR:", error)
    if "--check" in sys.argv[1:]:
        for path, want in ((OUT, text), (COUNT_OUT, counts)):
            current = path.read_text(encoding="utf-8") if path.exists() else ""
            if current != want:
                print(f"{path.relative_to(ROOT)} is stale: run tools/facility_spinners.py")
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
