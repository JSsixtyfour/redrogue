"""A mon left at either daycare counts as owned for every reward/trade roll.

AllSpeciesCheck used to build its owned list from the party and current box
only, so the lobby trader offered a Hitmonchan while the player's Hitmonchan
sat in a daycare."""
import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')


class DaycareOwnershipTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        cls.h.boot_to_lobby()
        cls.state = io.BytesIO()
        cls.h.save_state(cls.state)

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def owned(self, candidate, daycare1=None, daycare2=None):
        h = self.h
        self.state.seek(0)
        h.load_state(self.state)
        h.write8('wPartySpecies', SPECIES['OMASTAR'])
        h.write8('wPartySpecies', 255, offset=1)
        h.write8('wBoxSpecies', 255)
        for in_use, species_label, species in (('wDayCareInUse', 'wDayCareMonSpecies', daycare1),
                                               ('wDayCareInUse2', 'wDayCareMon2Species', daycare2)):
            # A stale species byte behind an empty daycare must not count.
            h.write8(species_label, SPECIES[species] if species else SPECIES[candidate])
            h.write8(in_use, 1 if species else 0)
        # Inputs at the routine's entry, not on the parked CPU (see test_swinub_rarity).
        bank, addr = h.symbols.get('AllSpeciesCheck')
        def arguments(_):
            h.pyboy.register_file.D = SPECIES[candidate]
            h.pyboy.register_file.E = 0
        h.pyboy.hook_register(bank, addr, arguments, None)
        try:
            h.call_routine('AllSpeciesCheck')
        finally:
            h.pyboy.hook_deregister(bank, addr)
        return h.last_call_registers['C']

    def test_daycare_mons_count_as_owned(self):
        self.assertEqual(self.owned('HITMONCHAN'), 0)
        self.assertEqual(self.owned('HITMONCHAN', daycare1='HITMONCHAN'), 1)
        self.assertEqual(self.owned('HITMONCHAN', daycare2='HITMONCHAN'), 1)
        # family-wide, like the party/box: an evolved mon in daycare blocks its base
        self.assertEqual(self.owned('MAGIKARP', daycare2='GYARADOS'), 1)
        self.assertEqual(self.owned('PSYDUCK', daycare1='HITMONCHAN', daycare2='GYARADOS'), 0)


if __name__ == '__main__':
    unittest.main()
