"""Shared rental dialogue dispatch and transaction seams in the built ROM."""
import unittest

import test_rental_delivery as delivery
from test_move_tutor_prices import run_entry, return_from_call


class RentalInteractionTest(unittest.TestCase):
    setUp = delivery.RentalDeliveryTest.setUp
    tearDown = delivery.RentalDeliveryTest.tearDown
    write = delivery.RentalDeliveryTest.write

    def interact(self, choice=0, setup=None):
        h = self.h
        texts = []
        previews = []
        menus = []
        rng = []
        stack = []
        def text(_):
            cpu = h.pyboy.register_file
            label = next((name for name in (
                "RentalOfferText", "RentalDeliveredText", "RentalDeclinedText",
                "RentalUnavailableText", "RentalUsedText", "RentalPartyFullText",
                "RentalNoMoneyText", "RentalBoxFullText") if h.address(name) == cpu.HL), None)
            self.assertIsNotNone(label)
            texts.append(label)
            if label == "RentalOfferText":
                previews.append((h.read_bytes("wNameBuffer", 11),
                                 h.read8("wRentalOfferLevel"),
                                 h.read_bytes("wPriceTemp", 3)))
            cpu.B, cpu.C = 0, 0
            return_from_call(h)
        def menu(_):
            menus.append(True)
            h.write8("hCurrentMenuItem", choice)
            # Menu scratch must never become the charged price or delivered DV.
            self.write("hMoney", [0x99, 0x99, 0x99])
            self.write("wPriceTemp", [0x99, 0x99, 0x99])
            return_from_call(h)
        def skip(_):
            return_from_call(h)
        result = run_entry(h, "RentalInteraction", registers={"B": 0x12, "C": 0x34},
            setup=setup, hooks={"PrintText": text, "YesNoChoice": menu,
                "DisplayTextBoxID": skip, "PlaySoundWaitForCurrent": skip,
                "Random": lambda _: rng.append(True),
                "GetMoveMaxPPFar": lambda _: stack.append(h.pyboy.register_file.SP)},
            capture=lambda h: {"bc": h.pyboy.register_file.B << 8 | h.pyboy.register_file.C,
                "money": h.read_bytes("wPlayerMoney", 3), "count": h.read8("wPartyCount"),
                "record": h.read_bytes("wRentalRecord", 16),
                "moves": h.read_bytes("wPartyMon2Moves", 4),
                "dvs": h.read_bytes("wPartyMon2DVs", 2)})
        self.assertEqual(result["bc"], 0x1234)
        self.assertTrue(all(0xDF00 <= sp <= 0xDFFF for sp in stack))
        result.update(texts=texts, previews=previews, menus=menus, rng=rng)
        return result

    def test_cancel_preserves_complete_offer_money_and_party(self):
        record = self.h.read_bytes("wRentalRecord", 16)
        result = self.interact(choice=1)
        self.assertEqual(result["texts"], ["RentalOfferText", "RentalDeclinedText"])
        self.assertEqual(result["record"], record)
        self.assertEqual(result["rng"], [])
        self.assertEqual(result["money"], [0, 0x70, 0])
        self.assertEqual(result["count"], 1)
        name, level, price = result["previews"][0]
        self.assertEqual(name[:7], [0x8f, 0x88, 0x8a, 0x80, 0x82, 0x87, 0x94])
        self.assertEqual((level, price), (50, [0, 0x60, 0]))

    def test_yes_delivers_displayed_offer_and_charges_real_quote(self):
        offer = self.h.read_bytes("wRentalOfferSpecies", 12)
        result = self.interact()
        self.assertEqual(result["texts"], ["RentalOfferText", "RentalDeliveredText"])
        self.assertEqual(result["money"], [0, 0x10, 0])
        self.assertEqual(result["count"], 2)
        self.assertEqual(result["record"][4:], offer)
        self.assertEqual(result["record"][:4], [1, 2, 0, 1])
        self.assertEqual(result["moves"], offer[5:9])
        self.assertEqual(result["dvs"], [0x12, 0x34])

    def test_failures_do_not_charge_or_consume_offer(self):
        record = self.h.read_bytes("wRentalRecord", 16)
        for field, value, message in (("wBoxCount", 20, "RentalBoxFullText"),
                                     ("wPlayerMoney", 0, "RentalNoMoneyText")):
            def setup(h):
                h.write8(field, value)
                if field == "wBoxCount":
                    h.write8("wPartyCount", 6)
                if field == "wPlayerMoney":
                    self.write(field, [0, 0, 0])
            result = self.interact(setup=setup)
            self.assertEqual(result["texts"], ["RentalOfferText", message])
            self.assertEqual(result["record"], record)
            self.assertEqual(result["money"], [0, 0, 0] if field == "wPlayerMoney" else [0, 0x70, 0])

    def test_active_used_and_invalid_offer_skip_purchase_menu(self):
        for field, value, text in (("wRentalState", 1, "RentalUnavailableText"),
                ("wRentalOwner", 7, "RentalUnavailableText"),
                ("wRentalFlags", 1, "RentalUsedText"),
                ("wRentalOfferMoves", 0, "RentalUnavailableText")):
            result = self.interact(setup=lambda h: h.write8(field, value))
            self.assertEqual(result["texts"], [text])
            self.assertEqual(result["menus"], [])
            self.assertEqual(result["money"], [0, 0x70, 0])
            self.assertEqual(result["count"], 1)

    def test_first_cancel_generates_and_latches_real_offer(self):
        result = self.interact(choice=1,
            setup=lambda h: h.write8("wRentalOfferFlags", 0))
        self.assertEqual(result["texts"], ["RentalOfferText", "RentalDeclinedText"])
        self.assertTrue(result["rng"])
        self.assertEqual(result["record"][15], 3)
        self.assertNotEqual(result["record"][9], 0)
        self.assertEqual(result["count"], 1)
        self.assertEqual(result["money"], [0, 0x70, 0])
