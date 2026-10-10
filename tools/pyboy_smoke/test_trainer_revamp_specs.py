"""Runtime checks for the Trainer Revamp's Elite Four and Champion-rival specs.

TRAINER_REVAMP_FIXES_PLAN.md steps 3-4. The byte layout of every record is
decoded from the built ROMs by test_party_spec_coverage.py; this file drives
ReadTrainer in the running ROM and reads the enemy party back, which is the
only thing that proves the pinned-slot rival-starter hook and the
NO_RIVAL_STARTER filter actually run.

Harness budget: ReadTrainer is called at most 8 times per boot (see the
measured ceiling in test_party_specs.py's module docstring), so each test
method boots fresh and stays under it.
"""
from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

MON_LEVEL = 0x21
PARTYMON_STRUCT_LENGTH = 0x2C
E4_TEAM_SIZE = 6

_BALANCE = parse_rgbds_constants(REPO_ROOT / "constants" / "balance_constants.asm")


def e4_levels(tier: int) -> tuple[int, int]:
    """E4_T curve: slot 0 is E4_BASE_LEVEL + tier, each slot adds E4_LEVEL_STEP."""
    low = _BALANCE["E4_BASE_LEVEL"] + tier
    return low, low + (E4_TEAM_SIZE - 1) * _BALANCE["E4_LEVEL_STEP"]

# class -> (variant A ace, variant C ace), species names as the ROM stores them.
# Forms are not visible in wEnemyPartySpecies, so Espeon / Umbreon read JOLTEON,
# Alolan Marowak MAROWAK and Galarian Weezing WEEZING.
E4_ACES = {
    "LORELEI": ("LAPRAS", "CLOYSTER"),
    "BRUNO": ("MACHAMP", "HITMONTOP"),
    "AGATHA": ("GENGAR", "MAROWAK"),
    "LANCE": ("DRAGONITE", "KINGDRA"),
    "KOGA_E4": ("CROBAT", "WEEZING"),
    "WILL": ("XATU", "JOLTEON"),
    "KAREN": ("HOUNDOOM", "JOLTEON"),
}
CHARMANDER_LINE = ("CHARMANDER", "CHARMELEON", "CHARIZARD")


class TrainerRevampSpecTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.species = parse_rgbds_constants(
            REPO_ROOT / "constants/pokemon_constants.asm")
        self.classes = parse_trainer_class_indexes(
            REPO_ROOT / "constants/trainer_constants.asm")

    def _build(self, trainer_class, trainer_no):
        h = self.harness
        assert h is not None
        h.write8("wTrainerClass", self.classes[trainer_class])
        h.write8("wTrainerNo", trainer_no)
        h.call_routine("ReadTrainer", limit=6000)
        count = h.read8("wEnemyPartyCount")
        party = h.read_bytes("wEnemyPartySpecies", count)
        levels = [h.read8("wEnemyMons", offset=i * PARTYMON_STRUCT_LENGTH + MON_LEVEL)
                  for i in range(count)]
        return count, party, levels

    def _check_e4(self, trainer_no, low, high):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.set_difficulty("HARD")  # expected levels are the 0% knobs
        for cls, aces in E4_ACES.items():
            with self.subTest(trainer=cls, trainer_no=trainer_no):
                count, party, levels = self._build(cls, trainer_no)
                self.assertEqual(count, E4_TEAM_SIZE,
                                 f"{cls} fielded {count} mons")
                # Party roster Phase 7a: the ace is drawn from the member's
                # Ace1 pool (these two signatures) on every variant.
                self.assertIn(party[-1], {self.species[a] for a in aces},
                              f"{cls} ace is species {party[-1]}")
                self.assertEqual((levels[0], levels[-1]), (low, high))

    def test_very_easy_never_reads_a_curated_set(self):
        """Player feedback #7 (2026-10-09): VERY EASY has no curated movesets.
        The HARD half is the control: the same builds do reach the reader, so a
        zero on VERY EASY means the gate, not a mix without MSRC_SET quota. One
        boot (a second fails), three tier-4 E4 builds per setting (call budget)."""
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        members = list(E4_ACES)[:3]
        reads = h.hook_flag("PartyGenApplySetMoveset")
        counts = {}
        for difficulty in ("HARD", "VERY_EASY"):
            h.set_difficulty(difficulty)
            before = reads["count"]
            for cls in members:
                self._build(cls, 11)
            counts[difficulty] = reads["count"] - before
        self.assertGreater(counts["HARD"], 0, counts)
        self.assertEqual(counts["VERY_EASY"], 0, counts)

    def test_e4_tier_one_builds_six_with_an_ace(self):
        """wTrainerNo 1 used to be the authored hole: a fixed 4-5 mon team.

        Now it is tier 1 - six mons from E4_BASE_LEVEL + 1, an Ace1 draw last.
        """
        self._check_e4(1, *e4_levels(1))

    def test_e4_tier_four_middle_variant_has_an_ace_too(self):
        """wTrainerNo 11: tier 4, the old variant B, which had no ace until
        party roster Phase 7a."""
        self._check_e4(11, *e4_levels(4))

    def test_rival3_ace_is_his_starter_and_the_pool_skips_its_line(self):
        """Slot 5 is wRivalStarter evolved; slots 0-4 never hold its line.

        CHARMANDER is in RivalThreePool's Kanto run, so without the
        NO_RIVAL_STARTER filter it is a live draw for every pool slot.
        test_no_rival_starter_filter_predicate below proves the filter is what
        rejects it; this one proves the whole build end to end.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.set_difficulty("HARD")  # expected levels are the 0% knobs
        h.write8("wRivalStarter", self.species["CHARMANDER"])
        line = {self.species[s] for s in CHARMANDER_LINE}
        for trainer_no in (1, 2, 3, 4, 5, 1):
            with self.subTest(trainer_no=trainer_no):
                count, party, levels = self._build("RIVAL3", trainer_no)
                self.assertEqual(count, 6)
                self.assertEqual(party[5], self.species["CHARIZARD"],
                                 "the ace must be his own starter, evolved")
                low = _BALANCE["CHAMPION_BASE_LEVEL"]
                self.assertEqual((levels[0], levels[5]),
                                 (low, low + 5 * _BALANCE["CHAMPION_LEVEL_STEP"]))
                for slot in range(5):
                    self.assertNotIn(party[slot], line,
                                     f"slot {slot} doubled up on his starter line")

    def test_no_rival_starter_filter_predicate(self):
        """BIT_PSPEC_NO_RIVAL_STARTER, deterministically and in both directions.

        Hooks the predicate's own .accept / .reject labels, because
        call_routine restores F on return (see test_uber_filter_reads_the_spec_flag).
          CHARMANDER + Rival3Spec   (flag set)  -> rejected
          SQUIRTLE   + Rival3Spec   (flag set)  -> accepted: only the starter
          CHARMANDER + LoreleiSpec2 (no flag)   -> accepted: the flag, not the
                                                   species, is what rejects
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.set_difficulty("HARD")  # expected levels are the 0% knobs
        h.write8("wRivalStarter", self.species["CHARMANDER"])
        verdict = []
        h.register_hook("PartyGenPoolCandidateOk.accept",
                        lambda ctx: verdict.append(True))
        h.register_hook("PartyGenPoolCandidateOk.reject",
                        lambda ctx: verdict.append(False))
        for spec_label, mon, expected in (
            ("Rival3Spec", "CHARMANDER", False),
            ("Rival3Spec", "SQUIRTLE", True),
            ("LoreleiTier1", "CHARMANDER", True),
        ):
            with self.subTest(spec=spec_label, mon=mon):
                verdict.clear()
                spec_addr = h.address(spec_label)
                h.write8("wPartyGenSpecPtr", spec_addr & 0xFF)
                h.write8("wPartyGenSpecPtr", spec_addr >> 8, offset=1)
                h.write8("wPartyGenSlot", 0)   # no override on slot 0 of either
                h.write8("wEnemyPartyCount", 0)
                h.write8("wCurEnemyLevel", 60)
                h.write8("wCurPartySpecies", self.species[mon])
                h.call_routine("PartyGenPoolCandidateOk", limit=600)
                self.assertEqual(verdict, [expected])


if __name__ == "__main__":
    import unittest
    unittest.main()
