"""Independent transaction detector sensitivity, including silent wrong charges."""
import copy
import unittest

from purchase_scenario import contract
from run_campaign import classify


class PurchaseContractTest(unittest.TestCase):
    def test_expected_purchase_and_cancel(self):
        before = {"money": 200, "items": [0, 5], "party": [1, 2, 3]}
        after = {"money": 0, "items": [1, 5], "party": [1, 2, 3]}
        self.assertEqual(contract(before, after, bought=True, potion_slot=0, paid_calls=1, give_calls=1), [])
        self.assertEqual(contract(before, before, bought=False, potion_slot=0, paid_calls=0, give_calls=0), [])

    def test_silent_overcharge_and_unrelated_item_loss_are_detected(self):
        before = {"money": 1000, "items": [0, 5], "party": [1, 2, 3]}
        after = {"money": 799, "items": [1, 4], "party": [1, 2, 3]}
        findings = contract(before, after, bought=True, potion_slot=0, paid_calls=1, give_calls=1)
        self.assertEqual([f["field"] for f in findings], ["money", "items"])
        self.assertEqual(findings, contract(before, copy.deepcopy(after), bought=True, potion_slot=0, paid_calls=1, give_calls=1))
        self.assertEqual(classify(0, {"runs": [{"outcome": "completed", "contract_findings": findings}]}, "completed"), "contract_violation")

    def test_cancel_cannot_change_party_or_attempt_payment(self):
        before = {"money": 1000, "items": [0], "party": [1]}
        after = {**before, "party": [2]}
        findings = contract(before, after, bought=False, potion_slot=0, paid_calls=1, give_calls=0)
        self.assertEqual([f["field"] for f in findings], ["party", "paid_calls"])

    def test_unreached_or_unknown_outcome_cannot_pass(self):
        for outcome in ("unreached", "unknown", None):
            self.assertEqual(classify(0, {"runs": [{"outcome": outcome}]}, "completed"), "incomplete")
