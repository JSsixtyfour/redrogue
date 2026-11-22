"""Walking the live Procedural Forest with real button presses.

The tile model is the cave's (test_cave_subroom.room_tiles/room_reach) for the
FOREST tileset: each step's collision tile is its quadrant's bottom-left 8x8
tile from forest.bst, walkable when it is in Forest_Coll, and a step between a
FOREST land tile pair is refused (pair_collision_tile_ids.asm). The map is read
live from wOverworldMap, so it is whichever floor is shown.
"""

from __future__ import annotations

import re
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SIZE, STRIDE, BASE = 20, 26, 81          # blocks; wOverworldMap row stride and (0, 0)
STEP = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}


def _walkable() -> set[int]:
    text = (ROOT / "data/tilesets/collision_tile_ids.asm").read_text(encoding="utf-8")
    m = re.search(r"^Forest_Coll::\s*\n\s*coll_tiles\s+([^\n;]+)", text, re.M)
    return {int(t.strip().lstrip("$"), 16) for t in m.group(1).split(",")}


def _pairs() -> set[tuple[int, int]]:
    text = (ROOT / "data/tilesets/pair_collision_tile_ids.asm").read_text(encoding="utf-8")
    land = text.split("TilePairCollisionsWater")[0]
    pairs = set()
    for a, b in re.findall(r"db FOREST, \$(\w\w), \$(\w\w)", land):
        pairs |= {(int(a, 16), int(b, 16)), (int(b, 16), int(a, 16))}
    return pairs


WALKABLE = _walkable()
PAIRS = _pairs()
BLOCKSET = (ROOT / "gfx/blocksets/forest.bst").read_bytes()


def tiles(h) -> dict[tuple[int, int], int]:
    """Step (x, y) -> its collision tile, from the live map."""
    origin = h.address("wOverworldMap") + BASE
    out = {}
    for by in range(SIZE):
        for bx in range(SIZE):
            block = h.pyboy.memory[origin + by * STRIDE + bx]
            for q, i in enumerate((4, 6, 12, 14)):
                out[(2 * bx + q % 2, 2 * by + q // 2)] = BLOCKSET[block * 16 + i]
    return out


def sprite_tiles(h, skip=()) -> set[tuple[int, int]]:
    """The steps every shown sprite (slots 1-15) stands on. A hidden one (a
    taken ball) keeps its picture but has image index $FF."""
    out = set()
    for s in range(1, 16):
        if s in skip or not h.read8(f"wSprite{s:02d}StateData1"):
            continue
        if h.read8(f"wSprite{s:02d}StateData1", offset=2) == 0xFF:
            continue
        out.add((h.read8(f"wSprite{s:02d}StateData2MapX") - 4, h.read8(f"wSprite{s:02d}StateData2MapY") - 4))
    return out


def path(h, goal, blocked=frozenset()) -> list[str] | None:
    """Buttons from the player's step to `goal`, or None."""
    grid = tiles(h)
    start = (h.read8("wXCoord"), h.read8("wYCoord"))
    came = {start: None}
    todo = deque([start])
    while todo:
        here = todo.popleft()
        if here == goal:
            break
        for button, (dx, dy) in STEP.items():
            there = (here[0] + dx, here[1] + dy)
            if (there in grid and there not in came and there not in blocked
                    and grid[there] in WALKABLE and (grid[here], grid[there]) not in PAIRS):
                came[there] = (here, button)
                todo.append(there)
    if goal not in came:
        return None
    out, at = [], goal
    while came[at]:
        at, button = came[at]
        out.append(button)
    return out[::-1]


def step(h, button: str, frames: int = 120, settle=None) -> bool:
    """Hold `button` until the player stands one step on. True when he did."""
    x, y = h.read8("wXCoord"), h.read8("wYCoord")
    want = (x + STEP[button][0], y + STEP[button][1])
    moved = False
    for _ in range(frames):
        if settle:
            settle()
        h.pyboy.button_press(button)
        h.tick(1)
        if (h.read8("wXCoord"), h.read8("wYCoord")) == want:
            moved = True
            break
    h.pyboy.button_release(button)
    h.tick(2)
    return moved


def walk(h, buttons, settle=None) -> None:
    for i, button in enumerate(buttons):
        if not step(h, button, settle=settle):
            raise AssertionError(f"stuck at {(h.read8('wXCoord'), h.read8('wYCoord'))} "
                                 f"pressing {button} (step {i + 1} of {len(buttons)})")
    for _ in range(16):                      # the last step's walk animation
        if settle:
            settle()
        h.tick(1)


def walk_to(h, goal, blocked=frozenset(), settle=None) -> None:
    buttons = path(h, goal, blocked)
    if buttons is None:
        raise AssertionError(f"no path from {(h.read8('wXCoord'), h.read8('wYCoord'))} to {goal}")
    walk(h, buttons, settle)


def outward(tile) -> str:
    """The button that leaves the 40x40 map from an edge step (x, y)."""
    x, y = tile
    return "up" if y == 0 else "down" if y == 2 * SIZE - 1 else "left" if x == 0 else "right"
