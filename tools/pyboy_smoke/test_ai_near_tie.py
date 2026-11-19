"""Near-tie mixing in the move chooser (AI_T4_REGRET_PLAN E4, 2026-11-19).

AIEnemyTrainerChooseMoves' random pick now takes every legal move scored up to
AI_NEAR_TIE worse than the best, not only exact ties, so the same board does not
always get the same answer. The counterfactual gate priced it at +0.0013 and
+0.0008 of party HP per decision on two seed pools (both CIs include 0), while a
move 2 points off already costs. Bounds: never on a reliable-KO turn, and a
near-tie must be encouraged (below AI_SCORE_BASE), because a move a layer pushed
back to neutral (setup the setup gate withheld) looks like an untouched one;
legality unchanged.

These enter at .loopFindMinimumEntries with forced final scores on a booted
FIGHT 2 battle, so the Explosion veto, AIReliableKOWins and the filter all run;
wBuffer then holds each candidate's move id (0 = not a candidate).
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
PP_FULL = 10


class NearTieTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        self.near, self.base = ai["AI_NEAR_TIE"], ai["AI_SCORE_BASE"]
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.set = [moves[m] for m in ("FIRE_BLAST", "BODY_SLAM", "GROWL", "TACKLE")]
        self.h.inject_fight2_spec(
            [{"species": species["SNORLAX"], "level": 50, "moves": [moves["SPLASH"]]}],
            [{"species": species["TAUROS"], "level": 50, "moves": self.set}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
        self.h.boot_fight2(seed=1)

    def tearDown(self) -> None:
        self.h.close()

    def candidates(self, scores, *, ko_mask=0, pp=(PP_FULL,) * 4, disabled=0):
        h = self.h
        h.park_before_hijack()
        for slot, score in enumerate(scores):
            h.write8("wBuffer", score, offset=slot)
            h.write8("wEnemyMonPP", pp[slot], offset=slot)
        h.write8("wAIReliableKOFound", ko_mask)
        h.write8("wEnemyDisabledMove", disabled)
        h.call_routine("AIEnemyTrainerChooseMoves.loopFindMinimumEntries", limit=4000)
        return [slot for slot, move in enumerate(h.read_bytes("wBuffer", 4)) if move]

    def test_the_margin_is_one_point(self) -> None:
        self.assertEqual(self.near, 1)

    def test_a_one_point_near_tie_is_mixed_in(self) -> None:
        self.assertEqual(self.candidates([14, 15, 16, 20]), [0, 1])

    def test_two_points_off_is_never_mixed_in(self) -> None:
        self.assertEqual(self.candidates([14, 16, 16, 17]), [0])

    def test_exact_ties_still_all_count(self) -> None:
        self.assertEqual(self.candidates([17, 18, 21, 17]), [0, 1, 3])

    def test_a_near_tie_must_be_encouraged(self) -> None:
        # A move a layer pushed back to neutral (the setup gate withholding Swords Dance) looks
        # exactly like an untouched one, so a near-tie at neutral never joins.
        self.assertEqual(self.candidates([19, 20, 21, 30]), [0])
        self.assertEqual(self.candidates([20, 21, 20, 25]), [0, 2])  # exact ties at neutral still count
        # Best 2 under neutral: the encouraged 19 joins; the neutral 20 does not.
        self.assertEqual(self.candidates([18, 19, 20, 30]), [0, 1])

    def test_a_reliable_ko_turn_stays_exact(self) -> None:
        # Slot 1 reliably kills: AIReliableKOWins lifts the rest above it, and no near-tie joins.
        self.assertEqual(self.candidates([15, 14, 15, 20], ko_mask=0b0010), [1])
        self.assertEqual(self.candidates([14, 15, 16, 20], ko_mask=0b0001), [0])

    def test_legality_still_wins(self) -> None:
        self.assertEqual(self.candidates([14, 15, 15, 20], pp=(PP_FULL, 0, PP_FULL, PP_FULL)), [0, 2])
        self.assertEqual(self.candidates([14, 15, 15, 20], disabled=0x21), [0, 2])  # slot 2 disabled
        # The best move is out of PP: the best LEGAL score sets the threshold.
        self.assertEqual(self.candidates([10, 15, 16, 18], pp=(0, PP_FULL, PP_FULL, PP_FULL)), [1, 2])


if __name__ == "__main__":
    unittest.main()
