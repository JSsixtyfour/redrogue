"""Stage reward ball level (engine/events/reward_poke_balls.asm, 2026-10-13).

The three floor balls on every stage gave a flat level 5 (`ld c, 5`) while the
vendor's menu used GetRewardMonLevel. Seen in play: a round 1 route Geodude and
a round 3 mini-boss stage gift both at level 5. The balls now take the level
from RewardBallLevel (GetRewardMonLevel on the stage path).
"""
import re
import unittest

from source_constants import parse_map_constants, parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

MAPS = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
ROUNDS = parse_rgbds_constants(REPO_ROOT / "constants" / "round_constants.asm")
KNOBS = parse_rgbds_constants(REPO_ROOT / "constants" / "balance_constants.asm", ROUNDS)
ROUND_BATTLES = ROUNDS["ROUND_BATTLES"]
SOURCE = REPO_ROOT / "engine" / "events" / "reward_poke_balls.asm"


class RewardBallSourceTest(unittest.TestCase):
    def test_every_ball_takes_its_level_from_reward_ball_level(self) -> None:
        text = SOURCE.read_text(encoding="utf-8")
        for n in (1, 2, 3):
            body = text.split(f"Rogue_Reward_Script_PokeballText_{n}::", 1)[1]
            body = body.split("call GivePokemon", 1)[0]
            tail = body.rsplit("call RewardBallLevel", 1)
            self.assertEqual(len(tail), 2, f"ball {n} never calls RewardBallLevel")
            # Nothing between the level and GivePokemon may write c.
            self.assertIsNone(re.search(r"^\s*(ld c,|ld bc,|lb bc,|pop bc|call|farcall)", tail[1], re.M),
                              f"ball {n}: c is clobbered before GivePokemon")


class RewardBallLevelTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.harness.boot_to_lobby(battle_count=1)

    def ball_level(self, round_index: int) -> tuple[int, int]:
        """(RewardBallLevel, GetRewardMonLevel) on a route stage mid-round."""
        h = self.harness
        h.write8("hCurMap", MAPS["ROUTE_1"])
        h.write8("wBattleCount", round_index * ROUND_BATTLES + 2)
        h.write8("wCurEnemyLevel", 0)
        h.park_before_hijack()
        h.call_routine("RewardBallLevel")
        ball = h.read8("wCurEnemyLevel")
        h.write8("wCurEnemyLevel", 0)
        h.park_before_hijack()
        h.call_routine("GetRewardMonLevel")
        vendor = h.read8("wCurEnemyLevel")
        h.write8("hCurMap", MAPS["INDIGO_PLATEAU_LOBBY"])
        return ball, vendor

    def test_balls_match_the_vendor_and_beat_the_starter(self) -> None:
        levels = []
        for round_index in (0, 2):
            with self.subTest(round=round_index + 1):
                ball, vendor = self.ball_level(round_index)
                levels.append(ball)
                self.assertEqual(ball, vendor)
                self.assertGreaterEqual(ball, KNOBS["REWARD_LEVEL_FLOOR"])
                self.assertGreater(ball, KNOBS["STARTER_LEVEL"])
        self.assertGreater(levels[1], levels[0], "round 3's balls outlevel round 1's")


if __name__ == "__main__":
    unittest.main(verbosity=2)
