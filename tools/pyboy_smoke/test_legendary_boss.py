"""Challenge 11 (Legendary Boss): the ace swap inside the party spec builder.

Every gym leader has a party spec, so ReadTrainer builds them through
RogueBuildParty and never reaches the old .SpecialTrainer hook. Measured in BGB
2026-10-13: PatchLegendaryBossSpecies never fired for Sabrina with the challenge
accepted. The swap now lives in PartyGenLegendaryBossAce, which farcalls
RollLegendaryBossAce for the team's last slot.

These drive the real ReadTrainer and read the built party back. Leaders are keyed
on TRAINER CLASS, never wGymLeaderNo: Kanto and Johto share leader numbers 1-8,
so BROCK (shares 1 with FALKNER), JASMINE (6, SABRINA) and CLAIR (8, GIOVANNI)
are the cases a number-keyed table would have swapped by mistake.

Each test boots once and stays under the harness's ~10 ReadTrainer calls per boot
(see the module note in test_party_specs.py).
"""
from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT

# Mirrors LegendaryBossTable in custom_functions/legendary_boss_helpers.asm.
LEGENDARY_POOLS = {
    "ERIKA": ["MEW", "CELEBI"],
    "SABRINA": ["MEWTWO", "MEW", "CELEBI", "LUGIA"],
    "BLAINE": ["MEW", "HO_OH"],
    "GIOVANNI": ["MEWTWO"],
    "FALKNER": ["LUGIA", "HO_OH"],
    "MORTY": ["HO_OH"],
    "PRYCE": ["CELEBI"],
}
NOT_ELIGIBLE = ["BROCK", "JASMINE", "CLAIR"]

# Round 6 A: a gym-5-or-later team, the only place the witch offers the challenge.
TRAINER_NO = 16


class LegendaryBossSwapSmokeTest(HarnessTestCase):
    def setUp(self):
        super().setUp()
        self.species = parse_rgbds_constants(
            REPO_ROOT / "constants/pokemon_constants.asm")
        self.classes = parse_trainer_class_indexes(
            REPO_ROOT / "constants/trainer_constants.asm")
        self.ram = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")

    def _set_challenge(self, on):
        h = self.harness
        flags = h.read8("wRogueFlagsBitfield")
        bit = 1 << self.ram["BIT_WITCH_ACCEPTED"]
        h.write8("wRogueFlagsBitfield", (flags | bit) if on else (flags & ~bit & 0xFF))
        h.write8("wWitchChallenge", self.ram["CHALLENGE_LEGENDARY_BOSS"] if on else 0)

    def _build(self, trainer_class):
        h = self.harness
        h.write8("wLegendaryBossSpecies", 0)
        h.write8("wTrainerClass", self.classes[trainer_class])
        h.write8("wTrainerNo", TRAINER_NO)
        h.call_routine("ReadTrainer", limit=4000)
        count = h.read8("wEnemyPartyCount")
        return count, h.read_bytes("wEnemyPartySpecies", count + 1)

    def test_every_eligible_leader_fields_a_legendary_from_its_pool(self):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self._set_challenge(True)
        stride = h.address("wEnemyMon2") - h.address("wEnemyMon1")
        for leader, pool in LEGENDARY_POOLS.items():
            with self.subTest(leader=leader):
                count, party = self._build(leader)
                self.assertGreater(count, 0)
                ace = party[count - 1]
                allowed = {self.species[s] for s in pool}
                self.assertIn(ace, allowed,
                              f"{leader}'s ace is {ace}, expected one of {pool}")
                self.assertEqual(h.read8("wLegendaryBossSpecies"), ace,
                                 "the trade byte must name the fielded ace")
                form = (h.read8("wEnemyMon1CatchRate",
                                offset=(count - 1) * stride) >> 5) & 0b11
                self.assertEqual(form, 0, "a swapped ace must carry no form")

    def test_no_swap_for_number_twins_or_without_the_challenge(self):
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        legendaries = {self.species[s] for pool in LEGENDARY_POOLS.values() for s in pool}
        self._set_challenge(True)
        for leader in NOT_ELIGIBLE:
            with self.subTest(leader=leader, challenge=True):
                count, party = self._build(leader)
                self.assertNotIn(party[count - 1], legendaries)
                self.assertEqual(h.read8("wLegendaryBossSpecies"), 0)
        self._set_challenge(False)
        for leader in ("SABRINA", "GIOVANNI"):
            with self.subTest(leader=leader, challenge=False):
                count, party = self._build(leader)
                self.assertNotIn(party[count - 1], legendaries)
                self.assertEqual(h.read8("wLegendaryBossSpecies"), 0)
