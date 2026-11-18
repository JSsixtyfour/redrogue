"""CGB half of test_stack_depth_postko.py: the same two post-KO paths with CGB
VBlank (palette transfers) on the stack. A separate module because run_smoke
picks DMG or CGB per module, by the test_cgb_ prefix."""
import unittest

import test_stack_depth_postko as dmg


class CGBStackDepthPostKOTest(dmg.StackDepthPostKOTest):
    CGB = True


if __name__ == "__main__":
    unittest.main()
