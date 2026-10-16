"""Compiled pair pools, every pick index, and generated form evolution."""
import io
from pathlib import Path
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')
EVENTS = parse_rgbds_constants(ROOT / 'constants/event_constants.asm')


class ExplicitRarityFormsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        cls.h.boot_to_lobby()
        cls.h.set_event(EVENTS['EVENT_JOHTO_ACTIVATED'])
        cls.h.set_event(EVENTS['EVENT_KANTO_TIMEWARP_ACTIVATED'])
        cls.h.pyboy.memory[0x0000] = 0x0A
        cls.h.pyboy.memory[0x4000] = 1
        cls.h.write8('sRogueSpeciesGroupsEnabled', 7)
        cls.h.pyboy.memory[0x0000] = 0
        cls.state = io.BytesIO()
        cls.h.save_state(cls.state)

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def reset(self):
        self.state.seek(0)
        self.h.load_state(self.state)

    def rom_bytes(self, label, count):
        bank, addr = self.h.symbols.get(label)
        offset = bank * 0x4000 + addr - (0x4000 if bank else 0)
        return self.h.rom_path.read_bytes()[offset:offset+count]

    def test_compiled_coverage_and_every_direct_index(self):
        source = (ROOT / 'engine/pokemon/rarity.asm').read_text()
        ordinary = []
        direct_forms = []
        for group in ('Kanto', 'Johto', 'Warp'):
            table = self.rom_bytes('Rarity' + group, 5 * 4)
            for tier_id, tier in enumerate(('Pokeball', 'Greatball', 'Ultraball', 'Masterball', 'Uber')):
                label = group + tier
                body = source.split(label + ':\n', 1)[1].split(label + '_End:', 1)[0]
                before, after = body.split(label + '_Evos:', 1)
                def pairs(text):
                    return [(SPECIES[m[0]], int(m[1] or 0)) for m in
                            re.findall(r'^\s*rarity_mon (\w+)(?:,\s*(\d+))?', text, re.M)]
                direct = pairs(before.split('.defaultEvos:', 1)[0])
                expected = pairs(before) + pairs(after)
                self.assertEqual(list(self.rom_bytes(label, len(expected)*2)),
                                 [x for pair in expected for x in pair], label)
                ordinary += [sp for sp, form in expected if not form]
                direct_forms += [pair for pair in direct if pair[1]]
                _, addr = self.h.symbols.get(label)
                self.assertEqual(list(table[tier_id*4:tier_id*4+4]),
                                 [len(direct), len(expected), addr & 255, addr >> 8], label)
                for species, form in expected:
                    if form:
                        continue
                    self.reset()
                    self.h.pyboy.register_file.E = species
                    self.h.call_routine('RogueGetSpeciesTierFar')
                    expected_tier = 1 if species in {SPECIES['SWINUB'], SPECIES['PILOSWINE'], SPECIES['MAMOSWINE']} else tier_id
                    self.assertEqual(self.h.last_call_registers['E'], expected_tier,
                                     (label, species))
                for index, pair in enumerate(direct):
                    self.reset()
                    bank, entry = self.h.symbols.get('RogueSpeciesAtIndex')
                    def arguments(_context):
                        self.h.pyboy.register_file.A = index
                        self.h.pyboy.register_file.HL = addr
                    self.h.pyboy.hook_register(bank, entry, arguments, None)
                    try:
                        self.h.call_routine('RogueSpeciesAtIndex')
                    finally:
                        self.h.pyboy.hook_deregister(bank, entry)
                    regs = self.h.last_call_registers
                    self.assertEqual((regs['D'], regs['E']), pair, (label, index))
        # Swinub has two physical placements; the active tier view exposes one.
        self.assertEqual(len(ordinary), 253)
        self.assertEqual(ordinary.count(SPECIES['SWINUB']), 2)
        self.assertEqual(len(set(ordinary)), 252)
        self.assertEqual(len(direct_forms), 27)
        self.assertEqual(len(set(direct_forms)), 27)
        # All active form records occur either in direct lists or commented
        # evolution references, never silently through a substitution rule.
        references = {(SPECIES[sp], int(form)) for sp, form in
                      re.findall(r'^; rarity_mon (\w+),\s*(\d+)', source, re.M)}
        records = self.rom_bytes('FormOverrides', 48 * 41)
        active = {(records[i], records[i+1]) for i in range(0, len(records), 41)}
        self.assertFalse(set(direct_forms) & references)
        self.assertEqual(set(direct_forms) | references, active)
        self.assertNotIn((SPECIES['MR_MIME'], 1), active)

    def test_evolution_keeps_explicit_identity(self):
        cases = [
            ('FARFETCHD',0,50,'FARFETCHD',0),
            ('FARFETCHD',1,10,'FARFETCHD',1),
            ('FARFETCHD',1,50,'SIRFETCHD',0),
            ('PRIMEAPE',0,50,'ANNIHILAPE',0),
            ('JIGGLYPUFF',1,50,'JIGGLYPUFF',1),
            ('MAGNETON',1,50,'MAGNETON',1),
            ('MEOWTH',1,50,'PERSIAN',1),
            ('MEOWTH',2,50,'PERSIAN',2),
            ('DIGLETT',2,50,'DUGTRIO',2),
            ('GRIMER',1,50,'MUK',1),
            ('VULPIX',1,50,'NINETALES',1),
            ('ARTICUNO',1,50,'ARTICUNO',1),
            ('ZAPDOS',1,50,'ZAPDOS',1),
            ('MOLTRES',1,50,'MOLTRES',1),
        ]
        for sp, form, level, target, target_form in cases:
            self.reset()
            self.h.write8('wCurEnemyLevel', level)
            self.h.write8('wSpawnForm', 3)  # deferred selection must not publish here
            self.h.write8('wPendingEeveeForm', 0x80)
            self.h.pyboy.register_file.D = SPECIES[sp]
            self.h.pyboy.register_file.E = form
            self.h.call_routine('EvolvePoolMon')
            regs = self.h.last_call_registers
            self.assertEqual((regs['D'], regs['E']), (SPECIES[target], target_form), sp)
            self.assertEqual(self.h.read8('wSpawnForm'), 3, sp)
            self.assertEqual(self.h.read8('wPendingEeveeForm'), 0, sp)

    def test_generic_species_never_substitutes_a_form(self):
        for sp in ('ARTICUNO', 'ZAPDOS', 'MOLTRES', 'FARFETCHD', 'MEOWTH'):
            self.reset()
            self.h.pyboy.register_file.D = 7
            self.h.pyboy.register_file.E = SPECIES[sp]
            self.h.call_routine('RogueRollFormForSpecies')
            self.assertEqual(self.h.last_call_registers['E'], 0, sp)

    def test_eevee_keeps_its_selected_branch_and_consumes_pending(self):
        for mask in (1, 3, 5, 7):
            branches = [('FLAREON',0), ('JOLTEON',0), ('VAPOREON',0)]
            if mask & 2:
                branches += [('JOLTEON',1), ('JOLTEON',2)]
            if mask & 4:
                branches += [('FLAREON',1), ('VAPOREON',1), ('VAPOREON',2)]
            allowed = {(SPECIES[sp], form) for sp, form in branches}
            for seed in range(16):
                self.reset()
                self.h.pyboy.memory[0x0000] = 0x0A
                self.h.pyboy.memory[0x4000] = 1
                self.h.write8('sRogueSpeciesGroupsEnabled', mask)
                self.h.pyboy.memory[0x0000] = 0
                self.h.write8('hRandomAdd', seed * 7)
                self.h.write8('hRandomSub', seed * 11)
                self.h.write8('wCurEnemyLevel', 50)
                self.h.write8('wSpawnForm', 3)
                self.h.pyboy.register_file.D = SPECIES['EEVEE']
                self.h.pyboy.register_file.E = 0
                self.h.call_routine('EvolvePoolMon')
                regs = self.h.last_call_registers
                self.assertIn((regs['D'], regs['E']), allowed, (mask, seed))
                self.assertEqual(self.h.read8('wPendingEeveeForm'), 0)
                self.assertEqual(self.h.read8('wSpawnForm'), 3)
