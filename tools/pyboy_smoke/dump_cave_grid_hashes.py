"""Print one hash per generated cave, for A/B-ing a generator change.

Phase 6 used this to prove that scoping PCAutotileRiverEdges to the river's
bounding box is output-identical rather than merely output-plausible. Run it on
the build before the change, run it on the build after, diff the two files. Any
line that differs is a cave whose blocks came out differently.

Two hashes per seed, because they answer different questions:

  post-river  the grid at PCPlaceExitLadder's entry - the river pass's own
              output, isolated, with nothing after it mixed in
  final       the grid once the map is fully up, which also covers every later
              phase (ladder, items, boss, decor, drop-in) and so catches a
              change that shifted the RNG stream out from under them

A change that is genuinely invisible leaves both columns untouched for every
seed. `audit_cave_river_edge_locality.py` is the stronger statement about WHY
the output is unchanged; this is the blunt check that it actually is.

Usage:
    python3 tools/pyboy_smoke/dump_cave_grid_hashes.py --layouts 64 > before.txt
    (apply the change, rebuild)
    python3 tools/pyboy_smoke/dump_cave_grid_hashes.py --layouts 64 > after.txt
    diff before.txt after.txt
"""

from __future__ import annotations

import argparse
import hashlib
import random
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

PC_SIZE = 20
PC_STRIDE = 26
PC_BASE = 81
RNG_STATE_BYTES = 10


def grid_bytes(harness: RedRogueHarness) -> bytes:
    origin = harness.address("wOverworldMap") + PC_BASE
    return bytes(
        harness.pyboy.memory[origin + y * PC_STRIDE + x]
        for y in range(PC_SIZE)
        for x in range(PC_SIZE)
    )


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:16]


def sample(map_id: int, seed: int) -> tuple[str, str]:
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    grabbed: list[bytes] = []
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)
        harness.register_hook(
            "PCPlaceExitLadder", lambda _ctx: grabbed.append(grid_bytes(harness))
        )
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
        final = grid_bytes(harness)
    finally:
        try:
            harness.close()
        except Exception:
            pass
    return digest(grabbed[0]) if grabbed else "NO-HOOK", digest(final)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=64)
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    print("seed  post-river        final")
    for seed in range(args.layouts):
        try:
            post, final = sample(map_id, seed)
        except Exception as exc:
            print("%4d  ERROR %s: %s" % (seed, type(exc).__name__, exc))
            continue
        print("%4d  %-16s  %-16s" % (seed, post, final))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
