"""The Facility's deep floor on CGB: the first descent generates floor 2 at
double speed (its own copy of the speed bracket, facility_deep_floor.asm). The
smoke runner classifies modules by hardware, so the CGB case lives in its own
module."""

import unittest

import test_facility_deep_floor as deep
from harness import RedRogueHarness


class CGBFacilityDeepFloorTest(deep.FacilityDeepFloorTest):
    def setUp(self) -> None:
        self.h = RedRogueHarness(deep.ROOT, deep.ARTIFACTS, cgb_mode=True)
        self.h.allow_deep_facility_floor = True


# Its second, ordinary harness checks the harness's default, not the hardware,
# and a second DMG harness cannot run in a CGB worker.
CGBFacilityDeepFloorTest.test_lobby_decides_and_the_default_is_ordinary = None


if __name__ == "__main__":
    unittest.main()
