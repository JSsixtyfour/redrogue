"""Later-run quotas must fail closed on missing or merely aggregate exposure."""
import copy
import unittest
from lifecycle_exposure import evaluate


class LifecycleExposureTest(unittest.TestCase):
    def data(self):
        from detector_health import CORE
        return {'outcome': 'completed', 'build_identity': {'gbc': 'rom', 'sym': 'sym'},
                'detector_ledger': {'detectors': {name: {'status': 'observed', 'enabled': True,
                    'available': True, 'errors': 0} for name in CORE +
                    ('screen_pointers', 'screen_code_rules', 'crash_vector')}},
                'anomalies': [], 'hook_errors': [],
                'runs': [{'run_index': i, 'outcome': 'blackout', 'stages_cleared': 1,
                          'battles_won': 2} for i in range(1, 4)],
                'events': [{'kind': 'playable_visit', 'run_index': i, 'map': 'ROUTE_1',
                            'state': {'wEndlessDepth': [0], 'hIsInBattle': [0], 'wBattleCount': [1]}}
                           for i in range(1, 4)]}

    def test_each_run_has_exposure(self):
        self.assertEqual(evaluate(self.data())['verdict'], 'exposure_met')

    def test_aggregate_stages_do_not_cover_early_blackouts(self):
        data = self.data()
        data['runs'][0]['stages_cleared'] = 100
        data['runs'][2]['stages_cleared'] = 0
        self.assertIn('run 3: meaningful progression quota unmet', evaluate(data)['gaps'])

    def test_missing_indexed_observations_are_incomplete(self):
        for field in ('events', 'runs', 'build_identity', 'detector_ledger'):
            data = copy.deepcopy(self.data())
            data.pop(field)
            with self.subTest(field=field):
                self.assertEqual(evaluate(data)['verdict'], 'incomplete')

    def test_unfinished_or_findings_cannot_meet_exposure(self):
        for field, value in [('outcome', 'frame_limit'), ('anomalies', ['suspect']),
                             ('hook_errors', ['broken observer'])]:
            data = self.data()
            data[field] = value
            self.assertEqual(evaluate(data)['verdict'], 'incomplete')

    def test_input_ready_poll_must_belong_to_current_map(self):
        from types import SimpleNamespace
        from autoplay import AutoplayAgent
        agent = AutoplayAgent.__new__(AutoplayAgent)
        agent.h = SimpleNamespace(pyboy=SimpleNamespace(frame_count=100),
                                  read8=lambda name: 12 if name == 'hCurMap' else 0)
        agent.naming_screen = False
        agent.last_ui_frame = -1
        agent.last_overworld_frame = 99
        agent.disable_joypad_mask = 1
        agent.last_overworld_map = 12
        self.assertEqual(agent.mode(), 'overworld')
        agent.last_overworld_map = 11
        self.assertEqual(agent.mode(), 'busy')

    def test_unobserved_state_or_endless_circuit_cannot_cover_ordinary_run(self):
        for state in ({}, {'wEndlessDepth': [1], 'hIsInBattle': [0], 'wBattleCount': [1]}):
            data = self.data()
            data['events'][0]['state'] = state
            self.assertEqual(evaluate(data)['verdict'], 'incomplete')
