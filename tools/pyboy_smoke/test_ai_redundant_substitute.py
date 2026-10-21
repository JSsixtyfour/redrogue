"""AI_REDUNDANT vs a player Substitute: only a move the doll stops ENTIRELY is
redundant (2026-10-21 AI review, S1).

In this engine a Substitute stops a damaging move's rider, not the move: the
side-effect routines in effects.asm skip their effect behind a doll, and
MoveHitTest (core.asm) misses only Dream Eater and Leech Seed. The damage hits
the doll. AI_REDUNDANT's side-effect handlers said "Substitute blocks the WHOLE
move" and gave Body Slam, Ice Beam, Twineedle, Bite, Psybeam and Aurora Beam the
heavy penalty, so the AI walked away from the attacks that break the doll. A
status move (Growl, Confuse Ray) behind a doll still does nothing at all and
stays heavily discouraged. Same for a stat-down side effect at the -6 floor: the
damage still lands, so only the pure stat-down move is redundant there.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
BASE = 20
DAMAGING_WITH_RIDERS = ("BODY_SLAM", "ICE_BEAM", "TWINEEDLE", "BITE", "PSYBEAM", "AURORA_BEAM")
STATUS_MOVES = ("GROWL", "CONFUSE_RAY")


class RedundantSubstituteTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.battle = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")
        self.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        # AI_REDUNDANT_HEAVY saturates the score (ai_redundant.asm: EQU AI_SATURATE).
        self.heavy = self.ai["AI_SCORE_MAX"] - BASE
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.h.inject_fight2_spec(
            [{"species": species["SNORLAX"], "level": 50, "moves": [self.moves["SPLASH"]]}],
            [{"species": species["TAUROS"], "level": 50, "moves": [self.moves["TACKLE"]]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
        self.h.boot_fight2(seed=1)

    def tearDown(self) -> None:
        self.h.close()

    def penalty(self, move: str, *, substitute: bool, attack_stage: int = 7) -> int:
        """AI_REDUNDANT's change to a lone move's score."""
        h = self.h
        h.park_before_hijack()
        h.write8("wPlayerBattleStatus2", (1 << self.battle["HAS_SUBSTITUTE_UP"]) if substitute else 0)
        h.write8("wPlayerSubstituteHP", 30 if substitute else 0)
        h.write8("wPlayerBattleStatus1", 0)
        h.write8("wBattleMonStatus", 0)
        h.write8("wPlayerMonStatMods", attack_stage)  # Attack; 7 = neutral, 1 = -6
        h.write8("wEnemyMonMoves", self.moves[move])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        h.write8("wBuffer", BASE)
        h.call_routine("AILayerRedundant", limit=240)
        return h.read8("wBuffer") - BASE

    def test_a_damaging_move_with_a_rider_is_not_redundant_into_a_substitute(self) -> None:
        for move in DAMAGING_WITH_RIDERS:
            with self.subTest(move=move):
                self.assertEqual(self.penalty(move, substitute=True), 0)

    def test_a_status_move_into_a_substitute_stays_heavily_redundant(self) -> None:
        for move in STATUS_MOVES:
            with self.subTest(move=move):
                self.assertEqual(self.penalty(move, substitute=True), self.heavy)

    def test_without_a_substitute_nothing_changes(self) -> None:
        for move in DAMAGING_WITH_RIDERS + STATUS_MOVES:
            with self.subTest(move=move):
                self.assertEqual(self.penalty(move, substitute=False), 0)

    def test_the_attack_floor_blocks_growl_but_not_aurora_beam(self) -> None:
        self.assertEqual(self.penalty("GROWL", substitute=False, attack_stage=1), self.heavy)
        self.assertEqual(self.penalty("AURORA_BEAM", substitute=False, attack_stage=1), 0)


if __name__ == "__main__":
    unittest.main()
