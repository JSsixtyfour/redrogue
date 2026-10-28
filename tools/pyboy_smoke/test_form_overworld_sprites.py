#!/usr/bin/env python3
"""Forms that share an overworld sheet (2026-10-27).

PCGetDedicatedPokemonSprite resolves a form only through its .formSprites
list: Galarian Mr. Mime -> the Mr. Mime sheet, Armored Mewtwo -> the Mewtwo
sheet. Every other form, and every fusion or special form, keeps the category
fallback. Driven through FollowerResolveLeadPicture so the follower's
catch-rate bits -> form index normalisation is measured too.
"""

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants


ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')
SPRITES = parse_rgbds_constants(ROOT / 'constants/sprite_constants.asm')
FORM_1 = 0b00100000      # MON_CATCH_RATE bits 5-6 = form 1
FUSION_BITS = 0b00001010  # fusion bit, special-form bit


class FormOverworldSpritesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        cls.h.boot_to_lobby()

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def run_direct(self, label, **regs_in):
        """Run one routine to its `ret` through a `jr @` stub with IE masked
        (reference_pyboy_direct_stub_executor); returns A, D, E and carry."""
        h = self.h
        regs, mem = h.pyboy.register_file, h.pyboy.memory
        stub = h.address('wStringBuffer') + 16
        mem[stub], mem[stub + 1] = 0x18, 0xFE  # jr @
        mem[0xFFFF] = 0
        bank, addr = h.symbols.get(label)
        h.write8('hLoadedROMBank', bank)
        mem[0x2000] = bank
        sp = (regs.SP - 2) & 0xFFFF
        mem[sp], mem[sp + 1] = stub & 0xFF, stub >> 8
        regs.SP = sp
        for name, value in regs_in.items():
            setattr(regs, name, value)
        regs.PC = addr
        for _ in range(20):
            h.pyboy.tick()
            if regs.PC == stub:
                break
        self.assertEqual(regs.PC, stub, f'{label} did not return')
        self.assertEqual(regs.SP, (sp + 2) & 0xFFFF, f'{label} unbalanced the stack')
        out = {name: getattr(regs, name) for name in ('A', 'D', 'E')}
        out['carry'] = bool(regs.F & 0x10)
        return out

    def follower_picture(self, species, catch_rate_bits):
        h = self.h
        h.write8('wPartyCount', 1)
        h.write8('wPartySpecies', SPECIES[species])
        h.write8('wPartySpecies', 0xFF, offset=1)
        h.write8('wPartyMon1HP', 0)
        h.write8('wPartyMon1HP', 50, offset=1)
        h.write8('wPartyMon1CatchRate', catch_rate_bits)
        return self.run_direct('FollowerResolveLeadPicture')

    def test_follower_form_sheets(self):
        cases = [
            ('MR_MIME', 0, 'SPRITE_MR_MIME'),
            ('MR_MIME', FORM_1, 'SPRITE_MR_MIME'),       # Galarian Mr. Mime
            ('MR_RIME', 0, 'SPRITE_MR_MIME'),
            ('MEWTWO', 0, 'SPRITE_MEWTWO'),
            ('MEWTWO', FORM_1, 'SPRITE_MEWTWO'),         # Armored Mewtwo
            ('MR_MIME', FORM_1 | 0b00001000, None),      # special form: fallback
            ('MR_MIME', 0b00000010, None),               # fusion: fallback
            ('FARFETCHD', 0, None),                      # no sheet at all
            ('GRIMER', FORM_1, None),                    # unlisted form: fallback
        ]
        for species, bits, sprite in cases:
            with self.subTest(species=species, bits=bits):
                out = self.follower_picture(species, bits)
                self.assertTrue(out['carry'])
                if sprite is None:
                    self.assertNotIn(out['E'], (SPRITES['SPRITE_MR_MIME'], SPRITES['SPRITE_MEWTWO']))
                else:
                    self.assertEqual(out['E'], SPRITES[sprite])

    def test_lookup_takes_a_form_index(self):
        # The cave/boss encoding: D = wRoguePokemonForm1's plain form index.
        for species, form, sprite in [('MR_MIME', 1, 'SPRITE_MR_MIME'),
                                      ('MEWTWO', 1, 'SPRITE_MEWTWO'),
                                      ('MR_MIME', 2, None),
                                      ('MR_MIME', 0xFF, None)]:
            with self.subTest(species=species, form=form):
                out = self.run_direct('PCGetDedicatedPokemonSprite', D=form, E=SPECIES[species])
                if sprite is None:
                    self.assertFalse(out['carry'])
                    self.assertEqual(out['E'], SPECIES[species])
                else:
                    self.assertTrue(out['carry'])
                    self.assertEqual(out['E'], SPRITES[sprite])


if __name__ == '__main__':
    unittest.main()
