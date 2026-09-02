from __future__ import annotations

import json
from pathlib import Path
import unittest


CONTRACTS_PATH = Path(__file__).with_name("pending_contracts.json")
REQUIRED_FIELDS = {
    "id", "status", "scope", "observation", "decision_needed", "test_boundary"
}
ALLOWED_STATUSES = {"pending", "design_review", "blocked", "resolved"}


class PendingContractRegistryTest(unittest.TestCase):
    def test_pending_contracts_are_explicit_and_unique(self) -> None:
        contracts = json.loads(CONTRACTS_PATH.read_text(encoding="utf-8"))
        self.assertIsInstance(contracts, list)
        identifiers = []
        for contract in contracts:
            self.assertEqual(set(contract), REQUIRED_FIELDS)
            self.assertIn(contract["status"], ALLOWED_STATUSES)
            for field in REQUIRED_FIELDS:
                self.assertTrue(str(contract[field]).strip(), f"empty {field}")
            identifiers.append(contract["id"])
        self.assertEqual(len(identifiers), len(set(identifiers)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
