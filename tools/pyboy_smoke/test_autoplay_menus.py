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


if __name__ == "__main__":
    unittest.main(verbosity=2)
