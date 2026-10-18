"""The optional witch EXP trajectory preserves encounters and baseline rules."""
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import model
import parse
import report


class WitchExpScenarioTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.g = parse.load_all()

    def test_integer_rounding_and_order(self):
        # 95 * 1 / 7 = 13; trainer bonus = 19; witch adds floor(19/10).
        self.assertEqual(model.exp_for_ko(self.g, 95, 1, True, witch_boost=True), 20)
        self.assertEqual(model.exp_for_ko(self.g, 95, 1, True), 19)
        self.assertEqual(model.exp_for_ko(self.g, 95, 1, True, False, True), 14)
        self.assertEqual(model.exp_for_ko(self.g, 255, 255, True, witch_boost=True), 15326)
        self.assertEqual(model.exp_for_ko(self.g, 65535, 7, True, witch_boost=True), 65535)

    def test_acquisition_threshold_applies_to_every_recipient(self):
        for exp_all in (None, "equal"):
            cfg = model.Config(exp_all=exp_all, witch_exp_start_count=17)
            sim = model.Simulator(self.g, cfg, 321)
            sim.members = [model.Member(10, 0), model.Member(10, 0)]
            base = self.g.species["PIDGEY"].base_exp
            if exp_all:
                base = model.exp_share_split(exp_all, base, 2)[0]
            normal = model.exp_for_ko(self.g, base, 20, True)
            boosted = model.exp_for_ko(self.g, base, 20, True, witch_boost=True)
            for count, expected in ((16, normal), (17, boosted), (17, boosted), (18, boosted)):
                before = [m.exp_gained for m in sim.members]
                sim.fight(model.Battle("route", count, [("PIDGEY", 20)], True))
                self.assertEqual(sim.members[0].exp_gained - before[0], expected)
                self.assertEqual(sim.members[1].exp_gained - before[1], expected if exp_all else 0)

    def test_paired_runs_have_identical_encounters_and_money(self):
        cfg = model.Config()
        for seed in range(3):
            baseline = model.Simulator(self.g, cfg, seed).simulate()
            alternative = model.Simulator(self.g, replace(cfg, witch_exp_start_count=17), seed).simulate()
            self.assertEqual(baseline.battles, alternative.battles)
            self.assertEqual(baseline.total_money, alternative.total_money)
            for a, b in zip(baseline.checkpoints, alternative.checkpoints):
                self.assertGreaterEqual(b.ace_exp, a.ace_exp)
                if baseline.battles[a.battle_index - 1].count < 17:
                    self.assertEqual(b.ace_exp, a.ace_exp)
            self.assertGreater(alternative.checkpoints[-1].ace_exp, baseline.checkpoints[-1].ace_exp)

    def test_report_keeps_baseline_and_labels_timing(self):
        args = SimpleNamespace(witch_exp_start_count=None, runs=1, seed=5)
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory)
            self.assertEqual(report.section_witch_exp(self.g, args, out), [])
            args.witch_exp_start_count = 17
            text = "\n".join(report.section_witch_exp(self.g, args, out))
            self.assertIn("wBattleCount >= 17", text)
            self.assertIn("round 3, battle-count step 1, after 2 badges", text)
            self.assertIn("no-prize baseline", text)
            self.assertTrue((out / "witch_exp.csv").is_file())


if __name__ == "__main__":
    unittest.main()
