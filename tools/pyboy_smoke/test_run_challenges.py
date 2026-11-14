"""Run challenges (custom_functions/run_challenges.asm): the state helpers, the
Hall of Fame commit, the badge conditions and the witch's overlap reroll.

Effect sites are covered where their witch twin already is; these tests pin the
run-challenge bookkeeping that has no witch counterpart.
"""
import unittest

import test_dex_forms
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_save_header import ARTIFACTS, REPO_ROOT

EVENTS = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")

NUM = RAM["RUN_CH_FEWER_REWARDS"] + 1  # NUM_RUN_CHALLENGES (the parser skips const_value aliases)
WEIGHTS = [1, 2, 2, 1, 2, 1, 1, 2, 2, 1, 1, 1, 1, 2, 2]  # RunChallengeWeights
IRONMAN, SET_STYLE, NO_GIFTS = (RAM["BIT_CHBADGE_" + n] for n in ("IRONMAN", "SET_STYLE", "NO_GIFTS"))
THREE, SIX, ALL = (RAM["BIT_CHBADGE_" + n] for n in ("THREE", "SIX", "ALL"))
CARRY = 0x10


class RunChallengeTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)
        self.h.boot_to_lobby()
        self.runner = test_dex_forms.DexFormsTest()
        self.runner.h = self.h
        for label in ("wChallengeBadges", "wChallengeBadgesHi", "wChallengeBadges2", "wBestHeat",
                      "wRunChallengeBroken"):
            self.h.write8(label, 0)
        self.choose()

    def call(self, label, **regs):
        return self.runner.run_routine(label, **regs)

    def choose(self, *ids):
        mask = sum(1 << i for i in ids)
        self.h.write8("wRunChallenges", mask & 0xFF)
        self.h.write8("wRunChallenges", mask >> 8, offset=1)

    def options(self, ironman=True, shift=False, difficulty=0):
        o3 = self.h.read8("wOptions3")
        self.h.write8("wOptions3", (o3 | 1) if ironman else (o3 & ~1))
        o1 = self.h.read8("wOptions")
        bit = 1 << RAM["BIT_BATTLE_SHIFT"]
        self.h.write8("wOptions", (o1 | bit) if shift else (o1 & ~bit))
        o2 = self.h.read8("wOptions2")
        self.h.write8("wOptions2", (o2 & ~RAM["DIFFICULTY_MASK"]) | difficulty)

    def test_mask_and_count_cover_both_bytes(self):
        self.choose(0, 7, 8, 14)
        for i in range(16):
            out = self.call("RunChallengeIsOn", A=i)
            self.assertEqual(not (out["F"] & 0x80), i in (0, 7, 8, 14), f"id {i}")

    def test_heat_sums_weights_ironman_and_lowest_difficulty(self):
        self.choose(1, 2, 13)                          # 2 + 2 + 2
        self.options(ironman=True, difficulty=RAM["DIFFICULTY_VERY_HARD"])
        self.call("RunChallengesStartRun")
        self.assertEqual(self.call("RunChallengeHeat")["A"], 6 + 3 + 2)
        # Lowering the difficulty mid-run lowers the floor for good.
        self.h.set_event(EVENTS["EVENT_GOT_STARTER"])
        self.options(ironman=True, difficulty=RAM["DIFFICULTY_HARD"])
        self.call("RunChallengesNoteOptions")
        self.options(ironman=True, difficulty=RAM["DIFFICULTY_VERY_HARD"])
        self.call("RunChallengesNoteOptions")
        self.assertEqual(self.call("RunChallengeHeat")["A"], 6 + 3 + 1)
        # Ironman off once: no Ironman heat, and the badge is broken.
        self.options(ironman=False, difficulty=RAM["DIFFICULTY_VERY_HARD"])
        self.call("RunChallengesNoteOptions")
        self.assertEqual(self.call("RunChallengeHeat")["A"], 6 + 1)
        self.assertTrue(self.h.read8("wRunChallengeBroken") & (1 << IRONMAN))

    def test_options_ignored_between_runs(self):
        self.call("RunChallengesStartRun")
        before = self.h.read8("wRunChallengeBroken")
        self.h.write8("wEventFlags", self.h.read8("wEventFlags", offset=EVENTS["EVENT_GOT_STARTER"] // 8)
                      & ~(1 << (EVENTS["EVENT_GOT_STARTER"] % 8)), offset=EVENTS["EVENT_GOT_STARTER"] // 8)
        self.options(ironman=False, shift=True)
        self.call("RunChallengesNoteOptions")
        self.assertEqual(self.h.read8("wRunChallengeBroken"), before)

    def test_commit_awards_badges_extras_combos_and_best_heat(self):
        self.choose(*range(NUM))
        self.options(ironman=True, shift=False, difficulty=0)
        self.call("RunChallengesStartRun")
        self.h.write8("wRunChallengeBroken", self.h.read8("wRunChallengeBroken") | (1 << NO_GIFTS))
        self.call("RunChallengesCommitClear")
        self.assertEqual(self.h.read8("wChallengeBadges"), 0xFF)
        self.assertEqual(self.h.read8("wChallengeBadgesHi"), (1 << (NUM - 8)) - 1)
        extras = self.h.read8("wChallengeBadges2")
        self.assertEqual(extras, (1 << IRONMAN) | (1 << SET_STYLE) | (1 << THREE) | (1 << SIX) | (1 << ALL))
        self.assertEqual(self.h.read8("wBestHeat"), sum(WEIGHTS) + 3)
        # A smaller later clear keeps everything earned.
        self.choose(3)
        self.call("RunChallengesCommitClear")
        self.assertEqual(self.h.read8("wBestHeat"), sum(WEIGHTS) + 3)
        self.assertEqual(self.h.read8("wChallengeBadges"), 0xFF)

    def test_witch_rerolls_only_true_duplicates(self):
        def active(witch_id):
            return bool(self.call("WitchChallengeIsRunActive", D=witch_id)["F"] & CARRY)
        self.choose()
        self.assertFalse(any(active(i) for i in range(1, RAM["NUM_WITCH_CHALLENGES"] + 1)))
        self.choose(RAM["RUN_CH_RECOIL_PHYSICAL"], RAM["RUN_CH_LESS_MONEY"], RAM["RUN_CH_FEWER_REWARDS"],
                    RAM["RUN_CH_TURN_LIMIT"])
        self.assertTrue(active(RAM["CHALLENGE_RECOIL_PHYSICAL"]))
        self.assertTrue(active(RAM["CHALLENGE_TURN_LIMIT"]))
        self.assertFalse(active(RAM["CHALLENGE_RECOIL_ATTACKS"]), "12 needs both halves")
        self.assertFalse(active(RAM["CHALLENGE_NO_MONEY"]))
        self.assertFalse(active(RAM["CHALLENGE_NO_REWARD_POKEMON"]))
        self.choose(RAM["RUN_CH_RECOIL_PHYSICAL"], RAM["RUN_CH_RECOIL_SPECIAL"])
        self.assertTrue(active(RAM["CHALLENGE_RECOIL_ATTACKS"]))

    def test_post_move_effect_bits_combine_witch_and_run(self):
        flags = self.h.read8("wRogueFlagsBitfield")
        accepted = 1 << RAM["BIT_WITCH_ACCEPTED"]
        self.h.write8("wRogueFlagsBitfield", flags | accepted)
        self.h.write8("wWitchChallenge", RAM["CHALLENGE_SAME_MOVE_PENALTY"])
        self.choose(RAM["RUN_CH_RECOIL_SPECIAL"])
        self.assertEqual(self.call("PostMoveChallengeEffects")["E"], 0b101)
        self.h.write8("wWitchChallenge", RAM["CHALLENGE_RECOIL_ATTACKS"])
        self.choose()
        self.assertEqual(self.call("PostMoveChallengeEffects")["E"], 0b110)
        self.h.write8("wRogueFlagsBitfield", flags & ~accepted)
        self.choose(RAM["RUN_CH_SAME_MOVE"], RAM["RUN_CH_RECOIL_PHYSICAL"])
        self.assertEqual(self.call("PostMoveChallengeEffects")["E"], 0b011)


if __name__ == "__main__":
    unittest.main()
