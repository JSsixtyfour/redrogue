"""CGB counterpart of the shared credit service/persistence chain."""
import unittest
import test_credit_service_chain as chain


class CGBCreditServiceChainTest(unittest.TestCase):
    def test_purchase_cold_continue_then_upgrade_refusal(self):
        chain.run_chain(self,cgb=True)

    def test_room_purchase_reset_inside_vendor_saves_debit_and_progress(self):
        chain.CreditServiceChainTest.test_room_purchase_reset_inside_vendor_saves_debit_and_progress(self, cgb=True)
