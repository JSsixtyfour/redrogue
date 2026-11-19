"""Find Facility wall caps standing alone: a cap block whose run axis has open
floor at BOTH ends (FACILITY_STRANDED_WALL_END/HANDOFF.md). N-S caps $55/$59
(W_LEFT) and $56/$5A (W_RIGHT); E-W caps $63/$67 (W_TOP) and $57/$58 (W_BOTTOM).

"Open" is a block whose four quadrants are all walkable (facility.bst), the
same test the stranded-quadrant audit uses per quadrant.

    python3 probe_facility_cap_islands.py [--seeds N] [--show N] [--trace SEEDHEX]

--trace dumps the 20x20 grid around each hit after every generation pass, by
hooking each pass's entry (the grid then holds the PREVIOUS pass's output) and
PFacGenerateFacility's return.
"""
from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import RedRogueHarness  # noqa: E402
from audit_facility_stranded_quadrants import (  # noqa: E402
    BLOCKSET, QUADRANT_TILE_INDEXES, WALKABLE_TILES)

ROOT = Path(__file__).resolve().parents[2]
ART = Path(__file__).resolve().parent / "artifacts"
NS = {0x55: "J_LEFT_N", 0x59: "J_LEFT_S", 0x56: "J_RIGHT_N", 0x5A: "J_RIGHT_S"}
EW = {0x63: "J_TOP_W", 0x67: "J_TOP_E", 0x57: "J_BOTTOM_E", 0x58: "J_BOTTOM_W"}
PASSES = ["PFacCarveEdgeOpenings", "PFacBuildCorridorWalls", "PFacApplyDoorJambs",
          "PFacFinalizeBlocks", "PFacRemoveIsolatedGeneratedCorners",
          "PFacNormalizeReversedCorners", "PFacApplyWallEndCaps", "PFacApplyCornerCaps",
          "PFacRemoveStrandedJambs", "PFacPlaceSpinnerDecor", "PFacPlaceLargeDecor",
          "PFacPlaceItems", "PFacDecorateExploreRooms", "PFacPlaceFakeBalls",
          "PFacDecorateCorridorWalls"]


def grid(h) -> list[list[int]]:
    buf = h.read_bytes("wOverworldMap", 601)
    return [[buf[81 + r * 26 + c] for c in range(20)] for r in range(20)]


