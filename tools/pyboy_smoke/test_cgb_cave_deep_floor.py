"""The cave's deep floor on CGB: the first descent generates floor 2 at double
speed (its own copy of the speed bracket, cave_deep_floor.asm). The smoke runner
classifies modules by hardware, so the CGB case lives in its own module."""

import unittest

import test_cave_deep_floor as deep
from harness import RedRogueHarness


class CGBCaveDeepFloorTest(deep.CaveDeepFloorTest):
    def setUp(self) -> None:
        self.h = RedRogueHarness(deep.ROOT, deep.ARTIFACTS, cgb_mode=True)
        self.h.allow_deep_cave_floor = True


for _name in [n for n in dir(deep.CaveDeepFloorTest) if n.startswith("test_")]:
    if _name != "test_first_descent_generates_floor_2_and_climbs_back":
        setattr(CGBCaveDeepFloorTest, _name, None)


if __name__ == "__main__":
    unittest.main()
