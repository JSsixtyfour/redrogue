#!/usr/bin/env python3
"""Offline validator for the Facility premade and large-decor fixtures."""

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
FULLY_WALKABLE_DECOR_BLOCKS = {0x0E, 0x2C, 0x3B, 0x3F}
VERTICAL_PASS_DECOR_BLOCKS = FULLY_WALKABLE_DECOR_BLOCKS | {
    0x20, 0x31, 0x38, 0x39, 0x45, 0x77,
}
HORIZONTAL_PASS_DECOR_BLOCKS = FULLY_WALKABLE_DECOR_BLOCKS | {0x19}
ITEM_ANCHOR_BLOCKS = FULLY_WALKABLE_DECOR_BLOCKS | {0x47}
LARGE_DECOR_FIXTURES = {
    "ProceduralFacility_2x2_eve_decor.blk": (2, 2),
    "ProceduralFacility_2x3_eve_decor.blk": (2, 3),
    "ProceduralFacility_3x2_tree_decor.blk": (3, 2),
    "ProceduralFacility_3x3_block_decor.blk": (3, 3),
    "ProceduralFacility_3x3_eve_decor.blk": (3, 3),
    "ProceduralFacility_3x3_rocktree_decor.blk": (3, 3),
}
LARGE_DECOR_RUNTIME_FIXTURES = tuple(
    filename for filename in LARGE_DECOR_FIXTURES
    if filename != "ProceduralFacility_3x3_block_decor.blk"
)


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


def large_decor_offset_safe(
    blocks: bytes,
    decor_w: int,
    decor_h: int,
    room_w: int,
    room_h: int,
    off_x: int,
    off_y: int,
    door_mask: int = 0x0F,
) -> bool:
    """Mirror the generator's hub and actual socket-lane contract."""
    if decor_w > room_w or decor_h > room_h:
        return False
    if not (0 <= off_x <= room_w - decor_w and 0 <= off_y <= room_h - decor_h):
        return False
    center_x, center_y = room_w // 2, room_h // 2
    for y in range(decor_h):
        for x, block in enumerate(blocks[y * decor_w:(y + 1) * decor_w]):
            room_x, room_y = off_x + x, off_y + y
            if (room_x, room_y) == (center_x, center_y):
                if block not in FULLY_WALKABLE_DECOR_BLOCKS:
                    return False
            elif room_x == center_x:
                north_lane = room_y < center_y and door_mask & 0x01
                south_lane = room_y > center_y and door_mask & 0x04
                if (north_lane or south_lane) and block not in VERTICAL_PASS_DECOR_BLOCKS:
                    return False
            elif room_y == center_y:
                west_lane = room_x < center_x and door_mask & 0x08
                east_lane = room_x > center_x and door_mask & 0x02
                if (west_lane or east_lane) and block not in HORIZONTAL_PASS_DECOR_BLOCKS:
                    return False
    return True


def valid_large_decor_offsets(
    blocks: bytes, decor_w: int, decor_h: int, room_w: int, room_h: int,
    door_mask: int = 0x0F,
) -> list[tuple[int, int]]:
    return [
        (x, y)
        for y in range(room_h - decor_h + 1)
        for x in range(room_w - decor_w + 1)
        if large_decor_offset_safe(
            blocks, decor_w, decor_h, room_w, room_h, x, y, door_mask
        )
    ]


def item_anchor_safe(blocks: list[list[int]], x: int, y: int) -> bool:
    """Mirror the generator's conservative block-level item-anchor rule."""
    block = blocks[y][x]
    if block in FULLY_WALKABLE_DECOR_BLOCKS:
        return True
    if block != 0x47:
        return False
    return any(
        0 <= nx < len(blocks[0])
        and 0 <= ny < len(blocks)
        and blocks[ny][nx] in FULLY_WALKABLE_DECOR_BLOCKS
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))
    )


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

    block_count = len(blockset) // 16
    for filename, (decor_w, decor_h) in LARGE_DECOR_FIXTURES.items():
        payload = (ROOT / "maps" / filename).read_bytes()
        expected_size = decor_w * decor_h
        if len(payload) != expected_size:
            errors.append(
                f"{filename} is {len(payload)} bytes, expected {expected_size}"
            )
            continue
        invalid = sorted(set(payload) - set(range(block_count)))
        if invalid:
            errors.append(
                f"{filename} contains invalid facility blocks: "
                + ", ".join(f"${block:02X}" for block in invalid)
            )
        if not set(payload) & FULLY_WALKABLE_DECOR_BLOCKS:
            errors.append(f"{filename} has no fully walkable block")
        if not any(
            valid_large_decor_offsets(
                payload, decor_w, decor_h, room_w, room_h
            )
            for room_h in range(decor_h, 8)
            for room_w in range(decor_w, 8)
        ):
            errors.append(
                f"{filename} has no center-cross-safe placement in a 1..7 interior"
            )

    if 0x47 not in ITEM_ANCHOR_BLOCKS:
        errors.append("table $47 must remain an approved item-display anchor")
    if 0x47 in FULLY_WALKABLE_DECOR_BLOCKS:
        errors.append("table $47 must not be treated as fully walkable decor")
    if "ProceduralFacility_3x3_block_decor.blk" in LARGE_DECOR_RUNTIME_FIXTURES:
        errors.append("nested 3x3 block fixture must remain disabled pending redesign")
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
