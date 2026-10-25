"""Exercise the wild-area encounter pool on both sides of round 3.

Only RNG outcomes are mocked; the ROM selects the pool and event type.
"""
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_move_tutor_prices import return_from_call

ROOT = Path(__file__).resolve().parents[2]
ROUNDS = parse_rgbds_constants(ROOT / "constants/round_constants.asm")
EVENTS = parse_rgbds_constants(ROOT / "constants/ram_constants.asm", ROUNDS)


class StageEventEligibilityTest(unittest.TestCase):
    def check_pool(self, battle_count, expected):
        h = RedRogueHarness(ROOT, Path(__file__).parent / "artifacts")
        try:
            h.boot_to_lobby()
            chosen = [0]
            ranges = []

            def called_from(label):
                stack = h.pyboy.register_file.SP
                address = h.pyboy.memory[stack] | (h.pyboy.memory[stack + 1] << 8)
                return address == h.address(label) + 3  # return after CALL

            def event_chance(_):
                if not called_from("StageEventRoll"):
                    return
                h.pyboy.register_file.A = 0
                return_from_call(h)

            def type_draw(_):
                if not called_from("StageEventRoll.rollType"):
                    return
                ranges.append(h.pyboy.register_file.C)
                h.pyboy.register_file.A = chosen[0]
                return_from_call(h)

            h.register_hook("Random", event_chance)
            h.register_hook("Rangerandom", type_draw)
            h.write8("wBattleCount", battle_count)
            # Eligibility follows progression even with a small late party.
            h.write8("wPartyCount", 3)
            actual = []
            for index in range(len(expected)):
                chosen[0] = index
                h.write8("wStageEvent", 0)
                h.call_routine("StageEventRoll")
                actual.append(h.read8("wStageEvent"))
            self.assertEqual(actual, expected)
            self.assertEqual(ranges, [len(expected)] * len(expected))
        finally:
            h.close()

    def test_round_two_excludes_only_pokemon_thieves(self):
        for count in (ROUNDS["ROUND_BATTLES"], 2 * ROUNDS["ROUND_BATTLES"] - 1):
            with self.subTest(battle_count=count):
                self.check_pool(count, [EVENTS[name] for name in (
                    "STAGE_EVENT_BURGLAR", "STAGE_EVENT_JOY", "STAGE_EVENT_JENNY")])

    def test_round_three_and_later_restore_full_pool(self):
        for count in (2 * ROUNDS["ROUND_BATTLES"], 255):
            with self.subTest(battle_count=count):
                self.check_pool(count, list(range(1, EVENTS["STAGE_EVENT_MAX_ROLLABLE"] + 1)))


if __name__ == "__main__":
    unittest.main()
