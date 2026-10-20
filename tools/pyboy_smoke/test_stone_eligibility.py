"""Stone verdicts and player evolution agree on enabled target groups.

Presentation is stubbed for the mutation checks: these verify the real parser,
group gates, species/form writeback and stat update, not animation choreography.
Every case restores a complete parked baseline.
"""
import io

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

SPECIES = parse_rgbds_constants(REPO_ROOT / 'constants/pokemon_constants.asm')
ITEMS = parse_rgbds_constants(REPO_ROOT / 'constants/item_constants.asm')
EVENTS = parse_rgbds_constants(REPO_ROOT / 'constants/event_constants.asm')
RAM = parse_rgbds_constants(REPO_ROOT / 'constants/ram_constants.asm')

# source, source form, stone, target, target form, required group
CASES = (
    ('MISDREAVUS', 0, 'DUSK_STONE', 'MISMAGIUS', 0, 4),
    ('SNEASEL', 0, 'ICE_STONE', 'WEAVILE', 0, 4),
    ('VULPIX', 1, 'ICE_STONE', 'NINETALES', 1, 0),
    ('GROWLITHE', 1, 'FIRE_STONE', 'ARCANINE', 1, 0),
    ('SLOWPOKE', 1, 'WATER_STONE', 'SLOWKING', 1, 2),
    ('PIKACHU', 0, 'MOON_STONE', 'RAICHU', 1, 4),
    ('EXEGGCUTE', 0, 'MOON_STONE', 'EXEGGUTOR', 1, 4),
    ('KOFFING', 0, 'MOON_STONE', 'WEEZING', 1, 4),
    ('CUBONE', 0, 'DUSK_STONE', 'MAROWAK', 1, 4),
    ('EEVEE', 0, 'DUSK_STONE', 'JOLTEON', 2, 2),
    ('EEVEE', 0, 'LEAF_STONE', 'FLAREON', 1, 4),
    ('EEVEE', 0, 'FIRE_STONE', 'FLAREON', 0, 0),
)


