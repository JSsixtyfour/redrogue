#!/usr/bin/env python3
"""Offline validator for the Checkpoint 4 Facility premade fixture."""

from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "maps" / "ProceduralFacility_3x3_rock_room.blkv"
BLOCKSET = ROOT / "gfx" / "blocksets" / "facility.bst"
WIDTH = HEIGHT = 3
HUB = ITEM = (1, 1)
SOCKETS = {"N": (1, 0), "E": (2, 1), "S": (1, 2), "W": (0, 1)}
SOCKET_MASK = 0x0F
WALKABLE_TILES = {
    0x01, 0x10, 0x11, 0x13, 0x1B, 0x20, 0x21, 0x22, 0x30,
    0x31, 0x32, 0x42, 0x43, 0x48, 0x52, 0x55, 0x58, 0x5E,
}
QUADRANT_INDEXES = (5, 7, 13, 15)


def block_quadrants(blockset: bytes, block_id: int) -> tuple[bool, ...]:
    base = block_id * 16
    return tuple(blockset[base + i] in WALKABLE_TILES for i in QUADRANT_INDEXES)


def select_fixture(
    room_id: int,
    floor_w: int,
    floor_h: int,
    required: int,
    corners_clear: bool = True,
) -> bool:
    return (
        1 <= room_id <= 10
        and floor_w == 1
        and floor_h == 1
        and required & ~SOCKET_MASK == 0
        and corners_clear
    )


def expanded_cells(blocks: bytes, blockset: bytes, cut_mask: int) -> set[tuple[int, int]]:
    socket_bits = dict(zip("NESW", (1, 2, 4, 8)))
    cut_positions = {
        SOCKETS[name] for name, bit in socket_bits.items() if cut_mask & bit
    }
    cells = set()
    for by in range(HEIGHT):
        for bx in range(WIDTH):
            block_id = 0x0E if (bx, by) in cut_positions else blocks[by * WIDTH + bx]
            for q, walkable in enumerate(block_quadrants(blockset, block_id)):
                if walkable:
                    cells.add((bx * 2 + q % 2, by * 2 + q // 2))
    return cells


def reachable(cells: set[tuple[int, int]], start: tuple[int, int]) -> set[tuple[int, int]]:
    seen = {start}
    todo = deque([start])
    while todo:
        x, y = todo.popleft()
        for nxt in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if nxt in cells and nxt not in seen:
                seen.add(nxt)
                todo.append(nxt)
    return seen


def validate() -> list[str]:
    errors = []
    blocks = FIXTURE.read_bytes()
    blockset = BLOCKSET.read_bytes()
    if len(blocks) != WIDTH * HEIGHT:
        return [f"fixture is {len(blocks)} bytes, expected 9"]
    if HUB != ITEM or blocks[HUB[1] * WIDTH + HUB[0]] != 0x0E:
        errors.append("hub/item anchor must share the plain-floor center")
    for x, y in SOCKETS.values():
        if not (x in (0, WIDTH - 1) or y in (0, HEIGHT - 1)):
            errors.append("socket is not on the footprint perimeter")
    for required in range(16):
        if not select_fixture(1, 1, 1, required):
            errors.append(f"all-socket descriptor rejected required mask {required:#x}")
    for room_id in range(1, 11):
        if not select_fixture(room_id, 1, 1, 1):
            errors.append(f"middle room {room_id} rejected compatible 3x3 footprint")
    for room_id, w, h in ((0, 1, 1), (11, 1, 1), (1, 2, 1), (5, 1, 2)):
        if select_fixture(room_id, w, h, 1):
            errors.append(f"generic fallback failed for room {room_id} at {w}x{h}")
    if select_fixture(5, 1, 1, 1, corners_clear=False):
        errors.append("corner-crossing corridor did not force generic fallback")
    for x in range(1, 19):
        for y in range(1, 19):
            if not (0 <= x - 1 and x + 1 < 20 and 0 <= y - 1 and y + 1 < 20):
                errors.append(f"footprint out of bounds at interior {(x, y)}")
    center_cell = (HUB[0] * 2, HUB[1] * 2)
    edge_cells = {
        "N": {(2, 0), (3, 0)}, "E": {(5, 2), (5, 3)},
        "S": {(2, 5), (3, 5)}, "W": {(0, 2), (0, 3)},
    }
    bits = dict(zip("NESW", (1, 2, 4, 8)))
    for name, bit in bits.items():
        cells = expanded_cells(blocks, blockset, bit)
        seen = reachable(cells, center_cell)
        if not (seen & edge_cells[name]):
            errors.append(f"{name} socket cannot reach hub after cut")
        for other in set(bits) - {name}:
            if seen & edge_cells[other]:
                errors.append(f"uncut {other} perimeter leaks while cutting {name}")
    return errors


def main() -> int:
    errors = validate()
    if errors:
        for error in errors:
            print(error)
        return 1
    print("Facility premade fixture valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
