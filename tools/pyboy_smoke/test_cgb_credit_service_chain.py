"""CGB counterpart of the shared credit service/persistence chain."""
import unittest
from test_credit_service_chain import run_chain


class CGBCreditServiceChainTest(unittest.TestCase):
    def test_purchase_cold_continue_then_upgrade_refusal(self):
        run_chain(self,cgb=True)
