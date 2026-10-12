"""Archive/debug full-party replacement cannot preserve a rental identity."""
import unittest

import test_rental_settlement as boxed
from test_move_tutor_prices import run_entry


class RentalReplacementTest(unittest.TestCase):
    setUp = boxed.RentalSettlementTest.setUp
    tearDown = boxed.RentalSettlementTest.tearDown
    seed = boxed.RentalSettlementTest.seed

    def two_mons(self, h, owner):
        self.seed(h, 0, {}, owner)
        mon = h.read_bytes("wPartyMons", 44)
        first, second = mon[:], mon[:]
        first[12], second[12] = 20, 21
        h.write8("wPartyCount", 2)
        start = h.address("wPartySpecies")
        h.pyboy.memory[start:start+3] = [mon[0], mon[0], 255]
        start = h.address("wPartyMons")
        h.pyboy.memory[start:start+88] = first + second

    def test_capture_settles_party_rental_and_archives_only_owned_survivor(self):
        h = self.h
        h.call_routine("FinalTeamArchiveInit")
        self.two_mons(h, 1)
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)
        self.assertEqual(h.read8("wPartyCount"), 1)
        self.assertEqual(h.read8("wPartyMons", offset=12), 21)
        self.assertEqual(h.read_bytes("wRentalRecord", 4), [0,0,0,3])
        raw = h.read_sram_bytes("sFinalTeamArchiveRecords", 404, bank=1)
        offset = h.address("wPartyMons") - h.address("wPartyDataStart")
        self.assertEqual(raw[0], 1)
        self.assertEqual(raw[offset+12], 21)
        # Successful capture performs the settlement save before writing archive.
        h.write8("wRentalState", 99)
        h.call_routine("LoadMainData")
        self.assertEqual(h.read_bytes("wRentalRecord", 4), [0,0,0,3])

    def test_invalid_party_contract_refuses_capture_without_sram_mutation(self):
        h = self.h
        h.call_routine("FinalTeamArchiveInit")
        before = h.read_sram_bytes("sFinalTeamArchive", 1635, bank=1)
        self.two_mons(h, 1)
        h.write8("wRentalState", 0)
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 0)
        self.assertEqual(h.read8("wPartyCount"), 2)
        self.assertEqual(h.read8("wRentalOwner"), 1)
        self.assertEqual(h.read_sram_bytes("sFinalTeamArchive", 1635, bank=1), before)

    def test_restore_clears_only_replaced_party_owner_and_keeps_external_rentals(self):
        h = self.h
        h.call_routine("FinalTeamArchiveInit")
        self.two_mons(h, 0)
        h.call_routine("FinalTeamArchiveCapture")
        for owner in (1,6,7,246,247,248,249):
            self.seed(h, 0, {}, owner)
            start = h.address("wBridgeSelectedEffects")
            h.pyboy.memory[start:start+4] = [owner,3,2,4]
            h.call_routine("FinalTeamArchiveRestoreLatest")
            self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)
            self.assertEqual(h.read8("wPartyCount"), 2)
            self.assertEqual(h.read8("wRentalOwner"), 0 if owner <= 6 else owner)
            self.assertEqual(h.read8("wRentalState"), 1)
            self.assertEqual(h.read8("wRentalFlags"), 3)
            self.assertEqual(h.read_bytes("wBridgeSelectedEffects", 4),
                             [0,0,2,4] if owner <= 6 else [owner,3,2,4])

    def test_failed_restore_does_not_discard_party_rental_pointer(self):
        h = self.h
        h.call_routine("FinalTeamArchiveInit")
        self.two_mons(h, 1)
        h.call_routine("FinalTeamArchiveRestoreLatest")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 0)
        self.assertEqual(h.read8("wRentalOwner"), 1)
        self.assertEqual(h.read8("wPartyCount"), 2)

    def test_debug_reset_clears_party_identity_and_bridge_effects_only(self):
        for owner in (1,6,7,247,249):
            def setup(h):
                self.seed(h, 0, {}, owner)
                start = h.address("wBridgeSelectedEffects")
                h.pyboy.memory[start:start+4] = [1,3,2,4]
            result = run_entry(self.h, "RentalPrepareDebugParty", setup=setup,
                capture=lambda h: {"record": h.read_bytes("wRentalRecord", 4),
                                   "bridge": h.read_bytes("wBridgeSelectedEffects", 4)})
            self.assertEqual(result["record"], [1,0 if owner <= 6 else owner,42,3])
            self.assertEqual(result["bridge"], [0,0,0,0])
