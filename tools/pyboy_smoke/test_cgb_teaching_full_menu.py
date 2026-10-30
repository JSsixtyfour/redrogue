"""CGB full learning-menu cancellation/retry chains."""
import unittest
from test_teaching_full_menu import run_chain


class CGBTeachingFullMenuTest(unittest.TestCase):
    def test_decline_then_retry_replacement(self):
        run_chain(self,cgb=True,cancellation='decline')

    def test_cancel_forget_then_retry_replacement(self):
        run_chain(self,cgb=True,cancellation='cancel_forget')
