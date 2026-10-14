"""AI accuracy must match the real hit formula without mutating its inputs."""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]


class AIHitChanceTest(unittest.TestCase):
    def test_matches_engine_and_preserves_inputs(self):
        h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        try:
            h.boot_to_lobby()
            # Exhaust neutral base bytes; cover every legal stage pairing at
            # boundaries where rounding, minimum-one and saturation matter.
            cases = [(7, 7, a) for a in range(256)]
            cases += [(a, e, chance) for a in range(1, 14)
                      for e in range(1, 14) if (a, e) != (7, 7)
                      for chance in (0, 1, 140, 229, 255)]
            for acc, eva, chance in cases:
                h.park_before_hijack()
                h.write8('wEnemyMonAccuracyMod', acc)
                h.write8('wPlayerMonEvasionMod', eva)
                h.write8('wEnemyMoveEffect', 0)
                h.write8('wEnemyMoveAccuracy', chance)
                h.write8('hWhoseTurn', 1)
                h.call_routine('CalcHitChance')
                expected = h.read8('wEnemyMoveAccuracy')
                for turn in (0, 1):
                    h.park_before_hijack()
                    h.write8('wEnemyMoveAccuracy', chance)
                    h.write8('hWhoseTurn', turn)
                    h.call_routine('AIGetMoveHitChance')
                    self.assertEqual(h.last_call_registers['A'], expected,
                                     (acc, eva, chance, turn))
                    self.assertEqual(h.read8('wEnemyMoveAccuracy'), chance)
                    self.assertEqual(h.read8('hWhoseTurn'), turn)
        finally:
            h.close()

    def test_swift_bypasses_stages_and_zero_accuracy(self):
        h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        try:
            h.boot_to_lobby()
            effects = parse_rgbds_constants(ROOT / 'constants/move_effect_constants.asm')
            h.write8('wEnemyMoveEffect', effects['SWIFT_EFFECT'])
            h.write8('wEnemyMoveAccuracy', 0)
            h.write8('wEnemyMonAccuracyMod', 1)
            h.write8('wPlayerMonEvasionMod', 13)
            h.call_routine('AIGetMoveHitChance')
            self.assertEqual(h.last_call_registers['A'], 255)
            self.assertEqual(h.read8('wEnemyMoveAccuracy'), 0)
        finally:
            h.close()
