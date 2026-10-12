"""Rental markers follow saved ownership and coexist with special forms."""
from pathlib import Path
import unittest

from harness import RedRogueHarness
import test_battle_variant_markers as variants

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).parent / "artifacts"


class RentalMarkerTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.h.boot_to_lobby()

    def tearDown(self):
        self.h.close()

    def clear(self):
        start = self.h.address("wTileMap")
        self.h.pyboy.memory[start:start + 360] = [0x7f] * 360

    def tile(self, x, y):
        return self.h.read8("wTileMap", offset=y * 20 + x)

    def test_battle_marker_coexists_with_all_variant_glyphs_and_tracks_switch(self):
        h = self.h
        h.write8("wRentalState", 2)
        h.write8("wRentalOwner", 2)
        h.write8("wPlayerMonNumber", 1)
        # Ghost, shiny, and type variants are still rendered in the old cell.
        for flags, mon_type, glyph in ((1, 0, 0xd0), (16, 0, 0xd4),
                                      (4, 21, 0xd1), (4, 5, 0xd2)):
            with self.subTest(flags=flags, mon_type=mon_type):
                h.write8("wBattleMonType2", mon_type)
                tiles = variants.BattleVariantMarkerRuntimeTest.capture_tiles(
                    self, "DrawPlayerHUDAndHPBar", "CenterMonName", flags, 0)
                self.assertEqual(tiles[8 * 20 + 12], 0x91)  # R
                self.assertEqual(tiles[8 * 20 + 13], glyph)
        h.write8("wPlayerMonNumber", 0)
        tiles = variants.BattleVariantMarkerRuntimeTest.capture_tiles(
            self, "DrawPlayerHUDAndHPBar", "CenterMonName", 1, 0)
        self.assertNotEqual(tiles[8 * 20 + 12], 0x91)
        h.write8("wRentalOwner", 1)
        tiles = variants.BattleVariantMarkerRuntimeTest.capture_tiles(
            self, "DrawEnemyHUDAndHPBar", "CenterMonName", 0, 1)
        self.assertNotEqual(tiles[1 * 20 + 8], 0x91)

    def test_status_locations_match_only_the_actual_rental(self):
        h = self.h
        for box in range(12):
            for slot in (0, 19):
                for state in (0, 1, 2, 255):
                    for owner in (7 + box * 20 + slot, 1, 247, 249):
                        with self.subTest(box=box, slot=slot, state=state, owner=owner):
                            self.clear()
                            h.write8("wCurrentBoxNum", box | 128)
                            h.write8("hWhichPokemon", slot)
                            h.write8("wMonDataLocation", 2)
                            h.write8("wRentalState", state)
                            h.write8("wRentalOwner", owner)
                            h.call_routine("RentalDrawStatusMarker")
                            expected = state in (1, 2) and owner == 7 + box * 20 + slot
                            self.assertEqual(self.tile(8, 7) == 0x91, expected)
        for location, slot, owner in ((0, 5, 6), (3, 0, 247), (5, 0, 248),
                                      (1, 0, 1), (4, 0, 1)):
            self.clear()
            h.write8("wMonDataLocation", location)
            h.write8("hWhichPokemon", slot)
            h.write8("wRentalState", 1)
            h.write8("wRentalOwner", owner)
            h.call_routine("RentalDrawStatusMarker")
            self.assertEqual(self.tile(8, 7) == 0x91, location in (0, 3, 5))

    def test_party_marker_uses_free_hp_row_cell_and_valid_contract(self):
        h = self.h
        for state in (0, 1, 2, 255):
            for selected in range(6):
                self.clear()
                h.write8("wRentalState", state)
                h.write8("wRentalOwner", 3)
                h.write8("hWhichPokemon", selected)
                origin = h.address("wTileMap") + selected * 40 + 3
                h.pyboy.register_file.D = origin >> 8
                h.pyboy.register_file.E = origin & 255
                h.call_routine("RentalDrawPartyMarker")
                markers = [self.tile(3, row * 2 + 1) for row in range(6)]
                expected = [0x7f] * 6
                if state in (1, 2) and selected == 2:
                    expected[selected] = 0x91
                self.assertEqual(markers, expected)

    def test_party_redraw_clears_marker_after_owner_moves(self):
        h = self.h
        h.write8("wRentalState", 1)
        h.write8("hWhichPokemon", 0)
        for owner, expected in ((1, 0x91), (2, 0x7f), (1, 0x91), (0, 0x7f)):
            h.write8("wRentalOwner", owner)
            origin = h.address("wTileMap") + 3
            h.pyboy.register_file.D = origin >> 8
            h.pyboy.register_file.E = origin & 255
            h.call_routine("RentalDrawPartyMarker")
            self.assertEqual(self.tile(3, 1), expected)

    def test_normal_menu_input_shows_party_and_both_status_page_markers(self):
        h = self.h
        # boot_to_lobby stops before the map script finishes its setup.
        h.tick(180)
        h.write8("wRentalState", 1)
        h.write8("wRentalOwner", 1)
        h.write8("wBattleAndStartSavedMenuItem", 1)
        h.tap("start")
        h.tick(30)
        h.tap("a")
        h.tick(60, render=True)
        self.assertEqual(self.tile(3, 1), 0x91)
        self.assertEqual(self.tile(3, 3), 0x7f)
        h.pyboy.screen.image.save(str(ARTIFACTS / "rental_marker_party_dmg.png"))
        h.tap("a")
        h.tick(20)
        h.tap("a")
        h.tick(120, render=True)
        self.assertEqual(self.tile(8, 7), 0x91)
        h.pyboy.screen.image.save(str(ARTIFACTS / "rental_marker_status_dmg.png"))
        h.tap("a")
        h.tick(80, render=True)
        self.assertEqual(self.tile(8, 7), 0x91)
        h.pyboy.screen.image.save(str(ARTIFACTS / "rental_marker_status2_dmg.png"))


if __name__ == "__main__":
    unittest.main()
