"""Multi-turn, full-flow AI fixtures (AI_BACKLOG L1 part 2 and L3).

Unlike the call_routine unit fixtures, these drive real battle turns through
the menus: SelectEnemyMove -> TrainerAI -> ExecuteEnemyMove, with hooks that
only prime state (HP, revealed moves) and record what happened. They catch
contracts that hold per call but break across turns: history that records a
move that never ran, a switch that ping-pongs, a plan that keeps pushing a
move after it landed.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class AIFullFlowTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.battle = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")
        self.ai = parse_rgbds_constants(ROOT / "constants/ai_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.executed_bit = 1 << self.ai["AI_MOVE_EXECUTED_BIT"]

    def tearDown(self):
        self.h.close()

    def mon(self, name, moves):
        return {"species": self.species[name], "level": 50,
                "moves": [self.moves[m] for m in moves]}

    def word(self, label, value, offset=0):
        self.h.write8(label, value >> 8, offset=offset)
        self.h.write8(label, value & 255, offset=offset + 1)

    def boot(self, player, enemy, trainer="JUGGLER", tier=2):
        self.h.inject_fight2_spec(player, enemy,
                                  trainer_class=self.trainers[trainer], ai_tier=tier)
        self.h.boot_fight2(seed=1)

    def drive_turns(self, stop, limit=2400):
        """Always FIGHT, always the player's move slot 0."""
        h = self.h
        h.hook_flag("DisplayBattleMenu", action=lambda:
                    h.write8("wBattleAndStartSavedMenuItem", 0))
        for _ in range(limit):
            if stop():
                return True
            h.tap("a", 1)
            h.tick(8)
        return stop()

    def no_items(self):
        # Items are not under test; an item turn would also skip execution.
        self.h.hook_flag("TrainerAI", action=lambda: self.h.write8("wAICount", 0))

    def history(self):
        h = self.h
        return (h.read8("wAILastMoveNum"), h.read8("wAISameMoveCount"),
                h.read8("wAILastMovePower"))

    # --- L1 part 2: the history records EXECUTED moves -----------------------
    def test_execution_hook_records_once_per_decision(self):
        # Unit contract of AITrackExecutedEnemyMove. The first call after a
        # decision wins: Metronome/Mirror Move re-enter EnemyCanExecuteMove
        # with wEnemySelectedMove overwritten by the called move.
        h = self.h
        self.boot([self.mon("SNORLAX", ["SPLASH"])], [self.mon("TAUROS", ["TACKLE"])])
        metronome, bolt = self.moves["METRONOME"], self.moves["THUNDERBOLT"]
        h.park_before_hijack()
        h.write8("wAILastMoveNum", 0)
        h.write8("wAISameMoveCount", 3)
        h.write8("wAILastMovePower", 0)
        h.call_routine("AITrackLastMove", limit=120)  # open a decision
        h.write8("wEnemySelectedMove", metronome)
        h.write8("wEnemyMovePower", 0)
        h.call_routine("AITrackExecutedEnemyMove", limit=120)
        first = self.history()
        h.write8("wEnemySelectedMove", bolt)  # the move Metronome called
        h.write8("wEnemyMovePower", 95)
        h.call_routine("AITrackExecutedEnemyMove", limit=120)
        self.assertEqual(first, (metronome, self.executed_bit, 0))
        self.assertEqual(self.history(), first)

        # Next decision, same move again: the streak grows by exactly one.
        h.call_routine("AITrackLastMove", limit=120)
        self.assertEqual(h.read8("wAISameMoveCount"), 0)  # flag cleared for scoring
        h.write8("wEnemySelectedMove", metronome)
        h.write8("wEnemyMovePower", 0)
        h.call_routine("AITrackExecutedEnemyMove", limit=120)
        self.assertEqual(self.history(), (metronome, self.executed_bit | 1, 0))

    def test_streak_saturates_below_the_executed_flag(self):
        h = self.h
        self.boot([self.mon("SNORLAX", ["SPLASH"])], [self.mon("TAUROS", ["TACKLE"])])
        tackle = self.moves["TACKLE"]
        cap = self.executed_bit - 1
        h.park_before_hijack()
        h.write8("wAILastMoveNum", tackle)
        h.write8("wAISameMoveCount", cap)
        h.write8("wEnemySelectedMove", tackle)
        h.write8("wEnemyMovePower", 40)
        h.call_routine("AITrackExecutedEnemyMove", limit=120)
        self.assertEqual(self.history(), (tackle, self.executed_bit | cap, 40))
        h.call_routine("AITrackLastMove", limit=120)
        self.assertEqual(h.read8("wAISameMoveCount"), cap)

    def test_flinched_turn_does_not_extend_the_streak(self):
        # Real turns. Tauros (faster) Tackles every turn except the second,
        # where it flinches. Before L1 part 2 the decision-time tracker counted
        # the flinched SELECTION, reading a streak of 2 at the fourth decision.
        h = self.h
        self.boot([self.mon("SNORLAX", ["SPLASH"])], [self.mon("TAUROS", ["TACKLE"])],
                  trainer="COOLTRAINER_M")
        self.no_items()
        tackle = self.moves["TACKLE"]
        decisions, executions = [], []

        def at_decision():
            decisions.append(self.history())

        def at_execute():
            executions.append(h.read8("wEnemySelectedMove"))
            if len(executions) == 2:
                h.write8("wEnemyBattleStatus1",
                         h.read8("wEnemyBattleStatus1") | (1 << self.battle["FLINCHED"]))

        h.hook_flag("AIEnemyTrainerChooseMoves", action=at_decision)
        h.hook_flag("ExecuteEnemyMove", action=at_execute)
        self.assertTrue(self.drive_turns(lambda: len(decisions) >= 4),
                        f"decisions={decisions}")
        print(f"\nL1 flinch decisions={decisions} executions={executions}")
        nums = [d[0] for d in decisions[:4]]
        streaks = [d[1] & (self.executed_bit - 1) for d in decisions[:4]]
        # Decision 1 sees the lead send-out's fresh-mon sentinel.
        self.assertEqual(nums, [self.ai["AI_LAST_MOVE_FRESH_MON"], tackle, tackle, tackle])
        self.assertEqual(streaks, [0, 0, 0, 1])
        self.assertNotEqual(decisions[1][2], 0)  # Tackle's power, from execution

    # --- L3: switching across real turns ------------------------------------
    def test_surviving_switch_in_happens_once_and_holds(self):
        # Slowpoke is kept in Thunderbolt's KO range and Thunderbolt is known,
        # so the AI switches to Geodude (immune: B4 says it survives). Geodude
        # must then stay, and start with a fresh move history.
        h = self.h
        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT"])],
                  [self.mon("SLOWPOKE", ["TACKLE"]), self.mon("GEODUDE", ["TACKLE"])])
        active, switches, first_geodude = [], [], []

        def at_trainer_ai():
            h.write8("wAICount", 0)
            h.reveal_player_moves(0, [1])
            pos = h.read8("wEnemyMonPartyPos")
            active.append(pos)
            if pos == 0:
                self.word("wEnemyMonHP", 2)

        def at_decision():
            if h.read8("wEnemyMonPartyPos") == 1 and not first_geodude:
                first_geodude.append(h.read8("wAILastMoveNum"))

        h.hook_flag("TrainerAI", action=at_trainer_ai)
        h.hook_flag("AIEnemyTrainerChooseMoves", action=at_decision)
        h.hook_flag("SwitchEnemyMon", action=lambda:
                    switches.append(h.read8("wEnemyMonPartyPos")))
        self.assertTrue(self.drive_turns(lambda: len(active) >= 5), f"active={active}")
        print(f"\nL3 survive active={active} switched-from={switches} "
              f"geodude-first-history={first_geodude}")
        self.assertEqual(switches, [0])
        self.assertEqual(active[:5], [0, 1, 1, 1, 1])
        self.assertEqual(first_geodude, [self.ai["AI_LAST_MOVE_FRESH_MON"]])

    def test_switch_in_that_would_be_koed_is_refused_every_turn(self):
        # Same threat, but Geodude sits at 1 HP and the player's Tackle is known
        # too. The ranking still prefers Geodude (Thunderbolt immunity), so the
        # B4 survival gate is what keeps Slowpoke in - on every turn, not once.
        h = self.h
        self.boot([self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT", "TACKLE"])],
                  [self.mon("SLOWPOKE", ["TACKLE"]), self.mon("GEODUDE", ["TACKLE"])])
        active, switches = [], []

        def at_trainer_ai():
            h.write8("wAICount", 0)
            h.reveal_player_moves(0, [1, 2])
            self.word("wEnemyMon2HP", 1)
            active.append(h.read8("wEnemyMonPartyPos"))
            self.word("wEnemyMonHP", 2)

        h.hook_flag("TrainerAI", action=at_trainer_ai)
        gate = h.hook_flag("AIBestReserveSurvivesThreat")
        h.hook_flag("SwitchEnemyMon", action=lambda:
                    switches.append(h.read8("wEnemyMonPartyPos")))
        self.assertTrue(self.drive_turns(lambda: len(active) >= 4), f"active={active}")
        print(f"\nL3 refuse active={active} switched-from={switches} gate={gate['count']}")
        self.assertEqual(switches, [])
        self.assertGreaterEqual(gate["count"], 3)

    # --- L3: a T3 plan across real turns ------------------------------------
    def test_para_sweep_paralyses_then_attacks(self):
        # Raichu is slower than Aerodactyl until paralysis quarters its Speed,
        # so ParaSweep fits with the flip bonus. Turn 1 must be Thunder Wave;
        # once it lands the plan goes quiet and Thunderbolt follows.
        h = self.h
        self.boot([self.mon("AERODACTYL", ["SPLASH"])],
                  [self.mon("RAICHU", ["THUNDER_WAVE", "THUNDERBOLT"])],
                  trainer="COOLTRAINER_M", tier=3)
        self.no_items()
        executed = []
        h.hook_flag("ExecuteEnemyMove", action=lambda: executed.append(
            (h.read8("wEnemySelectedMove"), h.read8("wBattleMonStatus"))))
        self.assertTrue(self.drive_turns(lambda: len(executed) >= 2), f"executed={executed}")
        print(f"\nL3 para-sweep executed={executed}")
        self.assertEqual([m for m, _ in executed[:2]],
                         [self.moves["THUNDER_WAVE"], self.moves["THUNDERBOLT"]])
        self.assertNotEqual(executed[1][1], 0)  # the second move saw a paralysed target


if __name__ == "__main__":
    unittest.main()
