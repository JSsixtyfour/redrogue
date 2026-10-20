"""Overworld model for the autoplay agent: walkability and path finding.

Pure functions over bytes already read out of the game, so everything here can
be unit-tested without a ROM (test_autoplay_world.py). autoplay.py does the
reading.

The model mirrors the overworld movement code in home/overworld.asm:

- A map step (x, y) stands on the lower-left tile of its 2x2 tile square
  (lda_coord 8, 9 in CheckForTilePairCollisions2), so that tile alone decides
  whether the step is walkable, checked against the tileset's passable list
  (CheckTilePassable, wTilesetCollisionPtr).
- TilePairCollisionsLand forbids crossing between two specific tiles on one
  tileset, in either direction (elevation edges in caverns and forests).
- LedgeTiles lets the player jump two steps in one direction when standing on
  a given tile with a ledge tile in front; ledges are otherwise impassable.
- Arrow tiles (DecodeArrowMovementRLE tables, e.g. Viridian Gym) take over
  the joypad when stepped on and carry the player along a fixed movement
  list, and warp pads into the same map (Saffron Gym) move the player to
  another pad. Both are teleports: entering the step lands somewhere else.

Sprites and warps are not part of the grid: the caller passes them as blocked
steps, because both change while the agent walks.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field

DIRECTIONS = {
    "up": (0, -1),
    "down": (0, 1),
    "left": (-1, 0),
    "right": (1, 0),
}

# PAD_* bits (constants/hardware.inc), as arrow movement lists store them.
PAD_DIRECTIONS = {0x80: "down", 0x40: "up", 0x20: "left", 0x10: "right"}

# SPRITE_FACING_* values, as LedgeTiles stores them.
FACING = {"down": 0x0, "up": 0x4, "left": 0x8, "right": 0xC}

BLOCK_TILES = 4  # a block is 4x4 tiles
MAP_BORDER = 3  # wOverworldMap pads each side with 3 border blocks


@dataclass(frozen=True)
class Ledge:
    facing: int
    standing: int
    ledge: int


@dataclass
class WalkGrid:
    width: int  # in steps
    height: int
    tiles: list[list[int]]  # [y][x] tile the player stands on at that step
    passable: frozenset[int]
    tileset: int = 0
    pair_collisions: frozenset[tuple[int, int, int]] = frozenset()  # (tileset, a, b)
    ledges: tuple[Ledge, ...] = ()
    teleports: dict[tuple[int, int], tuple[int, int]] = field(default_factory=dict)
    _pairs: set[tuple[int, int]] = field(init=False, repr=False)

    def __post_init__(self) -> None:
        self._pairs = set()
        for tileset, a, b in self.pair_collisions:
            if tileset == self.tileset:
                self._pairs.add((a, b))
                self._pairs.add((b, a))

    def in_bounds(self, x: int, y: int) -> bool:
        return 0 <= x < self.width and 0 <= y < self.height

    def tile(self, x: int, y: int) -> int:
        return self.tiles[y][x]

    def walkable(self, x: int, y: int) -> bool:
        return self.in_bounds(x, y) and self.tiles[y][x] in self.passable

    def moves(self, x: int, y: int):
        """Yield (direction, (nx, ny)) for each step the player can take from
        (x, y), ledge jumps included. Ignores sprites and warps."""
        here = self.tile(x, y)
        for direction, (dx, dy) in DIRECTIONS.items():
            nx, ny = x + dx, y + dy
            if not self.in_bounds(nx, ny):
                continue
            front = self.tile(nx, ny)
            if front in self.passable:
                if (here, front) not in self._pairs:
                    yield direction, self.teleports.get((nx, ny), (nx, ny))
                continue
            for ledge in self.ledges:
                if (
                    ledge.facing == FACING[direction]
                    and ledge.standing == here
                    and ledge.ledge == front
                ):
                    lx, ly = nx + dx, ny + dy
                    if self.walkable(lx, ly):
                        yield direction, (lx, ly)
                    break


def grid_from_blocks(
    width_blocks: int,
    height_blocks: int,
    overworld_map: bytes | list[int],
    blockset: bytes | list[int],
    passable,
    *,
    tileset: int = 0,
    pair_collisions=(),
    ledges=(),
    teleports=None,
) -> WalkGrid:
    """Build the step grid from wOverworldMap (with its 3-block border) and the
    tileset's blockset (16 tile ids per block)."""
    stride = width_blocks + 2 * MAP_BORDER
    tiles = []
    for y in range(height_blocks * 2):
        row = []
        for x in range(width_blocks * 2):
            block = overworld_map[(y // 2 + MAP_BORDER) * stride + x // 2 + MAP_BORDER]
            # Lower-left tile of the step's 2x2 square inside the 4x4 block.
            row.append(blockset[block * 16 + ((y % 2) * 2 + 1) * BLOCK_TILES + (x % 2) * 2])
        tiles.append(row)
    return WalkGrid(
        width=width_blocks * 2,
        height=height_blocks * 2,
        tiles=tiles,
        passable=frozenset(passable),
        tileset=tileset,
        pair_collisions=frozenset(pair_collisions),
        ledges=tuple(ledges),
        teleports=dict(teleports or {}),
    )


def arrow_destination(start: tuple[int, int], movements) -> tuple[int, int]:
    """Where an arrow tile's forced movement ends: movements is its decoded
    RLE list of (PAD_* direction bit, step count)."""
    x, y = start
    for pad, count in movements:
        dx, dy = DIRECTIONS[PAD_DIRECTIONS[pad]]
        x, y = x + dx * count, y + dy * count
    return x, y


def find_path(
    grid: WalkGrid,
    start: tuple[int, int],
    goals,
    blocked=frozenset(),
    *,
    enter_impassable_goals: bool = False,
) -> list[str] | None:
    """Shortest list of directions from start to any goal step, or None.

    With enter_impassable_goals, a goal one step away is entered even if its
    tile is not in the passable list: warp tiles often are not (doors,
    ladders, map-edge exits). Blocked steps are never entered."""
    goals = set(goals)
    if start in goals:
        return []
    blocked = set(blocked) - goals
    parents: dict[tuple[int, int], tuple[tuple[int, int], str] | None] = {start: None}
    queue = deque([start])
    while queue:
        x, y = queue.popleft()
        steps = list(grid.moves(x, y))
        # A goal that is terrain-impassable (warp tiles often are) is still
        # reachable by walking into it.
        for direction, (dx, dy) in DIRECTIONS.items():
            target = (x + dx, y + dy)
            if (
                enter_impassable_goals
                and target in goals
                and all(target != step for _, step in steps)
            ):
                steps.append((direction, target))
        for direction, step in steps:
            if step in parents or step in blocked:
                continue
            parents[step] = ((x, y), direction)
            if step in goals:
                path = []
                node = step
                while parents[node] is not None:
                    node, move = parents[node]
                    path.append(move)
                return path[::-1]
            queue.append(step)
    return None


def adjacent_facing(target: tuple[int, int], counters=frozenset(), grid: WalkGrid | None = None):
    """Steps from which pressing A talks to the object at target, with the
    direction to face. Includes standing two away across a counter tile
    (wTilesetTalkingOverTiles), which is how the lobby nurse and clerks are
    reached."""
    tx, ty = target
    result = {}
    for direction, (dx, dy) in DIRECTIONS.items():
        result[(tx - dx, ty - dy)] = direction
        if grid is not None and counters:
            mx, my = tx - dx, ty - dy
            if grid.in_bounds(mx, my) and grid.tile(mx, my) in counters:
                result[(tx - 2 * dx, ty - 2 * dy)] = direction
    return result


def render(grid: WalkGrid, marks: dict[tuple[int, int], str] | None = None) -> str:
    """ASCII map for logs: '.' walkable, '#' not, plus caller marks."""
    marks = marks or {}
    lines = []
    for y in range(grid.height):
        lines.append("".join(
            marks.get((x, y), "." if grid.walkable(x, y) else "#")
            for x in range(grid.width)
        ))
    return "\n".join(lines)
