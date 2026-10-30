"""CGB counterpart of the shared teaching/refusal/persistence chain."""
import unittest
from test_teaching_identity_chain import run_chain


class CGBTeachingIdentityChainTest(unittest.TestCase):
    def test_teach_refuse_duplicate_then_cold_continue(self):
        run_chain(self,cgb=True)
