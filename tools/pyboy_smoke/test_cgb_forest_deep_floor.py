"""The Forest's deep floor on CGB: the same trips (the second floor's palette and
VRAM, and floor 2's generation at double speed). The smoke runner classifies
modules by hardware, so the CGB case lives in its own module."""

import unittest

import test_forest_deep_floor as deep
from harness import RedRogueHarness


class CGBForestDeepFloorTest(deep.ForestDeepFloorTest):
    def setUp(self) -> None:
        self.h = RedRogueHarness(deep.ROOT, deep.ARTIFACTS, cgb_mode=True)
        self.h.allow_deep_forest_floor = True


# Its second, ordinary harness checks the harness's default, not the hardware,
# and a second DMG harness cannot run in a CGB worker.
CGBForestDeepFloorTest.test_lobby_decides_and_resets = None


if __name__ == "__main__":
    unittest.main()
