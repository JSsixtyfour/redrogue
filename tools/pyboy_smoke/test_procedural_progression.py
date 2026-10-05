"""Procedural stages replace one route, including its progression bookkeeping."""
import io

from test_smoke import HarnessTestCase, REPO_ROOT
from source_constants import parse_map_constants


class ProceduralProgressionTest(HarnessTestCase):
    def setUp(self):
        super().setUp()
        self.harness.boot_to_lobby(battle_count=17)
        self.maps = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
        self.harness.park_before_hijack()
        self.state = io.BytesIO()
        self.harness.pyboy.save_state(self.state)

    def restore(self):
        self.state.seek(0)
        self.harness.pyboy.load_state(self.state)

    def test_each_procedural_exit_credits_four_and_selects_third_gym(self):
        h = self.harness
        for name in ('PROCEDURAL_CAVE_1', 'PROCEDURAL_FOREST',
                     'PROCEDURAL_FACILITY', 'PROCEDURAL_CEMETERY_4'):
            with self.subTest(map=name):
                self.restore()
                h.write8('hCurMap', self.maps['INDIGO_PLATEAU_LOBBY'])
                h.write8('wWarpedFromWhichMap', self.maps[name])
                h.write8('wBattleCount', 17)
                h.write8('wObtainedBadges', 3)
                h.write8('wRogueFlagsBitfield', 2)
                h.call_routine('ProcStageLoadDispatch')
                self.assertEqual(h.read8('wBattleCount'), 21)
                self.assertEqual(h.read8('wRogueFlagsBitfield'), 3)
                h.call_routine('_PickNextStage')
                gyms = {value for key, value in self.maps.items() if key.endswith('_GYM')}
                self.assertIn(h.read8('wRogueMap'), gyms)

    def test_procedural_npc_victories_do_not_advance_battle_count(self):
        h = self.harness
        # Stop after the real progression/credit gate, before presentation.
        # The preceding function ends in RET, verified from the built ROM.
        bank, entry = h.symbols.get('TrainerBattleVictory')
        rom = h.rom_path.read_bytes()
        self.assertEqual(rom[bank * 0x4000 + entry - 0x4000 - 1], 0xc9)
        h.register_hook('TrainerBattleVictory.creditsDone',
                        lambda _: setattr(h.pyboy.register_file, 'PC', entry - 1))
        for name in ('PROCEDURAL_CAVE_1', 'PROCEDURAL_FOREST',
                     'PROCEDURAL_FACILITY', 'PROCEDURAL_CEMETERY_1',
                     'PROCEDURAL_CEMETERY_2', 'PROCEDURAL_CEMETERY_3',
                     'PROCEDURAL_CEMETERY_4', 'ROUTE_1', 'VICTORY_ROAD_1F'):
            with self.subTest(map=name):
                # Keep hooks installed; these calls stop before any map scripts run.
                h.write8('hCurMap', self.maps[name])
                h.write8('wBattleCount', 17)
                h.write8('wGymLeaderNo', 0)
                before = h.read8('wCreditsEarnedThisRun')
                h.call_routine('TrainerBattleVictory')
                expected = 17 if name.startswith('PROCEDURAL_') else 18
                self.assertEqual(h.read8('wBattleCount'), expected)
                self.assertEqual(h.read8('wCreditsEarnedThisRun'), before)

    def test_non_lobby_transitions_do_not_complete_procedural_stage(self):
        h = self.harness
        # Exercise the exit gate without running the destination's generator.
        # The PALLET_TOWN branch ends in RET immediately before .notPalletTown.
        bank, address = h.symbols.get('ProcStageLoadDispatch.notPalletTown')
        self.assertEqual(h.rom_path.read_bytes()[bank * 0x4000 + address - 0x4000 - 1], 0xc9)
        h.register_hook('ProcStageLoadDispatch.noExitBattles',
                        lambda _: setattr(h.pyboy.register_file, 'PC', address - 1))
        for destination in ('PROCEDURAL_CEMETERY_3', 'SILPH_CO_DORM'):
            with self.subTest(destination=destination):
                h.write8('hCurMap', self.maps[destination])
                h.write8('wWarpedFromWhichMap', self.maps['PROCEDURAL_CEMETERY_4'])
                h.write8('wBattleCount', 17)
                h.write8('wRogueFlagsBitfield', 2)
                h.call_routine('ProcStageLoadDispatch')
                self.assertEqual(h.read8('wBattleCount'), 17)
                self.assertEqual(h.read8('wRogueFlagsBitfield'), 2)
