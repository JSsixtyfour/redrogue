#!/usr/bin/env python3
"""Offline validator for the Facility premade and large-decor fixtures.

Two independent asset families live under maps/ProceduralFacility_*:

- Large-decor fixtures (``*_decor.blk``): interior-only decoration blitted
  inside a generated room. This category's validation is unchanged from the
  original version of this script.
- Full-room premades (``*_room.blk``, ``*_room2.blk``, ``*_combinedroom.blk``,
  ``*_pool*.blk``): a hand-authored footprint (interior + generated wall
  ring) that can replace an entire generated room, ring included. This is
  the "R4" checkpoint from PROCEDURAL_FACILITY_COMPLETION_PLAN.md and is the
  part this rewrite adds.

Run with no arguments for the pass/fail gate (exit 0/1), or with --report to
print the machine-readable full-room audit table instead.

THE BASEBOARD (least obvious fact about this tileset, read before touching
socket/connectivity logic): every standard ring tile has exactly its INNER
quadrant(s) walkable, independent of whether the generator has "cut" that
position. This forms a permanent one-tile-wide walkway hugging the whole
interior face of the ring, so a room with a fully solid centre block is not
necessarily isolated -- you walk around the furniture, not through it.
Decoded quadrant walkability (TL/TR/BL/BR) for blocks seen in this asset
family, against facility.bst + WALKABLE_TILES:

    $40 TL corner   F F F T      $41 top wall     F F T T      $42 TR corner F F T F
    $44 left wall   F T F T      $46 right wall   T F T F
    $48 BL corner   F T F F      $49 bottom wall  T T F F      $4A BR corner T F F F
    $0E plain floor T T T T      $1D solid-bottom T T F F      $06 solid     F F F F
    $5C left decor  F F F F      $5D right decor  F F F F      (both FULLY SOLID --
                                                                  these sever the
                                                                  baseboard on their side)

Consequence: whether two sockets actually end up mutually reachable in a
given asset depends on whether ITS baseboard segments are intact between
them, so connectivity must be measured per asset (cut all four sockets,
take connected components) rather than assumed from the hub block alone in
either direction -- neither "hub must be walkable" nor "hub must be solid
therefore isolated" holds in general. ProceduralFacility_3x3_rock_room.blkv
(`5c 0e 5d`) is the clearest example: its baseboard is severed left and
right by $5C/$5D, so its N/E/S/W connectivity runs through the open $0E
centre instead of around the ring.
"""

from __future__ import annotations

import argparse
import re
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAPS_DIR = ROOT / "maps"
FIXTURE = MAPS_DIR / "ProceduralFacility_3x3_rock_room.blkv"
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
    "ProceduralFacility_1x3_doubletabletree_decor.blk": (1, 3),
    "ProceduralFacility_2x1_doubletable_decor.blk": (2, 1),
    "ProceduralFacility_2x2_blocktree_decor.blk": (2, 2),
    "ProceduralFacility_2x2_rocktree_decor.blk": (2, 2),
    "ProceduralFacility_2x3_block_decor.blk": (2, 3),
    "ProceduralFacility_3x2_tree_decor.blk": (3, 2),
    "ProceduralFacility_3x3_block_decor.blk": (3, 3),
    "ProceduralFacility_3x3_blockrock_decor.blk": (3, 3),
    "ProceduralFacility_3x3_rocktree_decor.blk": (3, 3),
    "ProceduralFacility_3x3_triplebigtable_decor.blk": (3, 3),
}
LARGE_DECOR_RUNTIME_FIXTURES = tuple(
    filename for filename in LARGE_DECOR_FIXTURES
    if filename not in {
        "ProceduralFacility_2x2_blocktree_decor.blk",
        "ProceduralFacility_3x3_block_decor.blk",
    }
)

# --- Full-room premade contract -------------------------------------------
#
# A full-room premade's filename encodes its FULL FOOTPRINT (interior plus
# the generated one-block wall ring) as ProceduralFacility_<W>x<H>_*.blk,
# W and H each in [3, 9]. The interior is (W-2) x (H-2).
FULLROOM_MIN_DIM = 3
FULLROOM_MAX_DIM = 9
FULLROOM_GROUP_LIMIT = 16
FULLROOM_NAME_RE = re.compile(r"^ProceduralFacility_(\d+)x(\d+)_")


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
    if "ProceduralFacility_2x2_blocktree_decor.blk" in LARGE_DECOR_RUNTIME_FIXTURES:
        errors.append("solid 2x2 block/tree fixture disconnected a generated room")

    errors.extend(f"{r.filename}: {r.reason}" for r in fullroom_integrity_errors())
    return errors


