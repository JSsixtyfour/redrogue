"""Ghost variants retain their real typing through evolution and battle loads."""
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

SPECIES = parse_rgbds_constants(REPO_ROOT / 'constants/pokemon_constants.asm')
TYPES = parse_rgbds_constants(REPO_ROOT / 'constants/type_constants.asm')


class GhostImmunityTest(HarnessTestCase):
    def test_player_load_repairs_an_old_ghost_with_base_types(self):
        h = self.harness
        h.boot_to_lobby()
        h.write8('wPartyMon1Species', SPECIES['PARASECT'])
        h.write8('wBattleMonSpecies2', SPECIES['PARASECT'])
        h.write8('wPartyMon1Type2', TYPES['GRASS'])
        h.write8('wPartyMon1CatchRate', 1)
        h.write8('hWhichPokemon', 0)
        h.write8('wPlayerMonNumber', 0)
        h.call_routine('LoadBattleMonFromParty')
        self.assertEqual(h.read8('wBattleMonType2'), TYPES['GHOST'])

    def test_trainer_load_repairs_an_old_ghost_with_base_types(self):
        h = self.harness
        h.boot_to_lobby()
        h.write8('hIsInBattle', 2)
        h.write8('hWhichPokemon', 0)
        h.write8('wEnemyMon1Type2', TYPES['GRASS'])
        h.write8('wEnemyMon1CatchRate', 1)
        h.write8('wEnemyMonType2', TYPES['GRASS'])
        h.call_routine('GetEnemyCatchRateByte')
        self.assertEqual(h.read8('wEnemyMonType2'), TYPES['GHOST'])

    def test_enemy_party_switch_repairs_an_old_ghost(self):
        h = self.harness
        h.boot_to_lobby()
        h.write8('wEnemyMon1Species', SPECIES['PARASECT'])
        h.write8('wEnemyMon1Type2', TYPES['GRASS'])
        h.write8('wEnemyMon1CatchRate', 1)
        h.write8('hWhichPokemon', 0)
        h.call_routine('LoadEnemyMonFromParty')
        self.assertEqual(h.read8('wEnemyMonType2'), TYPES['GHOST'])

    def test_normal_damage_is_zero_with_ghost_in_either_slot(self):
        h = self.harness
        h.boot_to_lobby()
        for side in (0, 1):
            for ghost_slot in (0, 1):
                with self.subTest(side=side, ghost_slot=ghost_slot):
                    h.park_before_hijack()
                    h.write8('hWhoseTurn', side)
                    for mon in ('wBattleMonType', 'wEnemyMonType'):
                        h.write8(mon, TYPES['BUG'])
                        h.write8(mon, TYPES['BUG'], 1)
                    target = 'wBattleMonType' if side else 'wEnemyMonType'
                    h.write8(target, TYPES['GHOST'], ghost_slot)
                    h.write8('wPlayerMoveType', TYPES['NORMAL'])
                    h.write8('wEnemyMoveType', TYPES['NORMAL'])
                    h.write8('wDamage', 0)
                    h.write8('wDamage', 65, 1)
                    h.write8('wMoveMissed', 0)
                    h.call_routine('AdjustDamageForMoveType')
                    self.assertEqual(h.read_bytes('wDamage', 2), [0, 0])
                    self.assertNotEqual(h.read8('wMoveMissed'), 0)

    def test_evolved_ghost_keeps_its_secondary_type(self):
        self.check_evolution_types(1, 'GHOST')

    def test_ordinary_evolution_keeps_species_types(self):
        self.check_evolution_types(0, 'GRASS')

    def test_type_variant_evolution_keeps_its_stored_type(self):
        self.check_evolution_types(4, 'WATER')

    def check_evolution_types(self, flags, expected):
        h = self.harness
        h.boot_to_lobby()
        h.write8('wPartyMon1Species', SPECIES['PARASECT'])
        h.write8('wPartyMon1Type2', TYPES['WATER' if flags == 4 else 'GHOST'])
        h.write8('wPartyMon1CatchRate', flags)
        h.write8('wCurSpecies', SPECIES['PARASECT'])
        h.write8('wPokedexNum', SPECIES['PARASECT'])
        h.write8('wFormContextSpecies', SPECIES['PARASECT'])
        h.write8('wFormContextForm', 0)
        observed = []

        def enter(_):
            # This seam resumes with the party pointer saved on the stack.
            r = h.pyboy.register_file
            r.SP -= 2
            base = h.address('wPartyMon1')
            h.pyboy.memory[r.SP:r.SP + 2] = [base & 255, base >> 8]

        def capture(_):
            observed.append(h.read8('wPartyMon1Type2'))

        entry = 'Evolution_PartyMonLoop.finishedPostEvolutionLevelMove'
        exit_ = 'Evolution_PartyMonLoop.evolutionTypesSet'
        h.register_hook(entry, enter)
        h.register_hook(exit_, capture)
        try:
            h.probe_routine_until(entry, lambda: bool(observed), limit=120)
        finally:
            h.unregister_hook(entry, enter)
            h.unregister_hook(exit_, capture)
        self.assertEqual(observed, [TYPES[expected]])
