"""Audit: stage-event trainer victories must not advance the run.

A trainer-class victory on one of the three procedural maps can only be a
Phase 7 stage-event NPC - the wild-area boss and the Facility's fake balls are
all OW_POKEMON, so they run as WILD battles and never reach
TrainerBattleVictory at all. Those side encounters must cost the player
nothing: wBattleCount drives enemy levels, AI tier and reward tiers for
everything afterwards, and a Jessie & James pair would otherwise have added 2
to it on its own.

METHOD, and why it looks odd. TrainerBattleVictory is invoked directly with
hCurMap forced, because reaching it legitimately means winning a real trainer
battle in the emulator. The call ALWAYS times out - the routine ends in
victory music and frame delays, and harness.call_routine explicitly cannot run
anything that waits for VBlank. That does not matter here: the wBattleCount
increment is the first thing the routine does, so it has long since executed
(or been skipped) by the time the music stalls. The timeout is expected, and
the reading taken afterwards is still the answer.

Usage:
    python3 tools/pyboy_smoke/audit_stage_event_battle_count.py

Exits non-zero if a procedural map advances the count, or if an ordinary route
stops advancing it (which would mean the guard is catching everything).
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

# (map constant, must the count advance?)
CASES = [
    ("PROCEDURAL_CAVE_1", False),
    ("PROCEDURAL_FOREST", False),
    ("PROCEDURAL_FACILITY", False),
    ("ROUTE_1", True),          # control: the guard must not catch everything
]


def main() -> int:
    maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
    failures = []

    for map_name, should_advance in CASES:
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby()
            h.write8("hCurMap", maps[map_name])
            h.write8("wGymLeaderNo", 0)   # keep the gym-leader branch out of it
            before = h.read8("wBattleCount")
            try:
                # Small limit on purpose: the increment is the routine's first
                # act, and we do not want to sit through the music stall.
                h.call_routine("TrainerBattleVictory", limit=3000)
            except AssertionError:
                pass                      # expected - see the module docstring
            after = h.read8("wBattleCount")
            advanced = after != before
            ok = advanced == should_advance
            print("%-22s %3d -> %3d  %-9s %s"
                  % (map_name, before, after,
                     ("+%d" % (after - before)) if advanced else "skipped",
                     "OK" if ok else "WRONG"))
            if not ok:
                failures.append(
                    "%s: count %s, expected it to %s"
                    % (map_name,
                       "advanced" if advanced else "did not advance",
                       "advance" if should_advance else "stay put"))
        finally:
            try:
                h.close()
            except Exception:
                pass

    print()
    if failures:
        for line in failures:
            print("  FAIL: %s" % line)
        return 1
    print("PASS: procedural-map trainer victories are free; ordinary routes still count")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
