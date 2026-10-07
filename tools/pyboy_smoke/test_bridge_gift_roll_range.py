"""Bridge gift roll range guard, run as part of `make smoke`.

audit_bridge_gift_roll_range.py enters all 14 bridge rooms under several RNG
seeds and fails if any gift index lands past its giver's list (RR-0011: the
roll's count, cached in wBuffer+0, was overwritten by FarCopyData's bank, so
the menu showed a blank row that crashed on hover). Its docstring has the
details and the negative control (it fails on the archived 8e6ca844 ROM).
"""

import subprocess
import sys
import unittest
from pathlib import Path

SUITE_DIR = Path(__file__).resolve().parent


class BridgeGiftRollRangeTest(unittest.TestCase):
    def test_every_bridge_gift_index_is_inside_its_list(self):
        result = subprocess.run(
            [sys.executable, str(SUITE_DIR / "audit_bridge_gift_roll_range.py")],
            capture_output=True, text=True, timeout=300,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
