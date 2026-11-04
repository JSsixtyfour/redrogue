"""The special collection's pages on actual CGB emulation: palettes and the shadow's tiles."""
import unittest

import test_special_collection as special


class CgbPageTest(special.PageTest):
    cgb = True


if __name__ == "__main__":
    unittest.main()
