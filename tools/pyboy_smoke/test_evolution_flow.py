"""Evolution lifecycle through real enemy KOs, animation and victory cleanup.

The fixture seeds eligibility at the first post-EXP dispatch, then lets the ROM
own all evolution, cancellation, screen restoration and recovery sequencing.
"""
import unittest
from source_constants import parse_rgbds_constants, parse_trainer_constants
from test_smoke import HarnessTestCase, REPO_ROOT

SPECIES = parse_rgbds_constants(REPO_ROOT / 'constants/pokemon_constants.asm')
MOVES = parse_rgbds_constants(REPO_ROOT / 'constants/move_constants.asm')
TRAINERS = parse_trainer_constants(REPO_ROOT / 'constants/trainer_constants.asm')


class EvolutionFlowFixture:
    def run_evolution(self, *, flags=3, cancel=False, opponents=2, ironman=False):
        h = self.harness
        mon = lambda name, level, move: dict(species=SPECIES[name], level=level, moves=[MOVES[move]])
        h.inject_fight2_spec(
            [mon('BULBASAUR', 16, 'TACKLE'), mon('CHARMANDER', 16, 'TACKLE')],
            [mon('MAGIKARP', 2, 'SPLASH')] * opponents,
            trainer_class=TRAINERS['COOLTRAINER_M'], ai_tier=0,
        )
        h.boot_fight2(seed=1)
        h.write8('wOptions', h.read8('wOptions') | 0x40)  # SET: no switch prompt
        if h.hardware_mode == 'CGB':
            h.write8('wOptions2', h.read8('wOptions2') | 0xc0)
        h.write_sram_bytes('sKeyItemsBitfield', [0x0f])  # Leftovers + PP Tonic active
        if ironman:
            options = parse_rgbds_constants(REPO_ROOT / 'constants/ram_constants.asm')
            h.write8('wOptions3', h.read8('wOptions3') | (1 << options['BIT_IRONMAN']))
            h.write8('wPartyMon2HP', 0)
            h.write8('wPartyMon2HP', 0, 1)
        events = []
        final = {}
        seeded = []
        def seed(_):
            if not seeded:
                h.write8('wCanEvolveFlags', flags)
                seeded.append(True)
        h.register_hook('RogueTryMidBattleEvolution', seed)
        for label in ('EvolveMon', 'RogueRefreshBattleMonAfterEvolution',
                      'Evolution_ReloadTilesetTilePatterns', 'EndOfBattle',
                      'LeftoversRecovery', 'PPTonicRecovery',
                      'IronmanReleaseFaintedMons', 'EndOfBattle.clearBattleState', 'CrashScreen'):
            def record(_, label=label):
                if label == 'EndOfBattle.clearBattleState':
                    final.update(active=h.read8('wPartyMon1Species'), bench=h.read8('wPartyMon2Species'), count=h.read8('wPartyCount'))
                events.append((label, h.read8('hWhichPokemon'), tuple(h.read_bytes('wPartySpecies', 3))))
            h.register_hook(label, record)
        def recovery_text(_):
            if h.pyboy.register_file.HL == h.address('PartyHPAndPPRecoveredText') and h.read8('hLoadedROMBank') == h.symbols.bank('PartyHPAndPPRecoveredText'):
                events.append(('PartyHPAndPPRecoveredText', h.read8('hWhichPokemon'), ()))
        h.register_hook('PrintText', recovery_text)
        fast_vram = []
        def fast_copy(_):
            r = h.pyboy.register_file
            if 0x80 <= r.D < 0xa0:
                fast_vram.append((r.D * 256 + r.E, r.HL))
        h.register_hook('CopyVideoData', fast_copy)
        vblank_modes = []
        def vblank_copy(_):
            if 0x8000 <= h.pyboy.register_file.SP < 0xa000:
                vblank_modes.append(h.pyboy.memory[0xff41] & 3)
        h.register_hook('VBlankCopy.loop', vblank_copy)
        for frame in range(6500):
            evolving = sum(e[0] == 'EvolveMon' for e in events)
            refreshed = any(e[0] == 'RogueRefreshBattleMonAfterEvolution' for e in events)
            if cancel and evolving and not refreshed and not any(e[0] == 'EndOfBattle' for e in events):
                h.pyboy.button_press('b')
            else:
                h.pyboy.button_release('b')
            if frame % 12 == 0:
                h.pyboy.button_press('a')
            elif frame % 12 == 2:
                h.pyboy.button_release('a')
            h.tick(1)
            if any(e[0] in ('EndOfBattle.clearBattleState', 'CrashScreen') for e in events):
                break
        labels = [e[0] for e in events]
        self.assertNotIn('CrashScreen', labels, events)
        self.assertIn('EndOfBattle.clearBattleState', labels, h.diagnostic_state())
        self.assertEqual(fast_vram, [], 'VRAM reads must not use the write-only-safe HBlank copier')
        self.assertTrue(vblank_modes, events)
        self.assertEqual(set(vblank_modes), {1}, 'VRAM-source tile reads must stay in VBlank')
        before_end = events[:labels.index('EndOfBattle')]
        self.assertTrue(all(e[1] == 0 for e in before_end if e[0] == 'EvolveMon'), events)
        self.assertFalse(any(e[0] == 'Evolution_ReloadTilesetTilePatterns' for e in before_end), events)
        before_evolutions = [e for e in before_end if e[0] == 'EvolveMon']
        self.assertEqual(len(before_evolutions), int(bool(flags & 1) and opponents > 1), events)
        after_end = events[labels.index('EndOfBattle'):]
        after_labels = [e[0] for e in after_end]
        self.assertIn('PartyHPAndPPRecoveredText', after_labels, events)
        for i, event in enumerate(after_end):
            if event[0] == 'EvolveMon':
                self.assertGreater(i, after_labels.index('PartyHPAndPPRecoveredText'), events)
        expected_active = 'BULBASAUR' if cancel or not flags & 1 else 'IVYSAUR'
        self.assertEqual(final['active'], SPECIES[expected_active], events)
        if ironman:
            self.assertEqual(final['count'], 1, events)
            self.assertFalse(any(e[0] == 'EvolveMon' and e[1] == 1 for e in events), events)
        else:
            self.assertEqual(final['bench'], SPECIES['CHARMELEON' if flags & 2 else 'CHARMANDER'], events)
        self.assertEqual(sum(e[0] == 'EvolveMon' and e[1] == 0 for e in events), int(bool(flags & 1)), events)


class EvolutionFlowTest(EvolutionFlowFixture, HarnessTestCase):
    def test_active_midbattle_and_bench_after_recovery(self):
        self.run_evolution()

    def test_bench_only_waits_until_after_recovery(self):
        self.run_evolution(flags=2)

    def test_cancel_restores_battle_without_end_battle_retry(self):
        self.run_evolution(cancel=True)

    def test_last_opponent_uses_post_recovery_evolution(self):
        self.run_evolution(opponents=1)

    def test_ironman_filters_fainted_bench_before_party_compaction(self):
        self.run_evolution(ironman=True)

    def test_wild_context_does_not_scan_an_enemy_trainer_party(self):
        h = self.harness
        h.boot_fight2(seed=1)
        h.write8('hIsInBattle', 1)
        h.write8('wEnemyPartyCount', 0)
        h.write8('wCanEvolveFlags', 3)
        scan = h.hook_flag('AnyEnemyPokemonAliveCheck')
        h.call_routine('RogueTryMidBattleEvolution')
        self.assertEqual(scan['count'], 0)
        self.assertEqual(h.read8('wCanEvolveFlags'), 3)


if __name__ == '__main__':
    unittest.main()


