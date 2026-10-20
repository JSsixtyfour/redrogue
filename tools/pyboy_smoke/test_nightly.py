"""Nightly regression bookkeeping (nightly.py): what counts as worse than last
night. Source-only: synthetic reports, no emulator."""
import tempfile
import unittest
from pathlib import Path

import nightly


def suite(name, exit=0, failing=(), kinds=(), champion=None):
    return {"suite": name, "exit": exit, "failing": list(failing),
            "findings": [{"kind": k, "what": k} for k in kinds], "champion_rate": champion}


class RegressionsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.night = Path(tempfile.mkdtemp())

    def regressions(self, old_suites, new_suites):
        previous = {"night": str(self.night / "old"), "suites": old_suites}
        return nightly.regressions({"suites": new_suites}, previous, self.night)

    def test_no_previous_night_is_no_regression(self) -> None:
        self.assertEqual(nightly.regressions({"suites": [suite("smoke", exit=1)]}, None, self.night), [])

    def test_newly_failing_test_and_suite(self) -> None:
        found = self.regressions([suite("smoke", failing=["a.A.test_old"])],
                                 [suite("smoke", exit=1, failing=["a.A.test_old", "b.B.test_new"])])
        self.assertIn("smoke: newly failing b.B.test_new", found)
        self.assertFalse(any("test_old" in f for f in found))
        self.assertIn("smoke: passed last night, fails now (exit 1)", found)

    def test_only_new_kinds_of_finding_count(self) -> None:
        found = self.regressions([suite("lobby", kinds=["party"])],
                                 [suite("lobby", kinds=["party", "party", "crashed"])])
        self.assertEqual(found, ["lobby: new kind of finding: crashed"])

    def test_champion_rate_drop_beyond_noise(self) -> None:
        self.assertEqual(self.regressions([suite("lobby", champion=0.5)], [suite("lobby", champion=0.45)]), [])
        found = self.regressions([suite("lobby", champion=0.5)], [suite("lobby", champion=0.2)])
        self.assertEqual(found, ["lobby: champion rate 50% -> 20%"])


class QuickModeTest(unittest.TestCase):
    def test_quick_flags_exist_in_their_suites(self) -> None:
        for name, flags in nightly.QUICK.items():
            for flag in flags:
                self.assertIn(flag, nightly.SUITES[name][0], (name, flag))


if __name__ == "__main__":
    unittest.main()
