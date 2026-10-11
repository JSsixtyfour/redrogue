"""Rental identity follows locations, independently of species/bridge effects."""
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_save_header import ARTIFACTS, REPO_ROOT


class RentalOwnershipTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.h.boot_to_lobby()
        self.ids = parse_rgbds_constants(REPO_ROOT / "constants/menu_constants.asm")

    def tearDown(self):
        self.h.close()

    def seed(self, owner):
        h = self.h
        values = [1, owner, 42, 3] + list(range(12))
        start = h.address("wRentalRecord")
        h.pyboy.memory[start:start + 16] = values
        start = h.address("wBridgeSelectedEffects")
        h.pyboy.memory[start:start + 4] = [0] * 4
        return values

    def test_actual_daycare_transfer_moves_owner_before_source_compaction(self):
        h = self.h
        self.seed(1)
        species = h.read8("wPartyMon1Species")
        h.write8("wCurPartySpecies", species)
        h.write8("hWhichPokemon", 0)
        h.write8("wMoveMonType", self.ids["PARTY_TO_DAYCARE"])
        h.call_routine("MoveMon")
        self.assertEqual(h.read8("wDayCareMonSpecies"), species)
        self.assertEqual(h.read8("wRentalOwner"), 247)
        h.write8("wRemoveMonFromBox", 0)
        h.call_routine("RemovePokemon")
        self.assertEqual(h.read8("wRentalOwner"), 247)
        h.write8("wMoveMonType", self.ids["DAYCARE_TO_PARTY"])
        h.call_routine("MoveMon")
        self.assertEqual(h.read8("wRentalOwner"), h.read8("wPartyCount"))
        restored = h.address("wPartyMons") + (h.read8("wPartyCount") - 1) * 44
        self.assertEqual(h.pyboy.memory[restored], species)

    def test_compaction_distinguishes_identical_mons_and_retains_contract(self):
        h = self.h
        mon = h.read_bytes("wPartyMons", 44)
        for removed in range(3):
            for owner in range(1, 4):
                with self.subTest(removed=removed, owner=owner):
                    values = self.seed(owner)
                    h.write8("wPartyCount", 3)
                    start = h.address("wPartySpecies")
                    h.pyboy.memory[start:start + 4] = [mon[0]] * 3 + [255]
                    start = h.address("wPartyMons")
                    h.pyboy.memory[start:start + 132] = mon * 3
                    h.write8("hWhichPokemon", removed)
                    h.write8("wRemoveMonFromBox", 0)
                    h.call_routine("RemovePokemon")
                    expected = 0 if owner == removed + 1 else owner - (owner > removed + 1)
                    self.assertEqual(h.read8("wRentalOwner"), expected)
                    actual = h.read_bytes("wRentalRecord", 16)
                    values[1] = expected
                    self.assertEqual(actual, values)

    def test_box_front_insertion_shifts_only_current_box(self):
        h = self.h
        for box in range(12):
            # Include the save/UI marker in the current-box number.
            h.write8("wCurrentBoxNum", box | 128)
            h.write8("wBoxCount", 20)
            base = 7 + box * 20
            for owner in (0, 1, base, base + 18, 247, 248, 249):
                self.seed(owner)
                h.call_routine("BridgeTrackSendNewMonToBox")
                expected = owner + 1 if base <= owner <= base + 18 else owner
                self.assertEqual(h.read8("wRentalOwner"), expected)

    def test_party_swap_keeps_independent_bridge_effect(self):
        h = self.h
        self.seed(1)
        h.write8("wBridgeSelectedEffectOwner1", 1)
        h.write8("wBridgeSelectedEffect1", 3)
        h.write8("wSwappedMenuItem", 0)
        h.write8("hCurrentMenuItem", 2)
        h.call_routine("BridgeTrackPartySwap")
        self.assertEqual(h.read8("wRentalOwner"), 3)
        self.assertEqual(h.read_bytes("wBridgeSelectedEffects", 4), [3, 3, 0, 0])

    def test_theft_recovery_uses_stolen_owner_and_appended_box_slot(self):
        h = self.h
        for box in range(12):
            self.seed(2)
            h.write8("hWhichPokemon", 1)
            h.call_routine("RentalTrackTheft")
            self.assertEqual(h.read8("wRentalOwner"), 249)
            h.write8("wCurrentBoxNum", box | 128)
            h.write8("wBoxCount", 20)
            h.call_routine("RentalTrackBoxRecovery")
            self.assertEqual(h.read8("wRentalOwner"), 7 + box * 20 + 19)
        self.seed(249)
        h.write8("wPartyCount", 3)
        h.call_routine("RentalTrackPartyRecovery")
        self.assertEqual(h.read8("wRentalOwner"), 3)

    def test_record_rolls_back_with_save_and_resets_without_touching_snapshot(self):
        h = self.h
        values = self.seed(249)
        h.call_routine("SaveGameData")
        h.call_routine("RentalResetRecord")
        self.assertEqual(h.read_bytes("wRentalRecord", 16), [0] * 16)
        h.call_routine("LoadMainData")
        self.assertEqual(h.read_bytes("wRentalRecord", 16), values)
        snapshot = h.read_bytes("wStolenSaveSnapshot", 57)
        h.call_routine("RogueResetRunState")
        self.assertEqual(h.read_bytes("wRentalRecord", 16), [0] * 16)
        self.assertEqual(h.read_bytes("wStolenSaveSnapshot", 57), snapshot)
