"""Current-box rental delivery preserves a full owned party and existing box."""
import io
import unittest
import test_rental_delivery as delivery
from test_move_tutor_prices import return_from_call
from test_save_header import ColdBoot, dump_sram


class RentalBoxDeliveryTest(unittest.TestCase):
    setUp = delivery.RentalDeliveryTest.setUp
    tearDown = delivery.RentalDeliveryTest.tearDown
    write = delivery.RentalDeliveryTest.write

    def full_party(self):
        h = self.h
        h.write8("wPartyCount", 6)
        for slot in range(6):
            h.write8("wPartySpecies", h.read8("wPartyMons", offset=44 * slot), offset=slot)
        h.write8("wPartySpecies", 255, offset=6)

    def test_every_current_box_appends_and_preserves_full_owned_party(self):
        h = self.h
        self.full_party()
        baseline = io.BytesIO()
        h.save_state(baseline)
        stack = []
        h.register_hook("GetMoveMaxPPFar", lambda _: stack.append(h.pyboy.register_file.SP))
        for box in range(12):
            h.load_state(baseline)
            h.write8("wCurrentBoxNum", box | 128)
            h.write8("wBoxCount", 1)
            h.write8("wBoxSpecies", 10)
            h.write8("wBoxSpecies", 255, offset=1)
            party = h.read_bytes("wPartyCount", h.address("wPartyDataEnd") - h.address("wPartyCount"))
            owned = h.read_bytes("wBoxMons", 33)
            nick = h.read_bytes("wBoxMonNicks", 11)
            ot = h.read_bytes("wBoxMonOT", 11)
            h.call_routine("RentalDeliverOffer")
            self.assertTrue(h.last_call_registers["F"] & 0x10, box)
            self.assertEqual(h.read_bytes("wPartyCount", len(party)), party)
            self.assertEqual(h.read_bytes("wBoxMons", 33), owned)
            self.assertEqual(h.read_bytes("wBoxMonNicks", 11), nick)
            self.assertEqual(h.read_bytes("wBoxMonOT", 11), ot)
            self.assertEqual(h.read8("wBoxCount"), 2)
            self.assertEqual(h.read8("wRentalOwner"), 7 + 20 * box + 1)
            self.assertEqual(h.read_bytes("wBoxMon2DVs", 2), [0x12, 0x34])
            self.assertEqual(h.read_bytes("wBoxMon2Moves", 4), h.read_bytes("wRentalOfferMoves", 4))
            self.assertEqual(h.read_bytes("wBoxMon2PP", 4), [35, 15, 15, 0])
            self.assertEqual(h.read8("wBoxMon2BoxLevel"), 50)
            self.assertEqual(h.read_bytes("wPlayerMoney", 3), [0, 0x10, 0])
        self.assertTrue(stack)
        self.assertGreaterEqual(min(stack), 0xDF00)

    def test_full_box_fails_before_mutation_or_payment(self):
        h = self.h
        self.full_party()
        h.write8("wBoxCount", 20)
        record = h.read_bytes("wRentalRecord", 16)
        party = h.read_bytes("wPartyMons", 264)
        h.call_routine("RentalDeliverOffer")
        self.assertFalse(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.last_call_registers["E"], 6)
        self.assertEqual(h.read_bytes("wRentalRecord", 16), record)
        self.assertEqual(h.read_bytes("wPartyMons", 264), party)
        self.assertEqual(h.read_bytes("wPlayerMoney", 3), [0, 0x70, 0])

    def test_rejected_creation_restores_borrowed_slot_without_payment(self):
        h = self.h
        self.full_party()
        h.write8("wBoxCount", 0)
        party = h.read_bytes("wPartyCount", h.address("wPartyDataEnd") - h.address("wPartyCount"))
        def reject(_):
            h.pyboy.register_file.F &= 0xEF
            return_from_call(h)
        h.register_hook("AddPartyMon", reject)
        h.call_routine("RentalDeliverOffer")
        self.assertFalse(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.read_bytes("wPartyCount", len(party)), party)
        self.assertEqual(h.read8("wBoxCount"), 0)
        self.assertEqual(h.read8("wRentalOwner"), 0)
        self.assertEqual(h.read_bytes("wPlayerMoney", 3), [0, 0x70, 0])

    def test_boxed_form_and_owner_survive_cold_continue(self):
        h = self.h
        self.full_party()
        h.write8("wBoxCount", 0)
        h.write8("wBoxSpecies", 255)
        h.write8("wRentalOfferSpecies", self.species["EXEGGUTOR"])
        h.write8("wRentalOfferForm", 1)
        h.call_routine("RentalDeliverOffer")
        self.assertTrue(h.last_call_registers["F"] & 0x10)
        owner = h.read8("wRentalOwner")
        mon = h.read_bytes("wBoxMons", 33)
        self.assertEqual(mon[7] & 0x60, 0x20)
        h.call_routine("SaveGameData")
        boot = ColdBoot(dump_sram(h))
        self.addCleanup(boot.close)
        self.assertEqual(boot.to_menu(), 2)
        boot.continue_game()
        self.assertEqual(boot.h.read8("wRentalOwner"), owner)
        self.assertEqual(boot.h.read_bytes("wBoxMons", 33), mon)
        self.assertEqual(boot.h.read8("wPartyCount"), 6)


