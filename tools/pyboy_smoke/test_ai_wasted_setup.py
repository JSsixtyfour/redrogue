"""ai_telemetry's setup outcomes on real battles (AI_BACKLOG B12).

The pure classification is in test_ai_telemetry.py. These run the real hooks, so they
fail if a label moves or stops meaning "the move ran" or "the enemy fainted". The enemy's
HP is set by hand at the moment that matters, so no damage roll or critical hit decides
the outcome: Mr. Mime is faster and knows only Swift, which cannot miss.
"""
from pathlib import Path
import unittest

from ai_telemetry import BattleAITelemetry
from test_ai_turn_plan import TurnPlanBattle, mon

ROOT = Path(__file__).resolve().parents[2]
VILEPLUME = ['ABSORB', 'DOUBLE_EDGE', 'POISONPOWDER', 'SWORDS_DANCE']


class WastedSetupBattleTest(unittest.TestCase):
    def battle(self, *, kill_on_turn, player_moves=('SWIFT',), done=None):
        """Vileplume chooses Swords Dance on turn 1. kill_on_turn: drop her to 1 HP after
        that turn's decision, so the Swift that lands next is the one that kills."""
        state = {'telemetry': None, 'plans': 0}

        def prepare(h):
            if state['telemetry'] is None:
                state['telemetry'] = BattleAITelemetry(h, ROOT)
                state['telemetry'].begin_battle('ERIKA')
            state['plans'] += 1

        def commit(h):
            if state['plans'] == kill_on_turn:
                h.write8('wEnemyMonHP', 0)
                h.write8('wEnemyMonHP', 1, offset=1)

        b = TurnPlanBattle([mon('MR_MIME', list(player_moves), 46)], [mon('VILEPLUME', VILEPLUME, 42)],
                           'ERIKA', tier=3, prepare=prepare, hooks=[('AICommitEnemyTurn', commit)])
        self.addCleanup(b.close)
        telemetry = state['telemetry']
        h = b.h

        def over():
            ended = any(event['kind'] == 'faint' for event in telemetry.setup_events)
            return ended or (done is not None and done(telemetry))

        b.run_until(over)
        self.assertEqual(telemetry.errors, [])
        self.assertEqual(h.hook_errors, [])
        return telemetry.end_battle(0)['setup']

    def test_boost_then_killed_before_acting_again_is_wasted(self) -> None:
        setup = self.battle(kill_on_turn=2)
        self.assertEqual([(s['name'], s['outcome']) for s in setup], [('SWORDS_DANCE', 'wasted')])
        self.assertFalse(setup[0]['faster'])
        self.assertEqual(setup[0]['reserves'], 0)
        self.assertLess(setup[0]['hp_pct'], 100)  # Swift landed first: Mr. Mime is faster

    def test_chosen_boost_killed_before_it_runs_is_preempted(self) -> None:
        setup = self.battle(kill_on_turn=1)
        self.assertEqual([(s['name'], s['outcome']) for s in setup], [('SWORDS_DANCE', 'preempted')])
        self.assertEqual(setup[0]['hp_pct'], 100)  # read at selection, before the HP was dropped

    def test_boost_then_an_attack_is_used(self) -> None:
        def attacked(telemetry):
            return sum(event['kind'] == 'act' for event in telemetry.setup_events) >= 2

        setup = self.battle(kill_on_turn=None, done=attacked)
        self.assertEqual([(s['name'], s['outcome']) for s in setup], [('SWORDS_DANCE', 'used')])


if __name__ == '__main__':
    unittest.main(verbosity=2)
