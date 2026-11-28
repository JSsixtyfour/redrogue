"""Run challenges (custom_functions/run_challenges.asm): the state helpers, the
Hall of Fame commit, the badge conditions and the witch's overlap reroll.

Effect sites are covered where their witch twin already is; these tests pin the
run-challenge bookkeeping that has no witch counterpart.
"""
import unittest

import test_dex_forms
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
from test_save_header import ARTIFACTS, REPO_ROOT

EVENTS = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")
RAM_ROUND = parse_rgbds_constants(REPO_ROOT / "constants" / "round_constants.asm")

SPECIES = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
PLAYER = parse_rgbds_constants(REPO_ROOT / "constants" / "player_constants.asm")
MAPS = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
GROUPS = parse_rgbds_constants(REPO_ROOT / "constants" / "rogue_species_groups.asm")

NUM = RAM["RUN_CH_JOEY"] + 1  # NUM_RUN_CHALLENGES (the parser skips const_value aliases)
WEIGHTS = [1, 2, 2, 1, 2, 1, 1, 2, 2, 1, 1, 1, 1, 2, 2, 2, 1]  # RunChallengeWeights
IRONMAN, SET_STYLE = (RAM["BIT_CHBADGE_" + n] for n in ("IRONMAN", "SET_STYLE"))
THREE, SIX, ALL, JOEY_BADGE = (RAM["BIT_CHBADGE_" + n] for n in ("THREE", "SIX", "ALL", "JOEY"))
JOEY = RAM["RUN_CH_JOEY"]
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
        self.h.write8("wRunChallenges", (mask >> 8) & 0xFF, offset=1)
        self.h.write8("wRunChallengesExt", mask >> 16)

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
        for i in range(NUM):
            out = self.call("RunChallengeIsOn", A=i)
            self.assertEqual(not (out["F"] & 0x80), i in (0, 7, 8, 14), f"id {i}")
        self.choose(JOEY)                              # the third byte, not contiguous
        self.assertEqual(self.h.read8("wRunChallengesExt"), 1)
        for i in range(NUM):
            out = self.call("RunChallengeIsOn", A=i)
            self.assertEqual(not (out["F"] & 0x80), i == JOEY, f"id {i}")

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
        self.options(ironman=True, shift=True, difficulty=0)
        self.call("RunChallengesStartRun")              # SET STYLE broken: SHIFT at run start
        self.call("RunChallengesCommitClear")
        self.assertEqual(self.h.read8("wChallengeBadges"), 0xFF)
        self.assertEqual(self.h.read8("wChallengeBadgesHi"), 0xFF)
        extras = self.h.read8("wChallengeBadges2")
        self.assertEqual(extras, (1 << IRONMAN) | (1 << THREE) | (1 << SIX) | (1 << ALL)
                         | (1 << JOEY_BADGE))
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

    def test_fewer_rewards_withholds_only_rounds_two_and_six(self):
        rb = parse_rgbds_constants(REPO_ROOT / "constants" / "round_constants.asm")["ROUND_BATTLES"]
        mask = 0b00100010                                  # FEWER_REWARDS_ROUND_MASK
        self.h.write8("wRogueFlagsBitfield", self.h.read8("wRogueFlagsBitfield") & ~(1 << RAM["BIT_WITCH_ACCEPTED"]))
        self.choose()
        self.h.write8("wBattleCount", rb + 1)
        self.assertEqual(self.call("RewardChallengeFlags")["E"], 0, "off: nothing withheld")
        self.choose(RAM["RUN_CH_FEWER_REWARDS"])
        for rnd in range(9):
            for step in (1, rb - 1):                       # first and last stage battle of the round
                self.h.write8("wBattleCount", rnd * rb + step)
                want = 1 if (rnd < 8 and mask >> rnd & 1) else 0
                self.assertEqual(self.call("RewardChallengeFlags")["E"], want, f"round {rnd} step {step}")
        self.choose(RAM["RUN_CH_NO_RANDOM_ITEM"])
        self.h.write8("wBattleCount", 1)
        self.assertEqual(self.call("RewardChallengeFlags")["E"], 0b10)

    def test_no_gifts_keeps_the_guaranteed_gift_doors_shut(self):
        # Two badges: the last gym of the first gift window, where a gift is mandatory.
        h = self.h
        h.write8("wObtainedBadges", (1 << (RAM_ROUND["PAIR_BADGES_A"] - 1)) - 1)
        h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") | (1 << RAM["BIT_ROGUE_GYM_NEXT"]))
        h.write8("wStatusFlags6", h.read8("wStatusFlags6") & ~(1 << RAM["BIT_DEBUG2_MODE"]))
        for on in (False, True):
            with self.subTest(no_gifts=on):
                h.write8("wBridgeState", 0)
                h.write8("wBridgeOfferedLo", 0)
                self.choose(*([RAM["RUN_CH_NO_GIFTS"]] if on else []))
                fired = bool(self.call("BridgeRollAndAssign")["F"] & CARRY)
                self.assertEqual(fired, not on)

    def test_witch_party_limit_rerolled_while_fewer_rewards_on(self):
        self.choose(RAM["RUN_CH_FEWER_REWARDS"])
        out = self.call("WitchChallengeIsRunActive", D=RAM["CHALLENGE_PARTY_LIMIT"])
        self.assertTrue(out["F"] & CARRY)


    # --- JOEY -----------------------------------------------------------------

    def joey_starters(self, warp):
        """Ordinary offers in the three slots, then the override as Oak's Lab runs it."""
        h = self.h
        ev = EVENTS["EVENT_KANTO_TIMEWARP_ACTIVATED"]
        flags = h.read8("wEventFlags", offset=ev // 8)
        flags = (flags | (1 << (ev % 8))) if warp else (flags & ~(1 << (ev % 8)))
        h.write8("wEventFlags", flags, offset=ev // 8)
        h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [(1 << GROUPS["NUM_SPECIES_GROUPS"]) - 1])
        for i, mon in enumerate((SPECIES["PIDGEY"], SPECIES["ODDISH"], SPECIES["ABRA"])):
            h.write8("wRoguePokemon1", mon, offset=i)
            h.write8("wRoguePokemonForm1", 0, offset=i)
        h.write_sram_bytes("sRogueOfferDVs", [0x12] * 6 + [0] * 3, bank=2)
        self.call("JoeyStarterOverride")
        return ([h.read8("wRoguePokemon1", offset=i) for i in range(3)],
                [h.read8("wRoguePokemonForm1", offset=i) for i in range(3)])

    def test_joey_off_leaves_the_starters_alone(self):
        self.choose(RAM["RUN_CH_NO_GIFTS"])
        species, _ = self.joey_starters(warp=True)
        self.assertEqual(species, [SPECIES["PIDGEY"], SPECIES["ODDISH"], SPECIES["ABRA"]])
        self.assertEqual(self.h.read_sram_bytes("sRogueOfferDVs", 6, bank=2), [0x12] * 6)

    def test_joey_starters_are_rattata_with_perfect_dvs(self):
        self.choose(JOEY)
        for warp in (False, True):
            alolan_slots = set()
            for _ in range(12 if warp else 3):
                with self.subTest(warp=warp):
                    species, forms = self.joey_starters(warp)
                    self.assertEqual(species, [SPECIES["RATTATA"]] * 3)
                    if warp:
                        self.assertEqual(sorted(forms), [0, 0, 1], "exactly one Alolan Rattata")
                        alolan_slots.add(forms.index(1))
                    else:
                        self.assertEqual(forms, [0, 0, 0])
                    self.assertEqual(self.h.read_sram_bytes("sRogueOfferDVs", 6, bank=2), [0xFF] * 6)
                    self.assertEqual(self.h.read_sram_bytes("sRogueOfferDVTag", 3, bank=2),
                                     [SPECIES["RATTATA"]] * 3)
                    for slot in (1, 2, 3):          # what INFO shows and AddPartyMon gives
                        out = self.call("GetRogueOfferDVs", E=slot)
                        self.assertEqual(out["HL"], 0xFFFF, f"slot {slot}")
            if warp:
                self.assertGreater(len(alolan_slots), 1, "the Alolan ball is not always the same slot")

    def test_joey_starter_is_given_with_perfect_dvs(self):
        """The lab's give: AddPartyMon with wSpawnDVSlot = the ball taken."""
        h = self.h
        self.choose(JOEY)
        _, forms = self.joey_starters(warp=True)
        for slot in (1, 2, 3):                         # setUp boots fresh: the party is scratch
            with self.subTest(slot=slot):
                h.write8("wPartyCount", 0)
                h.write8("wPartySpecies", 0xFF)
                h.write8("wPartyMon1DVs", 0)
                h.write8("wPartyMon1DVs", 0, offset=1)
                h.write8("wCurPartySpecies", SPECIES["RATTATA"])
                h.write8("wCurEnemyLevel", 5)
                h.write8("wMonDataLocation", 0x10)     # player party, no naming screen
                h.write8("wSpawnDVSlot", slot)
                h.write8("wSpawnForm", forms[slot - 1])
                got = h.call_routine("_AddPartyMon", limit=60000, capture=lambda x: (
                    x.read_bytes("wPartySpecies", 2), x.read_bytes("wPartyMon1DVs", 2)))
                self.assertEqual(got[0], [SPECIES["RATTATA"], 0xFF])
                self.assertEqual(got[1], [0xFF, 0xFF])

    def test_joey_later_rattata_offers_roll_normally(self):
        self.choose(JOEY)
        self.joey_starters(warp=False)
        dvs = set()
        for _ in range(3):
            self.call("RogueOffersReset")              # the next stage's offers
            self.h.write8("wRoguePokemon1", SPECIES["RATTATA"])
            dvs.add(self.call("GetRogueOfferDVs", E=1)["HL"])
        self.assertNotEqual(dvs, {0xFFFF}, "a later Rattata offer must roll its own DVs")

    def test_joey_youngster_look_outside_silph_co(self):
        h = self.h
        youngster = PLAYER["PLAYER_APPEARANCE_YOUNGSTER"]
        own = PLAYER["PLAYER_APPEARANCE_GREEN"]
        saved_map = h.read8("hCurMap")
        try:
            h.write8("wPlayerAppearance", own)
            for joey in (False, True):
                self.choose(*([JOEY] if joey else []))
                for name in ("SILPH_CO_DORM", "SILPH_CO_1F", "SILPH_CO_VR", "SILPH_CO_ELEVATOR",
                             "SILPH_CO_B1F", "SILPH_CO_11F", "OAKS_LAB", "ROUTE_1", "HALL_OF_FAME"):
                    with self.subTest(joey=joey, map=name):
                        h.write8("hCurMap", MAPS[name])
                        got = self.call("GetEffectivePlayerAppearanceFar")["E"]
                        silph = name.startswith("SILPH_CO")
                        self.assertEqual(got, youngster if joey and not silph else own)
            # A corrupt index still reads as RED.
            h.write8("wPlayerAppearance", 0xEE)
            h.write8("hCurMap", MAPS["SILPH_CO_DORM"])
            self.assertEqual(self.call("GetEffectivePlayerAppearanceFar")["E"],
                             PLAYER["PLAYER_APPEARANCE_RED"])
        finally:
            h.write8("hCurMap", saved_map)
            h.write8("wPlayerAppearance", 0)


if __name__ == "__main__":
    unittest.main()
