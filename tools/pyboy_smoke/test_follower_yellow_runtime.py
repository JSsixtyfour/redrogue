"""Focused PyBoy smoke for the contained Yellow-derived follower slice."""

from pathlib import Path
import io
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants


ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"


class YellowFollowerRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.harness.close()

    def background_tiles_at(self, y_pixels: int, x_pixels: int) -> list[int]:
        y = (y_pixels + 4) & 0xF0
        x = (x_pixels + 2) >> 3
        bottom_left = 5 * (y >> 1) + x + 20
        tilemap = self.harness.address("wTileMap")
        return [
            self.harness.pyboy.memory[tilemap + bottom_left],
            self.harness.pyboy.memory[tilemap + bottom_left - 1],
            self.harness.pyboy.memory[tilemap + bottom_left - 20],
            self.harness.pyboy.memory[tilemap + bottom_left - 19],
        ]

    def follower_background_tiles(self) -> list[int]:
        return self.background_tiles_at(
            self.harness.read8("wSprite15StateData1YPixels"),
            self.harness.read8("wSprite15StateData1XPixels"),
        )

    def test_dorm_spawns_and_follows_after_two_accepted_steps(self) -> None:
        maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")
        sprites = parse_rgbds_constants(ROOT / "constants" / "sprite_constants.asm")
        enter_map = self.harness.hook_flag("EnterMap")
        load_map = self.harness.hook_flag("LoadMapData")
        init_sprites = self.harness.hook_flag("InitMapSprites")
        prepare = self.harness.hook_flag("FollowerPrepareMap")
        self.harness.boot_debug1(maps["SILPH_CO_DORM"])

        for _ in range(300):
            if prepare["count"]:
                break
            self.harness.tap("a", 1)
            self.harness.tick(4)
        self.harness.wait_until(
            lambda: prepare["count"] > 0,
            "Dorm follower map preparation",
            2400,
        )
        self.assertGreater(enter_map["count"], 0, "EnterMap was never reached")
        self.assertGreater(load_map["count"], 0, "LoadMapData was never reached")
        self.assertGreater(init_sprites["count"], 0, "InitMapSprites was never reached")
        self.assertGreater(prepare["count"], 0, "FollowerPrepareMap was never reached")
        self.assertEqual(
            self.harness.read8("wSprite15StateData1PictureID"),
            sprites["SPRITE_PIKACHU"],
        )
        self.assertEqual(self.harness.read8("wSprite15StateData2ImageBaseOffset"), 2)

        accepted = []
        for direction in ("up", "right", "down", "left") * 3:
            before = (
                self.harness.read8("wYCoord"),
                self.harness.read8("wXCoord"),
            )
            self.harness.move_tile(direction)
            after = (
                self.harness.read8("wYCoord"),
                self.harness.read8("wXCoord"),
            )
            if after != before:
                accepted.append((before, after))
            if len(accepted) == 2:
                break

        self.assertEqual(len(accepted), 2, "could not find two accepted Dorm steps")
        self.harness.tick(40)
        follower = (
            self.harness.read8("wSprite15StateData2MapY") - 4,
            self.harness.read8("wSprite15StateData2MapX") - 4,
        )
        player = (
            self.harness.read8("wYCoord"),
            self.harness.read8("wXCoord"),
        )
        self.assertNotEqual(follower, player)
        self.assertNotEqual(self.harness.read8("wSprite15StateData1ImageIndex"), 0xFF)

        dy = follower[0] - player[0]
        dx = follower[1] - player[1]
        self.assertEqual(abs(dy) + abs(dx), 1)
        reverse = {
            (-1, 0): "up",
            (1, 0): "down",
            (0, -1): "left",
            (0, 1): "right",
        }[(dy, dx)]
        walking_images = []
        self.harness.pyboy.button_press(reverse)
        for _ in range(20):
            self.harness.tick(1)
            image = self.harness.read8("wSprite15StateData1ImageIndex")
            if image != 0xFF:
                walking_images.append(image)
        self.harness.pyboy.button_release(reverse)
        self.harness.tick(4)
        self.assertEqual(
            (
                self.harness.read8("wYCoord"),
                self.harness.read8("wXCoord"),
            ),
            follower,
            "slot 15 still blocked the player's reverse step",
        )
        self.assertGreaterEqual(
            len({image & 0x3 for image in walking_images}),
            2,
            "follower walking frames did not visibly advance",
        )

        menu_init = self.harness.hook_flag("DisplayTextIDInit")
        follower_updates = self.harness.hook_flag("FollowerUpdate")
        updates_before_menu = follower_updates["count"]
        self.harness.wait_until(
            lambda: self.harness.read8("wWalkCounter") == 0,
            "player movement completion before menu",
            240,
        )
        overworld_tiles = self.harness.read_bytes("wTileMap", 20 * 18)
        self.harness.tap("start", 2)
        self.harness.wait_until(
            lambda: menu_init["count"] > 0,
            "start-menu DisplayTextIDInit",
            240,
        )
        self.harness.tick(6)
        self.assertGreater(
            follower_updates["count"],
            updates_before_menu,
            "menu initialization never dispatched slot 15",
        )
        covered_tiles = self.follower_background_tiles()
        self.assertTrue(
            any(tile >= 0x60 for tile in covered_tiles),
            f"test position was not covered by the Start menu: {covered_tiles}",
        )
        self.assertEqual(
            self.harness.read8("wSprite15StateData1ImageIndex"),
            0xFF,
            f"covered follower remained visible over Start menu tiles {covered_tiles}",
        )

        saved_map_y = self.harness.read8("wSprite15StateData2MapY")
        saved_map_x = self.harness.read8("wSprite15StateData2MapX")
        uncovered_position = None
        for map_delta_y in range(1, 9):
            for map_delta_x in range(1, 10):
                tiles = self.background_tiles_at(
                    map_delta_y * 16 - 4,
                    map_delta_x * 16,
                )
                if all(tile < 0x60 for tile in tiles):
                    uncovered_position = (map_delta_y, map_delta_x)
                    break
            if uncovered_position is not None:
                break
        self.assertIsNotNone(uncovered_position, "Start menu left no uncovered 2x2 region")
        map_delta_y, map_delta_x = uncovered_position
        self.harness.write8(
            "wSprite15StateData2MapY",
            self.harness.read8("wYCoord") + map_delta_y,
        )
        self.harness.write8(
            "wSprite15StateData2MapX",
            self.harness.read8("wXCoord") + map_delta_x,
        )
        self.harness.write8(
            "wSprite15StateData1YPixels",
            map_delta_y * 16 - 4,
        )
        self.harness.write8(
            "wSprite15StateData1XPixels",
            map_delta_x * 16,
        )
        self.harness.call_routine("FollowerUpdate")
        uncovered_tiles = self.follower_background_tiles()
        self.assertTrue(
            all(tile < 0x60 for tile in uncovered_tiles),
            f"synthetic left-side position was still covered: {uncovered_tiles}",
        )
        self.assertNotEqual(
            self.harness.read8("wSprite15StateData1ImageIndex"),
            0xFF,
            "uncovered follower was hidden by the Start menu",
        )
        self.harness.write8("wSprite15StateData2MapY", saved_map_y)
        self.harness.write8("wSprite15StateData2MapX", saved_map_x)
        self.harness.call_routine("FollowerUpdate")

        trainer_card_entry = io.BytesIO()
        self.harness.save_state(trainer_card_entry)
        try:
            tilemap = self.harness.address("wTileMap")
            for offset in range(20 * 18):
                self.harness.pyboy.memory[tilemap + offset] = 0x7F
            self.harness.call_routine("FollowerUpdate")
            self.assertEqual(
                self.harness.read8("wSprite15StateData1ImageIndex"),
                0xFF,
                "follower remained visible on the Trainer Card's cleared tilemap",
            )
        finally:
            self.harness.load_state(trainer_card_entry)

        tilemap = self.harness.address("wTileMap")
        for offset, tile in enumerate(overworld_tiles):
            self.harness.pyboy.memory[tilemap + offset] = tile
        self.harness.write8("wFontLoaded", 0)
        self.harness.write8(
            "wSprite15StateData2MapY",
            self.harness.read8("wYCoord") + map_delta_y,
        )
        self.harness.write8(
            "wSprite15StateData2MapX",
            self.harness.read8("wXCoord") + map_delta_x,
        )
        self.harness.write8("wSprite15StateData1YPixels", map_delta_y * 16 - 4)
        self.harness.write8("wSprite15StateData1XPixels", map_delta_x * 16)
        self.harness.call_routine("FollowerUpdate")
        self.assertNotEqual(
            self.harness.read8("wSprite15StateData1ImageIndex"),
            0xFF,
            "follower did not recover after restoring the saved map tilemap: "
            f"tiles={self.follower_background_tiles()} "
            f"player=({self.harness.read8('wYCoord')},{self.harness.read8('wXCoord')}) "
            f"follower=({self.harness.read8('wSprite15StateData2MapY')},"
            f"{self.harness.read8('wSprite15StateData2MapX')})",
        )


if __name__ == "__main__":
    unittest.main()
