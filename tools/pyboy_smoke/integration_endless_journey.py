"""Configured Hall of Fame entry, real prompt input, playable next-stage exit.

The first Hall of Fame entry is configured. Subsequent circuits use real input;
the fixture must not be described as an unmodified natural first Champion clear.
Run explicitly with unittest; it is not part of the everyday smoke allocation.
"""
import io
import json
import os
from pathlib import Path
import unittest

import autoplay
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = Path(__file__).parent / 'artifacts' / 'endless_journey'
EVENTS = parse_rgbds_constants(ROOT / 'constants/event_constants.asm')
RAM = parse_rgbds_constants(ROOT / 'constants/ram_constants.asm')
MAPS = parse_map_constants(ROOT / 'constants/map_constants.asm')
KEPT = ('wKODefianceUsages', 'wTurnRewindUsages', 'wDiceCharges',
        'wHealAllItemLevel', 'wRestorePPItemLevel', 'wDayCareInUse', 'wDayCareInUse2')


class JourneyAgent(autoplay.AutoplayAgent):
    def __init__(self, h, *, accept, target_continuations=1):
        super().__init__(h, seed=31, player='strong')
        self.accept = accept
        self.offering = self.choosing = False
        self.offer_before = self.continued = self.declined = None
        self.first_stage = None
        self.full_inputs = []
        self.target_continuations = target_continuations
        self.continuation_frames = []
        self.champion_entries = []
        h.register_hook('EndlessOffer', self.offer)
        h.register_hook('YesNoChoice', self.choice)
        h.register_hook('EndlessContinue', self.continuation)
        h.register_hook('HallOfFameResetEventsAndSaveScript.presented', self.decline)

    def preserved(self):
        h = self.h
        return {**{name: h.read8(name) for name in KEPT},
                'money': h.read_bytes('wPlayerMoney', 3),
                'credits': h.read_bytes('wPlayerCoins', 2),
                'party_count': h.read8('wPartyCount'),
                'party_identity': [[h.read8(f'wPartyMon{i}Species'),
                                    h.read8(f'wPartyMon{i}CatchRate')]
                                   for i in range(1, h.read8('wPartyCount') + 1)]}

    def offer(self, _):
        self.offering = True
        self.offer_before = self.preserved()

    def choice(self, _):
        if self.offering:
            self.choosing = True

    def continuation(self, _):
        self.choosing = self.offering = False
        self.continued = self.h.pyboy.frame_count
        self.continuation_frames.append(self.continued)
        self.first_stage = None

    def end_run(self, outcome, detail):
        if outcome == 'champion' and self.target_continuations > 1:
            self.champion_entries.append(self.h.pyboy.frame_count)
            self.event('circuit_champion', endless_depth=self.h.read8('wEndlessDepth'))
        else:
            super().end_run(outcome, detail)

    def decline(self, _):
        if self.offering:
            self.declined = self.preserved()
            self.choosing = self.offering = False

    def ui_step(self):
        if self.choosing and self.h.pyboy.frame_count - self.last_wait_frame <= 2:
            target = 0 if self.accept else 1
            # The game processes each direction and the confirmation.
            self.press('a' if self.h.read8('hCurrentMenuItem') == target else 'down')
        else:
            super().ui_step()

    def on_map_change(self, current):
        previous = self.current_map
        super().on_map_change(current)
        if previous == self.hall_of_fame and self.continued is not None:
            self.stage_map = self.last_stage = current

    def step(self):
        if (self.continued is not None and self.first_stage is None
                and self.h.read8('hCurMap') != self.hall_of_fame
                and self.mode() == 'overworld'):
            self.first_stage = {'map': self.h.read8('hCurMap'),
                                'depth': self.h.read8('wEndlessDepth'),
                                'battle_count': self.h.read8('wBattleCount'),
                                'kept': self.preserved()}
        super().step()
        self.full_inputs.extend(self.report.inputs)
        self.report.inputs.clear()


