"""Zone binding and loaded-hub expiry use the real rental transaction."""
import unittest
import io
import json
import shutil

import test_rental_settlement as boxed
import test_rental_replacement as replacement
from source_constants import parse_map_constants, parse_rgbds_constants
from test_move_tutor_prices import return_from_call
from test_save_header import ColdBoot, dump_sram


class RentalZoneTest(unittest.TestCase):
    setUp = boxed.RentalSettlementTest.setUp
    tearDown = boxed.RentalSettlementTest.tearDown
    seed = boxed.RentalSettlementTest.seed

    def map(self, name):
        maps = parse_map_constants(boxed.REPO_ROOT / "constants/map_constants.asm")
        self.h.write8("hCurMap", maps[name])
        return maps[name]

    def test_reserved_survives_hubs_dorm_bridges_and_internal_maps(self):
        h = self.h
        self.seed(h, 0, {}, 0)
        for name in ("INDIGO_PLATEAU_LOBBY", "REWARD_ROOM", "SILPH_CO_DORM",
                     "OAKS_LAB", "BILLS_HOUSE", "SS_ANNE_B1F_ROOMS"):
            self.map(name)
            h.call_routine("RentalRecordMapLoad")
            h.call_routine("RentalSettleZoneReturn")
            self.assertEqual(h.read_bytes("wRentalRecord", 4), [1,0,42,3])

    def test_export_phase1_party_rental_fixture_and_cold_continue(self):
        h = self.h
        owned = h.read_bytes("wPartyMons", 33, offset=44)
        owned[3] = h.read8("wPartyMon2Level")
        owned_ot = h.read_bytes("wPartyMonOT", 11, offset=11)
        self.seed(h, 5, {5:[25]}, 1)
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", self.mon[0])
        h.write8("wPartySpecies", 255, offset=1)
        h.write8("wRentalZone", 0)
        h.write8("wBoxSpecies", owned[0])
        start = h.address("wBoxMons")
        h.pyboy.memory[start:start+33] = owned
        start = h.address("wBoxMonOT")
        h.pyboy.memory[start:start+11] = owned_ot
        for target, name in (("wPartyMonNicks", "RENTAL"),
                             ("wBoxMonNicks", "OWNED MEW")):
            encoded = [127 if c == " " else 128 + ord(c) - ord("A") for c in name]
            start = h.address(target)
            h.pyboy.memory[start:start+11] = encoded + [80] * (11 - len(encoded))
        # Provider-free fixture: the real party mon is the reserved rental;
        # its owned fallback is in the currently selected box (box 6).
        start = h.address("wRentalOfferSpecies")
        h.pyboy.memory[start:start+12] = [0] * 12
        h.call_routine("SaveGameData")
        sav = dump_sram(h)
        destination = boxed.ARTIFACTS / "rental_phase1_fixed_party_recovery.sav"
        destination.write_bytes(sav)
        shutil.copyfile(h.rom_path, destination.with_suffix(".gbc"))
        shutil.copyfile(h.sym_path, destination.with_suffix(".sym"))
        destination.with_suffix(".json").write_text(json.dumps({
            "rom": destination.with_suffix(".gbc").name, "sha256": h.rom_sha256,
            "fixture": "Exeggutor named RENTAL in party; Mew named OWNED MEW in box 6",
            "steps": ["Continue in the lobby; visit a bridge or Dorm before use if desired",
                      "Enter and complete one ordinary route, gym or wild area",
                      "Return to the lobby (or Reward Room after paired gym A)",
                      "Verify rental removal, healed owned replacement, box 6 retained, saved notice",
                      "Reset and Continue; verify no repeated settlement"],
            "provider_enabled": False,
        }, indent=2) + "\n", encoding="utf-8")
        boot = ColdBoot(sav)
        self.addCleanup(boot.close)
        self.assertEqual(boot.to_menu(), 2)
        boot.continue_game()
        self.assertEqual(boot.h.read_bytes("wRentalRecord", 4), [1,1,0,3])
        self.assertEqual(boot.h.read8("wPartyCount"), 1)
        self.assertEqual(boot.h.read8("wCurrentBoxNum"), 133)
        self.assertEqual(boot.h.read8("wBoxCount"), 1)
        self.assertEqual(boot.h.read8("wBoxMons"), owned[0])
        self.assertNotEqual(owned[0], self.mon[0])

    def test_picked_up_owned_mon_survives_and_cursor_resets_before_save(self):
        h = self.h
        replacement.RentalReplacementTest.two_mons(self, h, 1)
        h.write8("wPartyAndBillsPCSavedMenuItem", 1)
        saved = []
        h.register_hook("SaveGameData", lambda _: saved.append(
            h.read8("wPartyAndBillsPCSavedMenuItem")))
        h.call_routine("RentalSettleAndSave")
        self.assertEqual(h.read8("wPartyCount"), 1)
        self.assertEqual(h.read8("wPartyMons", offset=12), 21)
        self.assertEqual(h.read8("wPartyAndBillsPCSavedMenuItem"), 0)
        self.assertEqual(saved, [0])

    def test_routes_wild_areas_and_every_gym_bind_once(self):
        h = self.h
        baseline = io.BytesIO()
        h.save_state(baseline)
        names = ("ROUTE_1", "VICTORY_ROAD_1F", "SS_ANNE_B1F",
                 "PROCEDURAL_CAVE_1", "PROCEDURAL_FOREST", "PROCEDURAL_FACILITY",
                 "PROCEDURAL_CEMETERY_1", "PROCEDURAL_CEMETERY_4",
                 "PEWTER_GYM", "CERULEAN_GYM", "VERMILION_GYM", "CELADON_GYM",
                 "FUCHSIA_GYM", "SAFFRON_GYM", "CINNABAR_GYM", "VIRIDIAN_GYM",
                 "VIOLET_GYM", "AZALEA_GYM", "GOLDENROD_GYM", "ECRUTEAK_GYM",
                 "CIANWOOD_GYM", "OLIVINE_GYM", "MAHOGANY_GYM", "BLACKTHORN_GYM")
        for name in names:
            h.load_state(baseline)
            self.seed(h, 0, {}, 0)
            zone = self.map(name)
            h.call_routine("RentalRecordMapLoad")
            self.assertEqual(h.read_bytes("wRentalRecord", 4), [2,0,zone,3], name)
            self.map("PROCEDURAL_CEMETERY_2")
            h.call_routine("RentalRecordMapLoad")
            self.assertEqual(h.read8("wRentalZone"), zone)

    def test_each_loaded_hub_reclaims_recovers_and_saves_once(self):
        h = self.h
        # The direct transaction fixture is parked inside VBlank. Sprite
        # updates can wait for graphics; the live lobby case below runs them.
        h.register_hook("UpdateSprites", lambda _: return_from_call(h))
        h.register_hook("RentalSettlementPopup", lambda _: return_from_call(h))
        for hub in ("REWARD_ROOM", "INDIGO_PLATEAU_LOBBY"):
            self.seed(h, 5, {5:[25], 8:[30]}, 167)
            zone = self.map("PEWTER_GYM")
            h.call_routine("RentalRecordMapLoad")
            self.assertEqual(h.read8("wRentalZone"), zone)
            self.map(hub)
            h.call_routine("RentalSettleZoneReturn")
            self.assertEqual(h.read_bytes("wRentalRecord", 4), [0,0,0,3])
            self.assertEqual(h.read8("wPartyCount"), 1)
            self.assertEqual(h.read8("wPartyMons", offset=12), 25)
            self.assertEqual(h.read_sram_bytes("sBox9", 1, bank=3), [0])
            h.write8("wPartyMons", 99, offset=12)
            h.call_routine("RentalSettleZoneReturn")
            h.call_routine("LoadPartyAndDexData")
            self.assertEqual(h.read8("wPartyMons", offset=12), 25)

    def test_active_internal_map_load_does_not_expire_or_rebind(self):
        h = self.h
        self.seed(h, 0, {}, 249)
        zone = self.map("ROUTE_1")
        h.call_routine("RentalRecordMapLoad")
        for name in ("ROUTE_1", "SS_ANNE_B1F_ROOMS", "SILPH_CO_DORM", "OAKS_LAB"):
            self.map(name)
            h.call_routine("RentalRecordMapLoad")
            h.call_routine("RentalSettleZoneReturn")
            self.assertEqual(h.read_bytes("wRentalRecord", 4), [2,249,zone,3])

    def test_live_lobby_settles_before_selection_and_saves_setup_as_pending(self):
        h = self.h
        event = parse_rgbds_constants(boxed.REPO_ROOT / "constants/event_constants.asm")["EVENT_ENTER_ROOM"]
        address = h.address("wEventFlags") + event // 8
        mask = 1 << (event % 8)
        trace = []
        started = []
        popup = []
        rendered = []
        visible_frames = []
        def check_notice(_):
            if not popup or rendered:
                return
            tilemap = h.read_bytes("wTileMap", 360)
            for row, label in ((2,"RentalEndedText"), (3,"RentalTeamReadyText"),
                               (4,"RentalSavedText")):
                bank, address = h.symbols.get(label)
                offset = bank * 0x4000 + address - 0x4000
                encoded = list(h._rom_file.getvalue()[offset:offset+18].split(b"\x50")[0])
                self.assertLessEqual(len(encoded), 17)
                if tilemap[row*20+2:row*20+2+len(encoded)] != encoded:
                    return
                self.assertEqual(list(h.pyboy.memory[0x9c00+row*32+2:
                    0x9c00+row*32+2+len(encoded)]), encoded)
            self.assertEqual(h.read8("hAutoBGTransferEnabled"), 1)
            self.assertEqual(h.read8("hWY"), 0)
            self.assertTrue(h.read8("wFontLoaded") & 1)
            rendered.append(True)
        def capture_visible_frame(_):
            if rendered and len(visible_frames) < 5:
                visible_frames.append(True)
                if len(visible_frames) == 5:
                    h.pyboy.screen.image.save(boxed.ARTIFACTS / "rental_settlement_visible.png")
        def enter(_):
            if started:
                return
            started.append(True)
            self.seed(h, 5, {5:[25], 8:[30]}, 167)
            h.write8("wRentalState", 2)
            h.pyboy.memory[address] &= 255 ^ mask
        h.register_hook("IndigoPlateauLobby_Script", enter)
        h.register_hook("SaveGameData", lambda _: trace.append(
            ("save", h.read8("wRentalState"), bool(h.pyboy.memory[address] & mask))))
        h.register_hook("SelectAndPatchLobbyExit", lambda _: trace.append(
            ("select", h.read8("wRentalState"), bool(h.pyboy.memory[address] & mask))))
        h.register_hook("RentalSettlementPopup", lambda _: popup.append(
            h.read_bytes("wTileMap", 360)))
        h.register_hook("RentalSettlementPopup.restored", lambda _: self.assertEqual(
            h.read_bytes("wTileMap", 360), popup[-1]))
        h.register_hook("DelayFrames", check_notice)
        h.register_hook("DelayFrame", capture_visible_frame)
        for _ in range(1200):
            h.tick(render=True)
            if any(row[0] == "select" for row in trace):
                break
        else:
            self.fail("loaded lobby settlement did not reach next selection")
        self.assertEqual(trace[:2], [("save",0,False), ("select",0,True)])
        self.assertEqual(len(popup), 1)
        self.assertEqual(rendered, [True])
        self.assertEqual(len(visible_frames), 5)
        self.assertEqual(h.read8("hWY"), 144)
        self.assertEqual(h.read8("hAutoBGTransferEnabled"), 0)
        self.assertFalse(h.read8("wFontLoaded") & 1)
        self.assertEqual(h.read8("wPartyCount"), 1)
        self.assertEqual(h.read8("wPartyMons", offset=12), 25)
        # Start a fresh emulator from battery SRAM, with no carried CPU state.
        # The settlement saved before next-stage selection and before popup.
        boot = ColdBoot(dump_sram(h))
        self.addCleanup(boot.close)
        self.assertEqual(boot.to_menu(), 2)
        saved = boot.h.hook_flag("SaveGameData")
        notices = boot.h.hook_flag("RentalSettlementPopup")
        selections = boot.h.hook_flag("SelectAndPatchLobbyExit")
        boot.continue_game()
        self.assertEqual(boot.h.read_bytes("wRentalRecord", 4), [0,0,0,3])
        self.assertEqual(boot.h.read8("wPartyCount"), 1)
        self.assertEqual(boot.h.read8("wPartyMons", offset=12), 25)
        self.assertEqual(boot.h.read8("wCurrentBoxNum"), 133)
        self.assertEqual(boot.h.read_sram_bytes("sBox9", 1, bank=3), [0])
        self.assertEqual((saved["count"], notices["count"], selections["count"]), (0,0,1))
