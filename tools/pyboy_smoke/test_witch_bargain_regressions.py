"""Prize offers never repeat an earned prize, and Game Corner survives a trainer win.

Both found by the witch autoplay campaign, 2026-11-04. The old prize roll took its
16th draw unchecked, which offered a duplicate about 18.5% of the time with nine
prizes owned. Game Corner's one-row script table sent the first win into code bytes.
"""
import re

from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_legendary_boss import enable_expansions
from test_move_tutor_prices import return_from_call
from test_smoke import HarnessTestCase, REPO_ROOT

ROUNDS = parse_rgbds_constants(REPO_ROOT / 'constants/round_constants.asm')
RAM = parse_rgbds_constants(REPO_ROOT / 'constants/ram_constants.asm', ROUNDS)
SPECIES = parse_rgbds_constants(REPO_ROOT / 'constants/pokemon_constants.asm')
UBER = 1 << RAM['BIT_WITCH_UBER_RECEIVED']
ALL_PRIZES = (0xFF, 0x03)


def script_tables():
    """(file, rows) for each map script with trainers that dispatches through a table."""
    for path in sorted((REPO_ROOT / 'scripts').glob('*.asm')):
        lines = path.read_text(encoding='utf-8', errors='ignore').splitlines()
        code = '\n'.join(line.split(';')[0] for line in lines if not line.lstrip().startswith(';'))
        if 'ExecuteCurMapScriptInTable' not in code or not re.search(r'^\s*trainer\s+EVENT', code, re.M):
            continue
        table = re.search(r'_ScriptPointers:\s*\n\s*def_script_pointers\s*\n((?:\s*dw_const.*\n)*)', code)
        if table:
            yield path.name, re.findall(r'dw_const\s+(\w+)', table.group(1))


class ScriptTableTest(HarnessTestCase):
    def test_every_map_with_trainers_has_a_row_for_the_post_battle_index(self):
        # TalkToTrainer and StartTrainerBattle each advance wCurMapScript: a win runs row 2.
        tables = dict(script_tables())
        self.assertIn('Route9.asm', tables, 'the scan found nothing to check')
        for name, rows in tables.items():
            with self.subTest(map=name):
                self.assertGreaterEqual(len(rows), 3, rows)

    def test_game_corner_row_two_is_end_trainer_battle(self):
        h = self.harness
        bank, table = h.symbols.get('GameCorner_ScriptPointers')
        word = h.pyboy.memory[bank, table + 4] | h.pyboy.memory[bank, table + 5] << 8
        self.assertEqual(word, h.address('EndTrainerBattle'))


    def test_game_corner_gamblers_use_their_sight_ranges(self):
        h = self.harness
        bank, script = h.symbols.get('GameCornerDefaultScript')
        target = h.address('CheckFightingMapTrainers')
        call = bytes([0xCD, target & 0xFF, target >> 8])
        self.assertIn(call, bytes(h.pyboy.memory[bank, script + i] for i in range(12)))


class PrizeOfferTest(HarnessTestCase):
    def setUp(self):
        super().setUp()
        h = self.harness
        h.boot_to_lobby()
        h.tick(180)
        h.park_before_hijack()
        h.write8('wStatusFlags6', h.read8('wStatusFlags6') | (1 << RAM['BIT_DEBUG_MODE']))
        h.write8('wRogueFlagsBitfield', 0)
        h.write8('wBattleCount', ROUNDS['ROUND_BATTLES'] + 1)
        h.write8('wLobbyDoor1StageMap', h.TARGET_ROUTE)
        h.write8('wLobbyDoor2StageMap', h.TARGET_ROUTE)
        self.draws = {'challenge': 0, 'prize': 0}
        self.prize_answers = []
        challenge_caller = h.address('PCWitchSetup.rollChallenge') + 5  # ld c,N; call
        prize_caller = h.address('PCWitchSetup.rollPrize') + 5

        def draw(_):
            registers = h.pyboy.register_file
            sp = registers.SP
            caller = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
            if caller == challenge_caller:
                self.draws['challenge'] += 1
                registers.A = RAM['CHALLENGE_NO_MONEY'] - 1
            elif caller == prize_caller:
                self.draws['prize'] += 1
                registers.A = self.prize_answers.pop(0) - 1
            else:
                return
            return_from_call(h)

        h.register_hook('Rangerandom', draw)

    def earned(self, low, high):
        self.harness.write8('wWitchPrizesEarned', low)
        self.harness.write8('wWitchPrizesEarned', high, offset=1)

    def offerable_legendary(self):
        """Four badges, two doors to Sabrina, a masterball-class mon: Challenge 11's gate."""
        h = self.harness
        classes = parse_trainer_class_indexes(REPO_ROOT / 'constants/trainer_constants.asm')
        for i, name in enumerate(('BROCK', 'SABRINA', 'MORTY', 'JASMINE', 'CLAIR', 'MISTY', 'LT_SURGE', 'KOGA')):
            h.write8('wRunGymLineup', classes[name], offset=i)
        h.write8('wObtainedBadges', 0b11110000)
        h.write8('wGymChoice', 1 << RAM['BIT_GYM_CHOICE_LATCHED'] | 1 | 1 << 3)
        h.write8('wPartySpecies', SPECIES['MEWTWO'])
        h.write8('wPartySpecies', 0xFF, offset=1)
        h.write8('wBoxCount', 0)
        h.write8('wBoxSpecies', 0xFF)
        enable_expansions(h)

    def offer(self):
        h = self.harness
        h.call_routine('PCWitchSetup')
        return h.read8('wWitchChallenge'), h.read8('wWitchPrize')

    def test_nine_owned_always_offers_the_missing_prize(self):
        # Past the old 16-draw budget, where the old roll took an owned prize.
        missing = RAM['PRIZE_EXP_BOOST']
        self.earned(0xFF & ~(1 << (missing - 1)), 0x03)
        owned = RAM['PRIZE_MONEY']
        self.prize_answers = [owned] * 24 + [missing]
        self.assertEqual(self.offer(), (RAM['CHALLENGE_NO_MONEY'], missing))
        self.assertEqual(self.draws['prize'], 25)

    def test_the_uber_flag_does_not_count_as_a_prize(self):
        self.earned(0, UBER)
        self.prize_answers = [RAM['PRIZE_MONEY']]
        self.assertEqual(self.offer(), (RAM['CHALLENGE_NO_MONEY'], RAM['PRIZE_MONEY']))

    def test_ten_owned_without_a_legendary_door_means_no_witch(self):
        self.earned(*ALL_PRIZES)
        self.assertEqual(self.offer(), (0, 0))
        self.assertEqual(self.draws, {'challenge': 0, 'prize': 0})

    def test_ten_owned_still_offers_the_legendary_with_no_prize(self):
        self.offerable_legendary()
        self.earned(*ALL_PRIZES)
        self.assertEqual(self.offer(), (RAM['CHALLENGE_LEGENDARY_BOSS'], 0))
        self.assertEqual(self.draws['prize'], 0)

    def test_one_received_legendary_per_run_until_endless(self):
        self.offerable_legendary()
        self.earned(ALL_PRIZES[0], ALL_PRIZES[1] | UBER)
        self.harness.write8('wEndlessDepth', 0)
        self.assertEqual(self.offer(), (0, 0), 'a second legendary before Endless')
        self.harness.park_before_hijack()
        self.harness.write8('wEndlessDepth', 1)
        self.assertEqual(self.offer(), (RAM['CHALLENGE_LEGENDARY_BOSS'], 0))
