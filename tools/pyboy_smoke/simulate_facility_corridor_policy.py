#!/usr/bin/env python3
"""Decide whether corridor rerouting would actually cut Facility layout retries.

`attribute_facility_rejections.py` establishes that every rejected Facility
layout is one parent-tree corridor clipping one room's footprint corner, and
that the opposite L leg order misses THAT corner. That is not sufficient: the
opposite order can clip a DIFFERENT room's corner instead, so the real rescue
rate has to be simulated over whole layouts.

This captures real rejected layouts from the ROM and replays three routing
policies against each, reporting how many layouts each one would have saved:

  current  what ships today: always horizontal leg first.
  greedy   horizontal first unless it clips a guarded corner, then vertical.
  elbow    the two L orders, then Z-routes with the elbow shifted along the
           horizontal span - still a monotone manhattan walk, one extra turn.

Premade footprints are exempt from the corner check exactly as
PFacValidateGeneratedCorners is (type byte bit 7).

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/simulate_facility_corridor_policy.py [--seeds N]
"""

from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

ROOM_MAX = 12
STRIDE = 6
TEMPLATE_BIT = 0x80


def centre(origin: int, size: int) -> int:
    """PFacRoomCenter: floor(size / 2) added to the origin."""
    return origin + (size >> 1)


def l_path(sx, sy, tx, ty, horizontal_first):
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


def corners(records, exempt_premades=True):
    """Footprint corners.

    PFacValidateGeneratedCorners exempts stamped premades, so that is the set a
    layout is JUDGED against. The router cannot use it: routing runs inside
    PFacCarveCorridors, which is called once BEFORE premade selection and once
    after, and both passes must choose the same route or the second pass carves
    a different corridor than the first. So the router is given the strict set
    (exempt_premades=False) and is deliberately conservative.
    """
    guarded = set()
    for room in range(ROOM_MAX):
        base = room * STRIDE
        x, y, w, h = records[base:base + 4]
        if w == 0:
            continue
        if exempt_premades and records[base + 5] & TEMPLATE_BIT:
            continue
        guarded |= {(x - 1, y - 1), (x + w, y - 1),
                    (x + w, y + h), (x - 1, y + h)}
    return guarded


def corridors(records):
    """(source centre, parent centre) per placed room, in PFacCarveCorridors order."""
    plan = []
    for source in range(ROOM_MAX - 1, 0, -1):
        base = source * STRIDE
        x, y, w, h = records[base:base + 4]
        if w == 0:
            continue
        parent = records[base + 4]
        pbase = parent * STRIDE
        px, py, pw, ph = records[pbase:pbase + 4]
        if pw == 0:
            continue
        plan.append(((centre(x, w), centre(y, h)), (centre(px, pw), centre(py, ph))))
    return plan


def routes(start, end, policy):
    """Candidate paths for one corridor, best-first, under the named policy."""
    options = [l_path(*start, *end, True)]
    if policy in ("greedy", "elbow"):
        options.append(l_path(*start, *end, False))
    if policy == "elbow":
        (sx, sy), (tx, ty) = start, end
        step = 1 if sx < tx else -1
        for elbow in range(sx, tx + step, step):
            options.append(
                l_path(sx, sy, elbow, sy, True)
                + l_path(elbow, sy, elbow, ty, False)
                + l_path(elbow, ty, tx, ty, True)
            )
    return options


def rescued(records, policy):
    """(layout would now pass validation, how many corridors were rerouted)."""
    routing_guard = corners(records, exempt_premades=False)
    validation_guard = corners(records, exempt_premades=True)
    stamped = set()
    reroutes = 0
    for start, end in corridors(records):
        options = routes(start, end, policy)
        chosen = options[0]
        for index, option in enumerate(options):
            if not routing_guard.intersection(option):
                chosen = option
                reroutes += 1 if index else 0
                break
        stamped |= set(chosen)
    return not validation_guard.intersection(stamped), reroutes


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
    captured: list[bytes] = []

    def on_invalid(_context) -> None:
        harness.pyboy.memory[0x0000] = 0x0A
        harness.pyboy.memory[0x4000] = 1
        captured.append(bytes(harness.pyboy.memory[scratch + i] for i in range(72)))
        harness.pyboy.memory[0x0000] = 0

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

    total = len(captured)
    print(f"seeds {args.seeds}   rejected layouts captured {total}\n")
    if not total:
        print("no rejections in this sample")
        return 0
    print("policy                             rescued   reroutes/layout")
    for policy, label in (
        ("current", "H-first always (today)"),
        ("greedy", "H-first, else V-first"),
        ("elbow", "H, V, then Z with shifted elbow"),
    ):
        results = [rescued(records, policy) for records in captured]
        saved = sum(1 for ok, _ in results if ok)
        reroutes = sum(count for _, count in results)
        print(f"{label:34s} {saved:4d} ({saved / total:3.0%})"
              f" {reroutes / total:14.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
