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

    def test_enemy_first_trainer_ai_rescans_the_ko_threat(self) -> None:
        h = self.h
        self.struggle_turn()
        h.park_before_hijack()
        cache = h.read8("wAIPlayerKOCache")
        h.write8("wAIPlayerKOCache", cache | (1 << self.ai["AI_KO_CACHE_KEEP_BIT"]))  # .enemyMovesFirst
        self.seen.clear()
        h.call_routine("TrainerAI", limit=6000)
        self.assertEqual(self.seen[:1], [self.ai["AI_KO_CACHE_EMPTY"]])  # was NO, a stale answer
        self.assertEqual(h.read8("wAIPlayerKOCache"), self.ai["AI_KO_CACHE_YES"])

    def test_struggle_opens_the_move_history(self) -> None:
        h = self.h
        self.struggle_turn()
        executed = 1 << self.ai["AI_MOVE_EXECUTED_BIT"]
        self.assertFalse(h.read8("wAISameMoveCount") & executed)


if __name__ == "__main__":
    unittest.main()
