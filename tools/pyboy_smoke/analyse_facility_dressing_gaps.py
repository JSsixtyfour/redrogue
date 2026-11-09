#!/usr/bin/env python3
"""Why is a Facility entry / item / exit room bare, and who made it bare?

`analyse_facility_room_coverage.py` says HOW MUCH content lands per slot. This
says WHY the rest does not, per footprint, and for perimeter refusals, WHOSE
corridor caused it. Every bare room (no premade, no large decor, no spinner) is
filed under one reason:

  no-art     the footprint's size group is empty, ChooseTemplate is never reached
  perimeter  art exists but PFacPremadePerimeterClear saw a corridor on a ring
             cell that is not a canonical socket
  sockets    ChooseTemplate ran but no payload passed the socket / role bits

Perimeter refusals are split by the corridor that stamped the offending cell:

  own        a corridor with this room as source or target (its parent edge or a
             child's edge). Corridor-accepting premades (plan phase 1) fix these.
  other      only corridors between OTHER rooms cross the cell. Phase 1 can still
             accept them, but only if the ring cell is safe to cut, so they are
             reported separately.
  shape      the refused cell is a footprint corner (never acceptable).

The refused cell is the FIRST ring cell the scan hit, not every offender.
Corridors are logged at PFacCorStampCell from the start of each attempt, so the
log matches the attempt that produced the final layout.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/analyse_facility_dressing_gaps.py [--seeds N]
"""

from __future__ import annotations

import argparse
import io
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
ASM = REPO_ROOT / "custom_functions" / "procedural_facility_gen.asm"

STRIDE = 6
WBUF_CUR_X, WBUF_CUR_Y, WBUF_COR_ID = 2, 3, 4   # wPFacCurX / CurY / CorId
WBUF_RM_RECT = 5                                 # wPFacRmX..H
WBUF_TPL_NEED = 19                               # wPFacTplNeed
ROLES = ("entry", "item", "exit")


def role_of(room: int) -> str:
    return "entry" if room == 0 else "exit" if room == 11 else "item"


def descriptor_groups() -> Counter:
    text = ASM.read_text()
    seg = text[text.index("PFacRoomDescriptors:"):text.index("PFacRoomDescriptorsEnd:")]
    return Counter(f"{w}x{h}" for w, h in re.findall(r"db (\d), (\d),", seg))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=128)
    args = ap.parse_args()

    groups = descriptor_groups()
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    h.boot_to_lobby()
    h.call_routine("PFacPreload", limit=60000)
    base = io.BytesIO()
    h.save_state(base)
    buf = h.address("wBuffer")
    scratch = h.address("sProcFacilityGenScratch")

    chose: dict = {}
    stamped: set = set()
    blocked: dict = {}
    cor_log: dict = defaultdict(set)   # (x, y) -> {source room ids}
    captured: list = []

    def rect():
        m = h.pyboy.memory
        return tuple(m[buf + WBUF_RM_RECT + i] for i in range(4))

    def on_attempt(_):
        cor_log.clear()

    def on_select(_):
        chose.clear()
        stamped.clear()
        blocked.clear()

    def on_cor_cell(_):
        m = h.pyboy.memory
        cor_log[(m[buf + WBUF_CUR_X], m[buf + WBUF_CUR_Y])].add(m[buf + WBUF_COR_ID])

    def on_choose(_):
        chose[rect()] = h.pyboy.memory[buf + WBUF_TPL_NEED]

    def on_stamp(_):
        stamped.add(rect())

    def on_blocked(_):
        m = h.pyboy.memory
        blocked[rect()] = (m[buf + WBUF_CUR_X], m[buf + WBUF_CUR_Y],
                           tuple(sorted(cor_log.get((m[buf + WBUF_CUR_X],
                                                     m[buf + WBUF_CUR_Y]), ()))))

    def on_items(_):
        captured.append(bytes(h.pyboy.memory[scratch + i] for i in range(72)))

    h.register_hook("PFacStampRoomFloors", on_attempt)
    h.register_hook("PFacCorStampCell", on_cor_cell)
    h.register_hook("PFacSelectPremadeMiddleRooms", on_select)
    h.register_hook("PFacChooseTemplate", on_choose)
    h.register_hook("PFacStampPremadeFootprint", on_stamp)
    h.register_hook("PFacPremadePerimeterClear.blocked", on_blocked)
    h.register_hook("PFacPlaceItems", on_items)

    res = {r: defaultdict(Counter) for r in ROLES}
    owner = {r: Counter() for r in ROLES}
    cells = {r: Counter() for r in ROLES}
    layouts = 0

    state = 0x1234_5678
    for i in range(args.seeds):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        h.load_state(base)
        h.write_sram_bytes("sProcFacilityExitEdge", [i % 3])
        h.seed_rng([(state >> s) & 0xFF for s in (0, 8, 16, 24)])
        captured.clear()
        h.call_routine("PFacFinalize", limit=4000)
        if not captured:
            continue
        layouts += 1
        rec = captured[0]
        parent = {r: rec[r * STRIDE + 4] for r in range(12) if rec[r * STRIDE + 2]}
        for room in (0, 1, 2, 3, 4, 11):
            x, y, w, hh, _, fl = rec[room * STRIDE:room * STRIDE + STRIDE]
            if w == 0:
                continue
            role = role_of(room)
            fp = f"{w + 2}x{hh + 2}"
            key = (x, y, w, hh)
            if fl & 0x80:
                why = "premade"
            elif fl & 0x40:
                why = "largedecor"
            elif fl & 0x0C:
                why = "spinner"
            elif groups[fp] == 0:
                why = "no-art"
            elif key in chose:
                why = "sockets"
            else:
                why = "perimeter"
                b = blocked.get(key)
                if b is None:
                    owner[role]["unknown"] += 1
                else:
                    cx, cy, srcs = b
                    dx, dy = cx - (x - 1), cy - (y - 1)     # footprint-relative
                    corner = dx in (0, w + 1) and dy in (0, hh + 1)
                    if corner:
                        owner[role]["shape (corner)"] += 1
                    elif any(s == room or parent.get(s) == room for s in srcs):
                        owner[role]["own"] += 1
                    elif srcs:
                        owner[role]["other"] += 1
                    else:
                        owner[role]["unknown (no corridor logged)"] += 1
                    side = ("N" if dy == 0 else "S" if dy == hh + 1
                            else "W" if dx == 0 else "E")
                    span = w if side in "NS" else hh
                    pos = (dx if side in "NS" else dy) - 1
                    cells[role][f"{side} pos {pos}/{span} (socket {span // 2})"] += 1
            res[role][fp][why] += 1

    print(f"layouts {layouts}\n")
    for role in ROLES:
        tot = Counter()
        for c in res[role].values():
            tot.update(c)
        n = sum(tot.values())
        print(f"== {role}: {n} rooms  " + ", ".join(
            f"{k} {v} ({v / n:.0%})" for k, v in tot.most_common()))
        for fp, c in sorted(res[role].items(), key=lambda kv: -sum(kv[1].values())):
            print(f"   {fp:5s} art={groups[fp]:<2d} n={sum(c.values()):<3d} "
                  + ", ".join(f"{k} {v}" for k, v in c.most_common()))
        if owner[role]:
            print("   perimeter refusals by corridor owner: " + ", ".join(
                f"{k} {v}" for k, v in owner[role].most_common()))
            print("   refused ring cells: " + "; ".join(
                f"{k} x{v}" for k, v in cells[role].most_common(8)))
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
