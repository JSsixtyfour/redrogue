"""The Warden's DETOX: one party mon loses a second POISON type, for good.

Runs the real gift dispatcher (BridgeDoGift) with only the party picker and the
text answered. Bit 2 keeps the stored monotype, so the checks here are the two
things bit 2 would otherwise get wrong: colour and the HUD mark. The stored pair's
own survival is in test_type_variant_lifecycle's VARIANTS.
"""
from __future__ import annotations

import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
import save_reload

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
SPECIES = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
TYPES = parse_rgbds_constants(ROOT / "constants/type_constants.asm")
PALETTES = parse_rgbds_constants(ROOT / "constants/palette_constants.asm")
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
MON = 44
GIFT_EVENT_BYTE, GIFT_EVENT_BIT = 26, 5  # EVENT_BRIDGE_RECEIVE_GIFT
DETOX_INDEX = 7  # WardenGiftList's eighth entry
VARIANT, SHINY = 4, 16
HUD_TILE = 8 * 20 + 13  # player HUD cell, hlcoord 13, 8
BOX_TO_PARTY, PARTY_TO_BOX = 0, 1


class WardenDetoxTest(unittest.TestCase):
    harness_args: dict = {}

    def setUp(self):
        self.h = h = RedRogueHarness(ROOT, ARTIFACTS, **self.harness_args)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.park_before_hijack()
        self.baseline = io.BytesIO()
        h.save_state(self.baseline)
        self.texts = 0
        self.picked = 1

        def return_now():
            regs, memory = h.pyboy.register_file, h.pyboy.memory
            sp = regs.SP
            regs.PC = memory[sp] | memory[sp + 1] << 8
            regs.SP = sp + 2

        def text(_):
            self.texts += 1
            return_now()

        def picker(_):
            h.write8("hWhichPokemon", self.picked)
            h.pyboy.register_file.F = 0  # carry clear: a mon was chosen
            return_now()

        h.pyboy.hook_register(*h.symbols.get("PrintText"), text, None)
        h.pyboy.hook_register(*h.symbols.get("BridgeSelectPartyMon"), picker, None)
        h.register_hook("BridgeDoGift", lambda _: setattr(h.pyboy.register_file, "A", 0))

    def restore(self):
        self.h.load_state(self.baseline)
        self.texts = 0

    def write_mon(self, slot, species, first, second, flags=0):
        h = self.h
        base = h.address("wPartyMons") + slot * MON
        memory = h.pyboy.memory
        memory[base] = SPECIES[species]
        memory[base + 5] = TYPES[first]
        memory[base + 6] = TYPES[second]
        memory[base + 7] = flags
        h.write8("wPartySpecies", SPECIES[species], offset=slot)
        return base

    def give(self, slot, species, first, second, flags=0):
        h = self.h
        self.restore()
        h.write8("wPartyCount", 3)
        for other in range(3):
            self.write_mon(other, "PIDGEY", "NORMAL", "FLYING")
        h.write8("wPartySpecies", 0xFF, offset=3)
        base = self.write_mon(slot, species, first, second, flags)
        registry = h.address("wBridgeSelectedEffects")
        h.pyboy.memory[registry:registry + 4] = [0, 0, 0, 0]
        h.write8("hCurMap", MAPS["WARDENS_HOUSE"])
        h.write8("wGift1", DETOX_INDEX)
        event = h.address("wEventFlags") + GIFT_EVENT_BYTE
        h.pyboy.memory[event] &= ~(1 << GIFT_EVENT_BIT)
        self.picked = slot
        before = list(h.pyboy.memory[base:base + MON])
        h.call_routine("BridgeDoGift", limit=8000)
        self.assertFalse(h.hook_errors, h.hook_errors)
        return base, before, bool(h.pyboy.memory[event] & 1 << GIFT_EVENT_BIT)

    def test_strips_only_the_chosen_mon_and_spends_no_registry_record(self):
        h = self.h
        for species, first in (("BULBASAUR", "GRASS"), ("VENUSAUR", "GRASS"), ("GLOOM", "GRASS"),
                               ("WEEDLE", "BUG"), ("GENGAR", "GHOST"), ("TENTACRUEL", "WATER")):
            for slot in (0, 2):
                with self.subTest(species=species, slot=slot):
                    base, before, given = self.give(slot, species, first, "POISON", flags=SHINY)
                    self.assertTrue(given, "the gift was not consumed")
                    after = list(h.pyboy.memory[base:base + MON])
                    self.assertEqual(after[5:8], [TYPES[first], TYPES[first], SHINY | VARIANT])
                    self.assertEqual(after[:5] + after[8:], before[:5] + before[8:])
                    self.assertEqual(h.read_bytes("wBridgeSelectedEffects", 4), [0, 0, 0, 0])
                    other = h.address("wPartyMons") + (1 * MON)
                    self.assertEqual(h.pyboy.memory[other + 6], TYPES["FLYING"], "another mon changed")
                    self.assertEqual(self.texts, 2, "its line, then the giver's goodbye")

    def test_refuses_anything_without_a_second_poison_type(self):
        h = self.h
        for species, first, second, flags in (("GRIMER", "POISON", "POISON", 0),
                                              ("GOLBAT", "POISON", "FLYING", 0),
                                              ("NIDOKING", "POISON", "GROUND", 0),
                                              ("CHARMANDER", "FIRE", "FIRE", 0),
                                              ("GASTLY", "GHOST", "GHOST", 1),
                                              ("BULBASAUR", "GRASS", "GRASS", VARIANT)):
            with self.subTest(species=species, flags=flags):
                base, before, given = self.give(1, species, first, second, flags)
                self.assertFalse(given, "a refused gift must not be consumed")
                self.assertEqual(list(h.pyboy.memory[base:base + MON]), before)
                self.assertEqual(self.texts, 1, "the refusal line")

    def test_a_stripped_mon_can_still_take_a_selected_effect(self):
        h = self.h
        self.give(1, "BULBASAUR", "GRASS", "POISON")
        h.write8("hWhichPokemon", 1)
        # At the entry: reaching the call can run frames first, and they use E.
        h.register_hook("BridgeGrantSelectedEffect",
                        lambda _: setattr(h.pyboy.register_file, "E", 1))  # ..._CRITICAL_RATE
        h.call_routine("BridgeGrantSelectedEffect")
        self.assertEqual(h.read_bytes("wBridgeSelectedEffects", 2), [2, 1])

    def palette_command(self, command, ready_label):
        h = self.h
        captured = []
        bank, address = h.symbols.get(ready_label)
        h.pyboy.hook_register(bank, address,
                              lambda _: captured.append(h.read_bytes("wPalPacket", 16)), None)
        try:
            h.call_routine(command, limit=4000)
        finally:
            h.pyboy.hook_deregister(bank, address)
        self.assertEqual(len(captured), 1)
        return captured[0]

    def status_colour(self, species, first, second, flags):
        h = self.h
        self.restore()
        h.write8("wCurPartySpecies", SPECIES[species])
        h.write8("wLoadedMon", SPECIES[species])
        h.write8("wLoadedMon", TYPES[first], offset=5)
        h.write8("wLoadedMon", TYPES[second], offset=6)
        h.write8("wLoadedMon", flags, offset=7)
        return self.palette_command("SetPal_StatusScreen", "SetPal_StatusScreen.notTypeVariant")[3]

    def battle_colours(self, species, first, second, flags):
        h = self.h
        self.restore()
        for mon in ("wBattleMon", "wEnemyMon"):
            h.write8(mon, SPECIES[species])
            h.write8(mon, TYPES[first], offset=5)
            h.write8(mon, TYPES[second], offset=6)
            h.write8(mon, flags, offset=7)
        h.write8("wEnemyMonSpecies2", SPECIES[species])
        h.write8("wPlayerBattleStatus3", 0)
        h.write8("wEnemyBattleStatus3", 0)
        packet = self.palette_command("SetPal_Battle", "SetPal_Battle.enemyNotTypeVariant")
        return packet[5], packet[7]

    def test_a_stripped_mon_keeps_its_own_colours_shiny_included(self):
        for species, first in (("IVYSAUR", "GRASS"), ("BEEDRILL", "BUG"), ("HAUNTER", "GHOST")):
            for shiny in (0, SHINY):
                with self.subTest(species=species, shiny=shiny):
                    plain = self.status_colour(species, first, "POISON", shiny)
                    self.assertEqual(self.status_colour(species, first, first, shiny | VARIANT), plain)
                    plain = self.battle_colours(species, first, "POISON", shiny)
                    self.assertEqual(self.battle_colours(species, first, first, shiny | VARIANT), plain)

    def test_authored_variants_keep_their_colours(self):
        for species, flags, first, second, expected in (
                ("SNORLAX", 12, "ICE", "ICE", "PAL_BLUEMON"),
                ("ONIX", 12, "ICE", "GROUND", "PAL_BLUEMON"),
                ("CHARIZARD", 12, "FIRE", "DRAGON", "PAL_BLACK"),
                ("PERSIAN", 4, "NORMAL", "WATER", "PAL_BLUEMON"),
                ("PSYDUCK", 12, "WATER", "PSYCHIC_TYPE", "PAL_PINKMON"),
                ("GOLDUCK", 12, "WATER", "PSYCHIC_TYPE", "PAL_PINKMON")):
            with self.subTest(species=species):
                self.assertEqual(self.status_colour(species, first, second, flags), PALETTES[expected])
                self.assertEqual(self.battle_colours(species, first, second, flags),
                                 (PALETTES[expected], PALETTES[expected]))

    def hud_mark(self, first, second, flags):
        h = self.h
        self.restore()
        h.write8("wBattleMon", SPECIES["IVYSAUR"])
        h.write8("wBattleMon", TYPES[first], offset=5)
        h.write8("wBattleMon", TYPES[second], offset=6)
        h.write8("wBattleMon", flags, offset=7)
        h.write8("wTileMap", 0x7F, offset=HUD_TILE)

        def player_side(_):
            h.pyboy.register_file.E = 0xFF

        h.register_hook("DrawBattleVariantMarker", player_side)
        h.call_routine("DrawBattleVariantMarker", limit=1000)
        h.unregister_hook("DrawBattleVariantMarker", player_side)
        return h.read8("wTileMap", offset=HUD_TILE)

    def test_a_stripped_mon_has_no_type_mark_but_keeps_the_shiny_one(self):
        self.assertEqual(self.hud_mark("GRASS", "GRASS", VARIANT), 0x7F)
        shiny = self.hud_mark("GRASS", "POISON", SHINY)
        self.assertNotEqual(shiny, 0x7F)
        self.assertEqual(self.hud_mark("GRASS", "GRASS", VARIANT | SHINY), shiny)
        self.assertNotIn(self.hud_mark("ICE", "ICE", VARIANT), (0x7F, shiny), "Ice Snorlax keeps a mark")
        self.assertNotIn(self.hud_mark("WATER", "PSYCHIC_TYPE", VARIANT), (0x7F, shiny))

    def test_the_box_keeps_it_both_ways(self):
        """Deposit and withdraw through the real _MoveMon, then evolve it out of the box."""
        h = self.h
        base, _, given = self.give(1, "BULBASAUR", "GRASS", "POISON", flags=SHINY)
        self.assertTrue(given)
        stripped = list(h.pyboy.memory[base:base + 8])
        h.write8("wBoxCount", 0)
        h.write8("wBoxSpecies", 0xFF)
        h.write8("wCurPartySpecies", SPECIES["BULBASAUR"])
        h.write8("hWhichPokemon", 1)
        h.write8("wMoveMonType", PARTY_TO_BOX)
        h.call_routine("_MoveMon", limit=4000)
        self.assertEqual(h.read8("wBoxCount"), 1)
        boxed = h.read_bytes("wBoxMon1", 8)
        self.assertEqual(boxed[:3] + boxed[4:], stripped[:3] + stripped[4:])  # 3 is the box's level
        h.write8("wPartyCount", 2)
        h.write8("wPartySpecies", 0xFF, offset=2)
        h.write8("hWhichPokemon", 0)
        h.write8("wCurPartySpecies", SPECIES["BULBASAUR"])
        h.write8("wMoveMonType", BOX_TO_PARTY)
        h.call_routine("_MoveMon", limit=4000)
        back = h.address("wPartyMons") + 2 * MON
        self.assertEqual(h.read8("wPartyCount"), 3)
        withdrawn = list(h.pyboy.memory[back:back + 8])
        self.assertEqual(withdrawn[:3] + withdrawn[4:], stripped[:3] + stripped[4:])
        h.write8("wPokedexNum", SPECIES["VENUSAUR"])
        h.write8("wPredefHL", back >> 8)
        h.write8("wPredefHL", back & 255, offset=1)
        h.call_routine("SetPartyMonTypes", limit=4000)
        self.assertEqual(list(h.pyboy.memory[back + 5:back + 8]),
                         [TYPES["GRASS"], TYPES["GRASS"], SHINY | VARIANT])

    def test_it_survives_a_save_and_reload(self):
        h = self.h
        base, _, given = self.give(1, "BULBASAUR", "GRASS", "POISON")
        self.assertTrue(given)
        h.write8("hCurMap", MAPS["INDIGO_PLATEAU_LOBBY"])
        h.pyboy.hook_deregister(*h.symbols.get("PrintText"))
        h.pyboy.hook_deregister(*h.symbols.get("BridgeSelectPartyMon"))
        saved = h.read_bytes("wPartyMon2", 8)
        h.park_before_hijack()
        h.call_routine("SaveGameData")
        reboot = save_reload.Reboot(save_reload.sram_image(h), cgb_mode=h.hardware_mode == "CGB")
        try:
            reboot.load()
            self.assertEqual(reboot.h.read_bytes("wPartyMon2", 8), saved)
            self.assertEqual(saved[5:7], [TYPES["GRASS"], TYPES["GRASS"]])
            self.assertTrue(saved[7] & VARIANT)
        finally:
            reboot.close()


if __name__ == "__main__":
    unittest.main()
