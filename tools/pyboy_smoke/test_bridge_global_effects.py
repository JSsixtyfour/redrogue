from __future__ import annotations

import io
from pathlib import Path
import unittest

from harness import RedRogueHarness


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class BridgeGlobalEffectsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.harness.boot_to_lobby()

    def tearDown(self) -> None:
        self.harness.close()

    def test_all_effect_bits_and_stat_mirrors(self) -> None:
        start = self.harness.address("wBridgeGlobalEffects")
        self.harness.pyboy.memory[start : start + 3] = [0, 0, 0]
        self.harness.write8("wEarnedStatBoosts", 0)
        baseline = io.BytesIO()
        self.harness.save_state(baseline)

        for effect in range(17):
            self.harness.load_state(baseline)
            self.harness.pyboy.register_file.E = effect
            self.harness.call_routine("BridgeGrantGlobalEffect")
            expected = [0, 0, 0]
            expected[effect // 8] = 1 << (effect % 8)
            self.assertEqual(list(self.harness.pyboy.memory[start : start + 3]), expected)
            expected_stat = {3: 0x01, 8: 0x04, 11: 0x02}.get(effect, 0)
            self.assertEqual(self.harness.read8("wEarnedStatBoosts") & 0x07, expected_stat)

    def test_run_reset_clears_effects_and_stat_mirrors(self) -> None:
        start = self.harness.address("wBridgeGlobalEffects")
        self.harness.pyboy.memory[start : start + 3] = [0xFF, 0xFF, 0x01]
        self.harness.write8("wEarnedStatBoosts", 0x0F)

        self.harness.call_routine("RogueResetRunState")

        self.assertEqual(list(self.harness.pyboy.memory[start : start + 3]), [0, 0, 0])
        self.assertEqual(self.harness.read8("wEarnedStatBoosts"), 0)

    def test_invalid_effect_indexes_cannot_spill_into_adjacent_state(self) -> None:
        start = self.harness.address("wBridgeGlobalEffects")
        witch = self.harness.address("wWitchPrizesEarned")
        self.harness.pyboy.memory[start : start + 3] = [0, 0, 0]
        self.harness.pyboy.memory[witch : witch + 2] = [0x5A, 0xA5]
        baseline = io.BytesIO()
        self.harness.save_state(baseline)

        for effect in (17, 23, 24, 0xFF):
            self.harness.load_state(baseline)
            self.harness.pyboy.register_file.E = effect
            self.harness.call_routine("BridgeGrantGlobalEffect")
            self.assertEqual(list(self.harness.pyboy.memory[start : start + 3]), [0, 0, 0])
            self.assertEqual(list(self.harness.pyboy.memory[witch : witch + 2]), [0x5A, 0xA5])

    def test_witch_special_prize_activates_the_shared_stat_bit(self) -> None:
        # PCWitchSetup grants the previous accepted offer before rolling the
        # next one. Eight badges plus Victory Road complete takes its short
        # hide-witch exit after that grant.
        self.harness.write8("wEarnedStatBoosts", 0)
        self.harness.write8("wWitchPrize", 7)  # PRIZE_SPECIAL_BOOST
        self.harness.write8("wRogueFlagsBitfield", 1 << 3)  # BIT_WITCH_ACCEPTED
        self.harness.write8("wObtainedBadges", 0xFF)
        self.harness.call_routine("PCWitchSetup")
        self.assertEqual(self.harness.read8("wEarnedStatBoosts") & 0x08, 0x08)

    def test_effect_storage_is_inside_saved_and_reset_ranges(self) -> None:
        start = self.harness.address("wBridgeGlobalEffects")
        end = self.harness.address("wBridgeGlobalEffectsEnd")
        self.assertEqual(end - start, 3)
        self.assertLessEqual(self.harness.address("wMainDataStart"), start)
        self.assertLessEqual(end, self.harness.address("wMainDataEnd"))
        self.assertLessEqual(self.harness.address("wGameProgressFlags"), start)
        self.assertLessEqual(end, self.harness.address("wGameProgressFlagsEnd"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
