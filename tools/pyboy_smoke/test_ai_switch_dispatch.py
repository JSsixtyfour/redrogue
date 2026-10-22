"""Checkpoint A: switch eligibility must survive TrainerAI's item gates.

2026-10-22: the switch decision moved out of TrainerAI into the planner
(AIDecideEnemyTurn, ai_turn_plan.asm), which runs before the player's battle
menu. TrainerAI now just reads wAITurnPlan's AI_TURN_SWITCH_BIT (T2+) or the
original class rolls (T0/T1); it never calls AIShouldSwitch itself any more.
So every probe that drives a decision directly now runs AIDecideEnemyTurn
first (to populate wAITurnPlan against the current board), re-parks, then
probes/calls TrainerAI to observe what it does with that plan.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import (parse_rgbds_constants, parse_trainer_constants,
                              parse_trainer_class_indexes)

ROOT = Path(__file__).resolve().parents[2]


class AISwitchDispatchTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.classes = parse_trainer_class_indexes(ROOT / "constants/trainer_constants.asm")
        def mon(name, move):
            return {"species": self.species[name], "level": 50,
                    "moves": [self.moves[move]]}
        self.h.inject_fight2_spec(
            [mon("SNORLAX", "SPLASH")],
            [mon("TAUROS", "TACKLE"), mon("RATTATA", "TACKLE")],
            trainer_class=self.trainers["JUGGLER"], ai_tier=3)
        self.h.boot_fight2(seed=1)

    def tearDown(self):
        self.h.close()

    def plan_then_probe_trainer_ai(self, predicate, limit=120):
        """Run AIDecideEnemyTurn against the current board (writing
        wAITurnPlan), re-park, then probe TrainerAI's dispatch of that plan."""
        h = self.h
        h.call_routine("AIDecideEnemyTurn", limit=6000)
        h.park_before_hijack()
        h.probe_routine_until("TrainerAI", predicate, limit=limit)

    def test_smart_switch_classes_bypass_item_count_and_ace_gate(self):
        h = self.h
        switched = h.hook_flag("SwitchEnemyMon")
        no_item = h.hook_flag("TrainerAI.noItem")
        for tier in (2, 3):
            for trainer in ("JUGGLER", "COOLTRAINER_F", "AGATHA", "MORTY", "KAREN"):
                for status in (1 << 5, 3):  # frozen and long sleep
                    with self.subTest(tier=tier, trainer=trainer, status=status):
                        h.park_before_hijack()
                        h.write8("wAITier", tier + 1)
                        h.write8("wTrainerClass", self.classes[trainer])
                        h.write8("wEnemyMonStatus", status)
                        h.write8("wAICount", 0)
                        before = switched["count"], no_item["count"]
                        self.plan_then_probe_trainer_ai(
                            lambda: (switched["count"], no_item["count"]) != before)
                        self.assertEqual(switched["count"], before[0] + 1)
                        self.assertEqual(no_item["count"], before[1])
                        self.assertEqual(h.read8("wAICount"), 0)

    def test_every_class_smart_switches_at_t2_plus(self):
        # 2026-09-29: smart switching is no longer limited to Juggler /
        # Cooltrainer F / AgathaAI. A class that never switched before now
        # switches a frozen mon, without spending an item use.
        h = self.h
        h.write8("wTrainerClass", self.classes["COOLTRAINER_M"])
        h.write8("wEnemyMonStatus", 1 << 5)
        h.write8("wAICount", 3)
        switched = h.hook_flag("SwitchEnemyMon")
        no_item = h.hook_flag("TrainerAI.noItem")
        self.plan_then_probe_trainer_ai(lambda: switched["count"] > 0)
        self.assertEqual((switched["count"], no_item["count"]), (1, 0))
        self.assertEqual(h.read8("wAICount"), 3)

    def test_lone_ace_does_not_try_to_switch(self):
        # AIDecideEnemyTurn checks AIActiveMonIsAce and returns before ever
        # calling AIShouldSwitchAtSelectedSpeed/AIShouldSwitch, so the
        # predicate hook now lives on the PLANNER's call, not on a direct
        # TrainerAI call (TrainerAI itself never reaches AIShouldSwitch any
        # more - measured: a direct call_routine("TrainerAI") here reports
        # predicate count 0 regardless of ace status, so that hook point no
        # longer tests anything).
        h = self.h
        h.write8("wEnemyMon2HP", 0)
        h.write8("wEnemyMon2HP", 0, offset=1)
        h.write8("wEnemyMonStatus", 1 << 5)
        h.write8("wAICount", 0)
        predicate = h.hook_flag("AIShouldSwitch")
        h.call_routine("AIDecideEnemyTurn", limit=6000)
        self.assertEqual(predicate["count"], 0)
        self.assertEqual(h.read8("wAITurnPlan"), 0, "no switch bit, no replacement")

    def test_low_tiers_keep_original_item_count_gate(self):
        # Same relocation as above: AIDecideEnemyTurn skips the farcall to
        # AIShouldSwitchAtSelectedSpeed entirely for T0/T1 (wAITier <=
        # AI_TIER_SKILLED), going straight to ranking a replacement instead.
        h = self.h
        predicate = h.hook_flag("AIShouldSwitch")
        for tier in (0, 1):
            h.park_before_hijack()
            h.write8("wAITier", tier + 1)
            h.write8("wEnemyMonStatus", 1 << 5)
            h.write8("wAICount", 0)
            h.call_routine("AIDecideEnemyTurn", limit=6000)
        self.assertEqual(predicate["count"], 0)

    def test_real_turn_switches_then_replacement_acts(self):
        # 2026-10-22: the switch is now decided by the PLANNER, before the
        # menu that precedes the commit it executes in. Priming the board at
        # the first TrainerAI (commit) call is one commit too late for that
        # commit's own plan (already baked in before this turn's menu); it
        # takes effect in the NEXT planning pass (before the following menu),
        # and the switch then executes within THAT commit. Measured sequence
        # (tools/pyboy_smoke/_probe_realturn.py, not committed):
        #   decisions = [0, 0, 1]   (wEnemyMonPartyPos read at each TrainerAI
        #                            entry, BEFORE that commit's own switch,
        #                            if any, executes)
        #   attacks   = [0, 1]      (ExecuteEnemyMove runs turns 1 and 3; turn
        #                            2's commit spends the turn switching)
        h = self.h
        decisions = []
        replacements = h.hook_enemy_send_out()
        attacks = []
        def prime_once():
            decisions.append(h.read8("wEnemyMonPartyPos"))
            if len(decisions) == 1:
                h.write8("wEnemyMonStatus", 1 << 5)
                h.write8("wAICount", 0)
        h.hook_flag("TrainerAI", action=prime_once)
        switched = h.hook_flag("SwitchEnemyMon")
        h.hook_flag("ExecuteEnemyMove", action=lambda:
                    attacks.append(h.read8("wEnemyMonPartyPos")))
        h.hook_flag("DisplayBattleMenu", action=lambda:
                    h.write8("wBattleAndStartSavedMenuItem", 0))
        for _ in range(600):
            h.tap("a", 1)
            h.tick(8)
            if 1 in attacks:
                break
        else:
            self.fail(f"replacement did not act: decisions={decisions}, attacks={attacks}")
        self.assertEqual(switched["count"], 1)
        self.assertTrue(any(r["selected_slot"] == 1 for r in replacements))
        self.assertEqual(decisions[:3], [0, 0, 1])
        self.assertEqual(attacks[:2], [0, 1])


if __name__ == "__main__":
    unittest.main()
