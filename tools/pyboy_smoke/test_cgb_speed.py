from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class CGBSpeedSmokeTest(unittest.TestCase):
    def test_default_options_enable_double_speed_and_patch_oam_wait(self) -> None:
        harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=True)
        try:
            harness.boot_to_lobby()
            self.assertEqual(harness.read8("wOptions2") & 0xC0, 0xC0)
            self.assertNotEqual(
                harness.read8("wRogueFlagsBitfield2") & 0x08,
                0,
                "Enhanced Colors is enabled but the overworld palette path is inactive",
            )
            self.assertEqual(harness.pyboy.memory[0xFF4D] & 0x80, 0x80)
            wait_immediate = harness.address("hDMARoutine.waitCount") + 1
            self.assertEqual(harness.pyboy.memory[wait_immediate], 0x50)
        finally:
            harness.close()
