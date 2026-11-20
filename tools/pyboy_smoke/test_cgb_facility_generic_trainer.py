"""test_facility_generic_trainer on CGB (the smoke runner classifies modules by name)."""

from __future__ import annotations

import unittest

import test_facility_generic_trainer as generic


class CGBFacilityGenericTrainerTest(generic.FacilityGenericTrainerTest):
    CGB = True
    test_keep_table_holds_him = None


if __name__ == "__main__":
    unittest.main()
