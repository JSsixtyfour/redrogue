"""Wild-area service readiness using genuine procedural entry and Continue.

No provider is placed and no map ID is overwritten. Dialogue boundaries are
mocked; this fixture does not establish visual or movement acceptance.
"""
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants
from test_save_header import ColdBoot, dump_sram
from test_move_tutor_prices import return_from_call
import test_rental_interaction as interaction

ROOT = Path(__file__).resolve().parents[2]


class RentalWildAreaTest(unittest.TestCase):
    write = interaction.RentalInteractionTest.write
    interact = interaction.RentalInteractionTest.interact

    def test_loaded_wild_area_service_lifecycle(self):
        maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        for name in ("PROCEDURAL_CAVE_1", "PROCEDURAL_FOREST",
                     "PROCEDURAL_CEMETERY_1", "PROCEDURAL_FACILITY"):
            with self.subTest(map=name):
                h = self.h = RedRogueHarness(ROOT, Path(__file__).parent / "artifacts")
                try:
                    # Isolate the service from independently rolled robbery
                    # cutscenes; theft has its own rental regression coverage.
                    def no_stage_event(_):
                        h.write8("wStageEvent", 0)
                        return_from_call(h)
                    h.register_hook("StageEventRoll", no_stage_event)
                    h.boot_to_lobby(battle_count=11, encounter_kind=4)
                    h.preload_and_enter_wild_area(maps[name], name)
                    self.assertEqual(h.read8("hCurMap"), maps[name])
                    h.call_routine("RentalResetRecord")
                    h.write8("wPartyCount", 1)
                    h.write8("wPartySpecies", 255, offset=1)
                    h.write8("wSpawnForm", 0)
                    h.write8("wSpawnDVSlot", 0)
                    self.write("wPlayerMoney", [0x99, 0x99, 0x99])
                    h.call_routine("GetRewardMonLevel")
                    expected_level = h.read8("wCurEnemyLevel")
                    h.call_routine("RentalPrepareOfferMoves")
                    self.assertEqual(h.read8("wRentalOfferFlags"), 3)
                    self.assertEqual(h.read8("wRentalOfferLevel"), expected_level)
                    self.assertEqual(h.read8("hCurMap"), maps[name])
                    record = h.read_bytes("wRentalRecord", 16)
                    cancelled = self.interact(choice=1)
                    self.assertEqual(cancelled["record"], record)
                    self.assertEqual(cancelled["money"], [0x99, 0x99, 0x99])
                    self.assertEqual(cancelled["count"], 1)
                    h.call_routine("RentalQuoteOffer")
                    price = h.read_bytes("hMoney", 3)
                    self.write("wPlayerMoney", price)
                    h.call_routine("RentalDeliverOffer")
                    self.assertTrue(h.last_call_registers["F"] & 0x10)
                    self.assertEqual(h.read_bytes("wPlayerMoney", 3), [0, 0, 0])
                    self.assertEqual(h.read8("wRentalState"), 2)
                    self.assertEqual(h.read8("wRentalZone"), maps[name])
                    self.assertEqual(h.read8("wRentalOwner"), 2)
                    # Debug wild entry can have no starter. Give the owned
                    # fixture slot a complete valid record before Continue.
                    self.write("wPartyMon1", h.read_bytes("wPartyMon2", 44))
                    self.write("wPartyMonNicks", h.read_bytes("wPartyMonNicks", 11, offset=11))
                    h.write8("wPartySpecies", h.read8("wRentalOfferSpecies"))
                    contract = h.read_bytes("wRentalRecord", 16)
                    h.call_routine("RentalSettleZoneReturn")
                    self.assertEqual(h.read_bytes("wRentalRecord", 16), contract)
                    h.call_routine("RentalDeliverOffer")
                    self.assertFalse(h.last_call_registers["F"] & 0x10)
                    self.assertEqual(h.read_bytes("wRentalRecord", 16), contract)
                    h.call_routine("SaveGameData")
                    self.assertEqual(h.read_bytes("wRentalRecord", 16), contract)
                    self.assertNotEqual(h.read_bytes("wPartyMon1HP", 2), [0, 0])
                    saved = dump_sram(h)
                finally:
                    h.close()
                boot = ColdBoot(saved)
                try:
                    self.assertEqual(boot.to_menu(), 2)
                    boot.continue_game()
                    h = boot.h
                    self.assertEqual(h.read8("hCurMap"), maps[name])
                    self.assertEqual(h.read_bytes("wRentalRecord", 16), contract)
                    h.call_routine("RentalRecordMapLoad")
                    self.assertEqual(h.read_bytes("wRentalRecord", 16), contract)
                    # Transaction coverage only: actual return choreography is
                    # deliberately left to the eventual provider acceptance.
                    h.call_routine("RentalSettleAndSave")
                    self.assertEqual(h.read8("wPartyCount"), 1)
                    self.assertEqual(h.read8("wRentalOwner"), 0)
                    self.assertEqual(h.read8("wRentalState"), 0)
                finally:
                    boot.close()
