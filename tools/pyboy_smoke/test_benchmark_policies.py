"""Pure unit tests for the benchmark's player policies (AI_BACKLOG L3).

No ROM: synthetic battle states against rules parsed from the real source
(moves.asm, type_matchups.asm, the constant files).
"""
from pathlib import Path
import unittest

import benchmark_policies as bp

ROOT = Path(__file__).resolve().parents[2]


class BenchmarkPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules = bp.load_rules(ROOT)
        cls.t = cls.rules.types
        cls.m = cls.rules.move_ids

    def mon(self, types, moves, hp=150, max_hp=150, level=50, stats=(100, 100, 100, 100),
            status=0, **kw):
        types = tuple(self.t[x] for x in types)
        if len(types) == 1:
            types = types * 2
        ids = tuple(self.m[x] for x in moves) + (0,) * (4 - len(moves))
        return bp.Mon(types=types, level=level, hp=hp, max_hp=max_hp,
                      attack=stats[0], defense=stats[1], speed=stats[2], special=stats[3],
                      status=status, moves=ids, pp=tuple(10 if i else 0 for i in ids), **kw)

    def state(self, player, enemy, party=None, active=0):
        return bp.State(player, enemy, party or [player], active)

    def slot(self, player, enemy, policy):
        return bp.choose_slot(self.rules, self.state(player, enemy), policy)

    # --- rules parsed from source ------------------------------------------
    def test_rules_match_the_source_tables(self):
        tb = self.rules.moves[self.m["THUNDERBOLT"]]
        self.assertEqual((tb.power, tb.type, tb.accuracy), (95, self.t["ELECTRIC"], 100))
        self.assertEqual(self.rules.chart[(self.t["WATER"], self.t["FIRE"])], 2.0)
        self.assertEqual(self.rules.chart[(self.t["ELECTRIC"], self.t["GROUND"])], 0.0)
        self.assertEqual(self.rules.chart[(self.t["FIRE"], self.t["WATER"])], 0.5)

    def test_fixed_damage_follows_the_engine_rules(self):
        attacker = self.mon(["FIGHTING"], ["SEISMIC_TOSS"], level=43)
        target = self.mon(["GHOST"], ["TACKLE"], hp=90)
        self.assertEqual(bp.expected_damage(self.rules, self.m["SEISMIC_TOSS"], attacker, target), 43)
        self.assertEqual(bp.expected_damage(self.rules, self.m["SUPER_FANG"], attacker, target),
                         45 * self.rules.moves[self.m["SUPER_FANG"]].accuracy / 100)
        self.assertEqual(bp.expected_damage(self.rules, self.m["SONICBOOM"], attacker, target),
                         20 * self.rules.moves[self.m["SONICBOOM"]].accuracy / 100)

    # --- type_aware ---------------------------------------------------------
    def test_type_aware_prefers_super_effective_over_raw_power(self):
        player = self.mon(["WATER"], ["BODY_SLAM", "WATER_GUN"])
        enemy = self.mon(["FIRE"], ["EMBER"])
        self.assertEqual(self.slot(player, enemy, "best_power"), 0)
        self.assertEqual(self.slot(player, enemy, "type_aware"), 1)

    def test_type_aware_never_picks_an_immune_move(self):
        player = self.mon(["GROUND"], ["EARTHQUAKE", "TACKLE"])
        enemy = self.mon(["FLYING"], ["PECK"])
        self.assertEqual(self.slot(player, enemy, "type_aware"), 1)

    def test_type_aware_discounts_recharge_turns(self):
        player = self.mon(["NORMAL"], ["HYPER_BEAM", "BODY_SLAM"])
        enemy = self.mon(["WATER"], ["TACKLE"])
        self.assertEqual(self.slot(player, enemy, "type_aware"), 1)

    def test_type_aware_uses_live_stats_for_the_physical_special_split(self):
        # Gen 1: the move's TYPE decides the stat pair. A frail-Special target
        # makes the special move win even at lower power.
        player = self.mon(["NORMAL"], ["BODY_SLAM", "EMBER"], stats=(100, 100, 100, 100))
        enemy = self.mon(["NORMAL"], ["TACKLE"], stats=(100, 300, 100, 30))
        self.assertEqual(self.slot(player, enemy, "type_aware"), 1)

    def test_legal_slots_skip_moves_without_pp(self):
        player = self.mon(["WATER"], ["TACKLE", "SURF"])
        player.pp = (10, 0, 0, 0)
        enemy = self.mon(["FIRE"], ["EMBER"])
        self.assertEqual(self.slot(player, enemy, "type_aware"), 0)

    # --- status_first -------------------------------------------------------
    def test_status_first_paralyses_a_healthy_target(self):
        player = self.mon(["ELECTRIC"], ["THUNDERBOLT", "THUNDER_WAVE"])
        enemy = self.mon(["NORMAL"], ["TACKLE"])
        self.assertEqual(self.slot(player, enemy, "status_first"), 1)

    def test_status_first_respects_type_immunity_and_existing_status(self):
        player = self.mon(["ELECTRIC"], ["TACKLE", "THUNDER_WAVE"])
        ground = self.mon(["GROUND"], ["TACKLE"])
        self.assertEqual(self.slot(player, ground, "status_first"), 0)
        paralysed = self.mon(["NORMAL"], ["TACKLE"], status=1 << 6)
        self.assertEqual(self.slot(player, paralysed, "status_first"), 0)

    def test_status_first_does_not_status_through_a_substitute(self):
        player = self.mon(["GRASS"], ["VINE_WHIP", "SLEEP_POWDER"])
        enemy = self.mon(["WATER"], ["TACKLE"], substitute=True)
        self.assertEqual(self.slot(player, enemy, "status_first"), 0)

    # --- setup_first --------------------------------------------------------
    def test_setup_first_boosts_to_plus_two_then_attacks(self):
        player = self.mon(["NORMAL"], ["BODY_SLAM", "SWORDS_DANCE"])
        enemy = self.mon(["NORMAL"], ["TACKLE"])
        self.assertEqual(self.slot(player, enemy, "setup_first"), 1)
        player.stat_mods = (bp.STAT_NEUTRAL + 2,) + (bp.STAT_NEUTRAL,) * 5
        self.assertEqual(self.slot(player, enemy, "setup_first"), 0)

    def test_setup_first_attacks_when_below_half_hp(self):
        player = self.mon(["NORMAL"], ["BODY_SLAM", "SWORDS_DANCE"], hp=70)
        enemy = self.mon(["NORMAL"], ["TACKLE"])
        self.assertEqual(self.slot(player, enemy, "setup_first"), 0)

    # --- type_switcher ------------------------------------------------------
    def switch_case(self, reserve_types, reserve_hp=150, switched=False):
        active = self.mon(["FIRE"], ["EMBER"], hp=30)
        reserve = self.mon(reserve_types, ["TACKLE"], hp=reserve_hp)
        enemy = self.mon(["WATER"], ["SURF"])
        state = self.state(active, enemy, [active, reserve])
        return bp.choose_switch(self.rules, state, "type_switcher", switched)

    def test_switcher_leaves_a_doomed_mon_for_a_reserve_that_survives(self):
        self.assertEqual(self.switch_case(["GRASS"]), 1)

    def test_switcher_never_switches_into_a_ko(self):
        self.assertIsNone(self.switch_case(["FIRE"], reserve_hp=20))

    def test_switcher_never_switches_twice_in_a_row(self):
        self.assertIsNone(self.switch_case(["GRASS"], switched=True))

    def test_switcher_stays_when_not_threatened(self):
        active = self.mon(["GRASS"], ["VINE_WHIP"])
        reserve = self.mon(["GRASS"], ["TACKLE"])
        enemy = self.mon(["WATER"], ["WATER_GUN"])
        state = self.state(active, enemy, [active, reserve])
        self.assertIsNone(bp.choose_switch(self.rules, state, "type_switcher", False))

    def test_only_the_switching_policy_switches(self):
        active = self.mon(["FIRE"], ["EMBER"], hp=30)
        reserve = self.mon(["GRASS"], ["TACKLE"])
        state = self.state(active, self.mon(["WATER"], ["SURF"]), [active, reserve])
        self.assertIsNone(bp.choose_switch(self.rules, state, "type_aware", False))


class BenchmarkSwitchDriverTest(unittest.TestCase):
    """End to end: the switching policy's request drives the real battle menu
    (PKMN, then the party menu) and every counted switch is a real voluntary
    one. Seed 92 at T3 switches twice (measured 2026-09-30)."""

    def test_voluntary_switches_are_real_and_counted(self):
        import run_ai_benchmark as rb
        from harness import RedRogueHarness

        hits = {}
        original = RedRogueHarness.boot_fight2

        def boot(harness, *args, **kwargs):
            hits["flag"] = harness.hook_flag("PartyMenuOrRockOrRun.switchMon")
            return original(harness, *args, **kwargs)

        RedRogueHarness.boot_fight2 = boot
        try:
            report = rb.run_tier(ROOT, ROOT / "tools/pyboy_smoke/artifacts", seed=92,
                                 trials_count=1, max_steps=5000, tier=3,
                                 player_policy="type_switcher",
                                 move_powers=rb.parse_move_powers(ROOT / "data/moves/moves.asm"))
        finally:
            RedRogueHarness.boot_fight2 = original
        trial = report["trial_results"][0]
        self.assertGreaterEqual(trial["player_switches"], 1)
        self.assertEqual(trial["player_switches"], hits["flag"]["count"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
