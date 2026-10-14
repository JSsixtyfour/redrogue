"""Real battle coverage for the computation-only AI switch speed wrapper."""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class CGBSwitchSpeedTest(unittest.TestCase):
    def exercise(self, enabled=True, already_double=False):
        h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts', cgb_mode=True)
        species = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')
        moves = parse_rgbds_constants(ROOT / 'constants/move_constants.asm')
        trainers = parse_trainer_constants(ROOT / 'constants/trainer_constants.asm')
        def mon(name, names):
            return dict(species=species[name], level=50, moves=[moves[n] for n in names])
        observations, presentation, switches = [], [], []
        pending = {}
        def state():
            return (h.pyboy.memory[0xFF4D] & 0x80,
                    h.pyboy.memory[h.address('hDMARoutine.waitCount') + 1])
        try:
            h.inject_fight2_spec(
                [mon('ELECTRODE', ['SPLASH', 'THUNDERBOLT'])],
                [mon('SLOWPOKE', ['TACKLE']), mon('GEODUDE', ['TACKLE'])],
                trainer_class=trainers['JUGGLER'], ai_tier=2)
            h.boot_fight2(seed=1)
            h.write8('wOptions2', (h.read8('wOptions2') & 0x7F) | (0x80 if enabled else 0))
            if already_double:
                # Test an alternate caller context by leaving move selection's
                # already-enabled double speed intact. Do not intercept the
                # wrapper's restoration: doing so would hide a wrapper bug.
                keep_choice_speed = {'value': True}
                h.hook_flag('AIEnemyTrainerChooseMoves', action=lambda:
                            keep_choice_speed.update(value=True))
                h.hook_flag('AIShouldSwitchAtSelectedSpeed', action=lambda:
                            keep_choice_speed.update(value=False))
                def leave_choice_double(_):
                    if keep_choice_speed['value']:
                        h.pyboy.register_file.PC = h.address('SingleCPUSpeed.return')
                h.register_hook('SingleCPUSpeed', leave_choice_double)
            def prepare():
                h.write8('wAICount', 0)
                h.reveal_player_moves(0, [1])
                if h.read8('wEnemyMonPartyPos') == 0:
                    hp = int.from_bytes(bytes(h.read_bytes('wEnemyMonMaxHP', 2)), 'big') // 4 + 1
                    h.write8('wEnemyMonHP', hp >> 8)
                    h.write8('wEnemyMonHP', hp & 255, 1)
            h.hook_flag('TrainerAI', action=prepare)
            h.hook_flag('AIShouldSwitchAtSelectedSpeed', action=lambda: pending.update(entry=state()))
            h.hook_flag('AIShouldSwitch', action=lambda: pending.update(inside=state()))
            h.hook_flag('AIShouldSwitch.switch', action=lambda: pending.update(expected=True))
            h.hook_flag('AIShouldSwitch.stay', action=lambda: pending.update(expected=False))
            def returned():
                observations.append(dict(pending, returned=state(), carry=bool(h.pyboy.register_file.F & 0x10)))
                pending.clear()
            h.hook_flag('AISwitchIfEnoughMons.switchDecisionReady', action=returned)
            h.hook_flag('SwitchEnemyMon', action=lambda: (switches.append(h.read8('wEnemyMonPartyPos')), presentation.append(state())))
            h.hook_flag('ExecuteEnemyMove', action=lambda: presentation.append(state()))
            h.hook_flag('DisplayBattleMenu', action=lambda: h.write8('wBattleAndStartSavedMenuItem', 0))
            for _ in range(2400):
                if len(observations) >= 3:
                    break
                h.tap('a', 1)
                h.tick(8)
            self.assertGreaterEqual(len(observations), 3)
            self.assertEqual(switches, [0], 'the real battle should switch once and then stay')
            self.assertEqual([r['carry'] for r in observations[:3]], [True, False, False])
            for row in observations:
                self.assertEqual(row['carry'], row['expected'], 'speed restoration lost the decision carry')
                self.assertEqual(row['inside'], (0x80, 0x50) if enabled else (0, 0x28))
                expected = (0x80, 0x50) if already_double else (0, 0x28)
                self.assertEqual(row['entry'], expected)
                self.assertEqual(row['returned'], expected)
            self.assertTrue(presentation)
            if not already_double:
                self.assertTrue(all(s == (0, 0x28) for s in presentation), presentation)
        finally:
            h.close()

    def test_enabled_accelerates_switch_and_stay_and_restores_presentation(self):
        self.exercise()

    def test_option_off_preserves_single_speed_and_decisions(self):
        self.exercise(enabled=False)

    def test_already_double_caller_keeps_its_speed(self):
        self.exercise(already_double=True)
