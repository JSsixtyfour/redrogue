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


class StatPocketSlotsTest(HarnessTestCase):
    """NUM_STAT_ITEMS read 15 while StatItemTable held 18, so PP UP, M.GENE and
    M.TOME (table entries 15-17) were counted in wValuableItemCounts[0-2] - the
    Pearl, Big Pearl and Nugget counts - and never listed in the Stat pocket."""

    def test_last_stat_items_count_in_their_own_pocket(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        stat_slots = parse_rgbds_constants(
            REPO_ROOT / "constants" / "ram_constants.asm"
        )["STAT_ITEM_SLOTS"]
        for i in range(stat_slots):
            h.write8("wStatItemCounts", 0, offset=i)
        for i in range(4):
            h.write8("wValuableItemCounts", 0, offset=i)
        for name in ("PP_UP", "M_GENE", "M_TOME"):
            h.write8("wCurItem", ITEMS[name])
            h.write8("wItemQuantity", 1)
            h.call_routine("GiveStatItem")
        self.assertEqual(h.read_bytes("wStatItemCounts", 3, offset=15), [1, 1, 1])
        self.assertEqual(h.read_bytes("wValuableItemCounts", 4), [0, 0, 0, 0])
        h.call_routine("BuildStatPocketList")
        count = h.read8("wStatPocketBuf")
        listed = h.read_bytes("wStatPocketBuf", count * 2 + 1, offset=1)
        self.assertEqual(
            listed,
            [ITEMS["PP_UP"], 1, ITEMS["M_GENE"], 1, ITEMS["M_TOME"], 1, 0xFF],
        )


class BattleItemListTest(HarnessTestCase):
    """The battle ITEM list used to be built into wKeyItemPocketBuf, which sits in
    the enemy-party UNION over wEnemyMon4's stats and most of wEnemyMon5, so
    opening ITEM against a trainer with 5+ mons corrupted the 5th before it was
    sent out. It now has its own wBattleItemList."""

    KEY_ITEMS = ("LEFTOVERS", "PP_TONIC", "KO_DEFIANCE", "SHINY_CHARM", "AMULET_COIN")

    def test_battle_list_leaves_the_enemy_party_alone(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=17)
        self.assertEqual(h.read8("wEnemyPartyCount"), 6)
        ram = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")
        bits = [0, 0, 0, 0]
        for name in self.KEY_ITEMS:  # five owned AND active: more than the cap of 3
            bit = ram[f"KEY_ITEM_BIT_{name}_OWNED"]
            for b in (bit, bit + 1):
                bits[b // 8] |= 1 << (b % 8)
        h.write_sram_bytes("sKeyItemsBitfield", bits)
        h.write8("wRecoveryItemCounts", 1, offset=20)  # POKE FLUTE's slot
        enemy_start = h.address("wEnemyPartyCount")
        enemy_len = h.address("wEnemyMonNicks") + 6 * 11 - enemy_start
        before = h.read_bytes("wEnemyPartyCount", enemy_len)

        h.call_routine("BuildBattleItemList")

        after = h.read_bytes("wEnemyPartyCount", enemy_len)
        changed = [hex(enemy_start + i) for i, (b, a) in enumerate(zip(before, after)) if b != a]
        self.assertEqual(changed, [], "the battle ITEM list wrote into the enemy party")
        cap = ram["KEY_ITEM_MAX_ACTIVE"]
        first = [ITEMS[name] for name in self.KEY_ITEMS[:cap]]
        expected = [cap + 1]
        for item in first + [ITEMS["POKE_FLUTE"]]:
            expected += [item, 1]
        expected.append(0xFF)
        size = h.address("wBattleItemListEnd") - h.address("wBattleItemList")
        self.assertEqual(len(expected), size, "wBattleItemList is sized for the cap plus the flute")
        self.assertEqual(h.read_bytes("wBattleItemList", size), expected)

        # The field bag's key pocket still builds into its own buffer, same cap.
        h.call_routine("BuildKeyItemPocketList")
        bag = [cap] + sum(([item, 1] for item in first), []) + [0xFF]
        self.assertEqual(h.read_bytes("wKeyItemPocketBuf", len(bag)), bag)


if __name__ == "__main__":
    unittest.main()
