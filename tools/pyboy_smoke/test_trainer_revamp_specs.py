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

    def _check_e4(self, trainer_no, ace_index, low, high):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        for cls, aces in E4_ACES.items():
            with self.subTest(trainer=cls, trainer_no=trainer_no):
                count, party, levels = self._build(cls, trainer_no)
                self.assertEqual(count, E4_TEAM_SIZE,
                                 f"{cls} fielded {count} mons")
                self.assertEqual(party[-1], self.species[aces[ace_index]],
                                 f"{cls} ace is species {party[-1]}")
                self.assertEqual((levels[0], levels[-1]), (low, high))

    def test_e4_tier_one_builds_six_with_the_a_ace(self):
        """wTrainerNo 1 used to be the authored hole: a fixed 4-5 mon team.

        Now it is tier 1 variant A - six mons at 52-62, the A ace last.
        """
        self._check_e4(1, 0, 52, 62)

    def test_e4_tier_four_builds_six_with_the_c_ace(self):
        """wTrainerNo 12: tier 4 variant C, 55-65. Champion Lance draws 10-12."""
        self._check_e4(12, 1, 55, 65)

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
        h.write8("wRivalStarter", self.species["CHARMANDER"])
        line = {self.species[s] for s in CHARMANDER_LINE}
        for trainer_no in (1, 2, 3, 4, 5, 1):
            with self.subTest(trainer_no=trainer_no):
                count, party, levels = self._build("RIVAL3", trainer_no)
                self.assertEqual(count, 6)
                self.assertEqual(party[5], self.species["CHARIZARD"],
                                 "the ace must be his own starter, evolved")
                self.assertEqual((levels[0], levels[5]), (60, 65))
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
        h.write8("wRivalStarter", self.species["CHARMANDER"])
        verdict = []
        h.register_hook("PartyGenPoolCandidateOk.accept",
                        lambda ctx: verdict.append(True))
        h.register_hook("PartyGenPoolCandidateOk.reject",
                        lambda ctx: verdict.append(False))
        for spec_label, mon, expected in (
            ("Rival3Spec", "CHARMANDER", False),
            ("Rival3Spec", "SQUIRTLE", True),
            ("LoreleiSpec2", "CHARMANDER", True),
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
