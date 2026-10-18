"""The offline wild encounter cap follows the source budget curve."""

import unittest
from unittest.mock import Mock, patch

import model
import parse


class WildBudgetModelTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.game = parse.load_all()

    def test_round_start_curve_and_all_counts_limit_encounters(self):
        knobs = self.game.knobs
        self.assertEqual((knobs["WILD_BUDGET_BASE"], knobs["WILD_BUDGET_MAX"],
                          knobs["WILD_BUDGET_DIVISOR"]), (8, 18, 4))
        cfg = model.Config(wild_steps=255, wild_path="beeline")
        sim = model.Simulator(self.game, cfg, 1)
        sim.fight = Mock()
        # Make every encounter roll succeed so sampling variance cannot hide
        # a missing or wrong cap. Boss fights are counted separately.
        sim.rng.randrange = Mock(return_value=0)
        observed = {}
        with patch.object(model, "wild_battle", return_value="wild") as wild, \
                patch.object(model, "wild_boss_battle", return_value="boss") as boss:
            for area in parse.WILD_AREA_TYPES:
                for count in range(256):
                    with self.subTest(area=area, battle_count=count):
                        sim.count = count
                        sim.fight.reset_mock()
                        wild.reset_mock()
                        boss.reset_mock()
                        sim.wild_area(False, area)
                        expected = min(18, 8 + count // 4)
                        self.assertEqual(wild.call_count, expected)
                        self.assertEqual(boss.call_count, 1)
                        self.assertEqual(sim.fight.call_count, expected + 1)
                        observed[count] = wild.call_count
        self.assertEqual([observed[r * knobs["ROUND_BATTLES"]] for r in range(8)],
                         [8, 10, 12, 14, 16, 18, 18, 18])


if __name__ == "__main__":
    unittest.main()
