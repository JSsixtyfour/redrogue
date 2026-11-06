"""Stored type-pair consumers for Dragon, Crystal, Ice and generic variants."""
from __future__ import annotations

import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
SPECIES = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
TYPES = parse_rgbds_constants(ROOT / "constants/type_constants.asm")
# species, flag byte, authored type1, authored type2
VARIANTS = (("ONIX", 12, "ICE", "GROUND"),
            ("SNORLAX", 12, "ICE", "ICE"),
            ("CHARIZARD", 12, "FIRE", "DRAGON"),
            ("PERSIAN", 4, "NORMAL", "WATER"),
            ("RATICATE", 4, "NORMAL", "ROCK"),
            ("GOLDUCK", 12, "WATER", "PSYCHIC_TYPE"),
            # The Warden's DETOX: a second POISON type gone for good.
            ("IVYSAUR", 4, "GRASS", "GRASS"),
            ("BEEDRILL", 20, "BUG", "BUG"))


class TypeVariantLifecycleTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.boot_to_lobby()
        self.baseline = io.BytesIO()
        self.h.save_state(self.baseline)

    def tearDown(self):
        self.h.close()

    def restore(self):
        self.h.load_state(self.baseline)

    def pair(self, first, second):
        return TYPES[first], TYPES[second]

    def write_mon(self, label, species, flags, first, second):
        h = self.h
        h.write8(label, SPECIES[species])
        h.write8(label, TYPES[first], offset=5)
        h.write8(label, TYPES[second], offset=6)
        h.write8(label, flags, offset=7)

    def saved_predef_pointer(self, address):
        # GetPredefRegisters stores high byte first, unlike ordinary GB words.
        self.h.write8("wPredefHL", address >> 8)
        self.h.write8("wPredefHL", address & 255, offset=1)

    def test_header_consumer_restores_both_slots_and_rejects_stale_species(self):
        h = self.h
        cases = [(*variant, variant[0], self.pair(variant[2], variant[3])) for variant in VARIANTS]
        cases += [("ONIX", 0, "ICE", "ICE", "ONIX", self.pair("ROCK", "GROUND")),
                  ("ONIX", 8, "ICE", "ICE", "ONIX", self.pair("ROCK", "GROUND")),
                  ("ONIX", 12, "ICE", "GROUND", "SNORLAX", self.pair("ROCK", "GROUND"))]
        for species, flags, first, second, current, expected in cases:
            with self.subTest(species=species, flags=flags, current=current):
                self.restore()
                self.write_mon("wLoadedMon", species, flags, first, second)
                h.write8("wCurSpecies", SPECIES[current])
                h.write8("wMonHType1", TYPES["ROCK"])
                h.write8("wMonHType2", TYPES["GROUND"])
                h.call_routine("ApplyStoredTypeVariantToHeader", limit=1000)
                self.assertEqual((h.read8("wMonHType1"), h.read8("wMonHType2")), expected)

    def test_actual_status_type_printer_uses_both_stored_slots(self):
        h = self.h
        for species, flags, first, second in VARIANTS:
            with self.subTest(species=species):
                self.restore()
                self.write_mon("wLoadedMon", species, flags, first, second)
                h.write8("wCurSpecies", SPECIES[species])
                self.saved_predef_pointer(h.address("wTileMap") + 20)
                captured = []
                bank, address = h.symbols.get("PrintType")
                h.pyboy.hook_register(bank, address, lambda _: captured.append(
                    (h.read8("wMonHType1"), h.read8("wMonHType2"))), None)
                try:
                    h.call_routine("PrintMonType", limit=4000)
                finally:
                    h.pyboy.hook_deregister(bank, address)
                self.assertTrue(captured)
                self.assertTrue(all(pair == self.pair(first, second) for pair in captured))

    def test_enemy_reload_restores_both_slots_without_changing_legacy_ghost_priority(self):
        h = self.h
        cases = [(*variant, self.pair(variant[2], variant[3])) for variant in VARIANTS]
        cases += [("ONIX", 0, "ICE", "ICE", self.pair("ROCK", "GROUND")),
                  ("ONIX", 8, "ICE", "ICE", self.pair("ROCK", "GROUND")),
                  ("ONIX", 13, "ICE", "GROUND", self.pair("ICE", "GHOST")),
                  ("PERSIAN", 5, "NORMAL", "WATER", self.pair("NORMAL", "GHOST"))]
        for species, flags, first, second, expected in cases:
            with self.subTest(species=species, flags=flags):
                self.restore()
                h.write8("hIsInBattle", 2)
                h.write8("hWhichPokemon", 1)
                self.write_mon("wEnemyMon2", species, flags, first, second)
                h.write8("wEnemyMonType1", TYPES["ROCK"])
                h.write8("wEnemyMonType2", TYPES["GROUND"])
                h.call_routine("GetEnemyCatchRateByte", limit=1000)
                self.assertEqual(h.last_call_registers["E"], flags)
                self.assertEqual((h.read8("wEnemyMonType1"), h.read8("wEnemyMonType2")), expected)

    def test_actual_evolution_type_consumer_preserves_both_variant_slots(self):
        h = self.h
        # Crystal Onix evolving to Steelix deliberately retains Ice/Ground,
        # following the same stored-pair rule as the existing Dragon gifts.
        cases = [(*variant, "STEELIX" if variant[0] == "ONIX" else variant[0],
                  self.pair(variant[2], variant[3])) for variant in VARIANTS]
        cases += [("ONIX", 0, "ICE", "ICE", "ONIX", self.pair("ROCK", "GROUND")),
                  ("ONIX", 8, "ICE", "ICE", "ONIX", self.pair("ROCK", "GROUND")),
                  ("ONIX", 1, "ICE", "ICE", "ONIX", self.pair("ROCK", "GHOST")),
                  ("GLOOM", 4, "GRASS", "GRASS", "VILEPLUME", self.pair("GRASS", "GRASS")),
                  ("GLOOM", 4, "GRASS", "GRASS", "BELLOSSOM", self.pair("GRASS", "GRASS"))]
        for species, flags, first, second, target, expected in cases:
            with self.subTest(species=species, flags=flags, target=target):
                self.restore()
                self.write_mon("wPartyMon1", species, flags, first, second)
                h.write8("wPokedexNum", SPECIES[target])
                self.saved_predef_pointer(h.address("wPartyMon1"))
                h.call_routine("SetPartyMonTypes", limit=4000)
                actual = (h.read8("wPartyMon1", offset=5), h.read8("wPartyMon1", offset=6))
                self.assertEqual(actual, expected)
                self.assertEqual(h.read8("wPartyMon1", offset=7), flags)
