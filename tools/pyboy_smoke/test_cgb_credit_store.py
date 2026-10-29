"""CGB real-input Credit Store transaction and return-control boundaries."""
import unittest
import test_credit_store


class CGBCreditStoreLiveTest(unittest.TestCase):
    def test_live_exact_funds(self):
        test_credit_store.CreditStoreLiveTest.live(self, "exact", cgb=True)

    def test_live_decline(self):
        test_credit_store.CreditStoreLiveTest.live(self, "decline", cgb=True)

    def test_live_insufficient(self):
        test_credit_store.CreditStoreLiveTest.live(self, "insufficient", cgb=True)

    def test_live_full_active_sends_owned_item_to_pc(self):
        test_credit_store.CreditStoreLiveTest.live(self, "full_active", cgb=True)

    def test_live_upgrade_exact_funds(self):
        test_credit_store.CreditStoreLiveTest.live(self, "upgrade_exact", cgb=True)

    def test_live_upgrade_final_tier_empties_shelf(self):
        test_credit_store.CreditStoreLiveTest.live(self, "upgrade_final", cgb=True)

    def test_live_upgrade_decline(self):
        test_credit_store.CreditStoreLiveTest.live(self, "upgrade_decline", cgb=True)

    def test_live_upgrade_insufficient(self):
        test_credit_store.CreditStoreLiveTest.live(self, "upgrade_insufficient", cgb=True)

    def test_live_upgrade_pc_owned_item_stays_inactive(self):
        test_credit_store.CreditStoreLiveTest.live(self, "upgrade_pc", cgb=True)

    def test_live_upgrade_max_tier_has_no_stock(self):
        test_credit_store.CreditStoreLiveTest.live(self, "upgrade_max", cgb=True)
