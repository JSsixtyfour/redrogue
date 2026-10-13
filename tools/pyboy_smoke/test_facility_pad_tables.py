"""Static guards for the Facility warp-pad tables (PROCEDURAL_SUBROOMS_PLAN Phase 2).

PFacPadSiteValid proves a pad cannot strand anything from the per-block
walkable-quadrant table, so a stale table is a softlock risk the build would
never notice. The site list is read by the ROM and by the audit from one
constants file; these checks keep the two readings and the warp budget in step.
"""

from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

from audit_facility_pad_sites import FIRST_PAD_WARP, PAD_SITES

ROOT = Path(__file__).resolve().parents[2]
MAX_WARP_EVENTS = 32


class FacilityPadTableTest(unittest.TestCase):
    def test_quad_mask_table_is_fresh(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/gen_facility_quad_masks.py"), "--check"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_site_list_parses_and_fits_the_warp_budget(self) -> None:
        self.assertEqual(len(PAD_SITES), 27, "audit parsed a different site count than expected")
        self.assertEqual(len(set(PAD_SITES)), len(PAD_SITES), "duplicate pad site")
        self.assertLessEqual(FIRST_PAD_WARP + len(PAD_SITES), MAX_WARP_EVENTS)
        for x, y in PAD_SITES:
            self.assertTrue(1 <= x <= 18 and 3 <= y <= 18, (x, y))


if __name__ == "__main__":
    unittest.main()
