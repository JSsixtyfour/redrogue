"""Reward offer DVs (custom_functions/reward_offer_info.asm).

Each reward offer slot (wRoguePokemon1-3) owns a DV pair in SRAM, rolled lazily
and keyed by species, so the INFO screen and the mon actually given agree.
Checks: a roll is tagged and stable, a new species re-rolls, the party path
(_AddPartyMon) writes exactly the stored pair, and the box path
(LoadEnemyMonData, used when the party is full) uses it too.

Kept to six call_routine invocations per boot (project_call_routine_harness_limits).
The DV Booster is not active on a fresh lobby boot, so floored == raw here.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

SRAM_BANK = 2  # "Reward Offer DVs SRAM", ram/sram.asm


class RewardOfferDVsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.harness.boot_to_lobby()

    def tearDown(self) -> None:
        self.harness.close()

    def offer_dvs(self, slot: int) -> list[int]:
        return self.harness.read_sram_bytes("sRogueOfferDVs", 6, bank=SRAM_BANK)[2 * slot : 2 * slot + 2]

    def tags(self) -> list[int]:
        return self.harness.read_sram_bytes("sRogueOfferDVTag", 3, bank=SRAM_BANK)

    def roll(self, slot_1_based: int) -> None:
        self.harness.pyboy.register_file.E = slot_1_based
        self.harness.call_routine("GetRogueOfferDVs", limit=2000)

    def test_offer_dvs_are_stable_and_given_on_both_paths(self) -> None:
        h = self.harness
        species = h.read8("wPartySpecies")  # any valid internal species
        other = h.read8("wPartySpecies", 1) if h.read8("wPartyCount") > 1 else species ^ 1
        self.assertNotEqual(species, other)

        h.call_routine("RogueOfferDVsClear", limit=2000)
        self.assertEqual(h.read_sram_bytes("sRogueOfferDVs", 9, bank=SRAM_BANK), [0] * 9)

        # Slot 2 (index 1): the roll tags the slot with the offered species.
        h.write8("wRoguePokemon2", species)
        self.roll(2)
        self.assertEqual(self.tags(), [0, species, 0])
        first = self.offer_dvs(1)
        self.assertEqual(self.offer_dvs(0), [0, 0], "other slots untouched")

        # Looking again does not re-roll.
        self.roll(2)
        self.assertEqual(self.offer_dvs(1), first)

        # Party path: _AddPartyMon takes the stored pair instead of rolling.
        count = min(h.read8("wPartyCount"), 5)  # the lobby fixture boots with a full party
        h.write8("wPartyCount", count)
        h.write8("wPartySpecies", 0xFF, offset=count)
        h.write8("wCurPartySpecies", species)
        h.write8("wCurEnemyLevel", 10)
        h.write8("wMonDataLocation", 0x10)  # player party, no naming screen
        h.write8("wSpawnForm", 0)
        h.write8("wSpawnDVSlot", 2)
        h.call_routine("_AddPartyMon", limit=60000)
        self.assertEqual(h.read8("wPartyCount"), count + 1)
        stride = h.address("wPartyMon2") - h.address("wPartyMon1")
        given = h.read_bytes("wPartyMon1DVs", 2, offset=stride * count)
        self.assertEqual(given, first, "given mon has the INFO screen's DVs")
        self.assertEqual(h.read8("wSpawnDVSlot"), 0, "spawn request consumed")

        # Box path: LoadEnemyMonData (outside battle) uses the same pair.
        h.write8("wEnemyBattleStatus3", 0)
        h.write8("wEnemyMonSpecies2", species)
        h.write8("wSpawnDVSlot", 2)
        h.call_routine("LoadEnemyMonData", limit=60000)
        self.assertEqual(h.read_bytes("wEnemyMonDVs", 2), first)
        h.write8("wSpawnDVSlot", 0)

        # A different species in the slot is a new offer: retagged (re-rolled).
        h.write8("wRoguePokemon2", other)
        self.roll(2)
        self.assertEqual(self.tags(), [0, other, 0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
