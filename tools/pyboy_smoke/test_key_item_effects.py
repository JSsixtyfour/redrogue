"""Focused key-item activation and run-boundary counter contracts.

These checks exercise shared key-item state plumbing. They do not count as
per-item trigger/effect coverage; see AUTOPLAY_KEY_ITEM_EFFECT_LEDGER_2026-11-01.md.
"""
from __future__ import annotations
import io
from itertools import combinations

from source_constants import parse_rgbds_constants
from routine_session import isolated_routine_calls
from test_key_item_equipment import ITEMS, NAMES, bits
from test_smoke import HarnessTestCase, REPO_ROOT


RAM = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")
TYPES = parse_rgbds_constants(REPO_ROOT / "constants/type_constants.asm")
LIVE_TIERS = range(3)  # internal 0/1/2 = displayed TIER 1/2/3


def tier_bytes(item: str, tier: int) -> list[int]:
    """Pack one item's internal tier into sKeyItemTiers' four-byte layout."""
    bit = RAM[f"KEY_ITEM_BIT_{item}_OWNED"]
    index = bit // 2
    packed = [0] * 4
    packed[index // 4] = tier << ((index % 4) * 2)
    return packed


def all_tiers(values: dict[str, int]) -> list[int]:
    packed = [0] * 4
    for item, tier in values.items():
        bit = RAM[f"KEY_ITEM_BIT_{item}_OWNED"]
        index = bit // 2
        packed[index // 4] |= tier << ((index % 4) * 2)
    return packed


class KeyItemEffectLifecycleTest(HarnessTestCase):
    def boot(self):
        self.harness.boot_fight2(seed=17)
        return self.harness

    def power(self, item: str) -> int:
        h = self.harness
        h.write8("wCurItem", ITEMS[item])
        h.call_routine("GetKeyItemPowerInE")
        return h.last_call_registers["E"]

    def test_every_item_live_tier_loadout_survives_endless_and_refills_on_ordinary_reset(self):
        h=self.harness
        h.boot_to_lobby()
        with isolated_routine_calls(h):
            baseline=io.BytesIO()
            h.save_state(baseline)
            for tier in LIVE_TIERS:
                for index in range(0,len(NAMES),3):
                    active=NAMES[index:index+3]
                    with self.subTest(tier=tier,active=active):
                        # Each case starts from a coherent rolled lobby. An
                        # ordinary reset clears the lineup and must be followed
                        # by normal initialization before another Champion clear.
                        h.load_state(io.BytesIO(baseline.getvalue()))
                        flags=bits(NAMES,active)
                        tiers=all_tiers({name:tier for name in NAMES})
                        h.write_sram_bytes('sKeyItemsBitfield',flags)
                        h.write_sram_bytes('sKeyItemTiers',tiers)
                        h.write8('wEndlessDepth',0)
                        h.write8('wRogueFlagsBitfield',0)
                        h.write8('wKODefianceUsages',0)
                        h.write8('wTurnRewindUsages',1)
                        h.write8('wDiceCharges',0x10)
                        h.write8('wHealAllItemLevel',(0,4,8)[tier])
                        h.write8('wRestorePPItemLevel',tier*2)
                        fields=('wKODefianceUsages','wTurnRewindUsages','wDiceCharges',
                                'wHealAllItemLevel','wRestorePPItemLevel')
                        before={name:h.read8(name) for name in fields}
                        party=h.read_bytes('wPartyDataStart',h.address('wPartyDataEnd')-h.address('wPartyDataStart'))
                        h.call_routine('EndlessContinue',limit=60000)
                        self.assertEqual(h.read8('wEndlessDepth'),1)
                        self.assertEqual({name:h.read8(name) for name in fields},before)
                        self.assertEqual(h.read_sram_bytes('sKeyItemsBitfield',4),flags)
                        self.assertEqual(h.read_sram_bytes('sKeyItemTiers',4),tiers)
                        self.assertEqual(h.read_bytes('wPartyDataStart',len(party)),party)
                        h.call_routine('RogueResetRunState')
                        self.assertEqual(h.read8('wEndlessDepth'),0)
                        self.assertEqual(h.read8('wKODefianceUsages'),tier+1)
                        self.assertEqual(h.read8('wTurnRewindUsages'),tier+2)
                        self.assertEqual(h.read8('wDiceCharges'),(tier+1)*0x15)
                        self.assertEqual(h.read_sram_bytes('sKeyItemsBitfield',4),flags)
                        self.assertEqual(h.read_sram_bytes('sKeyItemTiers',4),tiers)

    def test_every_item_inactive_pc_ownership_is_absent_from_field_and_battle_use_lists(self):
        h=self.boot()
        with isolated_routine_calls(h):
            h.write8('wRecoveryItemCounts',0,20)  # separate Poke Flute slot
            for item in NAMES:
                for tier in LIVE_TIERS:
                    for active in (False,True):
                        with self.subTest(item=item,tier=tier,active=active):
                            h.write_sram_bytes('sKeyItemsBitfield',bits([item],[item] if active else []))
                            h.write_sram_bytes('sKeyItemTiers',tier_bytes(item,tier))
                            expected=[1,ITEMS[item],1,255] if active else [0,255]
                            for routine,buffer in (('BuildKeyItemPocketList','wKeyItemPocketBuf'),
                                                   ('BuildBattleItemList','wBattleItemList')):
                                h.call_routine(routine)
                                self.assertEqual(h.read_bytes(buffer,len(expected)),expected)

    def test_all_item_pairs_keep_independent_tiers_and_shared_bag_list(self):
        h=self.boot()
        with isolated_routine_calls(h):
            for first,second in combinations(NAMES,2):
                for tier in LIVE_TIERS:
                    with self.subTest(first=first,second=second,tier=tier):
                        flags=bits(NAMES,[first,second])
                        tiers=all_tiers({first:tier,second:(tier+1)%3})
                        h.write_sram_bytes('sKeyItemsBitfield',flags)
                        h.write_sram_bytes('sKeyItemTiers',tiers)
                        self.assertEqual(self.power(first),tier+1)
                        self.assertEqual(self.power(second),(tier+1)%3+1)
                        h.call_routine('BuildKeyItemPocketList')
                        self.assertEqual(h.read_bytes('wKeyItemPocketBuf',6),
                                         [2,ITEMS[first],1,ITEMS[second],1,255])
                        self.assertEqual(h.read_sram_bytes('sKeyItemsBitfield',4),flags)
                        self.assertEqual(h.read_sram_bytes('sKeyItemTiers',4),tiers)

    def test_every_item_power_requires_active_loadout_and_tracks_live_tiers(self) -> None:
        h = self.boot()
        for item in NAMES:
            for tier in LIVE_TIERS:
                with self.subTest(item=item, tier=tier, active=False):
                    h.write_sram_bytes("sKeyItemTiers", tier_bytes(item, tier))
                    h.write_sram_bytes("sKeyItemsBitfield", bits([item], []))
                    self.assertEqual(self.power(item), 0, "PC ownership alone is inactive")

                with self.subTest(item=item, tier=tier, active=True):
                    h.write_sram_bytes("sKeyItemTiers", tier_bytes(item, tier))
                    h.write_sram_bytes("sKeyItemsBitfield", bits([item], [item]))
                    self.assertEqual(self.power(item), tier + 1)

    def test_blackout_reset_rederives_tiers_and_refills_spent_counters(self) -> None:
        h = self.boot()
        owned = list(NAMES)
        active = ["LEFTOVERS", "PP_TONIC", "ELEMENT_PRISM"]
        tiers = all_tiers({
            "LEFTOVERS": 2,
            "PP_TONIC": 1,
            "KO_DEFIANCE": 2,
            "TURN_REWIND": 1,
            "DOOR_DICE": 0,
            "MON_DICE": 1,
            "ITEM_DICE": 2,
            "ELEMENT_PRISM": 2,
        })
        flags = bits(owned, active)
        h.write_sram_bytes("sKeyItemsBitfield", flags)
        h.write_sram_bytes("sKeyItemTiers", tiers)
        h.write_sram_bytes("sElementPrismType", [TYPES["FIRE"]])
        h.write_sram_bytes("sPrismCartridges", [0, 1])  # FIRE is cartridge index 8
        h.write8("wHealAllItemLevel", 0)
        h.write8("wRestorePPItemLevel", 0)
        h.write8("wKODefianceUsages", 0)
        h.write8("wTurnRewindUsages", 0)
        h.write8("wDiceCharges", 0)

        h.call_routine("RogueResetRunState")

        self.assertEqual(h.read_sram_bytes("sKeyItemsBitfield", 4), flags)
        self.assertEqual(h.read_sram_bytes("sKeyItemTiers", 4), tiers)
        self.assertEqual(h.read8("wHealAllItemLevel"), 8)  # LEFTOVERS TIER 3: 1/8 HP
        self.assertEqual(h.read8("wRestorePPItemLevel"), 2)  # PP TONIC TIER 2: 1/14 PP
        self.assertEqual(h.read8("wKODefianceUsages"), 3)  # 1 + internal tier 2
        self.assertEqual(h.read8("wTurnRewindUsages"), 3)  # 2 + internal tier 1
        self.assertEqual(h.read8("wDiceCharges"), 1 | (2 << 2) | (3 << 4))
        self.assertEqual(h.read8("wPrismType"), TYPES["FIRE"])

    def test_element_prism_refresh_retains_each_selected_tier_bonus(self) -> None:
        """Legal active loadouts must keep the authored 10/15/20 percent cache.

        This is a routine fixture, not an actual battle activation journey.
        A failure is retained as a contract finding; no game rule is changed.
        """
        h = self.boot()
        for tier, expected in enumerate((10, 15, 20)):
            with self.subTest(tier=tier):
                h.write_sram_bytes('sKeyItemsBitfield', bits(['ELEMENT_PRISM'], ['ELEMENT_PRISM']))
                h.write_sram_bytes('sKeyItemTiers', tier_bytes('ELEMENT_PRISM', tier))
                h.write_sram_bytes('sElementPrismType', [TYPES['FIRE']])
                h.write_sram_bytes('sPrismCartridges', [0, 1])
                h.call_routine('RoguePrismRefreshCache')
                self.assertEqual(h.read8('wPrismType'), TYPES['FIRE'])
                self.assertEqual(h.read8('wPrismDamageBonus'), expected)

    def test_element_prism_tier_damage_and_inactive_controls(self) -> None:
        """Exercise the refreshed cache's consumer, with exact damage deltas."""
        h = self.boot()
        with isolated_routine_calls(h):
            self._check_prism_damage_controls(h)

    def _check_prism_damage_controls(self, h) -> None:
        species = h.read8('wCurPartySpecies')
        for tier, bonus in enumerate((10, 15, 20)):
            for active, selected, move, expected in (
                (True, TYPES['FIRE'], TYPES['FIRE'], 100 + bonus),
                (True, TYPES['FIRE'], TYPES['WATER'], 100),
                (False, TYPES['FIRE'], TYPES['FIRE'], 100),
                (True, 0xff, TYPES['FIRE'], 100),
            ):
                with self.subTest(tier=tier, active=active, selected=selected, move=move):
                    h.write_sram_bytes('sKeyItemsBitfield', bits(['ELEMENT_PRISM'],
                        ['ELEMENT_PRISM'] if active else []))
                    h.write_sram_bytes('sKeyItemTiers', tier_bytes('ELEMENT_PRISM', tier))
                    h.write_sram_bytes('sElementPrismType', [selected])
                    h.write_sram_bytes('sPrismCartridges', [0, 1])
                    h.write8('wCurPartySpecies', species)
                    h.call_routine('RoguePrismRefreshCache')
                    self.assertEqual(h.read8('wCurPartySpecies'), species)
                    h.write8('wMoveType', move)
                    h.write8('wDamage', 0)
                    h.write8('wDamage', 100, 1)
                    h.call_routine('RoguePrismDamageBoost')
                    self.assertEqual(h.read_bytes('wDamage', 2), [0, expected])


if __name__ == "__main__":
    import unittest

    unittest.main(verbosity=2)
