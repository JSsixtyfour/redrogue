"""test_cave_generic_trainer on CGB (the smoke runner classifies modules by name)."""

from __future__ import annotations

import unittest

import test_cave_generic_trainer as generic


class CGBCaveGenericTrainerTest(generic.CaveGenericTrainerTest):
    CGB = True
    test_keep_table_holds_him = None


if __name__ == "__main__":
    unittest.main()