# ---------------------------------------------------------------------------
# Full-room premade discovery and validation
# ---------------------------------------------------------------------------

class FullRoomResult:
    """Plain class, not @dataclass: this module is loaded by
    test_facility_premades.py via importlib.util.module_from_spec +
    exec_module without registering the module in sys.modules first, which
    makes CPython 3.10's dataclasses.KW_ONLY forward-ref check crash with
    "'NoneType' object has no attribute '__dict__'". A plain __init__
    sidesteps that entirely.
    """

    def __init__(
        self,
        filename: str,
        w: int = 0,
        h: int = 0,
        status: str = "QUARANTINE",
        reason: str = "",
        roles: tuple[str, ...] = (),
        item_anchor: tuple[int, int] | None = None,
        is_integrity_error: bool = False,
        socket_mask: str = "",
    ) -> None:
        self.filename = filename
        self.w = w
        self.h = h
        self.status = status
        self.reason = reason
        self.roles = roles
        self.item_anchor = item_anchor
        self.is_integrity_error = is_integrity_error
        self.socket_mask = socket_mask


def discover_fullroom_files(maps_dir: Path = MAPS_DIR) -> list[Path]:
    """Every ProceduralFacility_<W>x<H>_* full-room asset, .blk or .blkv.

    Covers the *_room.blk, *_room2.blk (alternate variant), *_combinedroom.blk,
    *_pool*.blk families, and the one currently-wired ProceduralFacility_
    3x3_rock_room.blkv fixture (the .blkv extension is deliberate: it is
    the sole full-room premade the generator actually INCBINs today).
    Large-decor payloads (*_decor.blk) are handled elsewhere.
    """
    out = []
    for pattern in ("ProceduralFacility_*.blk", "ProceduralFacility_*.blkv"):
        for path in maps_dir.glob(pattern):
            name = path.name
            if name.endswith("_decor.blk"):
                continue
            lowered = name.lower()
            if "room" in lowered or "pool" in lowered:
                out.append(path)
    return sorted(out, key=lambda p: p.name)


def _footprint_grid(payload: bytes, w: int, h: int) -> list[list[int]]:
    return [list(payload[row * w:(row + 1) * w]) for row in range(h)]


def _hub_and_sockets(w: int, h: int) -> tuple[tuple[int, int], dict[str, tuple[int, int]]]:
    # Interior is (w-2) x (h-2); interior-relative center matches the
    # generator's own PFacRoomCenter (cx = X + W_interior/2, floor division).
    cx = (w - 2) // 2
    cy = (h - 2) // 2
    hub = (cx + 1, cy + 1)
    sockets = {
        "N": (cx + 1, 0),
        "S": (cx + 1, h - 1),
        "W": (0, cy + 1),
        "E": (w - 1, cy + 1),
    }
    return hub, sockets


