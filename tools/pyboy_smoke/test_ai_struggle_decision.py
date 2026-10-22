"""A Struggle turn starts a new AI decision (S3, 2026-10-21 AI review).

ChooseEnemyMove (enemy_move_pp.asm) returns Struggle without running
AIEnemyTrainerChooseMoves, so the per-decision caches kept the last real
decision's answers. On an enemy-first turn core.asm sets AI_KO_CACHE_KEEP_BIT,
which tells TrainerAI those caches are current. Measured before the fix: a
full-HP decision cached "the player cannot KO us" (AI_KO_CACHE_NO), and at 1 HP
with no PP, TrainerAI's switch check read that NO; an emptied cache gives YES.
The Struggle exit now farcalls AIStartStruggleDecision (AITrackLastMove +
AIClearDecisionCaches).
"""
from __future__ import annotations

import unittest

import test_ai_heuristic_gaps as gaps  # module import: its test classes are not re-collected here


class StruggleDecisionTest(gaps._AIGapsBase):
    def setUp(self) -> None:
        super().setUp()
        self.boot([self.mon("RATTATA", ["TACKLE"], level=60)],
                  [self.mon("TAUROS", ["BODY_SLAM", "TACKLE"]), self.mon("SNORLAX", ["BODY_SLAM"])],
                  tier=3)
        self.h.reveal_player_moves(0, [0], clear=True)
        self.seen = []
        self.h.register_hook("AIPlayerWouldKO",
                             lambda _ctx: self.seen.append(self.h.read8("wAIPlayerKOCache")))

    def struggle_turn(self):
        """A real decision at full HP, then a Struggle pick at 1 HP with no PP."""
        h = self.h
        h.park_before_hijack()
        self.word("wEnemyMonHP", 150)
        self.word("wEnemyMonMaxHP", 150)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_EMPTY"])
        h.call_routine("AIEnemyTrainerChooseMoves", limit=3000)
        self.assertEqual(h.read8("wAIPlayerKOCache"), self.ai["AI_KO_CACHE_NO"])  # premise
        h.park_before_hijack()
        # Turn 1's move executed (AITrackExecutedEnemyMove sets the bit).
        h.write8("wAISameMoveCount", h.read8("wAISameMoveCount") | (1 << self.ai["AI_MOVE_EXECUTED_BIT"]))
        self.word("wEnemyMonHP", 1)
        for slot in range(4):
            h.write8("wEnemyMonPP", 0, offset=slot)
        h.call_routine("ChooseEnemyMove", limit=600)
        self.assertEqual(h.read8("wEnemySelectedMove"), self.moves["STRUGGLE"])

    def test_struggle_empties_the_last_decisions_ko_answer(self) -> None:
        self.struggle_turn()
        self.assertEqual(self.h.read8("wAIPlayerKOCache"), self.ai["AI_KO_CACHE_EMPTY"])

    def test_struggle_emptied_cache_rescans_correct_on_the_first_read(self) -> None:
        # 2026-10-22: AI_KO_CACHE_KEEP_BIT and the enemy-first "nothing changed,
        # trust the cache" skip it replaced are both gone - TrainerAI now always
        # calls AIRevalidateDecisionCaches unconditionally (ai_turn_plan.asm).
        # What this test actually needs is unchanged: the Struggle exit leaves
        # wAIPlayerKOCache EMPTY (confirmed by
        # test_struggle_empties_the_last_decisions_ko_answer, just above), so
        # the only question is whether the next real reader computes the TRUE
        # answer - YES, since the enemy is at 1 HP - rather than some stale
        # leftover from the earlier 150-HP decision.
        h = self.h
        self.struggle_turn()
        self.assertEqual(h.read8("wAIPlayerKOCache"), self.ai["AI_KO_CACHE_EMPTY"])  # premise
        self.seen.clear()
        h.park_before_hijack()
        h.call_routine("AIPlayerWouldKO", limit=3000)
        self.assertEqual(self.seen[:1], [self.ai["AI_KO_CACHE_EMPTY"]])  # entered empty, not stale
        self.assertEqual(h.read8("wAIPlayerKOCache"), self.ai["AI_KO_CACHE_YES"])

    def test_struggle_opens_the_move_history(self) -> None:
        h = self.h
        self.struggle_turn()
        executed = 1 << self.ai["AI_MOVE_EXECUTED_BIT"]
        self.assertFalse(h.read8("wAISameMoveCount") & executed)


if __name__ == "__main__":
    unittest.main()
