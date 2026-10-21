"""A disabled or 0-PP move slot is not usable by any AI check (S2, 2026-10-21).

AIEnemySlotIsLive (trainer_ai.asm) is the one definition of "this slot can be
chosen". AI_DAMAGE already used it (test_ai_reliable_ko_wins). These are the other
sites that used to treat a spent slot as a real move:

  AILayerRisky's guaranteed-win scan, AIClassifyMoveset (and through its masks
  AIPlanClassMoveLandsFar), AIHasSuperEffectiveMove (the switch "stay" veto),
  AIEnemyHasReliableFirstKO, and AISmart_Sleep's Dream Eater check.

Every test has a control with full PP that gives the opposite answer. The enemy is
a Tauros with SEISMIC_TOSS (Fighting, 100% accurate, super effective on a Snorlax),
GROWL, HYPNOSIS and DREAM_EATER.
"""
from __future__ import annotations

from pathlib import Path
import unittest

import test_ai_heuristic_gaps as gaps  # module import: its test classes are not re-collected here
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
FULL = (10, 10, 10, 10)
CARRY = 0x10


class DeadSlotTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        self.h.inject_fight2_spec(
            [{"species": species["SNORLAX"], "level": 50, "moves": [self.moves["SPLASH"]]}],
            [{"species": species["TAUROS"], "level": 50,
              "moves": [self.moves[m] for m in ("SEISMIC_TOSS", "GROWL", "HYPNOSIS", "DREAM_EATER")]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
        self.h.boot_fight2(seed=1)
        self.class_mask = 0
        regs = self.h.pyboy.register_file

        def load_mask(_context) -> None:  # D/E are set at the entry, not before the call
            regs.D = self.class_mask >> 8
            regs.E = self.class_mask & 0xFF

        self.h.register_hook("AIPlanClassMoveLandsFar", load_mask)

    def tearDown(self) -> None:
        self.h.close()

    def prepare(self, pp, disabled=0):
        h = self.h
        h.park_before_hijack()
        for slot in range(4):
            h.write8("wEnemyMonPP", pp[slot], offset=slot)
        h.write8("wEnemyDisabledMove", disabled)

    def call(self, label, limit=600):
        self.h.call_routine(label, limit=limit)
        return self.h.last_call_registers

    def carry(self, label, limit=600):
        return bool(self.call(label, limit)["F"] & CARRY)

    # --- AIHasSuperEffectiveMove --------------------------------------------
    def test_a_dead_super_effective_move_does_not_veto_the_switch(self) -> None:
        self.prepare(FULL)
        self.assertTrue(self.carry("AIHasSuperEffectiveMove"))
        self.prepare((0, 10, 10, 10))
        self.assertFalse(self.carry("AIHasSuperEffectiveMove"))
        self.prepare(FULL, disabled=0x13)  # slot 1 disabled
        self.assertFalse(self.carry("AIHasSuperEffectiveMove"))

    # --- AIClassifyMoveset / AIPlanClassMoveLandsFar ------------------------
    def classify(self):
        self.h.call_routine("AIClassifyMoveset", limit=400)
        raw = self.h.read_bytes("wBuffer", 8, offset=self.ai["AI_BUF_PLANCLASS"])
        return [raw[i] | (raw[i + 1] << 8) for i in range(0, 8, 2)]

    def test_a_zero_pp_move_classifies_as_an_empty_slot(self) -> None:
        self.prepare(FULL)
        control = self.classify()
        self.assertTrue(control[2])  # Hypnosis has a plan class
        self.prepare((10, 10, 0, 10))
        masks = self.classify()
        self.assertEqual(masks[2], 0)
        self.assertEqual([masks[0], masks[1], masks[3]], [control[0], control[1], control[3]])

    def test_a_plan_cannot_land_with_a_spent_key_move(self) -> None:
        # Hypnosis is the only sleep move; its mask is the plan class under test.
        self.prepare(FULL)
        sleep_mask = self.classify()[2]
        self.assertTrue(self.lands(sleep_mask, FULL))
        self.assertFalse(self.lands(sleep_mask, (10, 10, 0, 10)))

    def lands(self, mask, pp):
        h = self.h
        self.prepare(pp)
        self.classify()
        self.class_mask = mask
        return self.call("AIPlanClassMoveLandsFar")["E"] == 1

    # --- AIEnemyHasReliableFirstKO ------------------------------------------
    def first_ko(self, pp, disabled=0):
        h = self.h
        self.prepare(pp, disabled)
        for status in ("wEnemyMonStatus", "wEnemyBattleStatus1", "wEnemyBattleStatus2",
                       "wPlayerBattleStatus1"):
            h.write8(status, 0)
        h.write8("wBattleMonHP", 0)
        h.write8("wBattleMonHP", 1, offset=1)
        h.write8("wEnemySelectedMove", self.moves["SEISMIC_TOSS"])
        h.write8("wEnemyMoveListIndex", 0)
        return self.carry("AIEnemyHasReliableFirstKO", limit=1500)

    def test_a_selected_move_with_no_pp_is_not_a_first_ko(self) -> None:
        self.assertTrue(self.first_ko(FULL))
        self.assertFalse(self.first_ko((0, 10, 10, 10)))
        self.assertFalse(self.first_ko(FULL, disabled=0x13))

    # --- AISmart_Sleep's Dream Eater check ----------------------------------
    def sleep_bonus(self, pp):
        self.prepare(pp)
        self.h.write8("wEnemyMoveNum", self.moves["HYPNOSIS"])
        regs = self.call("AISmart_Sleep")
        return regs["A"], bool(regs["F"] & CARRY)

    def test_a_dead_dream_eater_does_not_encourage_sleep(self) -> None:
        self.assertEqual(self.sleep_bonus(FULL), (self.ai["AI_STRONG"], True))
        self.assertEqual(self.sleep_bonus((10, 10, 10, 0)), (0, False))


class RiskyScanDeadSlotTest(gaps._AIGapsBase):
    """AILayerRisky stays silent while a guaranteed win exists in the moveset (see
    test_ai_heuristic_gaps); a Tackle with no PP left is not that win."""

    def risky_scores(self, tackle_pp):
        h = self.h
        self.boot([self.mon("RATTATA", ["TACKLE"], level=60)],
                  [self.mon("TAUROS", ["TACKLE", "HORN_DRILL"])], tier=2)
        h.reveal_player_moves(0, [0], clear=True)
        h.park_before_hijack()
        self.word("wEnemyMonHP", 1)
        self.word("wEnemyMonMaxHP", 200)
        self.word("wBattleMonHP", 1)
        self.word("wBattleMonMaxHP", 200)
        self.word("wEnemyMonSpeed", 200)
        self.word("wBattleMonSpeed", 100)
        h.write8("wEnemyMonPP", tackle_pp)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.write8("wAIPlayerKOCache", self.ai["AI_KO_CACHE_EMPTY"])
        h.call_routine("AILayerRisky", limit=900)
        return list(h.read_bytes("wBuffer", 4))

    def test_risky_stays_silent_while_a_live_move_wins(self) -> None:
        self.assertEqual(self.risky_scores(10), [20, 20, 20, 20])

    def test_risky_does_not_defer_to_a_spent_guaranteed_win(self) -> None:
        dead = self.risky_scores(0)
        self.assertEqual(dead[1], 18)  # no usable win left: the OHKO gamble is nudged (AI_STRONG)


if __name__ == "__main__":
    unittest.main()
