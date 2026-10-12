"""Provider-free paid delivery is exact, guarded and tracked immediately."""
import unittest
import io
from pathlib import Path
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_map_constants
from test_move_tutor_prices import return_from_call
from test_save_header import ColdBoot, dump_sram

ROOT = Path(__file__).resolve().parents[2]


class RentalDeliveryTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, Path(__file__).parent / "artifacts")
        self.h.boot_to_lobby()
        self.h.call_routine("RentalResetRecord")
        self.h.write8("hIsInBattle", 0)
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        h = self.h
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", 255, offset=1)
        fields = {"wRentalOfferFlags": 3, "wRentalOfferSpecies": self.species["PIKACHU"],
                  "wRentalOfferForm": 0, "wRentalOfferClass": 2,
                  "wRentalOfferLevel": 50, "wRentalOfferSource": 3,
                  "wSpawnForm": 0, "wSpawnDVSlot": 0}
        for label, value in fields.items():
            h.write8(label, value)
        self.write("wRentalOfferDVs", [0x12, 0x34])
        self.write("wRentalOfferMoves", [self.moves["TACKLE"], self.moves["THUNDERBOLT"],
                                         self.moves["SURF"], 0])
        self.write("wPlayerMoney", [0, 0x70, 0])

    def tearDown(self):
        self.h.close()

    def write(self, label, values):
        for i, value in enumerate(values):
            self.h.write8(label, value, offset=i)

    def test_exact_paid_delivery_and_second_purchase_rejection(self):
        h = self.h
        count = h.read8("wPartyCount")
        owned = h.read_bytes("wPartyMons", count * 44)
        offer = h.read_bytes("wRentalOfferSpecies", 12)
        h.call_routine("RentalDeliverOffer")
        self.assertTrue(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.last_call_registers["E"], 0)
        self.assertEqual(h.read8("wPartyCount"), count + 1)
        self.assertEqual(h.read_bytes("wPartyMons", count * 44), owned)
        self.assertEqual(h.read_bytes("wPlayerMoney", 3), [0, 0x10, 0])
        self.assertEqual(h.read_bytes("wRentalOfferSpecies", 12), offer)
        self.assertEqual(h.read8("wRentalOwner"), count + 1)
        self.assertEqual(h.read8("wRentalState"), 1)
        self.assertEqual(h.read8("wRentalFlags") & 1, 1)
        for field, expected in (("DVs", [0x12, 0x34]), ("Moves", offer[5:9]),
                                ("PP", [35, 15, 15, 0])):
            self.assertEqual(h.read_bytes("wPartyMon1" + field, len(expected), offset=count * 44), expected)
        hp = h.read_bytes("wPartyMon1HP", 2, offset=count * 44)
        maximum = h.read_bytes("wPartyMon1MaxHP", 2, offset=count * 44)
        self.assertEqual(hp, maximum)
        # DVs 1/2/3/4 imply HP DV 10, stat exp is zero.
        base = h.read_bytes("wMonHeader", 6)[1:6]
        expected_stats = [((base[0] + 10) * 2 * 50) // 100 + 60]
        expected_stats += [((value + dv) * 2 * 50) // 100 + 5
                           for value, dv in zip(base[1:], (1, 2, 3, 4))]
        actual = h.read_bytes("wPartyMon1MaxHP", 10, offset=count * 44)
        self.assertEqual([actual[i] * 256 + actual[i+1] for i in range(0, 10, 2)], expected_stats)
        self.assertEqual(h.read_bytes("wPartyMonNicks", 7, offset=count * 11),
                         [0x8f, 0x88, 0x8a, 0x80, 0x82, 0x87, 0x94])  # PIKACHU
        party = h.read_bytes("wPartyMons", 264)
        h.call_routine("RentalDeliverOffer")
        self.assertFalse(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.read_bytes("wPartyMons", 264), party)
        self.assertEqual(h.read_bytes("wPlayerMoney", 3), [0, 0x10, 0])

    def test_failed_preflights_never_mutate_party_money_contract_or_offer(self):
        h = self.h
        cases = (("wPartyCount", 6, 3), ("wRentalFlags", 1, 1),
                 ("wRentalState", 1, 1), ("wRentalOwner", 249, 1),
                 ("hIsInBattle", 1, 1), ("wRentalOfferFlags", 1, 2),
                 ("wRentalOfferMoves", 255, 2), ("wSpawnForm", 1, 5),
                 ("wSpawnDVSlot", 1, 5), ("wPlayerMoney", 0, 4))
        for label, value, reason in cases:
            old = h.read8(label)
            money = h.read_bytes("wPlayerMoney", 3)
            if label == "wPlayerMoney":
                self.write(label, [0, 0x59, 0x99])
            else:
                h.write8(label, value)
            before = {name: h.read_bytes(name, length) for name, length in
                      (("wPartyMons", 264), ("wPartyCount", 8),
                       ("wPlayerMoney", 3), ("wRentalRecord", 16))}
            with self.subTest(label=label):
                h.call_routine("RentalDeliverOffer")
                self.assertFalse(h.last_call_registers["F"] & 0x10)
                self.assertEqual(h.last_call_registers["E"], reason)
                for name, snapshot in before.items():
                    self.assertEqual(h.read_bytes(name, len(snapshot)), snapshot)
            h.write8(label, old)
            self.write("wPlayerMoney", money)

    def test_exact_funds_and_in_zone_delivery_bind_immediately(self):
        h = self.h
        self.write("wPlayerMoney", [0, 0x60, 0])
        maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        h.write8("hCurMap", maps["PROCEDURAL_CEMETERY_2"])
        h.call_routine("RentalDeliverOffer")
        self.assertTrue(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.read_bytes("wPlayerMoney", 3), [0, 0, 0])
        self.assertEqual(h.read8("wRentalState"), 2)
        self.assertEqual(h.read8("wRentalZone"), maps["PROCEDURAL_CEMETERY_2"])

    def test_released_rental_cannot_buy_again_in_the_same_opportunity(self):
        h = self.h
        h.call_routine("RentalDeliverOffer")
        self.assertTrue(h.last_call_registers["F"] & 0x10)
        h.write8("wRentalState", 0)
        h.write8("wRentalOwner", 0)
        before = h.read_bytes("wPlayerMoney", 3)
        h.call_routine("RentalDeliverOffer")
        self.assertFalse(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.last_call_registers["E"], 1)
        self.assertEqual(h.read_bytes("wPlayerMoney", 3), before)

    def test_all_half_prices_and_stored_dvs_override_new_booster_floor(self):
        h = self.h
        baseline = io.BytesIO()
        # A later booster increase must not alter the displayed saved DVs.
        def booster(_):
            h.pyboy.register_file.E = 3
            return_from_call(h)
        h.register_hook("GetKeyItemPowerInE", booster)
        h.save_state(baseline)
        for rarity, price in ((1, [0, 0x25, 0]), (2, [0, 0x60, 0]), (3, [1, 0, 0])):
            h.load_state(baseline)
            h.write8("wRentalOfferClass", rarity)
            self.write("wPlayerMoney", price)
            h.call_routine("RentalDeliverOffer")
            with self.subTest(rarity=rarity):
                self.assertTrue(h.last_call_registers["F"] & 0x10)
                self.assertEqual(h.read_bytes("wPlayerMoney", 3), [0, 0, 0])
                self.assertEqual(h.read_bytes("wPartyMon2DVs", 2), [0x12, 0x34])

    def test_creation_rejection_does_not_charge_or_consume_opportunity(self):
        h = self.h
        def reject(_):
            h.pyboy.register_file.F &= ~0x10
            return_from_call(h)
        h.register_hook("AddPartyMon", reject)
        before = h.read_bytes("wRentalRecord", 16)
        money = h.read_bytes("wPlayerMoney", 3)
        party = h.read_bytes("wPartyMons", 264)
        h.call_routine("RentalDeliverOffer")
        self.assertFalse(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.read_bytes("wRentalRecord", 16), before)
        self.assertEqual(h.read_bytes("wPlayerMoney", 3), money)
        self.assertEqual(h.read_bytes("wPartyMons", 264), party)
        self.assertEqual(h.read8("wSpawnForm"), 0)
        self.assertEqual(h.read8("wSpawnDVSlot"), 0)

    def test_form_delivery_and_paid_contract_survive_cold_continue(self):
        h = self.h
        h.write8("wRentalOfferSpecies", self.species["EXEGGUTOR"])
        h.write8("wRentalOfferForm", 1)
        h.call_routine("RentalDeliverOffer")
        self.assertTrue(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.read8("wPartyMon2CatchRate") & 0x60, 0x20)
        self.assertEqual(h.read_bytes("wPartyMon2DVs", 2), [0x12, 0x34])
        party = h.read_bytes("wPartyMon2", 44)
        money = h.read_bytes("wPlayerMoney", 3)
        h.call_routine("SaveGameData")
        boot = ColdBoot(dump_sram(h))
        self.addCleanup(boot.close)
        self.assertEqual(boot.to_menu(), 2)
        boot.continue_game()
        self.assertEqual(boot.h.read_bytes("wPartyMon2", 44), party)
        self.assertEqual(boot.h.read_bytes("wPlayerMoney", 3), money)
        self.assertEqual(boot.h.read8("wRentalOwner"), 2)
        boot.h.call_routine("RentalDeliverOffer")
        self.assertFalse(boot.h.last_call_registers["F"] & 0x10)
        self.assertEqual(boot.h.read_bytes("wPlayerMoney", 3), money)
