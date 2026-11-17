"""ai_counterfactual (AI_T4_REGRET_PLAN Phase A5, 2026-11-17).

1. Pure arithmetic: split-seed regret and the summary table.
2. Determinism: replaying a decision AS CHOSEN with the original RNG reproduces the base battle.
3. Known answer: on a board where the AI has a guaranteed KO, the KO is the best alternative and
   the overridden move really is played (its outcome differs). This fails if overrides do nothing.
"""
from pathlib import Path
import statistics
import unittest

import ai_counterfactual as cf
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class RegretArithmeticTest(unittest.TestCase):
    def test_chosen_best_has_zero_regret(self):
        values = {"a": [1.0, 1.0, 1.0, 1.0], "b": [0.5, 0.4, 0.6, 0.5]}
        r = cf.split_regret(values, "a")
        self.assertEqual(r["best"], "a")
        self.assertEqual(r["regret"], 0.0)
        self.assertEqual(r["held_out"], 2)

    def test_best_is_selected_on_first_half_and_measured_on_second(self):
        # On seeds 0-1 "b" looks best; on the held-out seeds 2-3 it is worse than "a".
        values = {"a": [0.0, 0.0, 0.5, 0.5], "b": [1.0, 1.0, 0.2, 0.4]}
        r = cf.split_regret(values, "a")
        self.assertEqual(r["best"], "b")
        self.assertAlmostEqual(r["regret"], statistics.fmean([0.2 - 0.5, 0.4 - 0.5]))
        self.assertLess(r["regret"], 0, "selection noise must not be reported as regret")

    def test_unequal_seed_counts_are_rejected(self):
        with self.assertRaises(ValueError):
            cf.split_regret({"a": [1, 2], "b": [1]}, "a")

    def test_ties_keep_the_chosen_alternative(self):
        values = {"a": [0.5, 0.5, 0.5, 0.5], "b": [0.5, 0.5, 0.9, 0.9]}
        self.assertEqual(cf.split_regret(values, "a")["best"], "a")

    def test_summary_groups_and_shares(self):
        rows = cf.summarize([
            {"chosen_kind": "attack", "best_kind": "switch", "regret": 0.3},
            {"chosen_kind": "attack", "best_kind": "switch", "regret": 0.1},
            {"chosen_kind": "status", "best_kind": "attack", "regret": 0.1},
        ])
        self.assertEqual((rows[0]["chosen_kind"], rows[0]["best_kind"], rows[0]["count"]),
                         ("attack", "switch", 2))
        self.assertAlmostEqual(rows[0]["mean_regret"], 0.2)
        self.assertAlmostEqual(sum(r["share"] for r in rows), 1.0)

    def test_parse_seeds(self):
        self.assertEqual(cf.parse_seeds("17"), [17])
        self.assertEqual(cf.parse_seeds("100:103,7"), [100, 101, 102, 7])

    def test_seed_bytes_are_stable_and_distinct(self):
        self.assertEqual(len(cf.seed_bytes("17:3:best_power:0", 0)), 12)
        self.assertEqual(cf.seed_bytes("x", 1), cf.seed_bytes("x", 1))
        self.assertNotEqual(cf.seed_bytes("x", 1), cf.seed_bytes("x", 2))


class ReplayTest(unittest.TestCase):
    def test_as_chosen_with_original_rng_reproduces_the_base_battle(self):
        rp = cf.Replayer(seed=17, tier=3, policy="best_power")
        try:
            states, decisions, base = cf.record_battle(rp)
            self.assertGreater(len(decisions), 2)
            self.assertEqual(base["dropped_turn_states"], 0)
            for d in (decisions[0], decisions[len(decisions) // 2]):
                out = cf.play_branch(rp, states[d.state_index], d, d.chosen, None, "determinism")
                self.assertNotIn("invalid", out, out)
                for key in ("V", "player_lost", "enemy_lost", "ai_won"):
                    self.assertEqual(out[key], base[key], f"decision {d.index} {key}")
            self.assertEqual(rp.h.hook_errors, [])
        finally:
            rp.close()

    def test_guaranteed_ko_is_best_and_overrides_take_effect(self):
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

        def mon(name, names, level):
            return dict(species=species[name], level=level, moves=[moves[n] for n in names])

        def prepare(h):
            h.inject_fight2_spec([mon("PIDGEY", ["TACKLE"], 12)],
                                 [mon("MACHAMP", ["SPLASH", "KARATE_CHOP"], 60)],
                                 trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)

        rp = cf.Replayer(seed=1, tier=3, policy="best_power")
        try:
            states, decisions, base = cf.record_battle(rp, prepare=prepare)
            turn = [d for d in decisions if d.kind == "turn"]
            self.assertTrue(turn, "the KO turn is a recorded decision")
            d = turn[0]
            self.assertEqual(d.chosen, "move:1", "T3 takes the guaranteed KO")
            self.assertIn("move:0", d.alternatives)
            values = {}
            for alt in ("move:0", "move:1"):
                outs = [cf.play_branch(rp, states[d.state_index], d, alt, k, "known-answer")
                        for k in range(4)]
                for out in outs:
                    self.assertNotIn("invalid", out, out)
                values[alt] = [out["V"] for out in outs]
            for k in range(4):
                self.assertGreater(values["move:1"][k], values["move:0"][k],
                                   f"seed {k}: Splash must lose to the KO, {values}")
            r = cf.split_regret(values, d.chosen)
            self.assertEqual(r["best"], "move:1")
            self.assertEqual(r["regret"], 0.0)
            self.assertEqual(rp.h.hook_errors, [])
        finally:
            rp.close()


class SendOutReplayTest(unittest.TestCase):
    def test_send_out_decisions_replay_and_override(self):
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

        def mon(name, names, level):
            return dict(species=species[name], level=level, moves=[moves[n] for n in names])

        def prepare(h):
            # The player KOs every enemy mon, so each faint is a live send-out choice.
            h.inject_fight2_spec(
                [mon("MEWTWO", ["PSYCHIC_M", "ICE_BEAM", "THUNDERBOLT", "FLAMETHROWER"], 70)],
                [mon("RATTATA", ["TACKLE"], 30), mon("SANDSHREW", ["SCRATCH"], 30),
                 mon("ODDISH", ["ABSORB"], 30), mon("EKANS", ["BITE"], 30)],
                trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)

        rp = cf.Replayer(seed=1, tier=3, policy="best_power")
        try:
            states, decisions, base = cf.record_battle(rp, prepare=prepare)
            sends = [d for d in decisions if d.kind == "send_out"]
            self.assertTrue(sends, f"faint replacements recorded: {[d.kind for d in decisions]}")
            d = sends[0]
            self.assertGreaterEqual(len(d.alternatives), 2)
            same = cf.play_branch(rp, states[d.state_index], d, d.chosen, None, "send-determinism")
            self.assertNotIn("invalid", same, same)
            for key in ("V", "player_lost", "enemy_lost", "ai_won"):
                self.assertEqual(same[key], base[key], key)
            other = next(a for a in d.alternatives if a != d.chosen)
            sent = []
            rp.h.register_hook("AISelectSendOut.commit", lambda _c: sent.append(
                rp.h.pyboy.register_file.A))
            out = cf.play_branch(rp, states[d.state_index], d, other, None, "send-override")
            self.assertNotIn("invalid", out, out)
            # The hook above runs after the replayer's own commit hook: the overridden slot.
            self.assertIn(int(other[5:]), sent, f"override {other} not sent: {sent}")
            self.assertEqual(rp.h.hook_errors, [])
        finally:
            rp.close()


if __name__ == "__main__":
    unittest.main()
