"""Honchkrow (MURKROW form 1) and Ursaluna (URSARING form 1), added 2026-11-07.

Both are distinct species stored as forms of their OWN pre-evolution's species,
so the stone evolution changes only the form: Murkrow + Dusk Stone stays
MURKROW and becomes form 1. Every earlier form-setting evolution changed species
too (Cubone -> A-Marowak), so this drives the real evolution loop end to end:
the animation, RenameEvolvedMon, the stat recalculation, the type setter and the
Pokedex registration all see old species == new species.

Both need Johto AND Time Warp, like Mamoswine: the base mon is Johto, and the
form is a Warp form (absent from FormJohtoPairs). The Warp-off case must not
evolve and must keep the stone context clear.

The stone is armed at EvolutionAfterBattle.contextReady on the pass after a won
FIGHT2 battle: past the in-battle reset of wForceEvolution, the same loop the
bag's stone use enters. The evolving mon waits in slot 1.
"""
import unittest

from source_constants import parse_rgbds_constants, parse_trainer_constants
from test_smoke import HarnessTestCase, REPO_ROOT

SPECIES = parse_rgbds_constants(REPO_ROOT / 'constants/pokemon_constants.asm')
MOVES = parse_rgbds_constants(REPO_ROOT / 'constants/move_constants.asm')
TYPES = parse_rgbds_constants(REPO_ROOT / 'constants/type_constants.asm')
ITEMS = parse_rgbds_constants(REPO_ROOT / 'constants/item_constants.asm')
EVENTS = parse_rgbds_constants(REPO_ROOT / 'constants/event_constants.asm')
GROUPS = parse_rgbds_constants(REPO_ROOT / 'constants/rogue_species_groups.asm')
DEX = parse_rgbds_constants(REPO_ROOT / 'constants/pokedex_constants.asm')
TRAINERS = parse_trainer_constants(REPO_ROOT / 'constants/trainer_constants.asm')

KANTO = 1 << GROUPS['BIT_GROUP_KANTO']
JOHTO = 1 << GROUPS['BIT_GROUP_JOHTO']
WARP = 1 << GROUPS['BIT_GROUP_WARP']
TEXT_END = 0x50
SLOT = 1
STRUCT = 44       # PARTYMON_STRUCT_LENGTH
NAME_LENGTH = 11
LETTERS = {0x80 + i: c for i, c in enumerate('ABCDEFGHIJKLMNOPQRSTUVWXYZ')}


