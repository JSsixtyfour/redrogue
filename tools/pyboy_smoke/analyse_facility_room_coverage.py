#!/usr/bin/env python3
"""Per-room-slot coverage: who gets placed, who gets content, and who falls back.

`analyse_facility_room_sizes.py` answers "which SIZES occur". This answers
"which SLOTS occur, how big are they, and what content actually lands in them",
which is what the empty-entry/empty-exit and rare-big-room questions need.

The slots are fixed by role: 0 is the entry room, 1-4 are item rooms, 5-10 are
explore rooms, 11 is the exit room. The three content passes do not cover them
equally - the ranges are read off the source, not assumed:

  PFacSelectPremadeMiddleRooms   rooms 1-10
  PFacPlaceLargeDecor            rooms 1-10
  PFacDecorateExploreRooms       rooms 5-10

It also counts PFacForceItemRoom, the guaranteed-placement fallback an item room
takes when all 40 of its candidate rolls are rejected. That matters twice over:
the fallback hard-codes a 3x3 interior (5x5 footprint), falling back again to
1x1 (3x3 footprint), so a high fire rate would mean the two commonest sizes on
the map are not rolled at all, they are forced.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/analyse_facility_room_coverage.py [--seeds N]
"""

from __future__ import annotations

import argparse
import io
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

RECORD_STRIDE = 6
ROOM_MAX = 12
TEMPLATE_BIT = 0x80
LARGE_DECOR_BIT = 0x40


def role(room: int) -> str:
    if room == 0:
        return "entry"
    if room == 11:
        return "exit"
    return "item" if room <= 4 else "explore"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=64)
    args = parser.parse_args()

    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    harness.boot_to_lobby()
    harness.call_routine("PFacPreload", limit=60000)
    baseline = io.BytesIO()
    harness.save_state(baseline)

    scratch = harness.address("sProcFacilityGenScratch")
    captured: list[bytes] = []
    forced = {"total": 0, "small": 0}

    def capture(_context) -> None:
        captured.append(bytes(
            harness.pyboy.memory[scratch + offset] for offset in range(72)
        ))

    def count_forced(_context) -> None:
        forced["total"] += 1

    def count_forced_small(_context) -> None:
        forced["small"] += 1

    harness.register_hook("PFacPlaceItems", capture)
    harness.register_hook("PFacForceItemRoom", count_forced)
    # The second .scan entry is the 1x1 retry after the 3x3 sweep found nothing.
    harness.register_hook("PFacForceItemRoom.scan", count_forced_small)

    placed = Counter()
    premade = Counter()
    large = Counter()
    sizes: dict[int, Counter] = defaultdict(Counter)
    layouts = 0

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
        captured.clear()
        harness.call_routine("PFacFinalize", limit=4000)
        if not captured:
            continue
        layouts += 1
        records = captured[0]
        for room in range(ROOM_MAX):
            base = room * RECORD_STRIDE
            width, height = records[base + 2], records[base + 3]
            if width == 0:
                continue
            placed[room] += 1
            sizes[room][(width + 2, height + 2)] += 1
            if records[base + 5] & TEMPLATE_BIT:
                premade[room] += 1
            if records[base + 5] & LARGE_DECOR_BIT:
                large[room] += 1

    print(f"layouts {layouts}\n")
    print("slot  role     placed   premade  largedecor   mean footprint   modal footprint")
    for room in range(ROOM_MAX):
        count = placed[room]
        if count == 0:
            print(f"{room:4d}  {role(room):8s}   never placed")
            continue
        area = sizes[room]
        mean_w = sum(w * n for (w, _), n in area.items()) / count
        mean_h = sum(h * n for (_, h), n in area.items()) / count
        modal, modal_n = area.most_common(1)[0]
        print(
            f"{room:4d}  {role(room):8s} {count / layouts:6.0%}"
            f"  {premade[room] / count:8.0%}  {large[room] / count:10.0%}"
            f"      {mean_w:4.1f} x {mean_h:4.1f}"
            f"      {modal[0]}x{modal[1]} ({modal_n / count:.0%})"
        )

    print("\nfootprint distribution, entry (slot 0) and exit (slot 11):")
    for room in (0, 11):
        top = ", ".join(
            f"{w}x{h} {n / placed[room]:.0%}"
            for (w, h), n in sizes[room].most_common(6)
        )
        print(f"  {role(room):6s} {top}")

    item_rooms = layouts * 4
    print(f"\nPFacForceItemRoom fired {forced['total']} times"
          f" over {item_rooms} item-room placements"
          f" ({forced['total'] / item_rooms:.0%})")
    print("  when it fires the room is NOT rolled: it is a forced 3x3 interior"
          " (5x5 footprint),")
    print("  or a forced 1x1 interior (3x3 footprint) if no 3x3 fits.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
