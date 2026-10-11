"""Execute rental guards before trade/fusion mutation, with text input mocked."""
import unittest

from harness import RedRogueHarness
from test_save_header import ARTIFACTS, REPO_ROOT
from test_move_tutor_prices import run_entry, return_from_call


class RentalGuardsTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.h.boot_to_lobby()

    def tearDown(self):
        self.h.close()

    def snapshot(self, h):
        return {
            "party": h.read_bytes("wPartyDataStart", h.address("wPartyDataEnd") - h.address("wPartyDataStart")),
            "rental": h.read_bytes("wRentalRecord", 16),
            "fusion": [h.read8("wFusionSecondarySpecies"), h.read8("wFusionSecondaryForm")],
            "trades": h.read_bytes("wCompletedInGameTradeFlags", 2),
            "money": h.read_bytes("wPlayerMoney", 3),
        }

    def test_party_identity_rejects_only_the_exact_location(self):
        for owner in (0, 1, 2, 6, 7, 246, 247, 248, 249):
            for slot in (0, 1, 5, 6, 255):
                with self.subTest(owner=owner, slot=slot):
                    result = run_entry(self.h, "RentalIsPartySlot", registers={"E": slot},
                                       setup=lambda h: h.write8("wRentalOwner", owner))
                    self.assertEqual(bool(result["flags"] & 0x10), slot < 6 and owner == slot + 1)

    def test_trade_rejects_rental_before_flags_or_party_change(self):
        before = {}
        texts = []

        def setup(h):
            h.write8("wRentalOwner", 1)
            h.write8("hWhichPokemon", 0)
            before.update(self.snapshot(h))

        def text(_):
            texts.append(True)
            return_from_call(self.h)

        result = run_entry(self.h, "InGameTrade_DoTrade.checkRental", setup=setup,
                           hooks={"PrintText": text}, capture=self.snapshot)
        self.assertTrue(result["flags"] & 0x10)
        self.assertEqual(len(texts), 1)
        for key, value in before.items():
            self.assertEqual(result[key], value, key)

    def test_fusion_rejects_either_operand_before_mutation(self):
        for owner in (1, 2):
            before = {}
            texts = []

            def setup(h):
                h.write8("wRentalOwner", owner)
                h.write8("hSpriteDataOffset", 0)
                h.write8("hSpriteHeight", 1)
                before.update(self.snapshot(h))

            def text(_):
                texts.append(True)
                return_from_call(self.h)

            result = run_entry(self.h, "CreateFusion.checkRental", setup=setup,
                               hooks={"PrintText": text}, capture=self.snapshot)
            self.assertEqual(len(texts), 1)
            for key, value in before.items():
                self.assertEqual(result[key], value, (owner, key))

    def test_nonrental_selection_passes_both_guard_helpers_without_text(self):
        def unexpected_text(_):
            self.fail("nonrental selection opened rejection text")

        for owner in (0, 3, 7, 247, 248, 249):
            for label in ("RentalRejectSelectedTrade", "RentalRejectFusion"):
                def setup(h):
                    h.write8("wRentalOwner", owner)
                    h.write8("hWhichPokemon", 0)
                    h.write8("hSpriteDataOffset", 0)
                    h.write8("hSpriteHeight", 1)

                result = run_entry(self.h, label, setup=setup, hooks={"PrintText": unexpected_text})
                self.assertFalse(result["flags"] & 0x10, (owner, label))
