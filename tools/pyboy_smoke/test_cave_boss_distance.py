"""Source contracts for the cave boss's minimum distance (1E, 2026-09-22).

The boss stands on the EXIT ladder, so the exit roll IS the boss placement.
PC_BOSS_MIN_DIST puts a floor under how close that can be to the entrance, and
PC_BOSS_DIST_TRIES bounds the re-roll.

Two of these are worth having at build time rather than only in the runtime
audit, because both failure modes are silent in play:

  * a floor above the maximum achievable distance makes the gate reject EVERY
    candidate, burn the whole budget on every cave, and then accept the last
    roll anyway - a generator that is measurably slower and behaves exactly as
    if the feature were absent,
  * a re-roll that escaped onto the non-exit targets would break
    PCStageHideoutCapture, whose header reasons about targets (exit+1) mod 5
    and (exit+2) mod 5 being independently rolled and identically distributed.

The distances themselves are measured by
tools/pyboy_smoke/audit_cave_boss_distance.py against real layouts.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
CAVE_GEN = REPO_ROOT / "custom_functions" / "procedural_cave_gen.asm"


def source() -> str:
    return CAVE_GEN.read_text()


def const(name: str) -> int:
    m = re.search(r"^DEF %s\s+EQU\s+(\d+)" % name, source(), re.M)
    if m is None:
        raise AssertionError("no DEF %s in procedural_cave_gen.asm" % name)
    return int(m.group(1))


def pinned_entrance():
    out = []
    for axis in ("X", "Y"):
        m = re.search(r"^\tld a, (\d+)\n\tld \[wBuffer \+ wProcCaveEntrance%s\], a"
                      % axis, source(), re.M)
        if m is None:
            return None
        out.append(int(m.group(1)))
    return tuple(out)


def candidate_distances():
    """Every point PCRollTargetPoint can produce, and its Manhattan distance.

    3 edges x 18 offsets. The entrance is pinned on the BOTTOM edge and
    PCOtherEdgesTable excludes it, so the live edges are TOP, LEFT, RIGHT.
    """
    entrance = pinned_entrance()
    assert entrance is not None
    ex, ey = entrance
    last = const("PC_SIZE") - 1
    points = []
    for offset in range(1, 19):
        points += [(offset, 0), (0, offset), (last, offset)]
    return [abs(x - ex) + abs(y - ey) for x, y in points]


def routine(label, *, end=None):
    src = source()
    start = src.index(label)
    rest = src[start + len(label):]
    if end is not None:
        rest = rest[:rest.index(end)]
    else:
        m = re.search(r"\n(?=[A-Za-z_][A-Za-z0-9_]*::?\s*$)", rest, re.M)
        rest = rest[:m.start()] if m else rest
    return "\n".join(
        line for line in (re.sub(r";.*$", "", ln).rstrip() for ln in rest.splitlines())
        if line
    )


class BossDistanceFloorTest(unittest.TestCase):
    def test_entrance_is_still_pinned(self) -> None:
        """The random-entrance experiment is tabled; the floor assumes one spot.

        If it is ever switched back on, the candidate enumeration below and the
        runtime audit both stop being meaningful and need rewriting.
        """
        self.assertIsNotNone(
            pinned_entrance(),
            "the entrance is no longer pinned - PC_BOSS_MIN_DIST's candidate "
            "analysis assumes a single fixed entrance block")

    def test_floor_is_satisfiable_and_selective(self) -> None:
        floor = const("PC_BOSS_MIN_DIST")
        distances = candidate_distances()
        self.assertLessEqual(
            floor, max(distances),
            "a floor above the maximum achievable distance rejects every "
            "candidate, so the gate burns its whole budget on every cave and "
            "then accepts the last roll anyway")
        passing = [d for d in distances if d >= floor]
        # Both ends matter: a floor nothing fails is dead code, and one almost
        # everything fails makes the fallback the common path.
        self.assertGreater(len(passing), len(distances) // 4,
                           "fewer than a quarter of candidates pass; the "
                           "budget would be exhausted routinely")
        self.assertLess(len(passing), len(distances),
                        "every candidate already passes, so the gate is dead code")

    def test_budget_makes_the_fallback_rare(self) -> None:
        floor = const("PC_BOSS_MIN_DIST")
        tries = const("PC_BOSS_DIST_TRIES")
        distances = candidate_distances()
        reject = 1 - len([d for d in distances if d >= floor]) / len(distances)
        self.assertLess(reject ** tries, 1e-3,
                        "more than one cave in a thousand would fall back to an "
                        "under-floor boss; raise PC_BOSS_DIST_TRIES")


class ExitRollStructureTest(unittest.TestCase):
    def setUp(self) -> None:
        self.loop = routine(".targetLoop", end="\tcall PCStageHideoutCapture")

    def test_only_the_exit_target_is_rerolled(self) -> None:
        """PCStageHideoutCapture's targets must stay identically distributed."""
        # The non-exit arm rolls once and leaves.
        self.assertIn("call PCRollTargetPoint\n\tjr .haveTarget", self.loop)
        # The retry loop is reached only from the exit arm.
        self.assertIn("jr z, .exitTarget", self.loop)
        exit_arm = self.loop[self.loop.index("\n.exitTarget\n"):]
        self.assertIn("jr nz, .exitRoll", exit_arm)
        self.assertNotIn(".exitRoll", self.loop[:self.loop.index("\n.exitTarget\n")])

    def test_the_gate_is_decided_before_the_roll(self) -> None:
        """The exit branch has to come first, or it cannot re-roll."""
        self.assertLess(self.loop.index("wProcCaveExitIndex"),
                        self.loop.index("call PCRollTargetPoint"))

    def test_budget_degrades_rather_than_spinning(self) -> None:
        """PCPreloadCave runs in a double-speed window during LoadMapData."""
        exit_arm = self.loop[self.loop.index("\n.exitTarget\n"):]
        self.assertIn("ld a, PC_BOSS_DIST_TRIES", exit_arm)
        self.assertIn("dec [hl]", exit_arm)
        # On exhaustion it must FALL THROUGH into the accept, not loop or ret.
        tail = exit_arm[exit_arm.index("jr nz, .exitRoll"):]
        self.assertIn(".exitAccepted", tail)
        self.assertNotIn("ret", tail[:tail.index(".exitAccepted")])

    def test_gate_compares_against_the_entrance(self) -> None:
        body = routine("PCBossFarEnough:")
        self.assertIn("wProcCaveEntranceX", body)
        self.assertIn("wProcCaveEntranceY", body)
        self.assertIn("call PCManhattan", body)
        self.assertIn("cp PC_BOSS_MIN_DIST", body)
        # `cp` sets carry when the distance is too SHORT, so the sense has to
        # be inverted for "carry set = accept".
        self.assertIn("ccf", body)

    def test_retry_byte_survives_the_routines_it_spans(self) -> None:
        """It aliases LoopX, so nothing in the roll or the gate may touch 16."""
        self.assertIn("DEF wProcCaveBossDistRetry EQU wProcCaveLoopX", source())
        for label in ("PCRollTargetPoint:", "PCBossFarEnough:", "PCEdgePoint:",
                      "PCManhattan:", "PCAbs:"):
            with self.subTest(label):
                self.assertNotIn("wProcCaveLoopX", routine(label))


if __name__ == "__main__":
    unittest.main()