class StoneFormEvolutionTest(HarnessTestCase):
    def evolve(self, species: str, stone: str, enabled: int) -> dict:
        h = self.harness
        # The mon under test waits in slot 1 and evolves after the battle, the
        # shape FormEvolutionFlowTest uses, so the lead is not the evolving mon.
        lead = dict(species=SPECIES['SANDSHREW'], level=22, moves=[MOVES['SCRATCH']])
        mon = dict(species=SPECIES[species], level=40, moves=[MOVES['TACKLE']])
        h.inject_fight2_spec([lead, mon], [dict(species=SPECIES['MAGIKARP'], level=2,
                                          moves=[MOVES['SPLASH']])],
                             trainer_class=TRAINERS['COOLTRAINER_M'], ai_tier=0)
        h.boot_fight2(seed=1)
        h.write8('wOptions', h.read8('wOptions') | 0x40)
        if h.hardware_mode == 'CGB':
            h.write8('wOptions2', h.read8('wOptions2') | 0xc0)
        h.set_event(EVENTS['EVENT_JOHTO_ACTIVATED'])
        h.set_event(EVENTS['EVENT_KANTO_TIMEWARP_ACTIVATED'])
        h.write_sram_bytes('sRogueSpeciesGroupsEnabled', [enabled], bank=1)
        # FIGHT2 nicknames every mon "TEST", which RenameEvolvedMon rightly
        # keeps. Give slot 1 its species name so the rename path is exercised.
        to_char = {c: b for b, c in LETTERS.items()}
        name = [to_char[c] for c in species] + [TEXT_END] * (NAME_LENGTH - len(species))
        for i, b in enumerate(name):
            h.write8('wPartyMonNicks', b, offset=SLOT * NAME_LENGTH + i)
        rd = lambda label, i=0: h.read8(label, offset=SLOT * STRUCT + i)
        before = dict(maxhp=(rd('wPartyMon1MaxHP') << 8) | rd('wPartyMon1MaxHP', 1))
        ended, armed, final = [], [], {}

        def arm(_):
            # The first pass after EndOfBattle. hIsInBattle is still set there
            # in FIGHT2, so this hooks .contextReady, past the routine's own
            # in-battle clear of wForceEvolution, where the bag's stone use is.
            if ended and not armed:
                h.write8('wForceEvolution', 1)
                h.write8('wEvoStoneItemID', ITEMS[stone])
                h.write8('wCanEvolveFlags', 1 << SLOT)
                armed.append(True)

        def snap(_):
            if armed and not final:
                nick = []
                for i in range(11):
                    b = h.read8('wPartyMonNicks', offset=SLOT * NAME_LENGTH + i)
                    if b == TEXT_END:
                        break
                    nick.append(LETTERS.get(b, '?'))
                owned = h.address('wPokedexFormOwned')
                form_id = DEX['DEX_FORM_' + {'MURKROW': 'HONCHKROW', 'URSARING': 'URSALUNA'}[species]]
                final.update(
                    species=rd('wPartyMon1Species'),
                    form=(rd('wPartyMon1CatchRate') >> 5) & 3,
                    types=(rd('wPartyMon1Type1'), rd('wPartyMon1Type2')),
                    maxhp=(rd('wPartyMon1MaxHP') << 8) | rd('wPartyMon1MaxHP', 1),
                    nick=''.join(nick),
                    dex_owned=bool(h.pyboy.memory[owned + form_id // 8] & (1 << (form_id % 8))),
                )
        h.register_hook('EndOfBattle', lambda _: ended.append(True))
        h.register_hook('EvolutionAfterBattle.contextReady', arm)
        h.register_hook('Evolution_PartyMonLoop.done', snap)
        crash = h.hook_flag('CrashScreen')
        for frame in range(8000):
            if frame % 12 == 0:
                h.pyboy.button_press('a')
            elif frame % 12 == 2:
                h.pyboy.button_release('a')
            h.tick(1)
            if final or crash['count']:
                break
        self.assertEqual(crash['count'], 0)
        self.assertTrue(final, h.diagnostic_state())
        final['before_maxhp'] = before['maxhp']
        return final

    def check_evolves(self, species, stone, types, name):
        out = self.evolve(species, stone, KANTO | JOHTO | WARP)
        self.assertEqual((out['species'], out['form']), (SPECIES[species], 1), out)
        self.assertEqual(out['types'], tuple(TYPES[t] for t in types), out)
        self.assertGreater(out['maxhp'], out['before_maxhp'], out)
        self.assertEqual(out['nick'], name, out)
        self.assertTrue(out['dex_owned'], out)

    def check_blocked_without_warp(self, species, stone):
        out = self.evolve(species, stone, KANTO | JOHTO)
        self.assertEqual((out['species'], out['form']), (SPECIES[species], 0), out)
        self.assertEqual(out['maxhp'], out['before_maxhp'], out)
        self.assertFalse(out['dex_owned'], out)

    def test_murkrow_dusk_stone_becomes_honchkrow(self):
        self.check_evolves('MURKROW', 'DUSK_STONE', ('NORMAL', 'FLYING'), 'HONCHKROW')

    def test_ursaring_moon_stone_becomes_ursaluna(self):
        self.check_evolves('URSARING', 'MOON_STONE', ('GROUND', 'NORMAL'), 'URSALUNA')

    def test_murkrow_needs_time_warp(self):
        self.check_blocked_without_warp('MURKROW', 'DUSK_STONE')

    def test_ursaring_needs_time_warp(self):
        self.check_blocked_without_warp('URSARING', 'MOON_STONE')


if __name__ == '__main__':
    unittest.main()
