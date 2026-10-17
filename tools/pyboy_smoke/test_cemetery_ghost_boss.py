"""Cemetery boss native typing, form pairing, and bounded-retry fallback."""
import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')


class CemeteryGhostBossTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        cls.h.boot_to_lobby()
        cls.state = io.BytesIO()
        cls.h.save_state(cls.state)

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def check_candidate(self, species, form, banned, reroll=('MAROWAK', 1)):
        self.state.seek(0)
        h = self.h
        h.load_state(self.state)
        h.write8('wRoguePokemon1', SPECIES[species])
        h.write8('wRoguePokemonForm1', form)
        # Default every retry to Ghost, proving exhaustion cannot accept it.
        # Hook the caller after selection so the production selector still runs.
        bank, addr = h.symbols.get('PCemAvoidGhostBoss.storeReroll')
        rolls = []
        def ghost_roll(_):
            rolls.append(1)
            h.pyboy.register_file.D = SPECIES[reroll[0]]
            h.pyboy.register_file.E = reroll[1]
        h.pyboy.hook_register(bank, addr, ghost_roll, None)
        try:
            h.call_routine('PCemAvoidGhostBoss')
        finally:
            h.pyboy.hook_deregister(bank, addr)
        pair = (h.read8('wRoguePokemon1'), h.read8('wRoguePokemonForm1'))
        expected = (SPECIES[species], form)
        count = 0
        if banned:
            expected, count = (SPECIES['MAROWAK'], 0), 19
            if reroll != ('MAROWAK', 1):
                expected, count = (SPECIES[reroll[0]], reroll[1]), 1
        self.assertEqual(pair, expected)
        self.assertEqual(len(rolls), count)

    def test_native_ghost_species_and_forms_rejected(self):
        for species, form in [('GASTLY', 0), ('HAUNTER', 0), ('GENGAR', 0),
                              ('MISDREAVUS', 0), ('MISMAGIUS', 0),
                              ('ANNIHILAPE', 0), ('MAROWAK', 1)]:
            with self.subTest(species=species, form=form):
                self.check_candidate(species, form, True)

    def test_non_ghost_species_and_forms_unchanged(self):
        for species, form in [('MAROWAK', 0), ('RATTATA', 0), ('RATTATA', 1)]:
            with self.subTest(species=species, form=form):
                self.check_candidate(species, form, False)

    def test_reroll_keeps_selected_form(self):
        self.check_candidate('MISMAGIUS', 0, True, ('RATTATA', 1))
