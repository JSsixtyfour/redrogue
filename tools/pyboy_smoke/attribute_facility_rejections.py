#!/usr/bin/env python3
"""Attribute every rejected Facility layout to the exact spoiled room corner.

`PFacValidateGeneratedCorners` is the ONLY gate that can throw a layout away,
and a rejection costs a full pipeline re-run. This hooks its `.invalid` exit and
records, for each rejection: which room failed, which of its four footprint
corners, and what block was sitting there instead.

It then asks the question that decides whether a cheap fix exists: the corridor
carver always walks its L horizontal-leg-first, so would carving the SAME
corridor vertical-leg-first have missed the corner it clipped? Room records and
both centres are known here, so the alternate path is reproduced in Python
without touching the ROM.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/attribute_facility_rejections.py [--seeds N]
"""

from __future__ import annotations

import argparse
import io
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

PFAC_SIZE = 20
ROOM_MAX = 12
STRIDE = 6
CORNER_NAMES = ("TL", "TR", "BR", "BL")

# wBuffer offsets, from procedural_facility_gen.asm.
OFF_CUR_X, OFF_CUR_Y, OFF_RM_IDX = 2, 3, 4


def room_center(x: int, w: int) -> int:
    """PFacRoomCenter: floor(w / 2) added to the origin."""
    return x + (w >> 1)


def l_path(sx: int, sy: int, tx: int, ty: int, horizontal_first: bool):
    """Cells PFacCarveOneCorridor stamps, in either leg order."""
    cells = []
    x, y = sx, sy
    if horizontal_first:
        while x != tx:
            cells.append((x, y))
            x += 1 if x < tx else -1
        while y != ty:
            cells.append((x, y))
            y += 1 if y < ty else -1
    else:
        while y != ty:
            cells.append((x, y))
            y += 1 if y < ty else -1
        while x != tx:
            cells.append((x, y))
            x += 1 if x < tx else -1
    cells.append((tx, ty))
    return cells


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=48)
    args = parser.parse_args()

    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    harness.boot_to_lobby()
    harness.call_routine("PFacPreload", limit=60000)
    baseline = io.BytesIO()
    harness.save_state(baseline)

    scratch = harness.address("sProcFacilityGenScratch")
    buffer_base = harness.address("wBuffer")
    rejections: list[dict] = []

    def on_invalid(_context) -> None:
        harness.pyboy.memory[0x0000] = 0x0A
        harness.pyboy.memory[0x4000] = 1
        records = bytes(harness.pyboy.memory[scratch + i] for i in range(72))
        harness.pyboy.memory[0x0000] = 0
        rejections.append({
            "room": harness.pyboy.memory[buffer_base + OFF_RM_IDX],
            "x": harness.pyboy.memory[buffer_base + OFF_CUR_X],
            "y": harness.pyboy.memory[buffer_base + OFF_CUR_Y],
            "records": records,
        })

    harness.register_hook("PFacValidateGeneratedCorners.invalid", on_invalid)

    state = 0x1234_5678
    for index in range(args.seeds):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        seed = [(state >> shift) & 0xFF for shift in (0, 8, 16, 24)]
        harness.load_state(baseline)
        harness.write_sram_bytes("sProcFacilityExitEdge", [index % 3])
        harness.write8("hRandomAdd", seed[0])
        harness.write8("hRandomSub", seed[1])
        harness.write8("hRandomLast", seed[2])
        harness.write8("hRandomLast", seed[3], offset=1)
        harness.call_routine("PFacFinalize", limit=4000)

    by_room: Counter = Counter()
    by_corner: Counter = Counter()
    culprits: Counter = Counter()
    avoidable = 0
    unattributed = 0

    for entry in rejections:
        records, room = entry["records"], entry["room"]
        by_room[room] += 1
        base = room * STRIDE
        rx, ry, rw, rh = records[base:base + 4]
        corner = {
            (rx - 1, ry - 1): "TL", (rx + rw, ry - 1): "TR",
            (rx + rw, ry + rh): "BR", (rx - 1, ry + rh): "BL",
        }.get((entry["x"], entry["y"]), "?")
        by_corner[corner] += 1

        # Which corridor stamped that cell, and would the other leg order miss it?
        target = (entry["x"], entry["y"])
        found = False
        for source in range(1, ROOM_MAX):
            sbase = source * STRIDE
            sx, sy, sw, sh = records[sbase:sbase + 4]
            if sw == 0:
                continue
            parent = records[sbase + 4]
            pbase = parent * STRIDE
            px, py, pw, ph = records[pbase:pbase + 4]
            if pw == 0:
                continue
            start = (room_center(sx, sw), room_center(sy, sh))
            end = (room_center(px, pw), room_center(py, ph))
            if target in l_path(*start, *end, True):
                found = True
                culprits[f"room {source} -> parent {parent}"] += 1
                if target not in l_path(*start, *end, False):
                    avoidable += 1
                break
        if not found:
            unattributed += 1

    total = len(rejections)
    print(f"seeds {args.seeds}   rejections {total}\n")
    if not total:
        print("no layout was rejected in this sample")
        return 0
    print("failing room id:", dict(sorted(by_room.items())))
    print("failing corner: ", dict(by_corner))
    print(f"\nattributed to a parent-tree corridor : {total - unattributed}"
          f" ({(total - unattributed) / total:.0%})")
    print(f"unattributed (other corridor/cause)  : {unattributed}")
    if total - unattributed:
        print(f"\nwould the OTHER L leg order have missed the corner?")
        print(f"  yes: {avoidable} of {total - unattributed}"
              f" ({avoidable / (total - unattributed):.0%})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
