"""Box settlement uses real PC copies, recovery, and full save routines."""
import unittest

from harness import RedRogueHarness
from test_save_header import ARTIFACTS, REPO_ROOT
from test_move_tutor_prices import run_entry


class RentalSettlementTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.h.boot_to_lobby()
        self.mon = self.h.read_bytes("wPartyMons", 33)

    def tearDown(self):
        self.h.close()

    def seed(self, h, current, boxes, owner):
        size = h.address("wBoxDataEnd") - h.address("wBoxDataStart")
        for box in range(12):
            records = boxes.get(box, [])
            raw = [0] * size
            raw[0] = len(records)
            raw[1:len(records) + 2] = [self.mon[0]] * len(records) + [255]
            offset = h.address("wBoxMons") - h.address("wBoxDataStart")
            for slot, marker in enumerate(records):
                mon = self.mon[:]
                mon[12] = marker
                raw[offset + slot * 33:offset + (slot + 1) * 33] = mon
            h.write_sram_bytes("sBox" + str(box + 1), raw, bank=2 + box // 6)
            if box == current:
                start = h.address("wBoxDataStart")
                h.pyboy.memory[start:start + size] = raw
        h.write8("wCurrentBoxNum", current | 128)
        h.write8("wPartyCount", 0)
        h.write8("wPartySpecies", 255)
        start = h.address("wRentalRecord")
        h.pyboy.memory[start:start + 16] = [1, owner, 42, 3] + list(range(12))

    def test_inactive_rental_removed_and_boxed_owned_mon_recovered_before_save(self):
        h = self.h
        self.seed(h, 5, {0: [20, 21], 8: [30]}, 7 + 8 * 20)
        h.call_routine("RentalSettleBoxedAndSave")
        self.assertEqual(h.read8("wPartyCount"), 1)
        self.assertEqual(h.read8("wPartyMons", offset=12), 20)

        self.assertEqual(h.read8("wCurrentBoxNum"), 133)
        self.assertEqual(h.read_bytes("wRentalRecord", 4), [0, 0, 0, 3])
        self.assertEqual(h.read_sram_bytes("sBox9", 1, bank=3), [0])
        self.assertEqual(h.read_sram_bytes("sBox1", 1, bank=2), [1])
        size = h.address("wBoxDataEnd") - h.address("wBoxDataStart")
        for bank in (2, 3):
            raw = h.read_sram_bytes("sBox1", size * 6 + 7, bank=bank)
            self.assertEqual(raw[size * 6], (~sum(raw[:size * 6])) & 255)
            for box in range(6):
                self.assertEqual(raw[size * 6 + 1 + box],
                                 (~sum(raw[box * size:(box + 1) * size])) & 255)
        h.write8("wRentalState", 99)
        h.write8("wPartyCount", 0)
        h.call_routine("LoadMainData")
        h.call_routine("LoadPartyAndDexData")
        h.call_routine("LoadCurrentBoxData")
        self.assertEqual(h.read_bytes("wRentalRecord", 4), [0, 0, 0, 3])
        self.assertEqual(h.read8("wPartyCount"), 1)
        self.assertEqual(h.read8("wPartyMons", offset=12), 20)
        self.assertEqual(h.read8("wCurrentBoxNum"), 133)
        self.assertEqual(h.read8("wBoxCount"), 0)

    def test_party_rental_uses_current_box_and_saves_healthy_replacement(self):
        h = self.h
        self.seed(h, 5, {0: [20], 5: [25]}, 1)
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", self.mon[0])
        h.write8("wPartySpecies", 255, offset=1)
        h.call_routine("RentalSettleBoxedAndSave")
        self.assertEqual(h.read8("wPartyCount"), 1)
        self.assertEqual(h.read8("wPartyMons", offset=12), 25)
        self.assertEqual(h.read8("wBoxCount"), 0)
        self.assertEqual(h.read_bytes("wRentalRecord", 4), [0, 0, 0, 3])
        hp = h.read_bytes("wPartyMon1HP", 2)
        self.assertNotEqual(hp, [0, 0])

    def test_current_box_recovery_has_priority(self):
        def setup(h):
            self.seed(h, 5, {0: [20], 5: [25], 8: [30]}, 167)
        result = run_entry(self.h, "RentalSettleBoxedAndSave", setup=setup, capture=lambda h: {
            "marker": h.read8("wPartyMons", offset=12), "box": h.read8("wCurrentBoxNum"),
        })
        self.assertTrue(result["flags"] & 16)
        self.assertEqual((result["marker"], result["box"]), (25, 133))

    def test_only_rental_returns_without_mutation(self):
        result = run_entry(self.h, "RentalSettleBoxedAndSave",
                           setup=lambda h: self.seed(h, 5, {8: [30]}, 167),
                           capture=lambda h: {"record": h.read_bytes("wRentalRecord", 4),
                                              "count": h.read_sram_bytes("sBox9", 1, bank=3)})
        self.assertFalse(result["flags"] & 16)
        self.assertEqual(result["record"], [1, 167, 42, 3])
        self.assertEqual(result["count"], [1])
