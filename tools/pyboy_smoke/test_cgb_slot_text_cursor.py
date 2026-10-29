"""CGB regression for the intentional slot text output-cursor contract."""
import unittest
import test_slot_text_cursor


class CGBSlotTextCursorTest(unittest.TestCase):
    def test_all_winning_symbols_advance_cursor_and_keep_text_continuation(self):
        test_slot_text_cursor.SlotTextCursorTest.exercise(self, cgb=True)
