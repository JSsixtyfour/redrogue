"""Witch offer eligibility and progression-based party-limit quotes."""
import io

from source_constants import parse_map_constants, parse_rgbds_constants
from test_move_tutor_prices import return_from_call
from test_smoke import HarnessTestCase, REPO_ROOT

ROUNDS = parse_rgbds_constants(REPO_ROOT / 'constants/round_constants.asm')
RAM = parse_rgbds_constants(REPO_ROOT / 'constants/ram_constants.asm', ROUNDS)
MAPS = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
GYM_NEXT = 1 << RAM['BIT_ROGUE_GYM_NEXT']


class WitchChallengeOfferTest(HarnessTestCase):
    def setUp(self):
        super().setUp()
        h = self.harness
        h.boot_to_lobby()
        h.tick(180)  # finish the visit setup before parking
        h.park_before_hijack()
        self.saved = io.BytesIO()
        h.save_state(self.saved)

    def test_party_quote_counts_initial_and_route_rewards_at_each_visit(self):
        h = self.harness
        period = ROUNDS['ROUND_BATTLES']
        # Explicit expected quotes: route 2 / gym 2 = 2 / 3, not 3 / 3.
        # Paired gyms 4 and 7 receive their skipped route's replacement reward.
        route_limits = (1, 2, 3, 4, 5, 5, 5, 5, 5)
        gym_limits = (2, 3, 4, 5, 5, 5, 5, 5, 5)
        for round_index in range(ROUNDS['NUM_ROGUE_ROUNDS'] + 1):
            for gym_next, expected in ((False, route_limits[round_index]),
                                       (True, gym_limits[round_index])):
                for party_count in (1, 3, 6):
                    with self.subTest(round=round_index + 1, gym=gym_next,
                                      party_count=party_count):
                        h.load_state(self.saved)
                        h.write8('wBattleCount', round_index * period + (
                            ROUNDS['FIRST_GYM_STEP'] if gym_next else 1))
                        h.write8('wRogueFlagsBitfield', GYM_NEXT if gym_next else 0)
                        h.write8('wPartyCount', party_count)
                        h.write8('wWitchChallenge', RAM['CHALLENGE_PARTY_LIMIT'])
                        h.call_routine('WitchPrepChallengeParams')
                        self.assertEqual(h.read8('wPartyLimit'), expected)

    def test_reduced_reward_rarity_rerolls_for_gyms_but_not_routes_or_finale(self):
        h = self.harness
        draws = []
        caller = h.address('PCWitchSetup.rollChallenge') + 5  # ld c,N; call

        def challenge_roll(_):
            registers = h.pyboy.register_file
            stack = registers.SP
            return_address = h.pyboy.memory[stack] | h.pyboy.memory[stack + 1] << 8
            if return_address != caller:
                return
            # First offer worse reward luck, then a legal party-limit fallback.
            challenge = RAM['CHALLENGE_REDUCED_RARITY'] if not draws else RAM['CHALLENGE_PARTY_LIMIT']
            draws.append(challenge)
            self.assertLessEqual(len(draws), 2, 'legal fallback was rerolled')
            registers.A = challenge - 1
            return_from_call(h)

        h.register_hook('Rangerandom', challenge_roll)
        for label, gym_next, badges, count, destination, expected in (
                ('route 2', False, 1, ROUNDS['ROUND_BATTLES'] + 1,
                 h.TARGET_ROUTE, 'CHALLENGE_REDUCED_RARITY'),
                ('gym 2', True, 1, ROUNDS['ROUND_BATTLES'] + ROUNDS['FIRST_GYM_STEP'],
                 MAPS['PEWTER_GYM'], 'CHALLENGE_PARTY_LIMIT'),
                ('Victory Road with stale gym flag', True, 255,
                 ROUNDS['NUM_ROGUE_ROUNDS'] * ROUNDS['ROUND_BATTLES'] + 1,
                 MAPS['VICTORY_ROAD_1F'], 'CHALLENGE_REDUCED_RARITY')):
            with self.subTest(visit=label):
                h.load_state(self.saved)
                draws.clear()
                h.write8('wStatusFlags6', h.read8('wStatusFlags6') | (1 << RAM['BIT_DEBUG_MODE']))
                h.write8('wRogueFlagsBitfield', GYM_NEXT if gym_next else 0)
                h.write8('wObtainedBadges', badges)
                h.write8('wBattleCount', count)
                h.write8('wLobbyDoor1StageMap', destination)
                h.write8('wLobbyDoor2StageMap', destination)
                h.call_routine('PCWitchSetup')
                self.assertEqual(h.read8('wWitchChallenge'), RAM[expected])
                self.assertEqual(len(draws), 2 if expected == 'CHALLENGE_PARTY_LIMIT' else 1)
                if expected == 'CHALLENGE_PARTY_LIMIT':
                    self.assertEqual(h.read8('wPartyLimit'), 3)

    def test_turn_limit_quotes_are_unchanged(self):
        h = self.harness
        for round_index in range(ROUNDS['NUM_ROGUE_ROUNDS'] + 1):
            with self.subTest(round=round_index + 1):
                h.load_state(self.saved)
                h.write8('wBattleCount', round_index * ROUNDS['ROUND_BATTLES'] + 1)
                h.write8('wWitchChallenge', RAM['CHALLENGE_TURN_LIMIT'])
                h.call_routine('WitchPrepChallengeParams')
                self.assertEqual(h.read8('wBattleTurnLimit'), 6 + round_index)
