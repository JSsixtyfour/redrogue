"""The provider-free rental identity checkpoint never delivers an unfinished set."""
import unittest
import io
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants
from test_move_tutor_prices import return_from_call
from test_save_header import ColdBoot, dump_sram

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).parent / "artifacts"
# The player's level cap (235 since Endless checkpoint G); one past it is corrupt.
MAX_LEVEL = parse_rgbds_constants(ROOT / "constants" / "battle_constants.asm")["MAX_LEVEL"]


class RentalOfferIdentityTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.boot_to_lobby()
        self.h.call_routine("RentalResetRecord")
        self.h.write8("hIsInBattle", 0)
        self.species = self.h.read8("wPartyMon1Species")

    def tearDown(self):
        self.h.close()

    def forced_roll(self, first, tier=0):
        h = self.h
        self.rolls = iter((first, 0, 0))
        self.tier = tier
        if getattr(self, "forced_hooks_installed", False):
            return
        self.forced_hooks_installed = True
        h.register_hook("Random", lambda _: self.random_result(next(self.rolls, 0)))

        def selection(_):
            self.selection_class = h.pyboy.register_file.E
            h.pyboy.register_file.D = self.species
            h.pyboy.register_file.E = 0
            return_from_call(h)

        def power(_):
            h.pyboy.register_file.E = self.tier
            return_from_call(h)

        h.register_hook("Random_Pokemon_Selection_Far", selection)
        h.register_hook("GetKeyItemPowerInE", power)

    def random_result(self, value):
        self.h.pyboy.register_file.A = value
        return_from_call(self.h)

    def test_salesman_class_endpoints_and_booster_floor_are_latched(self):
        h = self.h
        # Source endpoints are inclusive, exactly like the existing salesman.
        self.forced_roll(0)
        baseline = io.BytesIO()
        h.save_state(baseline)
        for roll, expected in ((0, 1), (153, 1), (154, 2), (247, 2), (248, 3), (255, 3)):
            for tier, floor in ((0, 0), (1, 6), (2, 10), (3, 13)):
                with self.subTest(roll=roll, tier=tier):
                    h.load_state(baseline)
                    self.forced_roll(roll, tier)
                    h.call_routine("RentalPrepareOfferIdentity")
                    self.assertEqual(self.selection_class, expected)
                    self.assertEqual(h.read8("wRentalOfferClass"), expected)
                    self.assertEqual(h.read_bytes("wRentalOfferDVs", 2), [floor * 17] * 2)
                    self.assertEqual(h.read8("wRentalOfferFlags"), 1)
                    self.assertEqual(h.read_bytes("wRentalOfferMoves", 4), [0] * 4)
                    self.assertEqual(h.read8("wRentalState"), 0)

    def test_real_offer_is_stable_saved_and_preserves_caller_context(self):
        h = self.h
        h.call_routine("GetRewardMonLevel")
        expected_level = h.read8("wCurEnemyLevel")
        context = {"wFormContextSpecies": self.species, "wFormContextForm": 1,
                   "wCurSpecies": self.species, "wCurPartySpecies": self.species, "wCurEnemyLevel": 37}
        for label, value in context.items():
            h.write8(label, value)
        h.write8("wRentalFlags", 0xa0)
        party = h.read_bytes("wPartyMons", 44 * 6)
        money = h.read_bytes("wPlayerMoney", 3)
        active = {"value": False, "calls": 0}
        h.register_hook("RentalPrepareOfferIdentity", lambda _: active.update(value=True))
        h.register_hook("Random", lambda _: active.update(calls=active["calls"] + int(active["value"])))
        h.register_hook("RentalValidateOfferIdentity", lambda _: active.update(value=False))
        h.call_routine("RentalPrepareOfferIdentity")
        offer = h.read_bytes("wRentalOfferSpecies", 12)
        self.assertGreater(offer[0], 0)
        self.assertLess(offer[1], 4)
        self.assertEqual(offer[3], expected_level)
        self.assertGreater(active["calls"], 0)
        active["calls"] = 0
        for _ in range(3):
            h.call_routine("RentalPrepareOfferIdentity")
            self.assertEqual(h.read_bytes("wRentalOfferSpecies", 12), offer)
        self.assertEqual(active["calls"], 0)
        for label, value in context.items():
            self.assertEqual(h.read8(label), value)
        self.assertEqual(h.read_bytes("wPartyMons", 44 * 6), party)
        self.assertEqual(h.read_bytes("wPlayerMoney", 3), money)
        self.assertEqual(h.read8("wRentalFlags"), 0xa0)
        h.call_routine("SaveGameData")
        h.call_routine("RentalClearOfferIdentity")
        self.assertEqual(h.read_bytes("wRentalOfferSpecies", 12), [0] * 12)
        h.call_routine("LoadMainData")
        self.assertEqual(h.read_bytes("wRentalOfferSpecies", 12), offer)
        h.call_routine("RentalPrepareOfferIdentity")
        self.assertEqual(h.read_bytes("wRentalOfferSpecies", 12), offer)
        boot = ColdBoot(dump_sram(h))
        self.addCleanup(boot.close)
        self.assertEqual(boot.to_menu(), 2)
        boot.continue_game()
        self.assertEqual(boot.h.read_bytes("wRentalOfferSpecies", 12), offer)
        boot.h.call_routine("RentalPrepareOfferIdentity")
        self.assertEqual(boot.h.read_bytes("wRentalOfferSpecies", 12), offer)

    def test_active_rental_or_battle_blocks_prepare_and_invalidation(self):
        h = self.h
        for state, owner, battle in ((1, 1, 0), (2, 167, 0), (255, 0, 0), (0, 249, 0), (0, 0, 1)):
            h.write8("wRentalState", state)
            h.write8("wRentalOwner", owner)
            h.write8("hIsInBattle", battle)
            start = h.address("wRentalOfferSpecies")
            h.pyboy.memory[start:start + 12] = list(range(1, 13))
            for routine in ("RentalPrepareOfferIdentity", "RentalClearOfferIdentity"):
                h.call_routine(routine)
                self.assertEqual(h.read_bytes("wRentalOfferSpecies", 12), list(range(1, 13)))

    def test_half_price_quotes_and_invalid_identity_never_charge(self):
        h = self.h
        self.forced_roll(0)
        h.call_routine("RentalPrepareOfferIdentity")
        money = h.read_bytes("wPlayerMoney", 3)
        for rarity, price in ((1, [0, 0x25, 0]), (2, [0, 0x60, 0]), (3, [1, 0, 0])):
            h.write8("wRentalOfferClass", rarity)
            h.call_routine("RentalQuoteOffer")
            self.assertEqual(h.read_bytes("hMoney", 3), price)
            self.assertEqual(h.read_bytes("wPlayerMoney", 3), money)
        for label, value in (("wRentalOfferClass", 0), ("wRentalOfferClass", 4),
                             ("wRentalOfferLevel", 0), ("wRentalOfferLevel", MAX_LEVEL + 1),
                             ("wRentalOfferForm", 4), ("wRentalOfferSpecies", 0),
                             ("wRentalOfferFlags", 0)):
            previous = h.read8(label)
            h.write8(label, value)
            h.write8("hMoney", 0x55)
            h.call_routine("RentalQuoteOffer")
            self.assertEqual(h.read8("hMoney"), 0x55)
            self.assertEqual(h.read_bytes("wPlayerMoney", 3), money)
            h.write8(label, previous)
