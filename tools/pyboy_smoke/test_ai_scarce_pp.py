"""B9 scarce-PP tiebreak (2026-10-21 AI review, Phase 4).

AI_DAMAGE gives its highest-expected-damage slot one extra nudge. When that slot
has AI_SCARCE_PP (2) or less and is not a reliable KO, the nudge goes to the
first other slot in the same damage tier with more PP; across tiers it never
moves. Tauros (Double-Edge, Body Slam, Headbutt, Growl) against a full-HP
Snorlax, measured: Double-Edge and Body Slam both reach half (AI_DMG_TIER_HIGH),
Double-Edge does more; Headbutt reaches only a quarter.
AILayerDamage is called alone; scores start at 20, lower is better.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
FULL = 10
MOVES = ("DOUBLE_EDGE", "BODY_SLAM", "HEADBUTT", "GROWL")


class ScarcePPTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.h.inject_fight2_spec(
            [{"species": species["SNORLAX"], "level": 50, "moves": [self.moves["SPLASH"]]}],
            [{"species": species["TAUROS"], "level": 50, "moves": [self.moves[m] for m in MOVES]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
        self.h.boot_fight2(seed=1)

    def tearDown(self) -> None:
        self.h.close()

    def damage(self, pp=(FULL,) * 4, *, player_hp=None):
        """(scores, per-slot tiers) after AI_DAMAGE alone."""
        h = self.h
        h.park_before_hijack()
        if player_hp is not None:
            h.write8("wBattleMonHP", player_hp >> 8)
            h.write8("wBattleMonHP", player_hp & 0xFF, offset=1)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
            h.write8("wEnemyMonPP", pp[slot], offset=slot)
        h.write8("wEnemyDisabledMove", 0)
        h.write8("wAIReliableKOFound", 0)
        h.call_routine("AILayerDamage", limit=600)
        tiers = h.read8("wBuffer", self.ai["AI_BUF_DMGTIERS"])
        return list(h.read_bytes("wBuffer", 4)), [(tiers >> (2 * s)) & 3 for s in range(4)]

    def test_premise_tiers_and_double_edge_is_best(self) -> None:
        scores, tiers = self.damage()
        high, quarter, none = (self.ai[f"AI_DMG_TIER_{t}"] for t in ("HIGH", "QUARTER", "NONE"))
        self.assertEqual(tiers, [high, high, quarter, none])
        self.assertEqual(scores[0] + 1, scores[1])  # the best-damage nudge

    def test_scarce_best_hands_the_nudge_to_its_tier_mate(self) -> None:
        full, _ = self.damage()
        scarce, _ = self.damage(pp=(2, FULL, FULL, FULL))
        self.assertEqual(scarce, [full[0] + 1, full[1] - 1, full[2], full[3]])

    def test_three_pp_is_not_scarce(self) -> None:
        self.assertEqual(self.damage(pp=(3, FULL, FULL, FULL)), self.damage())

    def test_a_scarce_tier_mate_does_not_take_it(self) -> None:
        self.assertEqual(self.damage(pp=(2, 2, FULL, FULL))[0], self.damage()[0])

    def test_a_lower_tier_never_takes_it(self) -> None:
        # Body Slam out of PP (a dead slot, tier none): Headbutt is the only other
        # attack, a quarter against Double-Edge's half, so Double-Edge keeps the nudge.
        both = self.damage(pp=(FULL, 0, FULL, FULL))[0]
        self.assertEqual(self.damage(pp=(2, 0, FULL, FULL))[0], both)

    def test_a_reliable_ko_keeps_its_nudge(self) -> None:
        kill, _ = self.damage(player_hp=1)
        self.assertEqual(self.damage(pp=(2, FULL, FULL, FULL), player_hp=1)[0], kill)


if __name__ == "__main__":
    unittest.main()
