"""The autoplay agent's real menu input: it moves the move menu's cursor with
presses (not by writing the cursor byte) and the move it meant is the one
that runs, stray presses or not."""
import unittest

import autoplay
from test_smoke import HarnessTestCase


class RealMenuInputTest(HarnessTestCase):
    def play_first_turn(self, **options) -> tuple[autoplay.AutoplayAgent, list[int], list[int]]:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        agent = autoplay.AutoplayAgent(h, seed=1, **options)
        wanted, used = [], []
        set_goal = agent.set_menu_goal

        def record(kind, callers, target, *args, **kwargs):
            if kind == "move_menu":
                wanted.append(h.read8("wBattleMonMoves", target))
            set_goal(kind, callers, target, *args, **kwargs)

        agent.set_menu_goal = record
        h.register_hook("ExecutePlayerMove", lambda _c: used.append(h.read8("wPlayerSelectedMove")))
        for _ in range(3000):
            if used:
                break
            agent.step()
        return agent, wanted, used

    def test_the_move_chosen_with_presses_is_the_one_used(self) -> None:
        agent, wanted, used = self.play_first_turn()
        self.assertTrue(used, "no move ran")
        self.assertEqual(used[0], wanted[-1])
        # boot_fight2 stops with the battle menu already up, past its hook:
        # the first turn's menu with a goal is the move menu.
        self.assertGreaterEqual(agent.menu_stats["move_menu"]["choices"], 1)
        self.assertEqual(agent.checks.anomalies, [])

    def test_stray_presses_still_end_on_the_chosen_move(self) -> None:
        agent, wanted, used = self.play_first_turn(menu_chaos=0.5)
        self.assertTrue(used, "no move ran")
        self.assertEqual(used[0], wanted[-1])
        self.assertGreater(sum(stats["stray"] for stats in agent.menu_stats.values()), 0)


class SharedShopInputTest(HarnessTestCase):
    def test_default_shop_policy_still_buys_its_healing_stock_with_real_input(self):
        # Reuse the same documented stock/funds fixture as directed contracts.
        # The ordinary driver must choose its quantity itself and stop shopping.
        from purchase_scenario import configure, Observation, snapshot

        h = self.harness
        slot, _injections, agent = configure(h, 1, "success")
        # Debug 2 supplies other healing items. Empty those explicitly so the
        # ordinary stocking policy has a reason to buy the offered Potion.
        for item in agent.heal_amounts:
            h.write8("wRecoveryItemCounts", 0, agent.recovery_table.index(item))
        before = snapshot(h)
        self.assertEqual(sum(agent.recovery_counts().get(item, 0) for item in agent.heal_amounts), 0)
        obs = Observation(h)
        agent.plan = {"kind": "shop", "steps": 0, "done": False}
        start = h.pyboy.frame_count
        agent.press("a")
        while h.pyboy.frame_count - start < 8000:
            if obs.closed and obs.overworld_frame > start and h.pyboy.frame_count - obs.overworld_frame <= 2:
                break
            if h.pyboy.frame_count - agent.last_wait_frame <= 2:
                agent.shop_step()  # unchanged ordinary policy, no scenario overrides
            else:
                h.tick(1)
        self.assertTrue(obs.closed and obs.overworld_frame > start, obs.events)
        after = snapshot(h)
        expected = list(before["items"])
        expected[slot] = 4
        self.assertEqual(after["items"], expected)
        self.assertEqual(after["money"], before["money"] - 800)
        self.assertEqual(after["party"], before["party"])
        self.assertEqual((obs.paid, obs.given), (1, 1))


if __name__ == "__main__":
    unittest.main(verbosity=2)
