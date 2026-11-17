"""CGB double-speed wrap around the post-KO send-out pass (AI_T4_REGRET_PLAN C0 cut 1,
2026-11-17). With the 60 FPS option on CGB, AIRankPostKOSendOut's candidate loop runs at
double speed and hands back single speed, the same wrap AIShouldSwitchAtSelectedSpeed uses
(test_cgb_ai_switch_speed). The choice must not depend on the speed. Measured on the five-reserve
probe board: ~950k cycles either way, ~6.8 frames of wall time at double speed against 13.5.
KEY1 bit 7 is read through the harness's KEY1 fix ($FE double, $7E single).
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
RESERVES = [
    ("SLOWBRO", ["SURF", "PSYCHIC_M", "ICE_BEAM", "BODY_SLAM"]),
    ("MAGMORTAR", ["FLAMETHROWER", "THUNDERBOLT", "BODY_SLAM", "EARTHQUAKE"]),
    ("RHYDON", ["EARTHQUAKE", "ROCK_SLIDE", "BODY_SLAM", "HYPER_BEAM"]),
]


class CGBPostKOSpeedTest(unittest.TestCase):
    def run_pass(self, fps60):
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts", cgb_mode=True)
        try:
            def mon(name, names):
                return dict(species=species[name], level=50, moves=[moves[n] for n in names])
            h.inject_fight2_spec(
                [mon("STARMIE", ["SURF", "PSYCHIC_M", "THUNDERBOLT", "ICE_BEAM"])],
                [mon("RATTATA", ["TACKLE"]), *[mon(s, m) for s, m in RESERVES]],
                trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
            h.boot_fight2(seed=1)
            h.write8("wAITurnPlan", 0)
            h.write8("wAISeenPlayerMoveMask", 15)
            for label in ("wEnemyMonHP", "wEnemyMon1HP"):  # the lead has just fainted
                h.write8(label, 0)
                h.write8(label, 0, offset=1)
            h.write8("wOptions2", (h.read8("wOptions2") & 0x7F) | (0x80 if fps60 else 0))
            inside = []
            h.register_hook("AIPostKOReply", lambda _c: inside.append(h.pyboy.memory[0xFF4D] & 0x80))
            slot, after = h.call_routine("AISelectSendOut", limit=400000, capture=lambda hh: (
                hh.read8("hWhichPokemon"), hh.pyboy.memory[0xFF4D] & 0x80))
            self.assertEqual(h.hook_errors, [])
            return slot, inside, after
        finally:
            h.close()

    def test_sixty_fps_runs_the_pass_at_double_speed_and_restores_single(self):
        slot_on, inside_on, after_on = self.run_pass(True)
        slot_off, inside_off, after_off = self.run_pass(False)
        self.assertEqual(len(inside_on), len(RESERVES), "every reserve scored once")
        self.assertTrue(all(inside_on), f"KEY1 bit 7 inside the pass: {inside_on}")
        self.assertEqual(after_on, 0, "single speed handed back")
        # Control: option off never switches.
        self.assertFalse(any(inside_off), f"KEY1 bit 7 with the option off: {inside_off}")
        self.assertEqual(after_off, 0)
        self.assertEqual(slot_on, slot_off, "the choice does not depend on CPU speed")


if __name__ == "__main__":
    unittest.main()
