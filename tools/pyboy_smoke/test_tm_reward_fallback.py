"""Actual-ROM duplicate rejection, exhaustive fallback and exhausted-pool reward."""
import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from routine_session import isolated_routine_calls

ROOT = Path(__file__).resolve().parents[2]
NUGGET = 0x31


class TMRewardFallbackTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        cls.h.tick(240)
        cls.h.park_before_hijack()
        cls.baseline = io.BytesIO()
        cls.h.save_state(cls.baseline)
        bank, addr = cls.h.symbols.get('tm_pokeball_class')
        cls.h.pyboy.memory[0x2000] = bank
        cls.pool = list(cls.h.pyboy.memory[addr:addr + 55])
        assert len(set(cls.pool)) == 55

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def setUp(self):
        self.h.load_state(self.baseline)
        self.session = isolated_routine_calls(self.h)
        self.session.__enter__()
        self.addCleanup(self.session.__exit__, None, None, None)
        for name in ('wItemBonusRarity', 'wWitchPrizesEarned', 'wRogueFlagsBitfield',
                     'wItemSelectionRetryCount'):
            self.h.write8(name, 0)
        self.h.write8('wRogueDoorSelection', 2)
        self.h.write_sram_bytes('sKeyItemsBitfield', [0] * 4)
        self.h.write_sram_bytes('sKeyItemTiers', [0] * 4)

    def own_except(self, missing):
        bits = (1 << 55) - 1
        for item in missing:
            index = item - 0xC9 if item >= 0xC9 else 50 + item - 0xC4
            bits &= ~(1 << index)
        self.h.write_sram_bytes('sTMBitfield', bits.to_bytes(7, 'little'))

    def roll(self, routine='ItemSelectionFindUnownedTM'):
        before = self.h.read_sram_bytes('sTMBitfield', 7)
        self.h.call_routine(routine)
        self.assertEqual(self.h.read_sram_bytes('sTMBitfield', 7), before)
        self.assertEqual(self.h.read8('wItemSelectionRetryCount'), 0)
        return self.h.read8('wRogueItem')

    def test_each_single_missing_tm_or_hm_is_found(self):
        for item in self.pool:
            with self.subTest(item=item):
                self.own_except([item])
                self.assertEqual(self.roll(), item)

    def test_exhausted_pool_returns_nugget_after_twenty_real_rejections(self):
        self.own_except([])
        calls = []
        label = self.h.symbols.get('AllTMCheck')
        self.h.pyboy.hook_register(*label, lambda _: calls.append(1), None)
        try:
            self.assertEqual(self.roll('Random_Item_Selection'), NUGGET)
        finally:
            self.h.pyboy.hook_deregister(*label)
        self.assertEqual(len(calls), 20 + 55)

    def test_gym_preserves_door_bonus_and_excludes_common_tms(self):
        self.own_except(self.pool[:11])
        self.h.write8('wRogueDoorSelection', 1)
        self.assertEqual(self.roll('GymLeaderRandomItem'), NUGGET)
        self.assertEqual(self.h.read8('wRogueDoorSelection'), 1)
        self.assertEqual(self.h.read8('wItemBonusRarity'), 0)

    def test_gym_can_find_every_noncommon_tm(self):
        self.h.write8('wItemBonusRarity', 52)
        for item in self.pool[11:]:
            with self.subTest(item=item):
                self.own_except([item])
                self.assertEqual(self.roll(), item)

    def test_cascaded_bonus_excludes_exhausted_lower_tiers(self):
        self.h.write8('wItemBonusRarity', 255)
        # Even maximum bonus leaves some Ultra Ball probability: the cascade
        # redistributes drained Common/Great mass into Ultra before draining it.
        self.own_except(self.pool[:31])
        self.assertEqual(self.roll(), NUGGET)
        for item in (self.pool[31], self.pool[-1]):
            self.own_except([item])
            self.assertEqual(self.roll(), item)

    def test_random_fallback_reaches_each_remaining_choice(self):
        choices = [self.pool[0], self.pool[30], self.pool[-1]]
        self.own_except(choices)
        results = set()
        for seed in range(48):
            self.h.seed_rng([seed + 1, seed * 7 + 3, seed * 13 + 5, seed * 29 + 11])
            results.add(self.roll())
        self.assertEqual(results, set(choices))

    def test_each_random_ordinal_selects_one_remaining_choice(self):
        choices = [self.pool[0], self.pool[30], self.pool[-1]]
        self.own_except(choices)
        # Feed Random's output, leaving Rangerandom's mask/rejection logic real.
        # Random ends immediately before Rangerandom in HOME.
        address = self.h.address('Rangerandom') - 1
        self.assertEqual(self.h.pyboy.memory[address], 0xC9)
        for ordinal, expected in enumerate(choices):
            draws = []

            def output(_):
                draws.append(1)
                # 3 must be rejected for range 3, then accept the chosen ordinal.
                self.h.pyboy.register_file.A = 3 if len(draws) == 1 else ordinal

            self.h.pyboy.hook_register(0, address, output, None)
            try:
                self.assertEqual(self.roll(), expected)
            finally:
                self.h.pyboy.hook_deregister(0, address)
            self.assertEqual(len(draws), 2)

    def test_owned_flamethrower_is_never_returned_by_gym(self):
        flamethrower = 0xC9 + 29
        self.own_except([self.pool[-1]])
        for seed in range(12):
            self.h.seed_rng([seed + 1, seed * 7 + 3, seed * 13 + 5, seed * 29 + 11])
            item = self.roll('GymLeaderRandomItem')
            self.assertNotEqual(item, flamethrower)
            self.assertEqual(item, self.pool[-1])

    def test_unowned_roll_does_not_use_fallback(self):
        self.own_except(self.pool)
        calls = []
        label = self.h.symbols.get('ItemSelectionFindUnownedTM')
        self.h.pyboy.hook_register(*label, lambda _: calls.append(1), None)
        try:
            self.assertIn(self.roll('GymLeaderRandomItem'), self.pool[11:])
        finally:
            self.h.pyboy.hook_deregister(*label)
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
