"""The heal errand must find its item in the bag list the game draws.

bag_sort.asm shows the Recovery pocket in BagRecoveryTypeOrder (or ALPHA), not
RecoveryItemTable order. Assuming the table order selected FULL HEAL instead of
REVIVE on a fainted mon, which never took effect and looped until the stall
check fired (seeds 1-8, 2026-11-11).
"""
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

from autoplay import AutoplayAgent

POTION, FULL_RESTORE, FULL_HEAL, REVIVE = 0x14, 0x10, 0x34, 0x35
LIST = 0xC000
# TYPE order for this bag: POTION, FULL RESTORE, REVIVE, FULL HEAL, CANCEL.
SHOWN = [POTION, FULL_RESTORE, REVIVE, FULL_HEAL]


class HealBagOrderTest(unittest.TestCase):
    def agent(self, cursor, scroll, shown=SHOWN):
        memory = {LIST: len(shown)}
        for row, item in enumerate(shown + [0xFF]):
            memory[LIST + 1 + 2 * row] = item
            memory[LIST + 2 + 2 * row] = 1
        registers = {"hCurrentMenuItem": cursor, "wListScrollOffset": scroll, "wBagPocketsFlags": 0}
        agent = AutoplayAgent.__new__(AutoplayAgent)
        agent.mem = memory
        agent.word = lambda name: LIST
        agent.h = SimpleNamespace(read8=registers.__getitem__)
        agent.last_menu_caller = "DisplayListMenuIDLoop.readInput+$3"
        agent.recovery_counts = lambda: {POTION: 2, FULL_RESTORE: 91, FULL_HEAL: 99, REVIVE: 1}
        agent.event = Mock()
        agent.press = Mock()
        agent.plan = {"kind": "heal", "item": REVIVE, "slot": 3, "count": 1, "steps": 0, "done": False}
        return agent

    def test_row_comes_from_the_displayed_list(self):
        self.assertEqual(self.agent(0, 0).bag_list_index(REVIVE), 2)
        self.assertEqual(self.agent(0, 0).bag_list_index(FULL_HEAL), 3)

    def test_selects_revive_at_its_displayed_row(self):
        agent = self.agent(cursor=1, scroll=1)  # row 2 = REVIVE
        agent.heal_step()
        agent.press.assert_called_once_with("a")

    def test_does_not_select_full_heal_in_revives_table_slot(self):
        agent = self.agent(cursor=2, scroll=1)  # row 3 = FULL HEAL, REVIVE's table slot
        agent.heal_step()
        agent.press.assert_called_once_with("up")

    def test_alpha_order_is_followed_too(self):
        alpha = [FULL_HEAL, FULL_RESTORE, POTION, REVIVE]
        agent = self.agent(cursor=2, scroll=0, shown=alpha)
        agent.heal_step()
        agent.press.assert_called_once_with("down")

    def test_item_missing_from_list_backs_out(self):
        agent = self.agent(cursor=0, scroll=0, shown=[POTION, FULL_HEAL])
        agent.heal_step()
        agent.press.assert_called_once_with("b")
        self.assertTrue(agent.plan["done"])
        self.assertEqual(agent.event.call_args.args[0], "heal_abandoned")


if __name__ == "__main__":
    unittest.main()
