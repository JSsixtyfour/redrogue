import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "check_facility_premades", ROOT / "tools" / "check_facility_premades.py"
)
assert SPEC and SPEC.loader
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class FacilityPremadeContractTest(unittest.TestCase):
    def test_fixture_descriptor_contract(self) -> None:
        self.assertEqual(validator.validate(), [])

    def test_selection_and_generic_fallback(self) -> None:
        for required in range(16):
            for room_id in range(1, 11):
                self.assertTrue(validator.select_fixture(room_id, 1, 1, required))
        self.assertFalse(validator.select_fixture(0, 1, 1, 1))
        self.assertFalse(validator.select_fixture(11, 1, 1, 1))
        self.assertFalse(validator.select_fixture(1, 2, 1, 1))
        self.assertFalse(validator.select_fixture(5, 1, 2, 1))
        self.assertFalse(
            validator.select_fixture(5, 1, 1, 1, corners_clear=False)
        )


if __name__ == "__main__":
    unittest.main()