class EndlessJourneyIntegrationTest(unittest.TestCase):
    def setUp(self):
        self.output = OUTPUT / self._testMethodName
        self.output.mkdir(parents=True, exist_ok=True)
        self.h = RedRogueHarness(ROOT, self.output)
        self.addCleanup(self.h.close)
        autoplay.boot(self.h, 31, battle_count=73, difficulty='VERY_EASY')
        self.h.set_event(EVENTS['EVENT_AI_DEFEATED'])
        # The only navigation fixture: re-point the current arrival warp to
        # Hall of Fame. The engine then owns entry, scripts, prompt and exit.
        self.h.write8('wWarpEntries', 0, offset=2)
        self.h.write8('wWarpEntries', MAPS['HALL_OF_FAME'], offset=3)

    def journey(self, accept, target_continuations=1, later_blackout=False):
        h = self.h
        agent = JourneyAgent(h, accept=accept, target_continuations=target_continuations)
        baseline = io.BytesIO()
        h.save_state(baseline)
        (self.output / 'initial.state').write_bytes(baseline.getvalue())
        agent.walk('up')
        agent.walk('down')
        blackout_boundary = ordinary_progress = None
        try:
            if accept and target_continuations > 1:
                start = h.pyboy.frame_count
                agent.last_progress_frame = start
                frame_budget = 3_000_000 if later_blackout else 1_500_000
                while h.pyboy.frame_count - start < frame_budget:
                    agent.step()
                    agent.checks.after_step()
                    agent.note_progress()
                    if (agent.first_stage is not None
                            and len(agent.continuation_frames) >= target_continuations):
                        if not later_blackout:
                            agent.finish('completed', 'reached input-ready stage after natural intervening circuit')
                            break
                    if (later_blackout and len(agent.report.runs) == 1
                            and h.read8('hCurMap') == MAPS['SILPH_CO_DORM']
                            and blackout_boundary is None):
                        blackout_boundary = {'depth': h.read8('wEndlessDepth'),
                            'frame': h.pyboy.frame_count, 'kept': agent.preserved()}
                    if (blackout_boundary is not None
                            and agent.report.stages_cleared > agent.run_start['stages']
                            and agent.report.battles_won > agent.run_start['battles_won']):
                        ordinary_progress = {'depth': h.read8('wEndlessDepth'),
                            'battle_count': h.read8('wBattleCount'), 'frame': h.pyboy.frame_count}
                        agent.finish('completed', 'later-circuit blackout and next ordinary stage progressed')
                        break
                    if ((agent.report.runs and (not later_blackout or len(agent.report.runs) > 1))
                            or agent.checks.crash or h.hook_errors):
                        agent.finish('incomplete', 'blackout, crash or hook failure before target circuit')
                        break
                    if h.pyboy.frame_count - agent.last_progress_frame > agent.stall_frames:
                        agent.finish('stalled', 'no progress before target circuit')
                        break
                else:
                    agent.finish('frame_limit', 'later blackout/ordinary progression not reached within frame budget'
                                 if later_blackout else 'target circuit not reached within frame budget')
                agent.report.frames = h.pyboy.frame_count - start
            elif accept:
                agent.run(runs=1, stages=1, max_frames=300_000)
            else:
                start = h.pyboy.frame_count
                while agent.declined is None and h.pyboy.frame_count - start < 30_000:
                    agent.step()
                    agent.checks.after_step()
                    if agent.checks.crash or h.hook_errors:
                        break
        finally:
            data = {'provenance': {'natural_gameplay': False,
                        'injected_fields': ['EVENT_AI_DEFEATED', 'wWarpEntries[2:4]'],
                        'boot': 'Debug 2 battle count 73 VERY_EASY',
                        'interaction': 'real joypad Hall of Fame presentation and prompt'},
                    'rom_sha256': h.rom_sha256, 'sym_sha256': h.sym_sha256,
                    'accept': accept, 'offer_before': agent.offer_before,
                    'continue_frame': agent.continued, 'declined': agent.declined,
                    'continuation_frames': agent.continuation_frames,
                    'champion_entries_after_fixture': agent.champion_entries,
                    'blackout_boundary': blackout_boundary, 'ordinary_progress': ordinary_progress,
                    'first_stage': agent.first_stage, 'report': agent.report.to_json(),
                    'full_inputs': agent.full_inputs, 'anomalies': agent.checks.anomalies,
                    'checks': agent.checks.summary(), 'hook_errors': h.hook_errors}
            (self.output / 'journey.json').write_text(json.dumps(data, indent=2) + '\n')
            final = io.BytesIO()
            h.save_state(final)
            (self.output / 'final.state').write_bytes(final.getvalue())
            h.pyboy.tick(1, render=True)
            h.pyboy.screen.image.save(self.output / 'final.png')
        self.assertIsNotNone(agent.offer_before, 'never reached actual Endless offer')
        self.assertEqual(h.hook_errors, [])
        self.assertEqual(agent.checks.anomalies, [])
        return agent

    def test_accept_reaches_and_exits_playable_stage(self):
        agent = self.journey(True)
        self.assertIsNotNone(agent.continued)
        self.assertIsNotNone(agent.first_stage, 'no normal input poll on continued stage')
        self.assertEqual(agent.first_stage['depth'], 1)
        self.assertEqual(agent.first_stage['battle_count'], 1)
        self.assertEqual(agent.first_stage['kept'], agent.offer_before)
        self.assertEqual(agent.report.outcome, 'completed', agent.report.detail)
        self.assertEqual(agent.report.blackouts, 0)
        self.assertGreaterEqual(agent.report.stages_cleared, 1)
        self.assertGreaterEqual(agent.report.battles_won, 1, 'no actual trainer interaction')

    def test_decline_preserves_offer_state(self):
        agent = self.journey(False)
        self.assertIsNone(agent.continued)
        self.assertEqual(agent.declined, agent.offer_before)
        self.assertEqual(self.h.read8('wEndlessDepth'), 0)

    def test_two_acceptances_with_natural_intervening_circuit(self):
        """First HOF entry is configured; all intervening stages use real input."""
        agent = self.journey(True, target_continuations=2)
        self.assertEqual(agent.report.outcome, 'completed', agent.report.detail)
        self.assertEqual(len(agent.continuation_frames), 2)
        self.assertEqual(len(agent.champion_entries), 1)
        self.assertEqual(agent.first_stage['depth'], 2)
        self.assertGreaterEqual(agent.report.stages_cleared, 8)
        self.assertGreaterEqual(agent.report.battles_won, 8)

    @unittest.skipUnless(os.environ.get('REDROGUE_ENDLESS_LOSS_SEARCH') == '1',
                         'optional bounded natural-loss search; set REDROGUE_ENDLESS_LOSS_SEARCH=1')
    def test_later_circuit_blackout_then_next_ordinary_stage(self):
        """Bounded natural loss search after the configured first HOF entry."""
        agent = self.journey(True, target_continuations=2, later_blackout=True)
        evidence = json.loads((self.output / 'journey.json').read_text())
        self.assertEqual(agent.report.outcome, 'completed', agent.report.detail)
        self.assertGreaterEqual(len(agent.continuation_frames), 2)
        self.assertEqual(agent.report.runs[0]['outcome'], 'blackout')
        self.assertEqual(evidence['blackout_boundary']['depth'], 0)
        self.assertEqual(evidence['ordinary_progress']['depth'], 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
