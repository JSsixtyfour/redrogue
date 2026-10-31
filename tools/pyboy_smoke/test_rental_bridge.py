"""Gift interludes cannot sell rentals, including latched offers and Debug 2."""
import unittest

from source_constants import parse_map_constants, parse_rgbds_constants
from test_move_tutor_prices import run_entry
import test_rental_delivery as delivery


class RentalBridgeTest(unittest.TestCase):
    setUp = delivery.RentalDeliveryTest.setUp
    tearDown = delivery.RentalDeliveryTest.tearDown
    write = delivery.RentalDeliveryTest.write

    def test_every_gift_room_rejects_latched_delivery_without_mutation(self):
        h = self.h
        maps = parse_map_constants(delivery.ROOT / "constants/map_constants.asm")
        rooms = ("COPYCATS_HOUSE_2F", "BILLS_HOUSE", "MR_FUJIS_HOUSE",
                 "SS_ANNE_CAPTAINS_ROOM", "CINNABAR_LAB_FOSSIL_ROOM",
                 "POKEMON_FAN_CLUB", "WARDENS_HOUSE", "VIRIDIAN_SCHOOL_HOUSE",
                 "VIRIDIAN_NICKNAME_HOUSE", "CERULEAN_TRASHED_HOUSE",
                 "REDS_HOUSE_1F", "IGAS_DOJO", "FLORAS_GROTTO", "OAKS_LAB")

        def snapshot(h):
            return {"party": h.read_bytes("wPartyCount", h.address("wPartyDataEnd") - h.address("wPartyCount")),
                    "money": h.read_bytes("wPlayerMoney", 3),
                    "contract": h.read_bytes("wRentalRecord", 16),
                    "offer": h.read_bytes("wRentalOfferSpecies", 12)}

        original = snapshot(h)
        for room in rooms:
            with self.subTest(room=room):
                def setup(h):
                    h.write8("hCurMap", maps["INDIGO_PLATEAU_LOBBY"])
                    h.write8("wLobbyDoor1StageMap", maps[room])
                    h.write8("wLobbyDoor2StageMap", maps["OAKS_LAB"])
                result = run_entry(h, "RentalDeliverOffer", setup=setup,
                                   capture=lambda h: {**snapshot(h), "error": h.pyboy.register_file.E})
                self.assertFalse(result["flags"] & 0x10)
                self.assertEqual(result["error"], 1)
                self.assertEqual({key: result[key] for key in original}, original)

    def test_gift_gate_does_not_block_real_stages_or_wild_providers(self):
        h = self.h
        maps = parse_map_constants(delivery.ROOT / "constants/map_constants.asm")
        for current, door in (("INDIGO_PLATEAU_LOBBY", "PEWTER_GYM"),
                              ("INDIGO_PLATEAU_LOBBY", "ROUTE_1"),
                              ("PROCEDURAL_FOREST", "OAKS_LAB")):
            with self.subTest(current=current, door=door):
                def setup(h):
                    h.write8("hCurMap", maps[current])
                    h.write8("wLobbyDoor1StageMap", maps[door])
                result = run_entry(h, "RentalCanPrepareOffer", setup=setup)
                self.assertTrue(result["flags"] & 0x10)

    def test_official_hidden_for_gifts_even_in_debug_and_restored_afterward(self):
        h = self.h
        maps = parse_map_constants(delivery.ROOT / "constants/map_constants.asm")
        toggle = parse_rgbds_constants(delivery.ROOT / "constants/toggle_constants.asm")["TOGGLE_PC_RENTAL_OFFICIAL"]
        for debug, door, expected in ((0, "BILLS_HOUSE", True),
                                      (2, "OAKS_LAB", True),
                                      (2, "PEWTER_GYM", False)):
            with self.subTest(debug=debug, door=door):
                def setup(h):
                    h.write8("wStatusFlags6", debug)
                    h.write8("wLobbyDoor1StageMap", maps[door])
                    # Start with the opposite toggle to prove both paths write it.
                    h.write8("wToggleableObjectFlags", 0 if expected else 255, offset=toggle // 8)
                result = run_entry(h, "PCLobbyExtrasSetup", setup=setup,
                    capture=lambda h: {"hidden": bool(h.read8("wToggleableObjectFlags", offset=toggle // 8) & (1 << (toggle % 8)))})
                self.assertEqual(result["hidden"], expected)
