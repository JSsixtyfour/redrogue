"""Accessible rental reclamation preserves identity, unrelated holders and rollback."""
import unittest

from harness import RedRogueHarness
from test_save_header import ARTIFACTS, REPO_ROOT
from test_move_tutor_prices import run_entry


class RentalReclaimTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.h.boot_to_lobby()
        self.mon = self.h.read_bytes("wPartyMons", 44)

    def tearDown(self):
        self.h.close()

    def seed(self, h, owner):
        record = [1, owner, 42, 3] + list(range(12))
        start = h.address("wRentalRecord")
        h.pyboy.memory[start:start + 16] = record
        start = h.address("wBridgeSelectedEffects")
        h.pyboy.memory[start:start + 4] = [0] * 4
        return record

    def test_party_first_middle_last_removes_exact_mon_and_compacts_bridge_owner(self):
        for slot in (0, 2, 5):
            mons = [self.mon[:] for _ in range(6)]
            for i, mon in enumerate(mons):
                mon[12] = i + 20 # distinguish records without relying on species
            record = []
            def setup(h):
                record.extend(self.seed(h, slot + 1))
                h.write8("wPartyCount", 6)
                start = h.address("wPartySpecies")
                h.pyboy.memory[start:start + 7] = [self.mon[0]] * 6 + [255]
                start = h.address("wPartyMons")
                h.pyboy.memory[start:start + 264] = sum(mons, [])
                h.write8("wBridgeSelectedEffectOwner1", slot + 1)
                h.write8("wBridgeSelectedEffect1", 3)
                h.write8("wBridgeSelectedEffectOwner2", 6 if slot != 5 else 1)
                h.write8("wBridgeSelectedEffect2", 4)
            result = run_entry(self.h, "RentalReclaimAccessible", setup=setup, capture=lambda h: {
                "count": h.read8("wPartyCount"), "mons": h.read_bytes("wPartyMons", 5 * 44),
                "record": h.read_bytes("wRentalRecord", 16),
                "bridge": h.read_bytes("wBridgeSelectedEffects", 4),
            })
            record[1] = 0
            self.assertTrue(result["flags"] & 0x10)
            self.assertEqual(result["count"], 5)
            self.assertEqual(result["mons"], sum(mons[:slot] + mons[slot + 1:], []))
            self.assertEqual(result["record"], record)
            self.assertEqual(result["bridge"], [0, 0, 5 if slot != 5 else 1, 4])

    def test_current_box_first_middle_last_across_all_box_numbers(self):
        for box in range(12):
            for slot in (0, 9, 19):
                mons = [self.mon[:33] for _ in range(20)]
                for i, mon in enumerate(mons):
                    mon[12] = i + 20
                def setup(h):
                    self.seed(h, 7 + box * 20 + slot)
                    h.write8("wCurrentBoxNum", box | 128)
                    h.write8("wBoxCount", 20)
                    start = h.address("wBoxSpecies")
                    h.pyboy.memory[start:start + 21] = [self.mon[0]] * 20 + [255]
                    start = h.address("wBoxMons")
                    h.pyboy.memory[start:start + 660] = sum(mons, [])
                result = run_entry(self.h, "RentalReclaimAccessible", setup=setup, capture=lambda h: {
                    "count": h.read8("wBoxCount"), "mons": h.read_bytes("wBoxMons", 19 * 33),
                    "owner": h.read8("wRentalOwner"), "box": h.read8("wCurrentBoxNum"),
                })
                self.assertTrue(result["flags"] & 0x10, (box, slot))
                self.assertEqual(result["count"], 19)
                self.assertEqual(result["mons"], sum(mons[:slot] + mons[slot + 1:], []))
                self.assertEqual(result["owner"], 0)
                self.assertEqual(result["box"], box | 128)

    def test_inactive_or_invalid_location_leaves_records_untouched(self):
        for owner in (27, 246, 250, 255):
            before = {}
            def setup(h):
                self.seed(h, owner)
                h.write8("wCurrentBoxNum", 128)
                before["box"] = h.read_bytes("wBoxDataStart", h.address("wBoxDataEnd") - h.address("wBoxDataStart"))
                before["party"] = h.read_bytes("wPartyMons", 6 * 44)
            result = run_entry(self.h, "RentalReclaimAccessible", setup=setup, capture=lambda h: {
                "box": h.read_bytes("wBoxDataStart", h.address("wBoxDataEnd") - h.address("wBoxDataStart")),
                "party": h.read_bytes("wPartyMons", 6 * 44), "owner": h.read8("wRentalOwner"),
            })
            self.assertFalse(result["flags"] & 0x10)
            self.assertEqual(result["owner"], owner)
            self.assertEqual(result["box"], before["box"])
            self.assertEqual(result["party"], before["party"])

    def test_stolen_reclaim_and_continue_restore_owner_and_holder_together(self):
        h = self.h
        record = self.seed(h, 249)
        holder = [1] + [(i * 17 + 3) & 255 for i in range(1, 57)]
        h.write_sram_bytes("sStolenRecord", holder)
        h.call_routine("SaveGameData")
        h.call_routine("RentalReclaimAccessible")
        self.assertEqual(h.read_sram_bytes("sStolenRecord", 57), [0] * 57)
        self.assertEqual(h.read8("wRentalOwner"), 0)
        self.assertEqual(h.read_bytes("wStolenSaveSnapshot", 57), holder)
        h.call_routine("LoadMainData")
        self.assertEqual(h.read_sram_bytes("sStolenRecord", 57), holder)
        self.assertEqual(h.read_bytes("wRentalRecord", 16), record)

    def test_stale_stolen_owner_never_erases_an_item(self):
        h = self.h
        self.seed(h, 249)
        holder = [2] + [0x35] * 56
        h.write_sram_bytes("sStolenRecord", holder)
        h.call_routine("RentalReclaimAccessible")
        self.assertEqual(h.read_sram_bytes("sStolenRecord", 57), holder)
        self.assertEqual(h.read8("wRentalOwner"), 0)