def _expanded_cells_wh(
    grid: list[list[int]], blockset: bytes, w: int, h: int, cut: set[tuple[int, int]]
) -> set[tuple[int, int]]:
    cells = set()
    for by in range(h):
        for bx in range(w):
            block_id = 0x0E if (bx, by) in cut else grid[by][bx]
            for q, walkable in enumerate(block_quadrants(blockset, block_id)):
                if walkable:
                    cells.add((bx * 2 + q % 2, by * 2 + q // 2))
    return cells


def _side_edge_cells(w: int, h: int, hub_x: int, hub_y: int) -> dict[str, set[tuple[int, int]]]:
    return {
        "N": {(2 * hub_x, 0), (2 * hub_x + 1, 0)},
        "S": {(2 * hub_x, 2 * h - 1), (2 * hub_x + 1, 2 * h - 1)},
        "W": {(0, 2 * hub_y), (0, 2 * hub_y + 1)},
        "E": {(2 * w - 1, 2 * hub_y), (2 * w - 1, 2 * hub_y + 1)},
    }


def _side_leak_free(
    grid: list[list[int]], blockset: bytes, w: int, h: int,
    side: str, sockets: dict[str, tuple[int, int]],
    edge_cells: dict[str, set[tuple[int, int]]],
) -> bool:
    """Cut ONLY this side's socket to floor. If any OTHER (still-uncut)
    side's true outer-boundary quadrants become reachable, the wall ring
    has a hole independent of this cut and the side fails.
    """
    sx, sy = sockets[side]
    cells = _expanded_cells_wh(grid, blockset, w, h, {(sx, sy)})
    start = next(iter(edge_cells[side] & cells), None)
    if start is None:
        return False
    seen = reachable(cells, start)
    return not any(seen & edge_cells[other] for other in set("NESW") - {side})


def _connected_components(cells: set[tuple[int, int]]) -> list[set[tuple[int, int]]]:
    remaining = set(cells)
    components = []
    while remaining:
        seed = next(iter(remaining))
        comp = reachable(cells, seed)
        components.append(comp)
        remaining -= comp
    return components


def _outward_spills(
    grid: list[list[int]], blockset: bytes, w: int, h: int,
    sockets: dict[str, tuple[int, int]],
) -> list[tuple[int, int, int]]:
    """Perimeter cells that open OUTWARD anywhere other than a socket.

    The per-side leak test only asks about the four canonical outer edges, so it
    cannot see a payload that opens to the void somewhere else on its ring. Any
    such cell produces the "naked floor/void edge" defect in-game: the stamped
    room presents walkable ground with untouched void immediately beyond it and
    no wall in between.

    Two real causes in the authored set: a plain `$0E` left on the perimeter
    where the artist meant a wall, and a correct wall block placed on the WRONG
    side (a `$44` left-wall on the right edge), which points its walkable inner
    column outward.
    """
    socket_cells = set(sockets.values())
    spills: list[tuple[int, int, int]] = []
    for y in range(h):
        for x in range(w):
            if not (x in (0, w - 1) or y in (0, h - 1)):
                continue
            if (x, y) in socket_cells:
                continue
            block = grid[y][x]
            top_left, top_right, bottom_left, bottom_right = block_quadrants(
                blockset, block
            )
            outward = []
            if y == 0:
                outward += [top_left, top_right]
            if y == h - 1:
                outward += [bottom_left, bottom_right]
            if x == 0:
                outward += [top_left, bottom_left]
            if x == w - 1:
                outward += [top_right, bottom_right]
            if any(outward):
                spills.append((x, y, block))
    return spills


def evaluate_fullroom(path: Path, blockset: bytes, block_count: int) -> FullRoomResult:
    filename = path.name
    match = FULLROOM_NAME_RE.match(filename)
    if not match:
        return FullRoomResult(
            filename=filename, status="QUARANTINE",
            reason="filename dimensions do not parse", is_integrity_error=True,
        )
    w, h = int(match.group(1)), int(match.group(2))
    result = FullRoomResult(filename=filename, w=w, h=h)

    payload = path.read_bytes()
    expected_size = w * h
    if len(payload) != expected_size:
        result.reason = f"file is {len(payload)} bytes, expected {expected_size} ({w}x{h})"
        result.is_integrity_error = True
        return result

    invalid = sorted(set(payload) - set(range(block_count)))
    if invalid:
        result.reason = "invalid facility blocks: " + ", ".join(f"${b:02X}" for b in invalid)
        result.is_integrity_error = True
        return result

    if w < FULLROOM_MIN_DIM:
        result.reason = f"W={w} < {FULLROOM_MIN_DIM} (no interior)"
        return result
    if h < FULLROOM_MIN_DIM:
        result.reason = f"H={h} < {FULLROOM_MIN_DIM} (no interior)"
        return result
    if w > FULLROOM_MAX_DIM:
        result.reason = f"W={w} > {FULLROOM_MAX_DIM} (exceeds max footprint)"
        return result
    if h > FULLROOM_MAX_DIM:
        result.reason = f"H={h} > {FULLROOM_MAX_DIM} (exceeds max footprint)"
        return result

    grid = _footprint_grid(payload, w, h)
    hub, sockets = _hub_and_sockets(w, h)
    hub_x, hub_y = hub
    edge_cells = _side_edge_cells(w, h, hub_x, hub_y)

    spills = _outward_spills(grid, blockset, w, h, sockets)
    if spills:
        result.reason = (
            "walkable outward quadrant on a non-socket perimeter cell at "
            + ", ".join(f"({x},{y})=${block:02X}" for x, y, block in spills[:4])
            + (" ..." if len(spills) > 4 else "")
        )
        return result

    # Leak test: independent per side, cut in isolation (rule 1).
    leak_free = {
        name for name in "NESW"
        if _side_leak_free(grid, blockset, w, h, name, sockets, edge_cells)
    }

    # Connectivity: cut ALL FOUR sockets at once and partition into
    # connected components (rule 2). The shared ring art gives every wall
    # tile a permanently-open INNER quadrant (a one-tile baseboard hugging
    # the interior), so a solid-centre room is not necessarily isolated --
    # it may still be walkable all the way around its furniture. Whether
    # two sides actually end up mutually reachable is asset-specific (a
    # severed baseboard segment, e.g. $5C/$5D, can split the ring), so it
    # must be measured per asset rather than assumed either way.
    all_cut = set(sockets.values())
    full_cells = _expanded_cells_wh(grid, blockset, w, h, all_cut)
    components = _connected_components(full_cells)

    side_component: dict[str, int] = {}
    for name in "NESW":
        for idx, comp in enumerate(components):
            if edge_cells[name] & comp:
                side_component[name] = idx
                break

    # Only components that actually carry at least one socket are
    # candidates for "the" largest component; a stray decorative pocket
    # with no socket has nothing to report regardless of its size.
    comp_sides: dict[int, list[str]] = {}
    for name, idx in side_component.items():
        comp_sides.setdefault(idx, []).append(name)

    best_idx = None
    best_size = -1
    for name in "NESW":  # NESW order makes the size-tie tiebreak deterministic
        idx = side_component.get(name)
        if idx is None:
            continue
        size = len(components[idx])
        if size > best_size:
            best_size = size
            best_idx = idx

    mask_sides = comp_sides.get(best_idx, []) if best_idx is not None else []
    passed = "".join(name for name in "NESW" if name in mask_sides and name in leak_free)

    if len(passed) < 1:
        result.reason = "no mutually-connected socket pair (isolated or fully severed ring)"
        return result

    # Passed 1-6 with at least one reported socket: exploration-capable.
    result.status = "OK"
    result.roles = ("explore",)
    result.socket_mask = passed
    if item_anchor_safe(grid, hub_x, hub_y):
        result.roles = ("item", "explore")
        result.item_anchor = hub
    return result


def scan_fullrooms() -> list[FullRoomResult]:
    blockset = BLOCKSET.read_bytes()
    block_count = len(blockset) // 16
    return [
        evaluate_fullroom(path, blockset, block_count)
        for path in discover_fullroom_files()
    ]


def fullroom_integrity_errors() -> list[FullRoomResult]:
    """Only the subset of quarantines that indicate a genuinely broken asset
    (unparseable name, wrong byte count, illegal block id) rather than an
    asset quarantined by policy (dimension outside the supported 3..9
    window, or every socket failing the connectivity test). These are the
    only full-room findings that fail the default pass/fail gate;
    policy-quarantined assets are an expected, reviewable state surfaced by
    --report, not a build break.
    """
    return [r for r in scan_fullrooms() if r.is_integrity_error]


def format_report(results: list[FullRoomResult]) -> str:
    lines = []
    ok = [r for r in results if r.status == "OK"]
    quarantined = [r for r in results if r.status != "OK"]
    ordered = sorted(results, key=lambda r: (r.w, r.h, r.filename))
    for r in ordered:
        if r.status == "OK":
            item = f"{r.item_anchor[0]},{r.item_anchor[1]}" if r.item_anchor else "-,-"
            lines.append(
                f"{r.filename} W={r.w} H={r.h} sockets={r.socket_mask} "
                f"item={item} status=OK"
            )
        else:
            lines.append(
                f"{r.filename} W={r.w} H={r.h} status=QUARANTINE reason={r.reason}"
            )

    lines.append("")
    lines.append("# Size-group summary (status=OK only; item-capable listed first per group)")
    groups: dict[tuple[int, int], list[FullRoomResult]] = {}
    for r in ok:
        groups.setdefault((r.w, r.h), []).append(r)
    for (w, h), members in sorted(groups.items()):
        members = sorted(members, key=lambda r: (r.item_anchor is None, r.filename))
        item_capable = sum(1 for r in members if r.item_anchor is not None)
        flag = " OVER LIMIT" if len(members) > FULLROOM_GROUP_LIMIT else ""
        lines.append(
            f"{w}x{h}: count={len(members)} item_capable={item_capable}{flag}"
        )
        for r in members:
            tag = "item" if r.item_anchor is not None else "explore"
            lines.append(f"  {r.filename} ({tag}, sockets={r.socket_mask})")

    lines.append("")
    lines.append("# Socket-mask histogram (status=OK only)")
    mask_counts: dict[str, int] = {}
    for r in ok:
        mask_counts[r.socket_mask] = mask_counts.get(r.socket_mask, 0) + 1
    for mask, count in sorted(mask_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"{mask}: {count}")

    total = len(results)
    lines.append("")
    lines.append(
        f"# total={total} ok={len(ok)} quarantined={len(quarantined)}"
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--report", action="store_true",
        help="Print the full-room audit table instead of running the pass/fail gate.",
    )
    args = parser.parse_args()

    if args.report:
        print(format_report(scan_fullrooms()), end="")
        return 0

    errors = validate()
    if errors:
        for error in errors:
            print(error)
        return 1
    print("Facility premade fixture valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
