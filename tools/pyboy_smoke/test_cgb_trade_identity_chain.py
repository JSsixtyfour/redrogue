"""CGB counterpart of the shared real-trade identity/persistence chain."""
import unittest
from test_trade_identity_chain import run_chain


class CGBTradeIdentityChainTest(unittest.TestCase):
    def test_form_trade_compaction_then_cold_continue(self):
        run_chain(self,cgb=True)
