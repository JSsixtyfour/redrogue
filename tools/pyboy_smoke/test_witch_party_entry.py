"""Witch challenge 7 limits lobby-stage entry, not subsequent party growth."""
import io

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

RAM = parse_rgbds_constants(REPO_ROOT / 'constants/ram_constants.asm')
ACCEPTED = 1 << RAM['BIT_WITCH_ACCEPTED']


class WitchPartyEntryTest(HarnessTestCase):
    def setUp(self):
        super().setUp()
        self.harness.boot_to_lobby()
        # boot_to_lobby may park before this visit's PCWitchSetup finishes.
        self.harness.tick(180)
        self.harness.park_before_hijack()

    def arm(self, count, limit=3):
        h = self.harness
        h.write8('wWitchChallenge', RAM['CHALLENGE_PARTY_LIMIT'])
        h.write8('wPartyLimit', limit)
        h.write8('wRogueFlagsBitfield', h.read8('wRogueFlagsBitfield') | ACCEPTED)
        h.write8('wPartyCount', count)
        h.write8('wPartySpecies', 0xFF, offset=count)

    def skip_failure_text(self):
        """Exercise normal text dispatch/close; only bypass blocking PrintText."""
        h = self.harness
        seen = []

        def skip(_):
            rf = h.pyboy.register_file
            if rf.HL != h.address('WitchBargainBrokenText'):
                return
            seen.append((h.read8('hCurMap'), h.read8('wWarpedFromWhichWarp')))
            sp = rf.SP
            rf.PC = h.pyboy.memory[sp] | h.pyboy.memory[sp + 1] << 8
            rf.SP = sp + 2

        h.register_hook('PrintText', skip)

        def dismiss(_):
            if seen:
                h.pyboy.register_file.PC = h.address('CloseTextDisplay')

        h.register_hook('AfterDisplayingTextID', dismiss)
        return seen

    def enter_stage_door(self, warp=2):
        # The generic harness exits through arrival warp 0. Relocate an authored
        # stage warp (2/3) to that reachable tile, so WarpFound2 computes the
        # real stage-door index rather than manually forging its source fields.
        h = self.harness
        entry = list(h.warp_entries()[0])
        entry[3] = h.ROGUE_MAP
        h.write8('wLobbyDoor2StageMap', h.TARGET_ROUTE)  # warp 3 resolves as door 2
        for offset, value in enumerate(entry):
            h.write8('wWarpEntries', value, offset=warp * 4 + offset)
        h.write8('wWarpEntries', 0xFE, offset=0)
        h.write8('wWarpEntries', 0xFE, offset=1)
        h.enter_route_door1()

    def test_stage_door_checks_once_and_later_party_addition_is_allowed(self):
        h = self.harness
        self.arm(3)
        checks = h.hook_flag('WitchCheckPartyLimit')
        self.enter_stage_door()
        self.assertEqual(checks['count'], 1)
        self.assertTrue(h.read8('wRogueFlagsBitfield') & ACCEPTED)

        # Drive the same party-add engine used by captured/given Pokemon.
        h.park_before_hijack()
        h.write8('wCurPartySpecies', h.read8('wPartySpecies'))
        h.write8('wCurEnemyLevel', 10)
        h.write8('wMonDataLocation', 0x10)
        h.write8('wSpawnForm', 0)
        h.write8('wSpawnDVSlot', 0)
        h.call_routine('_AddPartyMon', limit=60000)
        self.assertEqual(h.read8('wPartyCount'), 4)
        h.move_tile('left')
        h.move_tile('right')
        self.assertTrue(h.read8('wRogueFlagsBitfield') & ACCEPTED)
        self.assertEqual(checks['count'], 1, 'Later steps repeated the entry check')

    def test_oversized_party_fails_before_transition_and_still_enters(self):
        self.check_oversized_entry(2)

    def test_second_stage_door_also_rejects_an_oversized_party(self):
        self.check_oversized_entry(3)

    def check_oversized_entry(self, warp):
        h = self.harness
        self.arm(4)
        messages = self.skip_failure_text()
        self.enter_stage_door(warp)
        self.assertEqual(len(messages), 1)
        self.assertEqual(messages[0][0], h.LOBBY_MAP)
        self.assertEqual(messages[0][1], warp)
        self.assertFalse(h.read8('wRogueFlagsBitfield') & ACCEPTED)
        self.assertEqual(h.read8('hCurMap'), h.TARGET_ROUTE)

    def test_only_lobby_stage_warps_fail_the_bargain(self):
        h = self.harness
        self.skip_failure_text()
        h.park_before_hijack()
        baseline = io.BytesIO()
        h.save_state(baseline)
        for source, warp, fails in ((h.LOBBY_MAP, 0, False),
                                    (h.LOBBY_MAP, 1, False),
                                    (h.LOBBY_MAP, 4, False),
                                    (h.TARGET_ROUTE, 2, False)):
            with self.subTest(source=source, warp=warp):
                h.load_state(baseline)
                self.arm(4)
                h.write8('wWarpedFromWhichMap', source)
                h.write8('wWarpedFromWhichWarp', warp)
                h.call_routine('WitchCheckPartyLimit')
                self.assertEqual(bool(h.read8('wRogueFlagsBitfield') & ACCEPTED),
                                 not fails)

    def test_reward_gift_reaches_give_pokemon_at_the_entry_limit(self):
        h = self.harness
        h.park_before_hijack()
        self.arm(3)
        species = h.read8('wPartySpecies')
        h.write8('wNamedObjectIndex', species)
        h.write8('wRoguePokemon2', species)
        h.write8('wRoguePokemonForm2', 0)
        reached = []

        def choose_slot(_):
            h.pyboy.register_file.B = 1

        def gift(_):
            reached.append(h.pyboy.register_file.B)
            # Park in a bounded emulated spin before the blocking gift dialogue.
            # The probe restores CPU/RAM; the ROM mirror bytes are restored below.
            h.pyboy.register_file.PC = 0x3FFE

        h.register_hook('HandleRewardChoice.giveMon', choose_slot)
        h.register_hook('GivePokemon', gift)
        original = [h.pyboy.memory[0, 0x3FFE], h.pyboy.memory[0, 0x3FFF]]
        try:
            h.pyboy.memory[0, 0x3FFE] = 0x18  # jr -2
            h.pyboy.memory[0, 0x3FFF] = 0xFE
            h.probe_routine_until('HandleRewardChoice.giveMon', lambda: bool(reached), limit=120)
        finally:
            h.pyboy.memory[0, 0x3FFE] = original[0]
            h.pyboy.memory[0, 0x3FFF] = original[1]
            h.unregister_hook('GivePokemon', gift)
            h.unregister_hook('HandleRewardChoice.giveMon', choose_slot)
        self.assertEqual(reached, [species])
