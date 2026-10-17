"""Swinub's conditional family rarity must change both picks and classification."""
import io
from pathlib import Path
import sys
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(ROOT / 'constants/pokemon_constants.asm')
EVENTS = parse_rgbds_constants(ROOT / 'constants/event_constants.asm')
sys.path.insert(0, str(ROOT / 'tools/balance'))
import parse as balance_parse


class SwinubRarityModelTest(unittest.TestCase):
    def test_model_selection_and_classification_match_the_same_group_rule(self):
        rarity = balance_parse.load_rarity()
        for groups in (('KANTO',), ('KANTO', 'JOHTO'), ('KANTO', 'WARP'), ('KANTO', 'JOHTO', 'WARP')):
            boosted = {'JOHTO', 'WARP'} <= set(groups)
            for tier in (0, 1):
                picks = balance_parse.base_species_for_tier(rarity, 'JOHTO', tier, groups)
                self.assertEqual(picks.count('SWINUB'), int(tier == int(boosted)))
            for species in ('SWINUB', 'PILOSWINE', 'MAMOSWINE'):
                self.assertEqual(balance_parse.classify(rarity, species, groups)[1], int(boosted))


class SwinubRarityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        cls.h.boot_to_lobby()
        cls.state = io.BytesIO()
        cls.h.save_state(cls.state)

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def configure(self, unlocked, enabled):
        self.state.seek(0)
        self.h.load_state(self.state)
        for bit, event in ((2, 'EVENT_JOHTO_ACTIVATED'), (4, 'EVENT_KANTO_TIMEWARP_ACTIVATED')):
            event = EVENTS[event]
            addr = self.h.address('wEventFlags') + event // 8
            value = self.h.pyboy.memory[addr] & ~(1 << (event % 8))
            if unlocked & bit:
                value |= 1 << (event % 8)
            self.h.pyboy.memory[addr] = value
        self.h.write_sram_bytes('sRogueSpeciesGroupsEnabled', [enabled], bank=1)

    def entry(self, group, tier):
        bank, addr = self.h.symbols.get('RogueGetTierEntry')
        def arguments(_):
            self.h.pyboy.register_file.A = group
            self.h.pyboy.register_file.B = tier
        self.h.pyboy.hook_register(bank, addr, arguments, None)
        try:
            self.h.call_routine('RogueGetTierEntry')
        finally:
            self.h.pyboy.hook_deregister(bank, addr)
        regs = self.h.last_call_registers
        pointer, count = regs['HL'], regs['B']
        rom = self.h.rom_path.read_bytes()
        offset = bank * 0x4000 + pointer - 0x4000
        direct = [(rom[offset+i], rom[offset+i+1]) for i in range(0, count*2, 2)]
        return count, direct

    def test_pool_membership_and_weights_follow_effective_groups(self):
        # Locked expansions must not be activated by stale SRAM preference bits.
        for unlocked in (1, 3, 5, 7):
            for enabled in (1, 3, 5, 7):
                boosted = unlocked & enabled & 6 == 6
                roots = []
                for tier in (0, 1):
                    self.configure(unlocked, enabled)
                    count, direct = self.entry(1, tier)
                    expected = (15, 20) if boosted else (16, 19)
                    self.assertEqual(count, expected[tier], (unlocked, enabled, tier))
                    self.assertEqual(direct.count((SPECIES['SWINUB'], 0)), int(tier == int(boosted)))
                    roots.extend(direct)
                self.assertEqual(len(roots), len(set(roots)))

    def test_whole_family_classifies_consistently_and_reversibly(self):
        for unlocked in (1, 3, 5, 7):
            for enabled in (1, 3, 5, 7):
                boosted = unlocked & enabled & 6 == 6
                for species in ('SWINUB', 'PILOSWINE', 'MAMOSWINE'):
                    for routine, expected in (('RogueGetSpeciesTierFar', int(boosted)),
                                              ('RogueClassifySpeciesFar', 1 + int(boosted))):
                        self.configure(unlocked, enabled)
                        self.h.pyboy.register_file.E = SPECIES[species]
                        self.h.call_routine(routine)
                        self.assertEqual(self.h.last_call_registers['E'], expected,
                                         (unlocked, enabled, species, routine))

    def test_group_picker_uses_the_adjusted_weight_boundaries(self):
        h = self.h
        bank, entry = h.symbols.get('RogueRollGroupForTier')
        _, pick = h.symbols.get('RogueRollGroupForTier.pick')
        rng_bank, rng_entry = h.symbols.get('Rangerandom')
        for mask in (1, 3, 5, 7):
            for tier in (0, 1):
                # Pool sizes come from the ROM's own pool getter, not literals:
                # hardcoded Kanto/Warp sizes went stale every time a form was
                # added to a pool. The Swinub boost itself (Johto 15/20 vs
                # 16/19) stays pinned in test_pool_membership_and_weights_...
                counts = []
                for group in range(3):
                    self.configure(7, mask)
                    counts.append(self.entry(group, tier)[0] if mask & (1 << group) else 0)
                if mask & 2:
                    self.assertEqual(counts[1], ((15, 20) if mask == 7 else (16, 19))[tier])
                start = 0
                for group, count in enumerate(counts):
                    if not count:
                        continue
                    for index in (start, start + count - 1):
                        self.configure(7, mask)
                        seen_counts = []
                        def arguments(_):
                            h.pyboy.register_file.B = tier
                        def ordinal(_):
                            if h.pyboy.register_file.C == 0:
                                h.pyboy.register_file.E = index
                        def rng_count(_):
                            seen_counts.append(h.pyboy.register_file.C)
                        h.pyboy.hook_register(bank, entry, arguments, None)
                        h.pyboy.hook_register(bank, pick, ordinal, None)
                        h.pyboy.hook_register(rng_bank, rng_entry, rng_count, None)
                        try:
                            h.call_routine('RogueRollGroupForTier')
                        finally:
                            h.pyboy.hook_deregister(bank, entry)
                            h.pyboy.hook_deregister(bank, pick)
                            h.pyboy.hook_deregister(rng_bank, rng_entry)
                        self.assertEqual(h.last_call_registers['A'], group, (mask, tier, index))
                        self.assertEqual(seen_counts, [sum(counts)])
                    start += count

    def test_relocated_ownership_walk_preserves_form_and_finds_evolved_family(self):
        for candidate, expected in (('SWINUB', 1), ('PILOSWINE', 1), ('PSYDUCK', 0)):
            self.configure(7, 7)
            self.h.write8('wPartySpecies', SPECIES['MAMOSWINE'])
            self.h.write8('wPartySpecies', 255, offset=1)
            self.h.write8('wBoxSpecies', 255)
            self.h.pyboy.register_file.D = SPECIES[candidate]
            self.h.pyboy.register_file.E = 2
            self.h.call_routine('AllSpeciesCheck')
            regs = self.h.last_call_registers
            self.assertEqual(regs['C'], expected, candidate)
            self.assertEqual((regs['D'], regs['E']), (SPECIES[candidate], 2))
