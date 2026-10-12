"""Read-only fallback search order, rental exclusion and SRAM preservation."""
import unittest

from harness import RedRogueHarness
from test_save_header import ARTIFACTS, REPO_ROOT
from test_move_tutor_prices import run_entry


class RentalBoxFallbackTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.h.boot_to_lobby()

    def tearDown(self):
        self.h.close()

    def seed(self, h, current, counts, owner=0):
        h.write8("wCurrentBoxNum", current | 128)
        h.write8("wRentalOwner", owner)
        h.write8("wBoxCount", counts.get(current, 0))
        for box in range(12):
            h.write_sram_bytes("sBox" + str(box + 1), [counts.get(box, 0), 255], bank=2 + box // 6)

    def find(self, setup):
        return run_entry(self.h, "RentalFindBoxFallback", setup=setup, capture=lambda h: {
            "box": h.pyboy.register_file.D, "slot": h.pyboy.register_file.E,
        })

    def test_current_box_has_priority_and_rental_slot_is_excluded(self):
        for box in range(12):
            result = self.find(lambda h: self.seed(h, box, {box: 2, (box + 1) % 12: 20}, 7 + box * 20))
            self.assertTrue(result["flags"] & 0x10)
            self.assertEqual((result["box"], result["slot"]), (box, 1))

    def test_inactive_boxes_are_scanned_by_number_in_both_sram_banks(self):
        for box in range(12):
            current = (box + 1) % 12
            result = self.find(lambda h: self.seed(h, current, {box: 2}, 7 + box * 20))
            self.assertTrue(result["flags"] & 0x10)
            self.assertEqual((result["box"], result["slot"]), (box, 1))
        result = self.find(lambda h: self.seed(h, 11, {0: 1, 3: 1, 9: 1}))
        self.assertEqual((result["box"], result["slot"]), (0, 0))

    def test_no_owned_boxed_mon_and_uninitialized_boxes_return_not_found(self):
        cases = ({}, {0: 1}, {0: 255, 5: 21})
        for counts in cases:
            result = self.find(lambda h: self.seed(h, 0, counts, 7))
            self.assertFalse(result["flags"] & 0x10)
        def no_boxes_yet(h):
            self.seed(h, 0, {6: 1})
            h.write8("wCurrentBoxNum", 0)
        self.assertFalse(self.find(no_boxes_yet)["flags"] & 0x10)

    def test_search_preserves_all_box_bytes_save_data_current_box_and_contract(self):
        before = {}
        def capture(h):
            return {
                "sram2": h.read_sram_bytes("sBox1", 0x1A53, bank=2),
                "sram3": h.read_sram_bytes("sBox7", 0x1A53, bank=3),
                "main": h.read_sram_bytes("sMainData", h.address("wMainDataEnd") - h.address("wMainDataStart")),
                "current": h.read_bytes("wBoxDataStart", h.address("wBoxDataEnd") - h.address("wBoxDataStart")),
                "record": h.read_bytes("wRentalRecord", 16),
                "box_num": h.read8("wCurrentBoxNum"),
            }
        def setup(h):
            self.seed(h, 5, {0: 1, 5: 1, 7: 2}, 7 + 5 * 20)
            before.update(capture(h))
        result = run_entry(self.h, "RentalFindBoxFallback", setup=setup, capture=capture)
        self.assertTrue(result["flags"] & 0x10)
        for key, value in before.items():
            self.assertEqual(result[key], value, key)
