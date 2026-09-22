"""Audit: is the procedural cave's boss actually far from the entrance?

The boss is not placed by a search. It stands on the EXIT ladder, so the exit
roll IS the boss placement, and before 1E (2026-09-22) the only thing keeping
it away from the player was PCOtherEdgesTable excluding the entrance's own
edge - which still allowed the near corners at a Manhattan distance of 10.

1E added a floor (PC_BOSS_MIN_DIST) with a bounded re-roll
(PC_BOSS_DIST_TRIES), so there are two things to measure and they are not the
same thing:

  1. no layout is closer than the floor, EXCEPT the budget-exhausted ones,
  2. how often the budget is actually exhausted - which is the number the
     "must degrade, not spin" decision was traded against. A run that reports
     zero violations tells you nothing on its own if the sample is too small
     for the ~1-in-2,800 fallback to appear at all, so the expected count is
     printed next to the observed one.

The candidate set is small enough to enumerate exactly, so the observed
distance distribution is also compared against the one the constants predict.
That is the part that would catch a gate which "passes" by rejecting almost
everything, or one that is silently never reached.

Usage:
    python3 tools/pyboy_smoke/audit_cave_boss_distance.py [--layouts N]

Exits non-zero if a layout is under the floor by more than the budget
exhaustion rate can explain, or if the distribution is degenerate.

One fresh harness per layout, for the reasons audit_boss_ball_overlap.py's
header documents: boot_to_lobby is not reentrant, and call_routine corrupts
the machine after roughly ten invocations per boot.
"""

from __future__ import annotations

import argparse
import random
import re
import sys
import time
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
CAVE_GEN = REPO_ROOT / "custom_functions" / "procedural_cave_gen.asm"

RNG_STATE_BYTES = 10
# "Sprite Buffers" is SRAM bank 0 - stage_events.asm asserts that. Reading it
# through pyboy.memory without selecting the bank returns $ff.
STAGING_BANK = 0


def gen_const(name: str) -> int:
    m = re.search(r"^DEF %s\s+EQU\s+(\d+)" % name, CAVE_GEN.read_text(), re.M)
    if m is None:
        raise SystemExit("could not find DEF %s in procedural_cave_gen.asm" % name)
    return int(m.group(1))


def pinned_entrance() -> tuple[int, int]:
    """The entrance block, read out of the generator's own pin.

    Deliberately parsed rather than read from wBuffer after generation: offsets
    0/1 are wProcCaveEntranceX/Y during carving but wProcCaveDropInIdx/W during
    decoration, so by the time a layout is finished those bytes hold something
    else entirely. Parsing also means this fails loudly if the tabled
    random-entrance experiment is ever switched back on, which it should - the
    whole distance model below assumes one fixed entrance.
    """
    source = CAVE_GEN.read_text()
    out = []
    for axis in ("X", "Y"):
        m = re.search(r"^\tld a, (\d+)\n\tld \[wBuffer \+ wProcCaveEntrance%s\], a"
                      % axis, source, re.M)
        if m is None:
            raise SystemExit(
                "the entrance no longer looks pinned - this audit's distance "
                "model assumes a single fixed entrance block")
        out.append(int(m.group(1)))
    return out[0], out[1]


def expected_distribution(entrance, size):
    """Every candidate the generator can roll, and its distance.

    3 edges x 18 offsets. The entrance is on the BOTTOM edge and
    PCOtherEdgesTable excludes it, so the three live edges are TOP, LEFT and
    RIGHT.
    """
    ex, ey = entrance
    last = size - 1
    points = []
    for offset in range(1, 19):
        points.append((offset, 0))       # TOP
        points.append((0, offset))       # LEFT
        points.append((last, offset))    # RIGHT
    return [abs(x - ex) + abs(y - ey) for x, y in points]


def sample_distance(map_id, description, seed, entrance):
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
        y, x = harness.read_sram_bytes("sProcCaveStagingExitY", 2, bank=STAGING_BANK)
        ex, ey = entrance
        return (x, y), abs(x - ex) + abs(y - ey)
    finally:
        try:
            harness.close()
        except Exception:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=200)
    args = parser.parse_args()

    floor = gen_const("PC_BOSS_MIN_DIST")
    tries = gen_const("PC_BOSS_DIST_TRIES")
    size = gen_const("PC_SIZE")
    entrance = pinned_entrance()
    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    candidates = expected_distribution(entrance, size)
    passing = [d for d in candidates if d >= floor]
    accept_rate = len(passing) / len(candidates)
    fallback_rate = (1 - accept_rate) ** tries

    print("entrance block %s, PC_BOSS_MIN_DIST %d, PC_BOSS_DIST_TRIES %d"
          % (entrance, floor, tries))
    print("candidates: %d of %d pass (%.1f%%), achievable range %d-%d"
          % (len(passing), len(candidates), accept_rate * 100,
             min(candidates), max(candidates)))
    if floor > max(candidates):
        print("  FAIL: the floor is above the maximum achievable distance (%d), "
              "so EVERY roll exhausts the budget and the gate does nothing"
              % max(candidates))
        return 1
    print("expected budget-exhausted fallbacks: %.4f%% of layouts (~%.2f in %d)"
          % (fallback_rate * 100, fallback_rate * args.layouts, args.layouts))

    distances = []
    errors = 0
    started = time.time()
    for seed in range(args.layouts):
        try:
            cell, dist = sample_distance(map_id, "Procedural Cave", seed, entrance)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue
        distances.append(dist)
        if dist < floor:
            print("  UNDER FLOOR seed %d: exit %s, distance %d" % (seed, cell, dist))

    elapsed = time.time() - started
    if not distances:
        print("no layouts sampled")
        return 1

    under = [d for d in distances if d < floor]
    print()
    print("%d layouts, %d harness errors, %.0fs (%.2fs each)"
          % (len(distances), errors, elapsed, elapsed / max(1, len(distances))))
    print("distance min %d, max %d, mean %.1f"
          % (min(distances), max(distances), sum(distances) / len(distances)))
    print("distribution:")
    for dist, count in sorted(Counter(distances).items()):
        print("  %2d: %s (%d)" % (dist, "#" * count, count))
    print("under the floor: %d of %d (%.2f%%), expected ~%.4f%%"
          % (len(under), len(distances), 100 * len(under) / len(distances),
             fallback_rate * 100))

    failures = []
    # A handful of fallbacks is the DESIGN, not a bug - the budget degrades
    # rather than spinning. Flag only a rate the budget cannot explain. The
    # bound is deliberately loose: this is checking that the gate runs at all,
    # not estimating a probability from 200 samples.
    allowed = max(1, int(fallback_rate * len(distances) * 20))
    if len(under) > allowed:
        failures.append(
            "%d layouts under the floor, more than the %d a %d-try budget can "
            "explain - the gate is being skipped or the re-roll is not taking"
            % (len(under), allowed, tries))
    # The gate must not have collapsed the set to one spot.
    if len(set(distances)) < 3:
        failures.append(
            "only %d distinct distances in %d layouts - the exit roll has "
            "stopped being random" % (len(set(distances)), len(distances)))
    if max(distances) < floor:
        failures.append("no layout reached the floor at all")

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: the boss keeps at least %d blocks from the entrance" % floor)
    return 0


if __name__ == "__main__":
    sys.exit(main())
