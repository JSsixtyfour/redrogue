"""The crash screen in CGB mode, crashing with WRAM bank 3 selected: the stack
must still be read from the bank the CPU was using ($DFxx is banked on CGB),
and the screen must name that bank. Cases live in test_crash_screen.py."""

from __future__ import annotations

import unittest

from test_crash_screen import CrashScreenCases


class CgbCrashScreenTest(CrashScreenCases, unittest.TestCase):
    CGB = True
    WRAM_BANK = 3


if __name__ == "__main__":
    unittest.main()
