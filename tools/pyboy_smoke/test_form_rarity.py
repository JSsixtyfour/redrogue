"""Compiled identity valuation, conditional Mankey pools, and reward colours."""
import io
from pathlib import Path
import unittest
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_map_constants
import test_swinub_rarity as swinub

ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')
SPRITES = parse_rgbds_constants(ROOT / 'constants/sprite_constants.asm')
MAPS = parse_map_constants(ROOT / 'constants/map_constants.asm')

class FormRarityTest(unittest.TestCase):
    setUpClass = classmethod(swinub.SwinubRarityTest.setUpClass.__func__)
    tearDownClass = classmethod(swinub.SwinubRarityTest.tearDownClass.__func__)
    configure = swinub.SwinubRarityTest.configure
    entry = swinub.SwinubRarityTest.entry

    def classify(self, label, species, d):
        h = self.h
        bank, addr = h.symbols.get(label)
        def args(_):
            h.pyboy.register_file.D = d
            h.pyboy.register_file.E = SPECIES[species]
        h.pyboy.hook_register(bank, addr, args, None)
        try:
            h.call_routine(label)
        finally:
            h.pyboy.hook_deregister(bank, addr)
        return h.last_call_registers['E']

    def test_form_override_and_family_fallback(self):
        for species, form, expected in [('MAGNETON',0,1), ('MAGNETON',1,3),
                ('JIGGLYPUFF',0,1), ('JIGGLYPUFF',1,4), ('URSARING',1,4),
                ('QWILFISH',2,2), ('BEEDRILL',0,1), ('ANNIHILAPE',0,3)]:
            self.configure(7,7)
            self.assertEqual(self.classify('RogueClassifyIdentityFar', species, form), expected,
                             (species,form))

    def test_mankey_pools_and_whole_family_follow_warp(self):
        for unlocked in (1,3,5,7):
            for enabled in (1,3,5,7):
                boosted = bool(unlocked & enabled & 4)
                for tier in (0,1,2,3):
                    self.configure(unlocked,enabled)
                    _, pairs = self.entry(0,tier)
                    self.assertEqual(pairs.count((SPECIES['MANKEY'],0)),
                                     int(tier == (2 if boosted else 0)))
                for species in ('MANKEY','PRIMEAPE','ANNIHILAPE'):
                    self.configure(unlocked,enabled)
                    expected = 3 if boosted or species == 'ANNIHILAPE' else 1
                    self.assertEqual(self.classify('RogueClassifyIdentityFar',species,0),expected)

    def test_trade_reads_selected_party_and_box_form(self):
        for index, field in ((1,'wPartyMon2CatchRate'), (3,'wBoxMon2CatchRate')):
            for form, expected in ((0,1),(1,3)):
                self.configure(7,7)
                self.h.write8('wPartyCount',2)
                self.h.write8(field, (form << 5) | 0x10) # shiny bit must not affect rarity
                self.assertEqual(self.classify('RogueClassifyOwnedMonFar','MAGNETON',index),expected)