def open_blocks(blockset: bytes) -> set[int]:
    out = set()
    for b in range(len(blockset) // 16):
        if all(blockset[b * 16 + i] in WALKABLE_TILES for i in QUADRANT_TILE_INDEXES):
            out.add(b)
    return out


def islands(g, opened) -> list[tuple[int, int, int]]:
    hits = []
    for r in range(20):
        for c in range(20):
            b = g[r][c]
            if b in NS and 0 < r < 19 and g[r - 1][c] in opened and g[r + 1][c] in opened:
                hits.append((r, c, b))
            if b in EW and 0 < c < 19 and g[r][c - 1] in opened and g[r][c + 1] in opened:
                hits.append((r, c, b))
    return hits


def show(g, r, c, label="") -> None:
    print(f"  {label}")
    lo_r, hi_r, lo_c, hi_c = max(0, r - 3), min(19, r + 3), max(0, c - 5), min(19, c + 5)
    print("       " + " ".join(f"{x:2d}" for x in range(lo_c, hi_c + 1)))
    for y in range(lo_r, hi_r + 1):
        cells = " ".join(("[" if (y, x) == (r, c) else "") + f"{g[y][x]:02X}" for x in range(lo_c, hi_c + 1))
        print(f"   {y:2d}  {cells}")


def seeds(n):
    state = 0x1234_5678
    for _ in range(n):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        yield [(state >> s) & 0xFF for s in (0, 8, 16, 24)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=300)
    ap.add_argument("--show", type=int, default=4)
    ap.add_argument("--trace", type=str, default=None)
    ap.add_argument("--uncapped", type=str, default=None,
                    help="SEEDHEX: print plain walls ending on floor, per exit edge")
    args = ap.parse_args()
    opened = open_blocks(BLOCKSET.read_bytes())
    h = RedRogueHarness(ROOT, ART)
    try:
        h.boot_to_lobby()
        h.call_routine("PFacPreload", limit=60000)
        base = io.BytesIO()
        h.save_state(base)
        if args.uncapped:
            seed = [int(args.uncapped[i:i + 2], 16) for i in range(0, 8, 2)]
            axis = {0x44: ((-1, 0), (1, 0)), 0x46: ((-1, 0), (1, 0)),
                    0x41: ((0, -1), (0, 1)), 0x49: ((0, -1), (0, 1))}
            for edge in range(3):
                h.load_state(base)
                h.write_sram_bytes("sProcFacilityExitEdge", [edge])
                h.seed_rng(seed)
                before = []
                h.register_hook("PFacRemoveStrandedJambs", lambda _c: before.append(grid(h)))
                h.call_routine("PFacFinalize", limit=4000)
                h.unregister_hook("PFacRemoveStrandedJambs", None) if False else None
                g = grid(h)
                for r in range(20):
                    for c in range(20):
                        for dr, dc in axis.get(g[r][c], ()):
                            if 0 <= r + dr < 20 and 0 <= c + dc < 20 and g[r + dr][c + dc] == 0x0E:
                                print(f"edge {edge}: ${g[r][c]:02X} at row {r}, col {c} ends on floor")
                                show(before[-1], r, c, "before PFacRemoveStrandedJambs")
                                show(g, r, c, "final")
            return 0
        if args.trace:
            seed = [int(args.trace[i:i + 2], 16) for i in range(0, 8, 2)]
            edge = int(args.trace[8:], 16) if len(args.trace) > 8 else 0
            h.load_state(base)
            h.write_sram_bytes("sProcFacilityExitEdge", [edge])
            h.seed_rng(seed)
            snaps = []
            for name in PASSES:
                h.register_hook(name, lambda _c, name=name: snaps.append((f"before {name}", grid(h))))
            h.call_routine("PFacFinalize", limit=4000)
            final = grid(h)
            hits = islands(final, opened)
            print("hits", [(r, c, f"{b:02X}") for r, c, b in hits])
            for r, c, b in hits:
                print(f"=== island {NS.get(b) or EW.get(b)} at row {r}, col {c}")
                prev = None
                for label, g in snaps + [("final", final)]:
                    window = [row[max(0, c - 5):c + 6] for row in g[max(0, r - 3):r + 4]]
                    if window != prev:
                        show(g, r, c, label)
                        prev = window
            return 0
        total, hit_layouts, by_id, shown, void_edges = 0, 0, {}, 0, 0
        for i, seed in enumerate(seeds(args.seeds)):
            h.load_state(base)
            h.write_sram_bytes("sProcFacilityExitEdge", [i % 3])
            h.seed_rng(seed)
            h.call_routine("PFacFinalize", limit=4000)
            g = grid(h)
            hits = islands(g, opened)
            total += 1
            # A repair that turns a wall into floor must not open floor onto void.
            void_edges += sum(1 for r in range(20) for c in range(20) if g[r][c] == 0x0E
                              for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1))
                              if 0 <= r + dr < 20 and 0 <= c + dc < 20 and g[r + dr][c + dc] == 0x2E)
            if hits:
                hit_layouts += 1
                for r, c, b in hits:
                    by_id[b] = by_id.get(b, 0) + 1
                    if shown < args.show:
                        shown += 1
                        tag = "".join(f"{x:02X}" for x in seed) + f"{i % 3:02X}"
                        show(g, r, c, f"seed {tag}: {NS.get(b) or EW.get(b)} at row {r}, col {c}")
        print(f"floor-to-void edges over all layouts: {void_edges}")
        print(f"layouts {total}, with a cap island {hit_layouts}, by block "
              + ", ".join(f"{NS.get(b) or EW.get(b)} ${b:02X} x{n}" for b, n in sorted(by_id.items())))
    finally:
        h.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
