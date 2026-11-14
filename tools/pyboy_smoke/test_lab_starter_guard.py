"""Starter selection stays closed on bridge visits, including skipped intros."""
from pathlib import Path
import unittest
from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]


class LabStarterGuardTest(unittest.TestCase):
    def test_bridge_and_intro_contexts_preserve_ball_visibility(self):
        h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        try:
            h.boot_to_lobby()
            for bridge, chosen, allowed in [(True, False, False),
                                             (True, True, False),
                                             (False, False, True),
                                             (False, True, False)]:
                with self.subTest(bridge=bridge, chosen=chosen):
                    h.write8('wWarpedFromWhichMap', 0xAE if bridge else 0)
                    flags = h.read8('wEventFlags', offset=30)
                    h.write8('wEventFlags', (flags & ~0x40) | (0x40 if chosen else 0), offset=30)
                    before = h.read_bytes('wToggleableObjectFlags', 32)
                    # Capture at the routine return, before the parked mainline resumes.
                    result = h.call_routine('OaksLabCheckStarterSelection', capture=lambda x: (
                        bool(x.pyboy.register_file.F & 0x80),
                        x.read_bytes('wToggleableObjectFlags', 32)))
                    self.assertEqual(result[0], allowed)
                    self.assertEqual(result[1], before)
        finally:
            h.close()


if __name__ == '__main__':
    unittest.main()

