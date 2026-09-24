from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from test_follower_yellow_runtime import YellowFollowerRoute1CGBContract


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

    def test_trainer_party_builds_double_speed_and_transition_runs_single(self) -> None:
        """ReadTrainerFast runs the enemy party build at the 60 FPS speed, and
        battle is back at single speed by the transition. Also pins the
        harness KEY1 fix: without it bit 7 reads 1 after every switch, so the
        BattleTransition half of this could never fail."""
        harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=True)
        seen: dict[str, int] = {}

        def record(label: str):
            def callback(_context) -> None:
                seen.setdefault(label, harness.pyboy.memory[0xFF4D] & 0x80)
            return callback

        try:
            harness.boot_to_lobby()
            harness.register_hook("ReadTrainer", record("ReadTrainer"))
            harness.register_hook("BattleTransition", record("BattleTransition"))
            # OPP_LORELEI = OPP_ID_OFFSET (160) + LORELEI ($2C); the lobby's own
            # OverworldLoop .newBattle path starts the battle from these bytes.
            harness.write8("wCurOpponent", 160 + 0x2C)
            harness.write8("wTrainerNo", 1)
            harness.write8("wIsTrainerBattle", 1)
            harness.wait_until(
                lambda: "BattleTransition" in seen,
                "the Lorelei battle transition",
                1500,
            )
            self.assertEqual(seen.get("ReadTrainer"), 0x80, "party build ran at single speed")
            self.assertEqual(seen["BattleTransition"], 0x00, "transition ran at double speed")
        finally:
            harness.close()


class YellowFollowerRoute1CGBTest(
    YellowFollowerRoute1CGBContract,
    unittest.TestCase,
):
    """Run the Route 1 60 FPS contract in the CGB-classified module."""
