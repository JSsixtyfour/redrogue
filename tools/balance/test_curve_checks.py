"""Curve checks: the two curve rules, the rarity snapshot drift and the slow-growth payoff.

Run from tools/balance: python -m unittest test_curve_checks
"""

import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

import curve
import parse


class RuleViolationsTest(unittest.TestCase):
    def test_holds_when_leader_tops_trainers_and_boss_tops_leader(self):
        gaps = {5: {"Route boss": 1.0, "Stage ev.": 2.5, "Gym final": 0.4, "Leader": 2.6, "Wild boss": 3.7}}
        self.assertEqual(curve.rule_violations(gaps), [])

    def test_trainer_at_or_above_leader_is_flagged(self):
        gaps = {5: {"Stage ev.": 2.9, "Gym final": 2.6, "Leader": 2.6, "Wild boss": 3.7}}
        bad = curve.rule_violations(gaps)
        self.assertEqual(len(bad), 2, bad)
        self.assertTrue(any("Stage ev." in b for b in bad))
        self.assertTrue(any("Gym final" in b for b in bad))   # a tie breaks the rule too

    def test_wild_boss_not_above_leader_is_flagged(self):
        bad = curve.rule_violations({8: {"Leader": 3.5, "Wild boss": 2.1}})
        self.assertEqual(len(bad), 1)
        self.assertIn("wild boss", bad[0])

    def test_wild_columns_and_finale_are_not_trainers(self):
        gaps = {3: {"Wild": 9.0, "Leader": 3.0}, 9: {"Route": 5.0, "E4": 2.0, "Champion": 3.0}}
        self.assertEqual(curve.rule_violations(gaps), [])


class RaritySnapshotTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.game = parse.load_all()

    def test_round_trip_matches_and_a_changed_block_is_named(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "snap.csv"
            curve.write_rarity_snapshot(self.game.tables, "test", path)
            snap = curve.load_rarity_snapshot(path)
        self.assertEqual(curve.rarity_drift(self.game.tables, snap), [])
        gym = list(self.game.tables.gym)
        old = gym[3].counts
        new = (old[0] - 1, old[1], old[2] + 1, old[3]) if old[0] else (old[0], old[1] - 1, old[2] + 1, old[3])
        gym[3] = replace(gym[3], counts=new)
        drift = curve.rarity_drift(replace(self.game.tables, gym=gym), snap)
        self.assertEqual([(k, o, n) for k, o, n in drift], [(("gym", 4, "regular"), old, new)])
        lines = curve.fmt_rarity_drift(drift)
        self.assertIn("rounds 4", lines[0])

    def test_skipped_route_is_marked_inert(self):
        key = ("route", 4, "regular")
        lines = curve.fmt_rarity_drift([(key, (1, 2, 1, 0), (2, 2, 0, 0))], skip_rounds=(4, 7))
        self.assertIn("no effect on the model", "\n".join(lines))

    def test_missing_file_is_empty(self):
        self.assertEqual(curve.load_rarity_snapshot(Path(tempfile.gettempdir()) / "no_such_snapshot.csv"), {})

    def test_mean_class(self):
        self.assertEqual(curve.mean_class((3, 1, 0, 0)), 0.25)
        self.assertEqual(curve.mean_class((0, 0, 0, 0)), 0.0)


class SlowPayoffTest(unittest.TestCase):
    def test_levels_come_from_the_source(self):
        g = parse.load_all()
        levels = curve.payoff_levels(g)
        self.assertEqual(sorted(sp for sps in levels.values() for sp in sps), sorted(curve.PAYOFF_SPECIES))
        for lv in levels:
            self.assertTrue(30 <= lv <= 70, lv)

    def test_payoff_follows_an_edited_evolution_level(self):
        g = parse.load_all()
        sp = dict(g.species)
        sp["DRAGONAIR"] = replace(sp["DRAGONAIR"], evos=[(parse.EVOLVE_LEVEL, 40, "DRAGONITE")])
        self.assertIn(40, curve.payoff_levels(replace(g, species=sp)))


class LedgerDriftTest(unittest.TestCase):
    def rows(self):
        base = {f"team_gym{r}": "10.0" for r in range(1, 9)}
        base.update({f"class_{t}_r{i}": "1.0" for t in ("route", "gym") for i in range(1, 10)})
        base.update(leader_aces="1 2", wild_levels="3", wild_boss_levels="4")
        return base, dict(base)

    def test_small_move_is_silent(self):
        import report
        a, b = self.rows()
        b["team_gym3"] = "10.2"
        self.assertEqual(report.ledger_drift(a, b), [])

    def test_names_the_mix(self):
        import report
        a, b = self.rows()
        b["team_gym3"] = "9.5"
        b["class_gym_r2"] = "0.5"
        out = report.ledger_drift(a, b)
        self.assertEqual(len(out), 1)
        self.assertIn("class mix", out[0])
        self.assertIn("class_gym_r2", out[0])

    def test_names_levels_then_neither_then_unknown(self):
        import report
        a, b = self.rows()
        b["team_gym3"] = "9.5"
        b["wild_levels"] = "9"
        self.assertIn("level tables", report.ledger_drift(a, b)[0])
        a, b = self.rows()
        b["team_gym3"] = "9.5"
        self.assertIn("neither", report.ledger_drift(a, b)[0])
        a.pop("class_gym_r1")
        self.assertIn("unknown", report.ledger_drift(a, b)[0])


if __name__ == "__main__":
    unittest.main()
