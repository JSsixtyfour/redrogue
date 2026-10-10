"""ROM policy coverage over every reachable quota state and door choice."""
import io
from itertools import product

from test_smoke import HarnessTestCase, REPO_ROOT
from source_constants import parse_map_constants, parse_rgbds_constants, parse_trainer_class_indexes

ROUNDS = parse_rgbds_constants(REPO_ROOT / 'constants/round_constants.asm')
# Back-to-back gyms: no route is selected at these badge counts (gym-next stays set).
PAIRS = (ROUNDS['PAIR_BADGES_A'], ROUNDS['PAIR_BADGES_B'])
ROUTE_BADGES = [b for b in range(1, 8) if b not in PAIRS]
HALF_ENDS = (max(b for b in ROUTE_BADGES if b < 4), max(ROUTE_BADGES))


def return_now(h, value):
    r = h.pyboy.register_file
    r.A = value
    address = h.pyboy.memory[r.SP] | h.pyboy.memory[r.SP + 1] << 8
    r.SP += 2
    r.PC = address


class SpecialScheduleTest(HarnessTestCase):
    def setUp(self):
        super().setUp()
        h = self.harness
        h.boot_to_lobby(battle_count=17)
        h.park_before_hijack()
        h.write8('wStatusFlags6', 0)
        self.maps = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
        self.wild = {self.maps[n] for n in ('PROCEDURAL_CAVE_1', 'PROCEDURAL_FOREST',
                                          'PROCEDURAL_CEMETERY_1', 'PROCEDURAL_FACILITY')}
        self.saved = io.BytesIO()
        h.save_state(self.saved)

    def reset(self):
        self.saved.seek(0)
        self.harness.load_state(self.saved)

    def setup_selection(self, badges, mini, wild, pressure):
        h = self.harness
        h.write8('wObtainedBadges', (1 << badges) - 1)
        h.write8('wBattleCount', badges * 8 + 1)
        h.write8('wRogueFlagsBitfield', 2)
        h.write8('wMiniBossCount', mini)
        h.write8('wWildAreaState', wild << 3)
        h.write8('wRoutesSinceSpecial', pressure)
        h.write8('wRogueMap', self.maps['ROUTE_1'])
        h.write8('wLobbyDoor1StageMap', self.maps['ROUTE_1'])
        h.write8('wLobbyDoor2StageMap', self.maps['ROUTE_1'])

    def test_every_reachable_policy_outcome_meets_both_half_run_quotas(self):
        h = self.harness
        bank, start = h.symbols.get('SpecialEncounterRollAndAssign')
        target_bank, target = h.symbols.get('SpecialEncounterPolicy')
        trampoline = h.address('Bankswitch')
        farcall = bytes([0x06, target_bank, 0x21, target & 255, target >> 8,
                         0xcd, trampoline & 255, trampoline >> 8])
        rom = h.rom_path.read_bytes()
        offset = bank * 0x4000 + start - 0x4000
        ready = start + rom[offset:offset + 180].index(farcall) + len(farcall)
        ret = h.address('MiniBossPickTypeAndStage') - 1
        self.assertEqual(rom[bank * 0x4000 + ret - 0x4000], 0xc9)
        result = []
        draws = []

        def capture(_):
            result.append(h.pyboy.register_file.E)
            h.pyboy.register_file.PC = ret  # skip assignment; test every allowed choice below

        def random(_):
            if h.read8('hLoadedROMBank') == target_bank:
                return_now(h, draws.pop(0) if draws else 255)

        h.pyboy.hook_register(bank, ready, capture, None)
        h.register_hook('Random', random)
        self.saved = io.BytesIO()
        h.save_state(self.saved)
        states = {(0, 0, 0)}
        probes = 0
        try:
            for badges in ROUTE_BADGES:
                following = set()
                for mini, wild, pressure in states:
                    # All comparison boundaries of the 25/50/75% curve and
                    # the independent optional mixed-door coin.
                    for chance, mixed in product((0, 63, 64, 127, 128, 191, 192, 255), (0, 255)):
                        self.reset()
                        self.setup_selection(badges, mini, wild, pressure)
                        draws[:] = [chance, mixed]
                        result.clear()
                        h.call_routine('SpecialEncounterRollAndAssign')
                        self.assertEqual(len(result), 1)
                        policy = result[0]
                        probes += 1
                        self.assertEqual(h.read8('wMiniBossCount'), mini)
                        self.assertEqual(h.read8('wWildAreaState') >> 3 & 3, wild)
                        choices = []
                        if not policy & (4 | 8):
                            choices.append((mini, wild, h.read8('wRoutesSinceSpecial')))
                        if policy & 1:
                            choices.append((mini + 1, wild, 0))
                        if policy & 2:
                            choices.append((mini, wild + 1, 0))
                        self.assertTrue(choices)
                        for next_state in choices:
                            cap = 1 if badges < 4 else 2
                            self.assertLessEqual(next_state[0], cap)
                            self.assertLessEqual(next_state[1], cap)
                            if badges in HALF_ENDS:  # each half's last route
                                self.assertEqual(next_state[:2], (cap, cap))
                            following.add(next_state)
                states = following
            self.assertTrue(all(s[:2] == (2, 2) for s in states))
            print(f'\nSpecial policy: {probes} ROM probes over route counts {ROUTE_BADGES}; '
                  'all reachable choices meet 1+1 / 2+2 quotas')
        finally:
            h.pyboy.hook_deregister(bank, ready)

    def test_mixed_and_mandatory_doors_and_completion_accounting(self):
        h = self.harness
        self.setup_selection(1, 0, 0, 0)  # two requirements, two slots (badges 1 and 2)
        h.call_routine('SpecialEncounterRollAndAssign')
        flags = h.read8('wRogueFlagsBitfield')
        self.assertNotEqual(flags & 0x30, 0)
        boss_door = 1 if flags & 0x40 else 0
        doors = [h.read8('wLobbyDoor1StageMap'), h.read8('wLobbyDoor2StageMap')]
        self.assertIn(doors[1 - boss_door], self.wild)
        self.assertNotIn(doors[boss_door], self.wild)
        self.assertEqual(h.read8('wMiniBossCount'), 0)
        self.assertEqual(h.read8('wWildAreaState') >> 3 & 3, 0)
        h.write8('hCurMap', doors[boss_door])
        h.call_routine('MiniBossCheckActivate')
        classes = parse_trainer_class_indexes(REPO_ROOT / 'constants/trainer_constants.asm')
        h.write8('wTrainerClass', classes['YOUNGSTER'])
        h.call_routine('RecordMiniBossVictory')
        self.assertEqual(h.read8('wMiniBossCount'), 0)
        boss_class = ('RIVAL_MINIBOSS', 'GIOVANNI_MINIBOSS', 'KARATE_MINIBOSS')[(flags >> 4 & 3) - 1]
        h.write8('wTrainerClass', classes[boss_class])
        h.write8('wGymLeaderNo', 0)
        victory = h.address('TrainerBattleVictory')
        h.register_hook('TrainerBattleVictory.creditsDone',
                        lambda _: setattr(h.pyboy.register_file, 'PC', victory - 1))
        h.call_routine('TrainerBattleVictory')
        self.assertEqual(h.read8('wMiniBossCount'), 1)
        self.assertEqual(h.read8('wRoutesSinceSpecial'), 0)
        for mini, wild, expected in ((1, 0, 'wild'), (0, 1, 'mini')):
            self.reset()
            self.setup_selection(HALF_ENDS[0], mini, wild, 0)  # the half's last route
            h.call_routine('SpecialEncounterRollAndAssign')
            door = h.read8('wLobbyDoor1StageMap')
            self.assertEqual(door, h.read8('wLobbyDoor2StageMap'))
            self.assertEqual(door in self.wild, expected == 'wild')

    def test_gift_windows_all_choices_and_visit_not_offer_accounting(self):
        h = self.harness
        start = h.address('BridgeShouldOccur')
        stop = h.address('BridgeGuaranteeThresholds')
        bank = h.symbols.bank('BridgeShouldOccur')
        choose_last = [False]

        def range_roll(_):
            r = h.pyboy.register_file
            caller = h.pyboy.memory[r.SP] | h.pyboy.memory[r.SP + 1] << 8
            if h.read8('hLoadedROMBank') == bank and start <= caller < stop:
                return_now(h, r.C - 1 if choose_last[0] else 0)

        h.register_hook('Rangerandom', range_roll)
        self.saved = io.BytesIO()
        h.save_state(self.saved)
        states = {0}
        for badges in range(8):
            following = set()
            for count, last in product(states, (False, True)):
                self.reset()
                self.setup_selection(badges, 0, 0, 0)
                h.write8('wBridgeState', count << 6)
                h.write8('wBridgeOfferedLo', 0)
                h.write8('wRogueFlagsBitfield', 3)
                gym = self.maps['PEWTER_GYM']
                for name in ('wRogueMap', 'wLobbyDoor1StageMap', 'wLobbyDoor2StageMap'):
                    h.write8(name, gym)
                choose_last[0] = last
                h.call_routine('BridgeRollAndAssign')
                self.assertEqual(h.read8('wBridgeState') >> 6, count)
                door = h.read8('wLobbyDoor1StageMap')
                if door != gym:
                    # Windows end before each pair's lobby, which never hosts a gift.
                    self.assertIn(badges, (1, 2) if count == 0 else (4, 5))
                    self.assertNotEqual(door, h.read8('wLobbyDoor2StageMap'))
                    h.write8('hCurMap', door)
                    h.write8('wWarpedFromWhichMap', self.maps['INDIGO_PLATEAU_LOBBY'])
                    h.call_routine('RecordStageMapLoad')
                    h.call_routine('RecordStageMapLoad')  # reload is not a second visit
                    self.assertEqual(h.read8('wRogueMap'), gym)
                    self.assertEqual(h.read8('wBridgeState') >> 6, count + 1)
                result = h.read8('wBridgeState') >> 6
                if badges == 3:
                    self.assertEqual(result, 1)
                if badges >= 6:
                    self.assertEqual(result, 2)
                following.add(result)
            states = following
        self.reset()
        self.setup_selection(3, 0, 0, 0)
        h.write8('wBridgeState', 0)
        h.call_routine('BridgeRollAndAssign')
        self.assertEqual(h.read8('wLobbyDoor1StageMap'), self.maps['ROUTE_1'])

    def test_miniboss_sign_pointers_include_door_boss_prize_and_preserve_cursor(self):
        h = self.harness
        bank, entry = h.symbols.get('LobbyMiniBossSign')
        ret = h.address('LobbyMiniBossSign.texts') - 1
        result = []
        category = [0]

        def setup(_):
            r = h.pyboy.register_file
            r.A = category[0]
            r.B, r.C = 0x12, 0x34

        def capture(_):
            r = h.pyboy.register_file
            result.append((r.HL, r.B << 8 | r.C))

        h.register_hook('LobbyMiniBossSign', setup)
        h.pyboy.hook_register(bank, ret, capture, None)
        try:
            for door, boss, reward in product(range(2), range(3), range(4)):
                h.write8('wRogueFlagsBitfield', (boss + 1) << 4 | door << 6)
                category[0] = reward
                result.clear()
                h.call_routine('LobbyMiniBossSign')
                name = (f'LobbyMiniBossSign.LobbyDoor{door + 1}'
                        f'{("Rival", "Giovanni", "Karate")[boss]}'
                        f'{("Healing", "Stat", "TM", "Money")[reward]}')
                self.assertEqual(result, [(h.address(name), 0x1234)])
        finally:
            h.pyboy.hook_deregister(bank, ret)
