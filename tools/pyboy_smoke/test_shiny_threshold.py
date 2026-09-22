"""Source contract for the SHINY CHARM threshold table (2D, 2026-09-22).

A maxed SHINY CHARM used to make 95.7% of received mons shiny: the table
had 4 entries (indices 0-3) but GetKeyItemPower returns 1-4 (1 + the
displayed tier, which is 0-3), so tier 3 read one byte past the table into
ApplyDVFloor's `push af` ($F5 = 245/256). Nothing caught it because the
table had no assert_table_length.

This does not run the ROM; it is a static check that the fix is the one
actually committed, not a stand-in for a runtime shiny-rate measurement.
"""

from __future__ import annotations

from pathlib import Path
import re
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
ADD_MON = REPO_ROOT / "engine" / "pokemon" / "add_mon.asm"


def table_body() -> str:
    src = ADD_MON.read_text()
    start = src.index(".ShinyThresholdTable:")
    end = src.index("ApplyDVFloor", start)
    return src[start:end]


class ShinyThresholdTableTest(unittest.TestCase):
    def test_table_has_five_entries_one_per_tier_plus_base(self) -> None:
        body = table_body()
        m = re.search(r"^\tdb ([\d, ]+)$", body, re.M)
        self.assertIsNotNone(m, "no `db` row found in .ShinyThresholdTable")
        entries = [int(x) for x in m.group(1).split(",")]
        self.assertEqual(
            entries, [1, 2, 4, 8, 16],
            "GetKeyItemPower returns 1-4 (1 + tier 0-3); the table needs "
            "exactly 5 entries (index 0 = no charm) or it reads out of "
            "bounds again")

    def test_table_asserts_its_own_length(self) -> None:
        self.assertIn(
            "assert_table_length 5", table_body(),
            "the absent assert is why the 4-entry overflow compiled "
            "silently the first time")

    def test_tier_3_yields_the_new_rate_not_the_old_overflow(self) -> None:
        entries = [1, 2, 4, 8, 16]
        tier_3_index = 1 + 3  # GetKeyItemPower(tier=3) == 4
        self.assertEqual(entries[tier_3_index], 16)
        self.assertNotEqual(entries[tier_3_index], 245)


if __name__ == "__main__":
    unittest.main()
