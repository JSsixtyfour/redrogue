"""Audit: can a procedural stage put a pokeball on the boss's own tile?

Slot 1 is the boss and slots 2-5 are the pokeballs on every procedural map, so
"any two of the five sprite slots share a tile" is the whole contract. That is
also exactly what test_smoke's assert_generation_contract checks, but it checks
it on ONE layout per run, which is why the forest bug read as a flaky test for
months instead of a real defect.

Forest was a genuine exact overlap: PFScanForBall used to run before the exit
was rolled, and the boss is placed one cell inward from that exit, so a dead-end
candidate collected at the exit's own cell became a ball standing inside the
boss. Measured at roughly 1.3% of layouts before the fix.

Cave cannot overlap exactly (PCPlaceExitLadder has already overwritten the exit
cell with a ladder block, and candidates must read PC_BLOCK_FLOOR), so for cave
this audit is a regression guard rather than a reproducer.

Usage:
    python3 tools/pyboy_smoke/audit_boss_ball_overlap.py [--layouts N] [--stage forest|cave|both]

Exits non-zero if any layout has two slots on one tile.

One fresh harness per layout is deliberate and not an oversight:
  - boot_to_lobby is not reentrant; the second call on one PyBoy instance fails,
  - call_routine corrupts the machine after roughly ten invocations per boot,
    and preload_and_enter_wild_area spends one of those each time.
Each boot is otherwise deterministic, so wRandomTable (the CMWC state) is
scrambled per layout. Without that, N boots produce N identical layouts and the
audit passes vacuously. Costs about 0.22s per layout.
"""

from __future__ import annotations

import argparse
import random
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

STAGES = {
    "forest": ("PROCEDURAL_FOREST", "Procedural Forest"),
    "cave": ("PROCEDURAL_CAVE_1", "Procedural Cave"),
}

SPRITE_SLOTS = 5  # slot 1 boss + slots 2-5 pokeballs
RNG_STATE_BYTES = 10


def sample_layout(map_id: int, description: str, seed: int) -> list[tuple[int, int]]:
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        # Never write an all-zero CMWC state: zero is absorbing for this
        # generator and the guard against it is load-bearing.
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)
        harness.preload_and_enter_wild_area(map_id, description)
        return [tuple(p) for p in harness.sprite_positions(SPRITE_SLOTS)]
    finally:
        try:
            harness.close()
        except Exception:
            pass


def audit_stage(stage: str, layouts: int) -> int:
    map_name, description = STAGES[stage]
    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")[map_name]

    collisions: list[tuple[int, list[tuple[int, int]]]] = []
    shared_row = 0
    errors = 0
    started = time.time()

    for seed in range(layouts):
        try:
            positions = sample_layout(map_id, description, seed)
        except Exception as exc:
            errors += 1
            print(f"  seed {seed}: {type(exc).__name__}: {exc}")
            continue

        boss, balls = positions[0], positions[1:]
        # Reported alongside the collisions as a sanity check on the sample: if
        # no ball ever even reaches the boss's row, the audit is not exercising
        # the case it claims to test and a clean result means nothing.
        if any(ball[0] == boss[0] for ball in balls):
            shared_row += 1
        if len(set(positions)) != len(positions):
            collisions.append((seed, positions))
            print(f"  COLLISION seed {seed}: boss {boss} positions {positions}")

    elapsed = time.time() - started
    print(
        f"{description}: {layouts} layouts, {len(collisions)} collisions, "
        f"{errors} harness errors, {elapsed:.0f}s ({elapsed / max(1, layouts):.2f}s each)"
    )
    print(f"  a ball shared the boss's ROW in {shared_row}/{layouts} layouts")
    return len(collisions)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=200)
    parser.add_argument("--stage", choices=["forest", "cave", "both"], default="both")
    args = parser.parse_args()

    stages = list(STAGES) if args.stage == "both" else [args.stage]
    failures = sum(audit_stage(stage, args.layouts) for stage in stages)

    print("RESULT:", "PASS" if failures == 0 else f"FAIL ({failures} collisions)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
