"""Matched natural later-circuit state plus a disclosed near-loss HP fixture.

Set REDROGUE_ENDLESS_SOURCE_JOURNEY to the prior journey.json. This case changes
only current HP, drives real battle inputs, then requires normal-run progression.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import unittest

from integration_endless_journey import JourneyAgent, MAPS, ROOT
from harness import RedRogueHarness


class EndlessRecoveryIntegrationTest(unittest.TestCase):
    def test_later_loss_resets_depth_and_next_ordinary_stage_is_playable(self):
        source_name = os.environ.get('REDROGUE_ENDLESS_SOURCE_JOURNEY')
        if not source_name:
            self.skipTest('requires retained matched-build ancestor via REDROGUE_ENDLESS_SOURCE_JOURNEY')
        source = Path(source_name)
        metadata = json.loads(source.read_text())
        state = source.with_name('final.state')
        output = Path(__file__).parent / 'artifacts/endless_recovery'
        output.mkdir(parents=True, exist_ok=True)
        h = RedRogueHarness(ROOT, output)
        self.addCleanup(h.close)
        self.assertEqual(h.rom_sha256, metadata['rom_sha256'])
        self.assertEqual(h.sym_sha256, metadata['sym_sha256'])
        agent = JourneyAgent(h, accept=True, target_continuations=2)
        h.load_state(io.BytesIO(state.read_bytes()))
        initial_depth = h.read8('wEndlessDepth')
        self.assertGreaterEqual(initial_depth, 2)
        self.assertTrue(h.read8('hIsInBattle'), 'ancestor must be the recorded active battle')
        ancestor = {'journey': str(source), 'journey_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                    'state': str(state), 'state_sha256': hashlib.sha256(state.read_bytes()).hexdigest(),
                    'depth': initial_depth, 'rom_sha256': h.rom_sha256, 'sym_sha256': h.sym_sha256}
        injected = {}
        for slot in range(1, h.read8('wPartyCount') + 1):
            name = f'wPartyMon{slot}HP'
            injected[name] = {'before': h.read_bytes(name, 2), 'after': [0, 1]}
            h.write8(name, 0)
            h.write8(name, 1, 1)
        injected['wBattleMonHP'] = {'before': h.read_bytes('wBattleMonHP', 2), 'after': [0, 1]}
        h.write8('wBattleMonHP', 0)
        h.write8('wBattleMonHP', 1, 1)
        agent.battle_policy = 'first_slot'
        initial = io.BytesIO()
        h.save_state(initial)
        (output / 'initial.state').write_bytes(initial.getvalue())
        boundary = ordinary = None
        started = h.pyboy.frame_count
        agent.last_progress_frame = started
        try:
            while h.pyboy.frame_count - started < 300_000:
                agent.step()
                agent.checks.after_step()
                agent.note_progress()
                if len(agent.report.runs) == 1 and h.read8('hCurMap') == MAPS['SILPH_CO_DORM']:
                    boundary = boundary or {'depth': h.read8('wEndlessDepth'), 'state': agent.preserved()}
                if (boundary is not None and agent.report.stages_cleared > agent.run_start['stages']
                        and agent.report.battles_won > agent.run_start['battles_won']):
                    ordinary = {'depth': h.read8('wEndlessDepth'), 'battle_count': h.read8('wBattleCount')}
                    agent.finish('completed', 'HP-fixture loss then next ordinary stage cleared')
                    break
                if agent.checks.crash or h.hook_errors or len(agent.report.runs) > 1:
                    agent.finish('incomplete', 'recovery target not reached before another boundary or error')
                    break
                if h.pyboy.frame_count - agent.last_progress_frame > agent.stall_frames:
                    agent.finish('stalled', 'recovery did not progress')
                    break
            else:
                agent.finish('frame_limit', 'recovery exposure quota not reached')
        finally:
            agent.report.frames = h.pyboy.frame_count - started
            data = {'ancestor': ancestor, 'provenance': 'natural ancestor plus constructed current-HP boundary',
                    'injected_fields': injected, 'battle_policy': 'first_slot', 'report': agent.report.to_json(),
                    'boundary': boundary, 'ordinary_progress': ordinary,
                    'inputs': agent.full_inputs, 'anomalies': agent.checks.anomalies, 'hook_errors': h.hook_errors}
            (output / 'recovery.json').write_text(json.dumps(data, indent=2) + '\n')
        self.assertEqual(agent.report.outcome, 'completed', agent.report.detail)
        self.assertEqual(boundary['depth'], 0)
        self.assertEqual(ordinary['depth'], 0)
        self.assertEqual(agent.report.runs[0]['outcome'], 'blackout')
        self.assertEqual(h.hook_errors, [])
        self.assertEqual(agent.checks.anomalies, [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
