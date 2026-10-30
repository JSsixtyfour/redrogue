"""Forced DEBUG 2 gym maps must agree with signs and badge-slot identities."""
from source_constants import parse_map_constants, parse_trainer_class_indexes
from test_smoke import HarnessTestCase, REPO_ROOT
import test_gym_choice as gym_choice


def trainer_classes():
    return parse_trainer_class_indexes(REPO_ROOT / 'constants/trainer_constants.asm')


class Debug2GymIdentityTest(HarnessTestCase):
    def test_both_blackthorn_choices_share_clair_identity(self):
        h = self.harness
        maps = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
        trainers = trainer_classes()

        def force_doors(_):
            h.write8('wDebug2ForcedDoor1', 16)
            h.write8('wDebug2ForcedDoor2', 16)

        h.register_hook('SelectAndPatchLobbyExit', force_doors)
        h.boot_to_lobby(battle_count=6)
        self.assertEqual(h.read8('wLobbyDoor1StageMap'), maps['BLACKTHORN_GYM'])
        self.assertEqual(h.read8('wLobbyDoor2StageMap'), maps['BLACKTHORN_GYM'])
        self.assertEqual(h.read8('wRogueMap'), maps['BLACKTHORN_GYM'])
        choice = h.read8('wGymChoice')
        slot = choice & 7
        self.assertEqual((choice >> 3) & 7, slot)
        self.assertEqual(h.read8('wRunGymLineup', offset=slot), trainers['CLAIR'])
        self.assertEqual(h.read8('wRogueCurGymBadgeMask'), 1 << slot)
        self.assertEqual(h.read8('wDebug2ForcedDoor1'), 0)
        self.assertEqual(h.read8('wDebug2ForcedDoor2'), 0)

        # The explicitly selected single gym is already known.
        self.assertTrue(choice & 0x40)
        self.assertEqual(gym_choice.GymChoiceLobbyTest.sign(self, 1), ('BLACKTHORN GYM', 'CLAIR/DRAGON'))

        h.write8('hCurMap', maps['BLACKTHORN_GYM'])
        h.write8('wRogueCurGymBadgeMask', 0)
        h.call_routine('RogueGymChoiceMapLoad')
        self.assertEqual(h.read8('wRogueCurGymBadgeMask'), 1 << slot)
        h.call_routine('RogueAwardCurrentGymBadge')
        self.assertEqual(h.read8('wObtainedBadges'), 1 << slot)

    def test_distinct_forced_gyms_swap_existing_leaders_without_duplicates(self):
        h = self.harness
        maps = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
        trainers = trainer_classes()
        h.boot_to_lobby(battle_count=6)
        lineup = ['BROCK', 'CLAIR', 'MISTY', 'ERIKA', 'KOGA', 'SABRINA', 'PRYCE', 'GIOVANNI']
        for slot, leader in enumerate(lineup):
            h.write8('wRunGymLineup', trainers[leader], offset=slot)
        h.write8('wGymChoice', 0x80 | (2 << 3))
        h.write8('wLobbyDoor1StageMap', maps['BLACKTHORN_GYM'])
        h.write8('wLobbyDoor2StageMap', maps['MAHOGANY_GYM'])
        h.call_routine('Debug2SyncGymChoice')
        expected = ['CLAIR', 'BROCK', 'PRYCE', 'ERIKA', 'KOGA', 'SABRINA', 'MISTY', 'GIOVANNI']
        self.assertEqual(h.read_bytes('wRunGymLineup', 8), [trainers[x] for x in expected])
        self.assertEqual(h.read8('wGymChoice'), 0x80 | (2 << 3))
        self.assertEqual(h.read8('wRogueMap'), maps['BLACKTHORN_GYM'])

    def test_final_badge_keeps_one_destination_and_fuchsia_keeps_janine(self):
        h = self.harness
        maps = parse_map_constants(REPO_ROOT / 'constants/map_constants.asm')
        trainers = trainer_classes()
        h.boot_to_lobby(battle_count=61)
        h.write8('wGymChoice', 0x80 | 7 | (7 << 3))
        # Supply a valid unique lineup. The seeded roster may already contain
        # Janine elsewhere; overwriting only slot3 would manufacture a duplicate.
        lineup = ['BROCK', 'CLAIR', 'MISTY', 'JANINE', 'ERIKA', 'SABRINA', 'PRYCE', 'GIOVANNI']
        for slot, leader in enumerate(lineup):
            h.write8('wRunGymLineup', trainers[leader], offset=slot)
        h.write8('wLobbyDoor1StageMap', maps['FUCHSIA_GYM'])
        h.write8('wLobbyDoor2StageMap', maps['BLACKTHORN_GYM'])
        h.call_routine('Debug2SyncGymChoice')
        self.assertEqual(h.read8('wLobbyDoor2StageMap'), maps['FUCHSIA_GYM'])
        self.assertEqual(h.read8('wRunGymLineup', offset=7), trainers['JANINE'])
        self.assertEqual(h.read_bytes('wRunGymLineup', 8).count(trainers['JANINE']), 1)
