"""Runtime regression fixtures for AI review checkpoint B contracts."""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class AICheckpointBTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

        def mon(name, moves):
            return {
                "species": self.species[name],
                "level": 50,
                "moves": [self.moves[move] for move in moves],
            }

        self.h.inject_fight2_spec(
            [mon("SNORLAX", ["SPLASH"])],
            [mon("TAUROS", ["TACKLE"])],
            trainer_class=trainers["COOLTRAINER_M"],
            ai_tier=2,
        )
        self.h.boot_fight2(seed=1)

    def tearDown(self):
        self.h.close()

    def word(self, label, value):
        self.h.write8(label, value >> 8)
        self.h.write8(label, value & 255, offset=1)

    def load_enemy_move(self, name):
        h = self.h
        bank, address = h.symbols.get("Moves")
        offset = bank * 0x4000 + address - 0x4000 + (self.moves[name] - 1) * 6
        data = (ROOT / "pokeblue_debug.gbc").read_bytes()[offset:offset + 6]
        for index, value in enumerate(data):
            h.write8("wEnemyMoveNum", value, offset=index)

    def estimate(self, name, crit=False):
        h = self.h
        h.park_before_hijack()
        self.load_enemy_move(name)
        h.call_routine("AIEstimateDamage", limit=120)
        if crit:
            h.park_before_hijack()
            h.call_routine("AIScaleDamageForCrit", limit=120)
        return int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big")

    def test_crit_expectation_cannot_invent_an_ordinary_hit_ko(self):
        h = self.h
        raw = self.estimate("TACKLE")
        weighted = self.estimate("TACKLE", crit=True)
        self.assertGreater(weighted, raw)

        # Put the target immediately above the maximum ordinary hit but below
        # the crit-weighted ranking value. Before R5 this received AI_KILL.
        hp = raw + 1
        self.assertLessEqual(hp, weighted)
        self.word("wBattleMonHP", hp)
        h.write8("wEnemyMonMoves", self.moves["TACKLE"])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)

        h.park_before_hijack()
        h.call_routine("AILayerDamage", limit=240)

        # Expected-value ranking still sees a strong hit and the best-damage
        # nudge, but the raw noncritical bound cannot earn the five-point kill.
        self.assertEqual(h.read8("wBuffer"), 17)


if __name__ == "__main__":
    unittest.main()