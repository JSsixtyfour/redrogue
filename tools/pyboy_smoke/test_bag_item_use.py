"""Bag item-use regressions (BAG_SYSTEM_OVERVIEW_2026-10-03.md, step 1).

1. RemoveUsedItem used to run vanilla RemoveItemFromInventory on the legacy
   wNumBagItems stub after the real pocket removal. That routine removes by
   SLOT, taking the slot from hWhichPokemon, which at that point is the item's
   position in its pocket list. Every consumed item therefore decremented the
   saved byte at wBagItems+1+2*index: index 3 is wBagPocketsFlags, 11 is
   wObtainedBadges, 18-20 are the current map's tileset/width/data pointer.
2. MistStoneChooseEvolution read the species from wCurPartySpecies, which is
   also wCurItem, and ItemUseEvoStone writes the stone's id back into it after
   the party menu. It saw MIST_STONE ($76, internal DUGTRIO), offered nothing,
   and the stone was never used.
"""
import unittest

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

ITEMS = parse_rgbds_constants(REPO_ROOT / "constants" / "item_constants.asm")
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")

# From the legacy stub through the end of the current-map header: every byte the
# old index-based removal could reach from a 21-entry Recovery list.
GUARD_START = "wNumBagItems"
GUARD_END = "wCurMapDataPtr"


class RemoveUsedItemTest(HarnessTestCase):
    def test_consuming_an_item_touches_only_its_pocket_count(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        potion_slot = 0  # RecoveryItemTable index of POTION
        guard_length = h.address(GUARD_END) + 2 - h.address(GUARD_START)
        # List indices that used to land on wBagPocketsFlags, wObtainedBadges and
        # the three map-header bytes, plus 0 (the legacy terminator).
        for list_index in (0, 3, 11, 18, 19, 20):
            with self.subTest(list_index=list_index):
                h.write8("wRecoveryItemCounts", 9, offset=potion_slot)
                h.write8("wCurItem", ITEMS["POTION"])
                h.write8("hWhichPokemon", list_index)
                before = h.read_bytes(GUARD_START, guard_length)
                h.call_routine("RemoveUsedItem")
                self.assertEqual(
                    h.read8("wRecoveryItemCounts", offset=potion_slot), 8,
                    "the POTION count should drop by exactly one",
                )
                after = h.read_bytes(GUARD_START, guard_length)
                changed = [
                    f"{GUARD_START}+{i}: {b:02x}->{a:02x}"
                    for i, (b, a) in enumerate(zip(before, after))
                    if b != a
                ]
                self.assertEqual(changed, [], "saved bytes past the legacy bag changed")


class MistStoneSpeciesTest(HarnessTestCase):
    def test_chooser_reads_the_picked_party_mon_not_the_item_byte(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        mist = ITEMS["MIST_STONE"]
        eevee_stones = {
            ITEMS[name]
            for name in (
                "FIRE_STONE", "THUNDER_STONE", "WATER_STONE", "LEAF_STONE",
                "SUN_STONE", "DUSK_STONE", "ICE_STONE", "MOON_STONE",
            )
        }
        party_slot = 1
        h.write8("wPartySpecies", SPECIES["EEVEE"], offset=party_slot)
        h.write8("hWhichPokemon", party_slot)
        # The real state after ItemUseEvoStone's party menu: the shared
        # wCurItem/wCurPartySpecies byte holds the stone, not the species.
        h.write8("wCurPartySpecies", mist)
        h.write8("wEvoStoneItemID", mist)
        h.call_routine("MistStoneChooseEvolution")
        chosen = h.read8("wEvoStoneItemID")
        self.assertIn(
            chosen, eevee_stones,
            f"Eevee should roll a real stone, got ${chosen:02x}",
        )


if __name__ == "__main__":
    unittest.main()
