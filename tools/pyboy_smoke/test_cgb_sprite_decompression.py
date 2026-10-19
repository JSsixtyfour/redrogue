"""Battle pic acceleration preserves pixels, speed, DMA and ROM-bank state."""
from pathlib import Path
import unittest
from unittest.mock import patch

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants
from sprite_decompression import load_golden, pic_labels, run_all


ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / 'tools/pyboy_smoke/artifacts'


class CGBSpriteDecompressionTest(unittest.TestCase):
    def exercise(self, *, battle=2, enabled=True, already_double=False, all_pics=False):
        h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=True)
        try:
            if already_double:
                h.boot_to_lobby()
            else:
                h.tick(120)
            h.park_before_hijack()
            expected_entry = 0x80 if already_double else 0
            self.assertEqual(h.pyboy.memory[0xff4d] & 0x80, expected_entry)
            h.write8('hIsInBattle', battle)
            h.write8('wOptions2', (h.read8('wOptions2') & 0x7f) | (0x80 if enabled else 0))
            should_switch = bool(battle and enabled and not already_double)
            inside_speed = 0x80 if already_double or should_switch else 0
            # Use a caller bank distinct from both pic and split banks. The
            # abandoned game is parked in VBlank; it will never resume.
            h.pyboy.memory[0x2000] = 1
            h.write8('hLoadedROMBank', 1)
            original_options = h.read8('wOptions2')
            decode, split, returned, switches = [], [], [], []

            def speed():
                return (h.pyboy.memory[0xff4d] & 0x80,
                        h.read8('hDMARoutine.waitCount', 1))

            h.register_hook('Decompress', lambda _: decode.append((speed(), h.read8('hLoadedROMBank'))))
            h.register_hook('SplitSpritePlanes', lambda _: split.append((speed(), h.read8('hLoadedROMBank'))))
            h.register_hook('DelayFrame', lambda _: returned.append((speed(), h.read8('hLoadedROMBank'), h.pyboy.register_file.SP)))
            h.register_hook('ToggleCPUSpeed', lambda _: switches.append(h.pyboy.memory[0xff4d] & 0x80))
            pics = pic_labels(ROOT)
            if not all_pics:
                names = {'RhydonPicFront', 'PikachuPicFront', 'RedPicBack', 'GiovanniPic'}
                pics = [(name, path) for name, path in pics if name in names]
                self.assertEqual(len(pics), len(names))
            with patch('sprite_decompression.pic_labels', return_value=pics):
                results = run_all(h)
            golden = load_golden()
            self.assertEqual({k: v['sha256'] for k, v in results.items()},
                             {k: golden[k] for k in results})
            count = len(results)
            self.assertEqual(len(decode), count)
            self.assertEqual(len(split), count)
            self.assertEqual(len(returned), count)
            inside = (inside_speed, 0x50 if inside_speed else 0x28)
            entry = (expected_entry, 0x50 if expected_entry else 0x28)
            expected_banks = [h.symbols.bank(name) for name, _ in pics for _flip in (0, 1)]
            for (name, _result), observed, bank in zip(results.items(), decode, expected_banks):
                self.assertEqual(observed, (inside, bank), name)
            self.assertTrue(all(row == (inside, h.symbols.bank('SplitSpritePlanes')) for row in split))
            self.assertTrue(all(row[:2] == (entry, 1) for row in returned))
            self.assertEqual(len({row[2] for row in returned}), 1, 'speed marker leaked stack bytes')
            self.assertEqual(switches, [0, 0x80] * count if should_switch else [])
            self.assertEqual(h.read8('wOptions2'), original_options)
        finally:
            h.close()

    def test_every_pic_accelerates_and_restores_single_speed(self):
        self.exercise(all_pics=True)

    def test_wild_battle_accelerates(self):
        self.exercise(battle=1)

    def test_option_off_preserves_single_speed(self):
        self.exercise(enabled=False)

    def test_outside_battle_preserves_single_speed(self):
        self.exercise(battle=0)

    def test_already_double_caller_stays_double(self):
        self.exercise(already_double=True)

    def test_already_double_option_off_stays_double(self):
        self.exercise(already_double=True, enabled=False)

    def test_real_battle_restores_single_before_send_out_animation(self):
        h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=True)
        species = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')
        moves = parse_rgbds_constants(ROOT / 'constants/move_constants.asm')
        trainers = parse_trainer_constants(ROOT / 'constants/trainer_constants.asm')
        decode, presentation, pending = [], [], []
        try:
            def enter(_):
                pending.append(h.read8('hIsInBattle'))
            def inside(_):
                if pending and pending[-1]:
                    decode.append((h.pyboy.memory[0xff4d] & 0x80,
                                   h.read8('hDMARoutine.waitCount', 1),
                                   h.read8('wOptions2'), h.read8('hGBC'),
                                   h.read8('hIsInBattle')))
            def leave(_):
                pending.pop()
            h.register_hook('UncompressSpriteData', enter)
            h.register_hook('Decompress', inside)
            h.register_hook('UncompressSpriteData.restoreBank', leave)
            # FIGHT 2 bypasses new-game option defaults. Select the normal
            # enabled setting before battle init; do not change CPU speed here.
            h.register_hook('InitBattleVariables', lambda _: h.write8(
                'wOptions2', h.read8('wOptions2') | 0x80))
            for label in ('RogueAnimateEnemySendOut', 'RogueAnimatePlayerSendOut', 'DisplayBattleMenu'):
                h.register_hook(label, lambda _: presentation.append(
                    (h.pyboy.memory[0xff4d] & 0x80, h.read8('hDMARoutine.waitCount', 1))))
            mon = dict(species=species['RHYDON'], level=50, moves=[moves['TACKLE']])
            h.inject_fight2_spec([mon], [mon], trainer_class=trainers['JUGGLER'], ai_tier=0)
            h.boot_fight2(seed=1)
            self.assertGreaterEqual(len(decode), 2)
            self.assertTrue(all(state[:2] == (0x80, 0x50) for state in decode), decode)
            self.assertGreaterEqual(len(presentation), 2)
            self.assertTrue(all(state == (0, 0x28) for state in presentation), presentation)
            self.assertEqual(pending, [])
        finally:
            h.close()
