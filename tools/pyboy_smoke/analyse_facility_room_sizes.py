#!/usr/bin/env python3
"""Cross-reference how OFTEN each Facility room size occurs against how much
premade variety exists for it.

Answers two questions the descriptor table alone cannot: which frequently-rolled
sizes have no template (so they always fall back to the generic room), and which
have only one (so that size always looks identical).

Room records store the FLOOR INTERIOR; a premade replaces the full footprint,
which is the interior plus the one-block ring, so footprint = interior + 2 per
axis. Records are captured at the PFacPlaceItems seam because item-coordinate
baking reuses record bytes 0-7 afterwards.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/analyse_facility_room_sizes.py [--seeds N]
"""

from __future__ import annotations

import argparse
import io
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
GEN_SOURCE = REPO_ROOT / "custom_functions" / "procedural_facility_gen.asm"

RECORD_STRIDE = 6
MIDDLE_ROOMS = range(1, 11)
TEMPLATE_BIT = 0x80


def template_counts() -> Counter:
    """Descriptors per footprint size, parsed from the generated table."""
    source = GEN_SOURCE.read_text(encoding="utf-8", errors="replace")
    counts: Counter = Counter()
    for width, height, body in re.findall(
        r"^PFacTpl(\d+)x(\d+):\n(.*?)^PFacTpl\1x\2End:",
        source,
        re.MULTILINE | re.DOTALL,
    ):
        counts[(int(width), int(height))] = body.count("    dw ")
    return counts


def item_capable_counts() -> Counter:
    source = GEN_SOURCE.read_text(encoding="utf-8", errors="replace")
    counts: Counter = Counter()
    for width, height, body in re.findall(
        r"^PFacTpl(\d+)x(\d+):\n(.*?)^PFacTpl\1x\2End:",
        source,
        re.MULTILINE | re.DOTALL,
    ):
        counts[(int(width), int(height))] = body.count("PFAC_TPL_ITEM")
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=96)
    args = parser.parse_args()

    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    harness.boot_to_lobby()
    harness.call_routine("PFacPreload", limit=60000)
    baseline = io.BytesIO()
    harness.save_state(baseline)

    scratch = harness.address("sProcFacilityGenScratch")
    captured: list[bytes] = []

    def capture(_context) -> None:
        captured.append(bytes(
            harness.pyboy.memory[scratch + offset] for offset in range(72)
        ))

    harness.register_hook("PFacPlaceItems", capture)

    placed: Counter = Counter()
    premade: Counter = Counter()
    interiors: Counter = Counter()
    state = 0x1234_5678
    for index in range(args.seeds):
        # Plain xorshift over the four RNG bytes: any spread of states will do,
        # this only has to cover the size space, not reproduce the corpus.
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        seed = [(state >> shift) & 0xFF for shift in (0, 8, 16, 24)]
        harness.load_state(baseline)
        harness.write_sram_bytes("sProcFacilityExitEdge", [index % 3])
        harness.seed_rng(seed)
        captured.clear()
        harness.call_routine("PFacFinalize", limit=4000)
        if not captured:
            continue
        records = captured[0]
        for room_id in MIDDLE_ROOMS:
            base = room_id * RECORD_STRIDE
            width, height = records[base + 2], records[base + 3]
            if width == 0:
                continue
            footprint = (width + 2, height + 2)
            placed[footprint] += 1
            interiors[(width, height)] += 1
            if records[base + 5] & TEMPLATE_BIT:
                premade[footprint] += 1

    templates = template_counts()
    items = item_capable_counts()
    total = sum(placed.values())

    print(f"placed middle rooms sampled: {total} over {args.seeds} layouts\n")
    print("footprint  rooms   share  templates  item-capable  premade uptake")
    for size in sorted(placed, key=lambda key: -placed[key]):
        count = placed[size]
        available = templates.get(size, 0)
        uptake = premade.get(size, 0)
        flag = ""
        if available == 0:
            flag = "  <-- NO TEMPLATE"
        elif available == 1:
            flag = "  <-- single, no variety"
        elif available == 2:
            flag = "  <-- thin"
        print(
            f"{size[0]}x{size[1]}      {count:5d}  {count / total:5.1%}"
            f"  {available:9d}  {items.get(size, 0):12d}"
            f"  {uptake:6d} ({uptake / count:.0%}){flag}"
        )

    print("\nsizes with templates that never occurred in this sample:")
    unused = [size for size in sorted(templates) if size not in placed]
    print("  " + (", ".join(f"{w}x{h}" for w, h in unused) if unused else "(none)"))

    print("\ninterior sizes (what large decor has to fit inside):")
    for size in sorted(interiors, key=lambda key: -interiors[key])[:14]:
        print(f"  {size[0]}x{size[1]}  {interiors[size]:5d}"
              f"  {interiors[size] / total:5.1%}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
