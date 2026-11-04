"""Trainer Ditto send-out on the color battle path."""
import unittest

from source_constants import parse_trainer_constants
from harness import RedRogueHarness
from test_crystal_pink_forms import ARTIFACTS, MOVES, PALETTES, ROOT, SPECIES


class TrainerShinySendOutTest(unittest.TestCase):
    def test_cgb_trainer_ditto_send_out(self):
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        for flags, expected in ((0, "PAL_GRAYMON"), (16, "PAL_MEWMON")):
            with self.subTest(flags=flags):
                h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=True)
                try:
                    h.inject_fight2_spec(
                        [dict(species=SPECIES["ONIX"], level=20, moves=[MOVES["TACKLE"]])],
                        [dict(species=SPECIES["DITTO"], level=20, moves=[MOVES["TRANSFORM"]])],
                        trainer_class=trainers["YOUNGSTER"], ai_tier=0)
                    h.register_hook("GetEnemyCatchRateByte",
                                    lambda _: h.write8("wEnemyMon1CatchRate", flags))
                    sparkles = []
                    palettes = []
                    h.register_hook("PlaySelectedAnimation", lambda _:
                                    sparkles.append((h.pyboy.register_file.D, h.pyboy.register_file.E)))
                    def capture(_):
                        if h.read8("wEnemyMonSpecies2") == SPECIES["DITTO"]:
                            palettes.append(h.read8("wPalPacket", 7))
                    h.register_hook("SetPal_Battle.enemyNotTypeVariant", capture)
                    h.boot_fight2(seed=1)
                    self.assertEqual(h.read8("wEnemyMonSpecies"), SPECIES["DITTO"])
                    self.assertEqual(h.read8("wEnemyMonCatchRate"), flags)
                    self.assertEqual([s for s in sparkles if s[0] == 1],
                                     [(1, 182)] if flags else [])
                    self.assertEqual(set(palettes), {PALETTES[expected]})
                finally:
                    h.close()
