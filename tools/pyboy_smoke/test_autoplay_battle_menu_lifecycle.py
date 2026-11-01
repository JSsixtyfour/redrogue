"""Accepted battle choices must not turn later narration into redraw findings."""
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from autoplay import AutoplayAgent


class BattleMenuLifecycleTest(unittest.TestCase):
    def agent(self, kind="battle_menu"):
        agent = AutoplayAgent.__new__(AutoplayAgent)
        agent.menu_goal = SimpleNamespace(kind=kind, waiting=lambda: True,
                                         created=1, next_button=lambda: None,
                                         target=0, button="a", presses=0)
        agent.menu_stats = {}
        agent.menu_frame = 2
        agent.text_wait_frame = 3
        agent.menu_chaos = 0
        agent.h = SimpleNamespace(read8=lambda _: 0)
        agent.checks = SimpleNamespace(anomaly=Mock())
        agent.press = Mock()
        return agent

    def test_game_acceptance_retires_pending_battle_goal(self):
        agent = self.agent()
        agent._on_battle_menu_selection(None)
        self.assertIsNone(agent.menu_goal)

    def test_acceptance_without_pending_goal_is_safe(self):
        agent = self.agent()
        agent.menu_goal = None
        agent._on_battle_menu_selection(None)
        self.assertIsNone(agent.menu_goal)

    def test_other_menu_goal_is_preserved(self):
        agent = self.agent("move_menu")
        goal = agent.menu_goal
        agent._on_battle_menu_selection(None)
        self.assertIs(agent.menu_goal, goal)

    def test_narration_after_acceptance_is_not_a_redraw(self):
        agent = self.agent()
        agent._on_battle_menu_selection(None)
        self.assertFalse(agent.menu_goal_step())
        agent.checks.anomaly.assert_not_called()
        agent.press.assert_not_called()

    def test_genuine_redraw_wait_before_acceptance_still_reports(self):
        agent = self.agent()
        self.assertTrue(agent.menu_goal_step())
        self.assertEqual(agent.checks.anomaly.call_args.args[0], "menu_text_wait")
        agent.press.assert_called_once_with("a")

    def test_next_menu_choice_still_works(self):
        agent = self.agent()
        agent.text_wait_frame = -1
        self.assertTrue(agent.menu_goal_step())
        self.assertIsNone(agent.menu_goal)
        agent.checks.anomaly.assert_not_called()
        agent.press.assert_called_once_with("a")
