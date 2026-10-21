"""A reliable KO always wins outright (2026-10-21 AI review).

The autoplay swarm found T3 trainers throwing away reliable KOs: seed 39's WILL
had Body Slam score AI_KILL (-5), and a non-lethal, 85%-accurate Fire Blast
reached the same score through AI_SMART's burn rider (-2) plus AI_DAMAGE's
unreliable tier (-3), so the tie-break took the KO about half the time. Per-layer
caps do not bound a sum (FOLLOWUPS #55). AI_DAMAGE now records WHICH slots
reliably kill (AIMarkReliableKOSlot, a bitmask in wAIReliableKOFound), and
AIReliableKOWins, just past .loopFindMinimumEntries, raises every other slot to
at least the best live KO's score + 1.

These call the two routines directly on a booted FIGHT 2 battle.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
PP_FULL = 10


class ReliableKOWinsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.opp_offset = parse_rgbds_constants(ROOT / "constants/trainer_constants.asm")["OPP_ID_OFFSET"]
        self.h.inject_fight2_spec(
            [{"species": species["SNORLAX"], "level": 50, "moves": [self.moves["SPLASH"]]}],
            [{"species": species["TAUROS"], "level": 50,
              "moves": [self.moves[m] for m in ("FIRE_BLAST", "BODY_SLAM", "GROWL", "TACKLE")]}],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
        self.h.boot_fight2(seed=1)

    def tearDown(self) -> None:
        self.h.close()

    def run_pass(self, scores, mask, *, pp=(PP_FULL,) * 4, disabled=0, trainer="COOLTRAINER_M",
                 money_match=False):
        h = self.h
        h.park_before_hijack()
        for slot, score in enumerate(scores):
            h.write8("wBuffer", score, offset=slot)
            h.write8("wEnemyMonPP", pp[slot], offset=slot)
        h.write8("wAIReliableKOFound", mask)
        h.write8("wEnemyDisabledMove", disabled)
        h.write8("wTrainerClass", self.trainers[trainer] - self.opp_offset)  # OPP id -> class
        state = h.read8("wMoneyMatchState")
        h.write8("wMoneyMatchState", state | 0x80 if money_match else state & 0x7F)  # BIT_MONEY_MATCH_ACTIVE
        h.call_routine("AIReliableKOWins", limit=200)
        return h.read_bytes("wBuffer", 4)

    def test_the_seed_39_tie_breaks_to_the_kill(self) -> None:
        # Fire Blast 14 (SMART -2, DAMAGE -3, RISKY -1), Body Slam 14 (DAMAGE -5, RISKY -1).
        self.assertEqual(self.run_pass([14, 14, 30, 17], 0b0010), [15, 14, 30, 17])

    def test_kill_slots_keep_their_own_order(self) -> None:
        # Two kills (AI_KILL_FIRST on slot 4): both untouched, everything else above the best.
        self.assertEqual(self.run_pass([12, 15, 13, 11], 0b1010), [12, 15, 13, 11])
        self.assertEqual(self.run_pass([10, 15, 13, 11], 0b1010), [12, 15, 13, 11])

    def test_scores_are_only_raised(self) -> None:
        self.assertEqual(self.run_pass([40, 14, 79, 80], 0b0010), [40, 14, 79, 80])

    def test_no_kill_changes_nothing(self) -> None:
        self.assertEqual(self.run_pass([9, 14, 12, 17], 0), [9, 14, 12, 17])

    def test_a_dead_kill_slot_does_not_count(self) -> None:
        out_of_pp = self.run_pass([10, 14, 12, 17], 0b0010, pp=(PP_FULL, 0, PP_FULL, PP_FULL))
        self.assertEqual(out_of_pp, [10, 14, 12, 17])
        disabled = self.run_pass([10, 14, 12, 17], 0b0010, disabled=0x21)  # slot 2, 1 turn
        self.assertEqual(disabled, [10, 14, 12, 17])

    def test_the_themed_gambler_keeps_its_own_rules(self) -> None:
        self.assertEqual(self.run_pass([10, 14, 12, 17], 0b0010, trainer="GAMBLER"), [10, 14, 12, 17])
        self.assertEqual(self.run_pass([10, 14, 12, 17], 0b0010, trainer="GAMBLER", money_match=True),
                         [15, 14, 15, 17])

    def damage_mask(self, *, pp=(PP_FULL,) * 4, disabled=0) -> int:
        """AI_DAMAGE alone against a 1-HP player: which slots it marks as reliable kills."""
        h = self.h
        h.park_before_hijack()
        h.write8("wBattleMonHP", 0)
        h.write8("wBattleMonHP", 1, offset=1)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
            h.write8("wEnemyMonPP", pp[slot], offset=slot)
        h.write8("wEnemyDisabledMove", disabled)
        h.write8("wAIReliableKOFound", 0)
        h.call_routine("AILayerDamage", limit=600)
        return h.read8("wAIReliableKOFound")

    def test_a_dead_slot_is_never_marked_as_a_kill(self) -> None:
        # S2: slots are FIRE_BLAST, BODY_SLAM, GROWL, TACKLE. At 1 HP, Body Slam and
        # Tackle kill reliably; Fire Blast can miss (85%).
        self.assertEqual(self.damage_mask(), 0b1010)
        self.assertEqual(self.damage_mask(pp=(PP_FULL, 0, PP_FULL, PP_FULL)), 0b1000)
        self.assertEqual(self.damage_mask(disabled=0x41), 0b0010)  # slot 4 disabled
        self.assertEqual(self.damage_mask(pp=(PP_FULL, 0, PP_FULL, 0)), 0)

    def test_mark_sets_one_bit_per_slot(self) -> None:
        h = self.h
        h.park_before_hijack()
        h.write8("wAIReliableKOFound", 0)
        for slot in (0, 3, 2):
            h.write8("wBuffer", slot, offset=17)  # AI_BUF_CURSLOT
            h.call_routine("AIMarkReliableKOSlot", limit=100)
        self.assertEqual(h.read8("wAIReliableKOFound"), 0b1101)


if __name__ == "__main__":
    unittest.main()