class StoneEligibilityTest(HarnessTestCase):
    def baseline(self):
        h = self.harness
        h.boot_to_lobby()
        h.write8('wStatusFlags6', h.read8('wStatusFlags6') & ~(1 << RAM['BIT_DEBUG2_MODE']))
        h.set_event(EVENTS['EVENT_JOHTO_ACTIVATED'])
        h.set_event(EVENTS['EVENT_KANTO_TIMEWARP_ACTIVATED'])
        self.saved = io.BytesIO()
        h.save_state(self.saved)

    def source(self, species, form, stone, enabled, level=50):
        h = self.harness
        self.saved.seek(0)
        h.load_state(self.saved)
        h.write_sram_bytes('sRogueSpeciesGroupsEnabled', [enabled], bank=1)
        h.write8('hIsInBattle', 0)
        h.write8('hWhichPokemon', 0)
        h.write8('wMonDataLocation', 0)
        h.write8('wPartyCount', 1)
        h.write8('wPartySpecies', SPECIES[species])
        h.write8('wPartySpecies', 0xff, offset=1)
        h.write8('wPartyMon1Species', SPECIES[species])
        h.write8('wPartyMon1CatchRate', form << 5)
        h.write8('wPartyMon1Level', level)
        h.write8('wLinkState', 0)
        h.write8('wEvoStoneItemID', ITEMS[stone] if stone else 0)
        h.call_routine('LoadMonData')

    def test_menu_gate_for_species_forms_and_disabled_groups(self):
        self.baseline()
        h = self.harness
        for species, form, stone, target, target_form, group in CASES:
            for enabled in (1, 3, 5, 7):
                with self.subTest(species=species, form=form, stone=stone, enabled=enabled):
                    self.source(species, form, stone, enabled)
                    h.call_routine('CanLoadedMonEvolveWithStone')
                    self.assertEqual(bool(h.last_call_registers['F'] & 0x10),
                                     not group or bool(enabled & group))

    def presentation_ret(self, _):
        h = self.harness
        r = h.pyboy.register_file
        r.F &= ~0x10  # no cancellation
        r.PC = h.pyboy.memory[r.SP] | (h.pyboy.memory[r.SP + 1] << 8)
        r.SP = (r.SP + 2) & 0xffff

    def stub_presentation(self):
        for label in ('PrintText', 'PrintText_NoCreatingTextBox', 'DelayFrames', 'DelayFrame',
                      'PlaySoundWaitForCurrent', 'WaitForSoundToFinish',
                      'EvolveMon', 'Evolution_ReloadTilesetTilePatterns',
                      'LearnMoveFromLevelUp', 'PlayDefaultMusic'):
            self.harness.register_hook(label, self.presentation_ret)

    def test_stones_mutate_species_and_forms_only_when_allowed(self):
        self.baseline()
        self.stub_presentation()
        h = self.harness
        for species, form, stone, target, target_form, group in CASES:
            for enabled in (3, 7):
                with self.subTest(species=species, form=form, enabled=enabled):
                    self.source(species, form, stone, enabled)
                    h.write8('wForceEvolution', 1)
                    h.call_routine('TryEvolvingMon')
                    allowed = not group or bool(enabled & group)
                    self.assertEqual(h.read8('wEvolutionOccurred'), int(allowed))
                    self.assertEqual(h.read8('wPartyMon1Species'), SPECIES[target if allowed else species])
                    self.assertEqual((h.read8('wPartyMon1CatchRate') >> 5) & 3,
                                     target_form if allowed else form)

    def test_level_evolution_into_warp_is_also_blocked_in_johto(self):
        self.baseline()
        self.stub_presentation()
        h = self.harness
        for species, target in (('PILOSWINE', 'MAMOSWINE'), ('TANGELA', 'TANGROWTH'),
                                ('LICKITUNG', 'LICKILICKY'), ('PORYGON2', 'PORYGON_Z')):
            for enabled in (3, 7):
                with self.subTest(species=species, enabled=enabled):
                    self.source(species, 0, None, enabled, level=100)
                    h.write8('wForceEvolution', 0)
                    h.call_routine('TryEvolvingMon')
                    self.assertEqual(h.read8('wPartyMon1Species'),
                                     SPECIES[target if enabled & 4 else species])

    def test_mist_and_wrong_stones_do_not_advertise_blocked_targets(self):
        self.baseline()
        h = self.harness
        for species, form, stone, enabled, expected in (
            ('MISDREAVUS', 0, 'MIST_STONE', 3, False),
            ('MISDREAVUS', 0, 'MIST_STONE', 7, True),
            ('PILOSWINE', 0, 'MIST_STONE', 3, False),
            ('PILOSWINE', 0, 'MIST_STONE', 7, True),
            ('VULPIX', 1, 'FIRE_STONE', 7, False),
            ('JIGGLYPUFF', 1, 'MIST_STONE', 7, False),
        ):
            with self.subTest(species=species, stone=stone, enabled=enabled):
                self.source(species, form, stone, enabled)
                h.call_routine('CanLoadedMonEvolveWithStone')
                self.assertEqual(bool(h.last_call_registers['F'] & 0x10), expected)

    def test_mist_chooser_filters_locked_targets_and_reloads_selected_source(self):
        self.baseline()
        h = self.harness
        offers = []
        menu = parse_rgbds_constants(REPO_ROOT / 'constants/menu_constants.asm')

        def offer(_):
            offers.append(h.read8('wNamedObjectIndex'))
            self.presentation_ret(None)

        def yes(_):
            h.write8('wMenuExitMethod', menu['CHOSE_FIRST_ITEM'])
            self.presentation_ret(None)

        h.register_hook('PrintText', offer)
        h.register_hook('DisplayTextBoxID', yes)
        for enabled in (3, 7):
            with self.subTest(enabled=enabled):
                self.source('MISDREAVUS', 0, 'MIST_STONE', enabled)
                h.write8('wLoadedMonSpecies', SPECIES['VULPIX'])
                h.write8('wLoadedMonCatchRate', 1 << 5)  # stale last menu row
                offers.clear()
                h.call_routine('MistStoneChooseEvolution')
                self.assertEqual(offers, [SPECIES['MISMAGIUS']] if enabled & 4 else [])
                self.assertEqual(bool(h.last_call_registers['F'] & 0x10), bool(enabled & 4))

    def test_trade_into_warp_is_blocked_in_johto(self):
        self.baseline()
        self.stub_presentation()
        h = self.harness
        serial = parse_rgbds_constants(REPO_ROOT / 'constants/serial_constants.asm')
        for enabled in (3, 7):
            with self.subTest(enabled=enabled):
                self.source('PORYGON2', 0, None, enabled, level=1)
                h.write8('wLinkState', serial['LINK_STATE_TRADING'])
                h.write8('wForceEvolution', 0)
                h.call_routine('TryEvolvingMon')
                self.assertEqual(h.read8('wPartyMon1Species'),
                                 SPECIES['PORYGON_Z' if enabled & 4 else 'PORYGON2'])
