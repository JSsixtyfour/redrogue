"""Forms of Johto species, and Warp evolutions of Johto lines, need Johto AND Warp.

A Warp-only run (Johto toggled off) rolled a Paldean Wooper: the Warp rarity
pool picked it directly, trainer band pools' Warp runs held Wooper/Qwilfish
forms, Weavile, Mamoswine..., and IsFormAllowed treated every such form as
Warp-only. Each gate is measured here in both states, so the test fails if a
gate leaks (Warp only) and also if it over-blocks (Johto + Warp).
"""
import io
from pathlib import Path
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')
EVENTS = parse_rgbds_constants(ROOT / 'constants/event_constants.asm')
GROUP_KANTO, GROUP_JOHTO, GROUP_WARP = 1, 2, 4
WARP_ONLY = GROUP_KANTO | GROUP_WARP
JOHTO_WARP = GROUP_KANTO | GROUP_JOHTO | GROUP_WARP
SPECIES_GROUP_WARP = 2
RARITY_TIER_GREATBALL = 1
CARRY = 0x10
DRAWS = 150


def band_pools():
    """{name: (pool id, [(species id, form spec)] warp tail)}, ids in table order:
    FalknerPool is 0, then each band_pool (band_same aliases take no id)."""
    out, name, tail, next_id = {}, None, False, 1
    for raw in (ROOT / 'data/trainers/band_pools.asm').read_text().splitlines():
        code = raw.split(';', 1)[0].strip()
        op, _, arg = code.partition(' ')
        if op == 'band_pool':
            name, tail = arg.strip(), False
            out[name] = (next_id, [])
            next_id += 1
        elif op == 'band_warp_johto':
            tail = True
        elif op == 'band_end':
            name, tail = None, False
        elif op in ('band_mon', 'band_ace') and name and tail:
            args = [a.strip() for a in arg.split(',')]
            spec = int(args[1]) if len(args) > 1 else None
            out[name][1].append((SPECIES[args[0]], spec))
    return out


class JohtoBaseFormsNeedJohtoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        cls.h.boot_to_lobby()
        cls.h.set_event(EVENTS['EVENT_JOHTO_ACTIVATED'])
        cls.h.set_event(EVENTS['EVENT_KANTO_TIMEWARP_ACTIVATED'])
        cls.state = io.BytesIO()
        cls.h.save_state(cls.state)
        cls.pools = band_pools()

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def use_groups(self, enabled):
        self.state.seek(0)
        self.h.load_state(self.state)
        mem = self.h.pyboy.memory
        mem[0x0000] = 0x0A
        mem[0x4000] = 1
        self.h.write8('sRogueSpeciesGroupsEnabled', enabled)
        mem[0x0000] = 0

    def warp_greatball_base_count(self):
        bank, entry = self.h.symbols.get('RogueGetTierBaseCount')

        def arguments(_context):
            self.h.pyboy.register_file.A = SPECIES_GROUP_WARP
            self.h.pyboy.register_file.B = RARITY_TIER_GREATBALL
        self.h.pyboy.hook_register(bank, entry, arguments, None)
        try:
            self.h.call_routine('RogueGetTierBaseCount')
        finally:
            self.h.pyboy.hook_deregister(bank, entry)
        return self.h.last_call_registers['A']

    def form_unlocked(self, species, form):
        self.h.pyboy.register_file.D = SPECIES[species]
        self.h.pyboy.register_file.E = form
        self.h.call_routine('IsFormUnlockedFar')
        return bool(self.h.last_call_registers['F'] & CARRY)

    def draws(self, pool):
        pool_id = self.pools[pool][0]
        seen = set()
        for _ in range(DRAWS):
            self.h.pyboy.register_file.E = pool_id
            seen.add(self.h.call_routine(
                'RogueDrawFromPoolFar',
                capture=lambda h: (h.read8('wCurPartySpecies'), h.read8('wSpawnForm'))))
        return seen

    def test_rarity_warp_greatball_rolls_johto_forms_only_with_johto(self):
        source = (ROOT / 'engine/pokemon/rarity.asm').read_text()
        body = source.split('\nWarpGreatball:\n', 1)[1].split('\nWarpGreatball_Evos:', 1)[0]
        default, conditional = body.split('.defaultEvos:', 1)
        count = lambda text: len(re.findall(r'^\s*rarity_mon ', text, re.M))
        self.assertIn('WOOPER, 1', conditional)
        self.assertIn('QWILFISH, 1', conditional)
        self.use_groups(WARP_ONLY)
        self.assertEqual(self.warp_greatball_base_count(), count(default))
        self.use_groups(JOHTO_WARP)
        self.assertEqual(self.warp_greatball_base_count(), count(default) + count(conditional))

    def test_form_gate_needs_johto_for_johto_species(self):
        johto_based = (('WOOPER', 1), ('QUAGSIRE', 1), ('QWILFISH', 1), ('QWILFISH', 2),
                       ('MURKROW', 1), ('SLOWKING', 1), ('URSARING', 1))
        self.use_groups(WARP_ONLY)
        for pair in johto_based:
            self.assertFalse(self.form_unlocked(*pair), pair)
        self.assertTrue(self.form_unlocked('MEOWTH', 1))      # Kanto base: Warp alone
        self.assertTrue(self.form_unlocked('SLOWPOKE', 1))
        self.use_groups(JOHTO_WARP)
        for pair in johto_based:
            self.assertTrue(self.form_unlocked(*pair), pair)

    def test_trainer_pool_warp_tail_needs_johto(self):
        # Koga's band-1 fodder: Kanto run, Warp run with Galarian Slowpoke kept,
        # Paldean Wooper and Hisuian Qwilfish in the tail.
        tail = set(self.pools['Koga_Fod1'][1])
        self.assertIn((SPECIES['WOOPER'], 1), tail)
        self.assertIn((SPECIES['QWILFISH'], 1), tail)
        self.use_groups(WARP_ONLY)
        self.assertFalse(self.draws('Koga_Fod1') & tail)
        self.use_groups(JOHTO_WARP)
        self.assertTrue(self.draws('Koga_Fod1') & tail)


if __name__ == '__main__':
    unittest.main()
