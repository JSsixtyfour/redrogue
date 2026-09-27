"""Regression for code sweep 2026-09-27 F1: ParalyzeEffect_ must set PAR.

ParalyzeEffect_ does `callfar CheckTargetSubstitute` with hl = the target's
status byte. callfar loads hl with the far target's address and Bankswitch's
return path never restores it, so without a push/pop around the call hl came
back as CheckTargetSubstitute's own ROM address: `set PAR, [hl]` wrote to ROM
and the Ground-immunity check read two ROM bytes instead of the target's types.
Thunder Wave, Stun Spore and Glare never paralyzed anything.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]

PAR_MASK = 1 << 6            # PAR = 6 (constants/battle_constants.asm)
USING_X_ACCURACY_MASK = 1 << 0  # USING_X_ACCURACY = 0, wPlayerBattleStatus2
NORMAL = 0x00                # constants/type_constants.asm
GROUND = 0x04
ELECTRIC = 0x17


class ParalyzeEffectTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.thunder_wave = moves["THUNDER_WAVE"]

        def mon(name, move_names):
            return {"species": species[name], "level": 50,
                    "moves": [moves[m] for m in move_names]}

        self.h.inject_fight2_spec(
            [mon("PIKACHU", ["THUNDER_WAVE"])],
            [mon("TAUROS", ["SPLASH"])],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=1)
        self.h.boot_fight2(seed=1)

    def tearDown(self) -> None:
        self.h.close()

    def run_thunder_wave(self, enemy_type2: int) -> dict[str, object]:
        """Run ParalyzeEffect_ up to its first exit and capture state there.

        Every exit goes on to DelayFrames / animations / text, which wait on
        VBlank and cannot run under a PC hijack, so the probe stops at the exit
        seam (probe_routine_until restores the machine afterwards). On the
        success path QuarterSpeedDueToParalysis is entered only AFTER
        `set PAR, [hl]`, so the status read there is the result.
        """
        h = self.h
        h.park_before_hijack()
        h.write8("hWhoseTurn", 0)
        h.write8("wPlayerMoveNum", self.thunder_wave)
        h.write8("wPlayerMoveType", ELECTRIC)
        # X Accuracy makes MoveHitTest deterministic (Gen 1 "100%" moves miss 1/256).
        h.write8("wPlayerBattleStatus2", USING_X_ACCURACY_MASK)
        h.write8("wEnemyBattleStatus2", 0)  # no Substitute
        h.write8("wEnemyMonStatus", 0)
        h.write8("wEnemyMonType1", NORMAL)
        h.write8("wEnemyMonType2", enemy_type2)

        captured: dict[str, object] = {}
        hooks = []

        def on_hit_test(_context) -> None:
            captured["hl"] = h.pyboy.register_file.HL

        def exit_hook(name):
            def callback(_context) -> None:
                if "exit" not in captured:
                    captured["exit"] = name
                    captured["status"] = h.read8("wEnemyMonStatus")
            return callback

        seams = [("ParalyzeEffect_.hitTest", on_hit_test)] + [
            (label, exit_hook(label)) for label in (
                "QuarterSpeedDueToParalysis",
                "ParalyzeEffect_.didntAffect",
                "ParalyzeEffect_.doesntAffect",
            )
        ]
        for label, callback in seams:
            bank, address = h.symbols.get(label)
            h.pyboy.hook_register(bank, address, callback, None)
            hooks.append((bank, address))
        try:
            h.probe_routine_until("ParalyzeEffect_", lambda: "exit" in captured, limit=120)
        finally:
            for bank, address in hooks:
                h.pyboy.hook_deregister(bank, address)
        return captured

    def test_thunder_wave_paralyzes_a_normal_type(self) -> None:
        captured = self.run_thunder_wave(NORMAL)
        # hl must still address the target's status byte after the far call.
        self.assertEqual(captured.get("hl"), self.h.address("wEnemyMonStatus"))
        self.assertEqual(captured.get("exit"), "QuarterSpeedDueToParalysis")
        self.assertEqual(captured["status"] & PAR_MASK, PAR_MASK)

    def test_thunder_wave_does_not_affect_a_ground_type(self) -> None:
        captured = self.run_thunder_wave(GROUND)
        # The immunity branch must fire, which requires the type bytes it read
        # to have been the enemy's real ones, not ROM.
        self.assertEqual(captured.get("exit"), "ParalyzeEffect_.doesntAffect")
        self.assertNotIn("hl", captured)
        self.assertEqual(captured["status"], 0)


if __name__ == "__main__":
    unittest.main()
