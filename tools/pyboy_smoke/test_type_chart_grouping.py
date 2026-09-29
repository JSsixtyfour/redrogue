"""The type chart is grouped by attacking type (2026-09-29, AI review option 2).

TypeMatchupScan now skips whole groups, so two things must hold: every
attacker has exactly ONE group (the scan stops at the first match), and the
walk itself returns the engine's real dual-type multiplier. Regrouping was
proven equivalent to the old flat Gen 1 order on all 4096 attacker/defender
triples when it landed; these tests guard the grouped form from here on.
"""
from pathlib import Path
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
CHART = ROOT / "data/types/type_matchups.asm"


class TypeChartStructureTest(unittest.TestCase):
    def test_each_attacker_has_exactly_one_group(self):
        attackers = re.findall(r"^\s*type_group\s+(\w+)", CHART.read_text(), re.M)
        self.assertEqual(len(attackers), len(set(attackers)), attackers)
        self.assertGreater(len(attackers), 10)

    def test_every_group_is_closed_by_its_own_end_label(self):
        text = CHART.read_text()
        for attacker in re.findall(r"^\s*type_group\s+(\w+)", text, re.M):
            self.assertRegex(text, rf"(?m)^\.end_{attacker}\s*$")


class TypeChartRuntimeTest(unittest.TestCase):
    # (attacking type, defender type 1, defender type 2, expected tenths)
    CASES = [
        ("GROUND", "FIRE", "FLYING", 0),         # Earthquake vs Charizard: immune
        ("ICE", "DRAGON", "FLYING", 40),         # Ice vs Dragonite: x4
        ("ELECTRIC", "WATER", "FLYING", 40),     # Electric vs Gyarados: x4
        ("GRASS", "GRASS", "POISON", 2),         # Grass vs Venusaur: x1/4 (5/20 -> 2/10)
        ("NORMAL", "ROCK", "GROUND", 5),         # Normal vs Geodude: x1/2
        ("GROUND", "GRASS", "POISON", 10),       # x1/2 and x2 cancel to neutral
        ("GHOST", "PSYCHIC_TYPE", "PSYCHIC_TYPE", 20),  # the ShinRed Ghost fix
        ("BIRD", "NORMAL", "NORMAL", 10),        # attacker with no group: neutral
    ]

    def test_grouped_walk_matches_the_real_multipliers(self):
        types = parse_rgbds_constants(ROOT / "constants/type_constants.asm")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        from source_constants import parse_trainer_constants
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            mon = {"species": species["SNORLAX"], "level": 50, "moves": [moves["TACKLE"]]}
            h.inject_fight2_spec([mon], [mon], trainer_class=trainers["COOLTRAINER_M"],
                                 ai_tier=0)
            h.boot_fight2(seed=1)
            saved = [h.read8("wEnemyMoveType"), *h.read_bytes("wBattleMonType", 2)]
            for attacker, def1, def2, expected in self.CASES:
                with self.subTest(attacker=attacker, defender=(def1, def2)):
                    h.park_before_hijack()
                    h.write8("wEnemyMoveType", types[attacker])
                    h.write8("wBattleMonType", types[def1])
                    h.write8("wBattleMonType", types[def2], offset=1)
                    h.call_routine("AIGetTypeEffectiveness", limit=120)
                    self.assertEqual(h.read8("wTypeEffectiveness"), expected)
            h.write8("wEnemyMoveType", saved[0])
            h.write8("wBattleMonType", saved[1])
            h.write8("wBattleMonType", saved[2], offset=1)
        finally:
            h.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