class RentalBoxExchangeSettlementTest(unittest.TestCase):
    setUp = delivery.RentalDeliveryTest.setUp
    tearDown = delivery.RentalDeliveryTest.tearDown
    write = delivery.RentalDeliveryTest.write
    full_party = RentalBoxDeliveryTest.full_party

    def test_boxed_delivery_exchange_faint_and_settlement_preserve_owned_mon(self):
        h = self.h
        self.full_party()
        h.write8("wRentalOfferSpecies", self.species["OMANYTE"])
        h.write8("wBoxCount",0)
        h.write8("wBoxSpecies",255)
        baseline = io.BytesIO()
        h.save_state(baseline)
        for box in range(12):
            for party_first in (True,False):
                with self.subTest(box=box,party_first=party_first):
                    h.load_state(baseline)
                    h.write8("wCurrentBoxNum",box | 128)
                    h.write8("wBridgeSelectedEffectOwner1",1)
                    h.write8("wBridgeSelectedEffect1",3)
                    owned = h.read_bytes("wPartyMon1",33)
                    owned[3] = h.read8("wPartyMon1Level")
                    h.call_routine("RentalDeliverOffer")
                    self.assertEqual(h.read8("wRentalOwner"),7+20*box)
                    h.write8("wParentMenuItem",0 if party_first else 6)
                    h.write8("hCurrentMenuItem",6 if party_first else 0)
                    h.call_routine("SwapBillsPCSelectedPartyAndBoxMons")
                    self.assertEqual(h.read8("wRentalOwner"),1)
                    self.assertEqual(h.read8("wBridgeSelectedEffectOwner1"),7+20*box)
                    self.assertEqual(h.read8("wPartySpecies"),self.species["OMANYTE"])
                    self.assertEqual(h.read_bytes("wBoxMon1",33),owned)
                    h.write8("wPartyMon1HP",0)
                    h.write8("wPartyMon1HP",0,offset=1)
                    h.write8("wRentalState",2)
                    h.call_routine("RentalSettleAndSave")
                    self.assertEqual(h.read8("wPartyCount"),5)
                    self.assertEqual(h.read8("wBoxCount"),1)
                    self.assertEqual(h.read8("wBridgeSelectedEffectOwner1"),7+20*box)
                    self.assertEqual(h.read_bytes("wBoxMon1",33),owned)
                    self.assertNotIn(self.species["OMANYTE"],h.read_bytes("wPartySpecies",5))
                    self.assertEqual(h.read_bytes("wRentalRecord",3),[0,0,0])

        # Settlement's actual saved box/party state must survive cold Continue.
        boot = ColdBoot(dump_sram(h))
        self.addCleanup(boot.close)
        self.assertEqual(boot.to_menu(),2)
        boot.continue_game()
        self.assertEqual(boot.h.read8("wPartyCount"),5)
        self.assertEqual(boot.h.read8("wBoxCount"),1)
        self.assertEqual(boot.h.read_bytes("wBoxMon1",33),owned)
        self.assertEqual(boot.h.read_bytes("wRentalRecord",3),[0,0,0])
