"""Banded kinds whose team size is tied to the route table (party roster Phase 3).

A wild-area ambush, and a mini-boss (Phase 4), fields what that round's largest route trainer does
(user decision 2026-10-07): STAGE_EVENT_R<n>_MONS must equal the class-count
sum of round n's trainer_difficulty_settings block in
data/balance/trainer_levels.asm. Retuning route sizes without the ambush
sizes, or the other way round, fails here. No emulator needed.
"""
import unittest

from source_constants import parse_rgbds_constants
from test_smoke import REPO_ROOT

ROUND = parse_rgbds_constants(REPO_ROOT / "constants/round_constants.asm")
BALANCE = parse_rgbds_constants(REPO_ROOT / "constants/balance_constants.asm", ROUND)
BLOCK = 11  # trainer_levels.asm: one 11-byte block per round
NUM_TIERS = 9


def route_max_sizes():
    """[largest route team for round 1..9]: bytes 2-5 (normal class counts) and
    7-10 (the final route trainer's) of each trainer_difficulty_settings block,
    whichever sums higher."""
    values, inside = [], False
    for raw in (REPO_ROOT / "data/balance/trainer_levels.asm").read_text().splitlines():
        code = raw.split(";", 1)[0].strip()
        if code.endswith(":"):
            inside = code.rstrip(":") == "trainer_difficulty_settings"
            continue
        if inside and code.startswith("db "):
            values.append(int(code[3:].strip(), 0))
    sizes = []
    for r in range(NUM_TIERS):
        cells = values[r * BLOCK:(r + 1) * BLOCK]
        sizes.append(max(sum(cells[2:6]), sum(cells[7:11])))
    return sizes


class RouteMaxTeamSizeTest(unittest.TestCase):
    def test_route_table_is_parsed(self):
        # Shipping values when this test was written; a change here is fine,
        # the test below is the real contract.
        self.assertEqual(NUM_TIERS, len(route_max_sizes()))
        self.assertTrue(all(2 <= n <= 6 for n in route_max_sizes()))

    def test_stage_event_sizes_are_the_route_max(self):
        for r, expected in enumerate(route_max_sizes(), 1):
            with self.subTest(round=r):
                self.assertEqual(BALANCE[f"STAGE_EVENT_R{r}_MONS"], expected)

    def test_miniboss_sizes_are_the_route_max(self):
        # The mini-boss stands in for the route's final trainer (Phase 4).
        for r, expected in enumerate(route_max_sizes(), 1):
            with self.subTest(round=r):
                self.assertEqual(BALANCE[f"MINIBOSS_R{r}_MONS"], expected)

    def test_miniboss_ace_stays_under_the_leader(self):
        # Curve F: a mini-boss lands between the route's final trainer and the
        # round's leader, never above the leader. Round 9 (Victory Road) has
        # no gym leader after it.
        for r in range(1, 9):
            with self.subTest(round=r):
                mb = BALANCE[f"MINIBOSS_R{r}_BASE"] + (BALANCE[f"MINIBOSS_R{r}_MONS"] - 1) * BALANCE[f"MINIBOSS_R{r}_STEP"]
                gym = BALANCE[f"GYM_R{r}_BASE"] + (BALANCE[f"GYM_R{r}_MONS"] - 1) * BALANCE[f"GYM_R{r}_STEP"]
                self.assertLess(mb, gym)


if __name__ == "__main__":
    unittest.main()
