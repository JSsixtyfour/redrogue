"""The Cemetery's deep chain on CGB: a floor generates at double speed inside the
stage dispatch (CemDeepFinalizeMap). The smoke runner classifies modules by
hardware, so the CGB case lives in its own module."""

import unittest

import test_cemetery_deep_floor as deep
from harness import RedRogueHarness


class CGBCemeteryDeepFloorTest(deep.CemeteryDeepFloorTest):
    def setUp(self) -> None:
        self.h = RedRogueHarness(deep.ROOT, deep.ARTIFACTS, cgb_mode=True)
        self.h.allow_deep_cemetery_floor = True


# Its extra harnesses check the harness's defaults, not the hardware, and a
# second DMG harness cannot run in a CGB worker.
CGBCemeteryDeepFloorTest.test_the_cemetery_rolls_the_ramp = None


if __name__ == "__main__":
    unittest.main()
