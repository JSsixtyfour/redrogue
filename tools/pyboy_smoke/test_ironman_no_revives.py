"""Ironman: no REVIVE or MAX_REVIVE from the route roller or the healing clerk.

Both rollers read REVIVE / MAX_REVIVE as the last entry of the ultra / master
healing tier (engine/items/item_rarity.asm) and drop it with Ironman on. The
Ironman-off half is the control: the same seeds must still produce both, or
the Ironman half could pass on a roller that never reaches those tiers.
"""
import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from routine_session import isolated_routine_calls

ROOT = Path(__file__).resolve().parents[2]
REVIVE, MAX_REVIVE = 0x35, 0x36
REVIVES = {REVIVE, MAX_REVIVE}
HEALING = 0
BIT_IRONMAN = 0
SEEDS = 120
MART_ITEMS = 10


class IronmanNoRevivesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, ROOT / 'tools/pyboy_smoke/artifacts')
        cls.h.tick(240)
        cls.h.park_before_hijack()
        cls.baseline = io.BytesIO()
        cls.h.save_state(cls.baseline)
        bank, addr = cls.h.symbols.get('healing_pokeball_class')
        cls.h.pyboy.memory[0x2000] = bank
        cls.pool = set(cls.h.pyboy.memory[addr:addr + 20])  # all four healing tiers
        assert REVIVES <= cls.pool

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
        self.h.write_sram_bytes('sKeyItemsBitfield', [0] * 4)
        self.h.write_sram_bytes('sKeyItemTiers', [0] * 4)

    def set_ironman(self, on):
        options = self.h.read8('wOptions3') & ~(1 << BIT_IRONMAN)
        self.h.write8('wOptions3', options | (on << BIT_IRONMAN))

    def seed(self, n):
        self.h.seed_rng([n + 1, n * 7 + 3, n * 13 + 5, n * 29 + 11])

    def route_items(self, ironman):
        self.set_ironman(ironman)
        items = []
        for n in range(SEEDS):
            self.seed(n)
            self.h.write8('wRogueDoorSelection', HEALING)
            self.h.call_routine('Random_Item_Selection')
            items.append(self.h.read8('wRogueItem'))
        return items

    def mart_shelves(self, ironman):
        self.set_ironman(ironman)
        buffer = self.h.address('PCClerkText1Items')
        shelves = []
        for n in range(SEEDS // 4):
            self.seed(n)
            self.h.pyboy.register_file.D = buffer >> 8
            self.h.pyboy.register_file.E = buffer & 0xFF
            shelf = self.h.call_routine(
                'Random_Healing_Mart_Selection', limit=60000,
                capture=lambda h: list(h.pyboy.memory[buffer:buffer + MART_ITEMS + 1]))
            self.assertEqual(shelf[MART_ITEMS], 0xFF)
            shelves.append(shelf[:MART_ITEMS])
        return shelves

    def test_route_roller(self):
        off = self.route_items(False)
        self.assertTrue(REVIVES <= set(off), 'control: Ironman off must still roll both')
        on = self.route_items(True)
        self.assertFalse(REVIVES & set(on))
        self.assertTrue(set(on) <= self.pool - REVIVES)

    def test_healing_clerk(self):
        off = [item for shelf in self.mart_shelves(False) for item in shelf]
        self.assertTrue(REVIVES <= set(off), 'control: Ironman off must still stock both')
        for shelf in self.mart_shelves(True):
            self.assertFalse(REVIVES & set(shelf))
            self.assertTrue(set(shelf) <= self.pool - REVIVES)
            self.assertEqual(len(set(shelf)), MART_ITEMS)


if __name__ == '__main__':
    unittest.main()
