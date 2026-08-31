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

    def load_debug_follower_map(self, map_id: int) -> dict[str, int]:
        prepare = self.harness.hook_flag("FollowerPrepareMap")
        self.harness.boot_debug1(map_id)
        for _ in range(300):
            if prepare["count"]:
                break
            self.harness.tap("a", 1)
            self.harness.tick(4)
        self.harness.wait_until(
            lambda: prepare["count"] > 0,
            "follower map preparation",
            2400,
        )
        return prepare

    def test_dorm_spawns_and_follows_after_two_accepted_steps(self) -> None:
        maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")
        sprites = parse_rgbds_constants(ROOT / "constants" / "sprite_constants.asm")
        ram_constants = parse_rgbds_constants(ROOT / "constants" / "ram_constants.asm")
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
            sprites["SPRITE_MONSTER"],
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
        saved_pixel_y = self.harness.read8("wSprite15StateData1YPixels")
        saved_pixel_x = self.harness.read8("wSprite15StateData1XPixels")
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
        self.harness.write8("wSprite15StateData1YPixels", saved_pixel_y)
        self.harness.write8("wSprite15StateData1XPixels", saved_pixel_x)
        self.harness.call_routine("FollowerUpdate")

        prepare_before_close = prepare["count"]
        init_before_close = init_sprites["count"]
        for _ in range(30):
            if self.harness.read8("wFontLoaded") == 0:
                break
            self.harness.tap("start", 1)
            self.harness.tick(4)
        self.harness.wait_until(
            lambda: (
                self.harness.read8("wFontLoaded") == 0
                and prepare["count"] > prepare_before_close
                and init_sprites["count"] > init_before_close
            ),
            "Start-menu close and follower refresh",
            480,
        )
        self.harness.tick(6)
        self.assertEqual(
            (
                self.harness.read8("wSprite15StateData1PictureID"),
                self.harness.read8("wSprite15StateData2ImageBaseOffset"),
                self.harness.read8("wSprite15StateData2MapY"),
                self.harness.read8("wSprite15StateData2MapX"),
                self.harness.read8("wSprite15StateData1YPixels"),
                self.harness.read8("wSprite15StateData1XPixels"),
            ),
            (
                sprites["SPRITE_MONSTER"],
                2,
                saved_map_y,
                saved_map_x,
                saved_pixel_y,
                saved_pixel_x,
            ),
            "closing the Start menu changed the follower's identity or position",
        )

        battle_fields = (
            "wSprite15StateData1PictureID",
            "wSprite15StateData1ImageIndex",
            "wSprite15StateData1YPixels",
            "wSprite15StateData1XPixels",
            "wSprite15StateData1MovementStatus",
            "wSprite15StateData1AnimFrameCounter",
            "wSprite15StateData2MapY",
            "wSprite15StateData2MapX",
            "wSprite15StateData2ImageBaseOffset",
            "wFollowerCommandBufferSize",
        )
        battle_snapshot = tuple(self.harness.read8(field) for field in battle_fields)
        queue_snapshot = self.harness.read_bytes("wFollowerCommandBuffer", 16)
        battle_bit = ram_constants["BIT_BATTLE_OVER_OR_BLACKOUT"]
        self.harness.write8(
            "wStatusFlags4",
            self.harness.read8("wStatusFlags4") | (1 << battle_bit),
        )
        prepare_before_battle_return = prepare["count"]
        self.harness.call_routine("LoadMapData")
        self.assertGreater(
            prepare["count"],
            prepare_before_battle_return,
            "battle-return map load did not reach follower scheduling",
        )
        self.assertEqual(
            tuple(self.harness.read8(field) for field in battle_fields),
            battle_snapshot,
            "battle-return map loading changed slot-15 follower state",
        )
        self.assertEqual(
            self.harness.read_bytes("wFollowerCommandBuffer", 16),
            queue_snapshot,
            "battle-return map loading changed the follower queue",
        )
        self.harness.write8(
            "wStatusFlags4",
            self.harness.read8("wStatusFlags4") & ~(1 << battle_bit),
        )
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

    def test_talking_to_follower_uses_slot15_text_and_face_lifecycle(self) -> None:
        maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")
        sprites = parse_rgbds_constants(ROOT / "constants" / "sprite_constants.asm")
        facing = {
            "SPRITE_FACING_DOWN": 0x00,
            "SPRITE_FACING_UP": 0x04,
            "SPRITE_FACING_LEFT": 0x08,
            "SPRITE_FACING_RIGHT": 0x0C,
        }
        self.load_debug_follower_map(maps["SILPH_CO_DORM"])

        accepted = 0
        for direction in ("up", "right", "down", "left") * 3:
            before = (self.harness.read8("wYCoord"), self.harness.read8("wXCoord"))
            self.harness.move_tile(direction)
            after = (self.harness.read8("wYCoord"), self.harness.read8("wXCoord"))
            accepted += after != before
            if accepted == 2:
                break
        self.assertEqual(accepted, 2)
        self.harness.tick(40)

        player = (self.harness.read8("wYCoord"), self.harness.read8("wXCoord"))
        follower = (
            self.harness.read8("wSprite15StateData2MapY") - 4,
            self.harness.read8("wSprite15StateData2MapX") - 4,
        )
        delta = (follower[0] - player[0], follower[1] - player[1])
        direction_for_delta = {
            (1, 0): facing["SPRITE_FACING_DOWN"],
            (-1, 0): facing["SPRITE_FACING_UP"],
            (0, -1): facing["SPRITE_FACING_LEFT"],
            (0, 1): facing["SPRITE_FACING_RIGHT"],
        }
        self.assertIn(delta, direction_for_delta)
        player_facing = direction_for_delta[delta]
        self.harness.write8("wSpritePlayerStateData1FacingDirection", player_facing)

        interaction = self.harness.hook_flag("FollowerFindInteraction")
        face_player = self.harness.hook_flag("FollowerFacePlayer")
        display_text = self.harness.hook_flag("DisplayTextID")
        get_mon_name = self.harness.hook_flag("GetMonName")
        play_cry = self.harness.hook_flag("PlayCry")
        wait_text = self.harness.hook_flag("WaitForTextScrollButtonPress")
        close_text = self.harness.hook_flag("CloseTextDisplay")
        authored_count = self.harness.read8("wNumSprites")
        self.harness.tap("a", 3)
        self.harness.wait_until(
            lambda: wait_text["count"] > 0,
            "follower interaction prompt",
            600,
        )
        self.assertEqual(close_text["count"], 0)
        self.assertNotEqual(self.harness.read8("wFontLoaded") & 1, 0)
        self.assertGreater(display_text["count"], 0)
        self.assertNotEqual(self.harness.read8("hTextID"), 0)
        self.harness.tap("a", 3)
        self.harness.wait_until(
            lambda: close_text["count"] > 0,
            "follower interaction text close",
            600,
        )

        self.assertGreater(interaction["count"], 0)
        self.assertGreater(face_player["count"], 0)
        self.assertGreater(wait_text["count"], 0)
        self.assertGreater(get_mon_name["count"], 0)
        self.assertGreater(play_cry["count"], 0)
        self.assertEqual(self.harness.read8("wNumSprites"), authored_count)
        self.assertEqual(
            self.harness.read8("wSprite15StateData1FacingDirection"),
            player_facing ^ 4,
        )
        self.assertEqual(
            self.harness.read8("wSprite15StateData1PictureID"),
            sprites["SPRITE_MONSTER"],
        )
        self.assertEqual(self.harness.read8("wSprite15StateData2ImageBaseOffset"), 2)
        self.assertEqual(self.harness.read8("wFontLoaded") & 1, 0)

    def test_lead_sheet_change_during_text_reload_preserves_visible_pose(self) -> None:
        maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")
        sprites = parse_rgbds_constants(ROOT / "constants" / "sprite_constants.asm")
        pokemon = parse_rgbds_constants(ROOT / "constants" / "pokemon_constants.asm")
        self.load_debug_follower_map(maps["SILPH_CO_DORM"])

        accepted = 0
        for direction in ("up", "right", "down", "left") * 3:
            before = (self.harness.read8("wYCoord"), self.harness.read8("wXCoord"))
            self.harness.move_tile(direction)
            after = (self.harness.read8("wYCoord"), self.harness.read8("wXCoord"))
            accepted += after != before
            if accepted == 2:
                break
        self.assertEqual(accepted, 2)
        self.harness.tick(40)

        saved_pose = (
            self.harness.read8("wSprite15StateData2MapY"),
            self.harness.read8("wSprite15StateData2MapX"),
            self.harness.read8("wSprite15StateData1YPixels"),
            self.harness.read8("wSprite15StateData1XPixels"),
            self.harness.read8("wSprite15StateData1FacingDirection"),
        )
        self.assertNotEqual(self.harness.read8("wSprite15StateData1ImageIndex"), 0xFF)
        self.harness.write8("wPartySpecies", pokemon["PIKACHU"])
        self.harness.write8("wFontLoaded", 1)
        self.harness.call_routine("FollowerPrepareMap")

        self.assertEqual(
            self.harness.read8("wSprite15StateData1PictureID"),
            sprites["SPRITE_PIKACHU"],
        )
        self.assertEqual(
            (
                self.harness.read8("wSprite15StateData2MapY"),
                self.harness.read8("wSprite15StateData2MapX"),
                self.harness.read8("wSprite15StateData1YPixels"),
                self.harness.read8("wSprite15StateData1XPixels"),
                self.harness.read8("wSprite15StateData1FacingDirection"),
            ),
            saved_pose,
        )
        self.assertNotEqual(
            self.harness.read8("wSprite15StateData1ImageIndex"),
            0xFF,
            "new lead remained hidden until the next accepted player step",
        )
        self.harness.write8("wFontLoaded", 0)

    def test_dorm_b1f_warp_uses_yellow_default_state_zero(self) -> None:
        maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")
        sprites = parse_rgbds_constants(ROOT / "constants" / "sprite_constants.asm")
        prepare = self.load_debug_follower_map(maps["SILPH_CO_DORM"])

        for _ in range(3):
            self.harness.move_tile("right")
        prepare_before = prepare["count"]
        self.harness.move_tile("down")
        self.harness.wait_until(
            lambda: (
                self.harness.read8("hCurMap") == maps["SILPH_CO_B1F"]
                and prepare["count"] > prepare_before
            ),
            "Dorm to B1F follower warp",
            1200,
        )
        self.harness.tick(60)
        self.assertEqual(
            (
                self.harness.read8("wSprite15StateData1PictureID"),
                self.harness.read8("wSprite15StateData2ImageBaseOffset"),
                self.harness.read8("wSprite15StateData2MapY"),
                self.harness.read8("wSprite15StateData2MapX"),
                self.harness.read8("wFollowerSpawnState"),
            ),
            (
                sprites["SPRITE_MONSTER"],
                2,
                self.harness.read8("wYCoord") + 4,
                self.harness.read8("wXCoord") + 4,
                0,
            ),
            "Dorm to B1F did not consume Yellow's default overlap state",
        )

        prepare_before = prepare["count"]
        self.harness.move_tile("up")
        self.harness.wait_until(
            lambda: (
                self.harness.read8("hCurMap") == maps["SILPH_CO_DORM"]
                and prepare["count"] > prepare_before
            ),
            "B1F to Dorm follower warp",
            1200,
        )
        self.harness.tick(60)
        self.assertEqual(self.harness.read8("wSprite15StateData1PictureID"), sprites["SPRITE_MONSTER"])
        self.assertEqual(self.harness.read8("wSprite15StateData2ImageBaseOffset"), 2)
        self.assertEqual(self.harness.read8("wFollowerSpawnState"), 0)

    def test_active_yellow_ledge_latch_and_two_tile_motion(self) -> None:
        maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")
        sprites = parse_rgbds_constants(ROOT / "constants" / "sprite_constants.asm")
        ram_constants = parse_rgbds_constants(ROOT / "constants" / "ram_constants.asm")
        prepare = self.harness.hook_flag("FollowerPrepareMap")
        self.harness.boot_debug1(maps["SILPH_CO_DORM"])
        for _ in range(300):
            if prepare["count"]:
                break
            self.harness.tap("a", 1)
            self.harness.tick(4)
        self.harness.wait_until(
            lambda: prepare["count"] > 0,
            "Dorm follower map preparation for ledge probe",
            2400,
        )
        self.harness.tick(8)

        ledge_flag = 1 << ram_constants["BIT_LEDGE_OR_FISHING"]
        command_by_direction = (
            (1 << 2, 5),  # PLAYER_DIR_DOWN -> FOLLOWER_COMMAND_LEDGE_DOWN
            (1 << 3, 6),  # PLAYER_DIR_UP -> FOLLOWER_COMMAND_LEDGE_UP
            (1 << 1, 7),  # PLAYER_DIR_LEFT -> FOLLOWER_COMMAND_LEDGE_LEFT
            (1 << 0, 8),  # PLAYER_DIR_RIGHT -> FOLLOWER_COMMAND_LEDGE_RIGHT
        )
        for direction, expected_command in command_by_direction:
            self.harness.call_routine("FollowerClearQueue")
            self.harness.write8("wFollowerLedgeLatch", 0)
            self.harness.write8("wWalkBikeSurfState", 0)
            self.harness.write8("wMovementFlags", ledge_flag)
            self.harness.write8("wPlayerDirection", direction)
            self.harness.call_routine("FollowerQueuePlayerStep")
            self.assertEqual(self.harness.read8("wFollowerLedgeLatch"), 1)
            self.assertEqual(self.harness.read8("wFollowerCommandBufferSize"), 0)
            self.assertEqual(
                self.harness.read8("wFollowerCommandBuffer"), expected_command
            )
            self.harness.call_routine("FollowerQueuePlayerStep")
            self.assertEqual(self.harness.read8("wFollowerLedgeLatch"), 0)
            self.assertEqual(self.harness.read8("wFollowerCommandBufferSize"), 0)

        self.harness.call_routine("FollowerClearQueue")
        self.harness.write8("wFollowerLedgeLatch", 0)
        self.harness.write8("wMovementFlags", ledge_flag)
        self.harness.write8("wPlayerDirection", 1 << 2)
        self.harness.call_routine("FollowerQueuePlayerStep")
        self.harness.call_routine("FollowerQueuePlayerStep")
        self.harness.write8("wMovementFlags", 0)

        start_map_y = self.harness.read8("wYCoord") + 3
        start_map_x = self.harness.read8("wXCoord") + 4
        start_pixel_y = 44
        start_pixel_x = 64
        self.harness.write8("wSprite15StateData2MapY", start_map_y)
        self.harness.write8("wSprite15StateData2MapX", start_map_x)
        self.harness.write8("wSprite15StateData1YPixels", start_pixel_y)
        self.harness.write8("wSprite15StateData1XPixels", start_pixel_x)
        self.harness.write8("wSprite15StateData1MovementStatus", 1)
        self.harness.write8("wFontLoaded", 0)
        tile_y = (start_pixel_y + 4) & 0xF0
        tile_x = (start_pixel_x + 2) >> 3
        bottom_left = 5 * (tile_y >> 1) + tile_x + 20
        tilemap = self.harness.address("wTileMap")
        for offset in (bottom_left, bottom_left - 1, bottom_left - 20, bottom_left - 19):
            self.harness.pyboy.memory[tilemap + offset] = 0
        self.assertEqual(
            (
                self.harness.read8("wWalkBikeSurfState"),
                self.harness.read8("wMovementFlags"),
                self.harness.read8("wPlayerDirection"),
                self.harness.read8("wFollowerLedgeLatch"),
                self.harness.read8("wFollowerCommandBufferSize"),
                self.harness.read8("wSprite15StateData1PictureID"),
                self.harness.read8("hCurMap"),
            ),
            (0, 0, 1 << 2, 0, 0, sprites["SPRITE_MONSTER"], maps["SILPH_CO_DORM"]),
        )
        append_commands = []
        append_bank, append_address = self.harness.symbols.get("FollowerAppendCommand")
        reject_hook = self.harness.hook_flag("FollowerAppendCommand.reject")
        command_start = self.harness.hook_flag("FollowerStartCommand")
        visibility_hidden = self.harness.hook_flag("FollowerCheckVisibility.hidden")

        def capture_append(_context) -> None:
            append_commands.append(self.harness.pyboy.register_file.A)

        self.harness.pyboy.hook_register(
            append_bank, append_address, capture_append, None
        )
        try:
            self.harness.call_routine("FollowerQueuePlayerStep")
        finally:
            self.harness.pyboy.hook_deregister(append_bank, append_address)
        self.assertEqual(append_commands, [1], "ordinary post-ledge command was not encoded")
        self.assertEqual(reject_hook["count"], 0, "ordinary post-ledge command was rejected")
        self.assertEqual(self.harness.read8("wFollowerCommandBufferSize"), 0)
        self.assertEqual(self.harness.read_bytes("wFollowerCommandBuffer", 2), [1, 0xFF])
        self.assertEqual(
            visibility_hidden["count"],
            0,
            "synthetic ledge fixture was rejected by follower visibility",
        )
        self.assertGreater(command_start["count"], 0, "queued ledge command was not dispatched")
        self.assertEqual(self.harness.read8("wSprite15StateData1MovementStatus"), 4)
        for _ in range(20):
            if self.harness.read8("wSprite15StateData1MovementStatus") == 1:
                break
            self.harness.call_routine("FollowerUpdate")
        self.assertEqual(self.harness.read8("wSprite15StateData1MovementStatus"), 1)
        self.assertEqual(self.harness.read8("wSprite15StateData2MapY"), start_map_y + 2)
        self.assertEqual(self.harness.read8("wSprite15StateData2MapX"), start_map_x)
        self.assertEqual(
            self.harness.read8("wSprite15StateData1YPixels"),
            (start_pixel_y + 32) & 0xFF,
        )
        self.assertEqual(self.harness.read8("wSprite15StateData1XPixels"), start_pixel_x)


class YellowFollowerRoute1CGBTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=True)

    def tearDown(self) -> None:
        self.harness.close()

    def test_route1_fixed_set_and_player_movement_at_60fps(self) -> None:
        maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")
        sprites = parse_rgbds_constants(ROOT / "constants" / "sprite_constants.asm")
        self.harness.boot_to_lobby(battle_count=1)
        self.harness.enter_stage_door1(maps["ROUTE_1"], description="Route 1")

        self.assertEqual(self.harness.read8("hCurMap"), maps["ROUTE_1"])
        self.assertEqual(self.harness.read8("wOptions2") & 0x40, 0x40)
        self.assertEqual(self.harness.pyboy.memory[0xFF4D] & 0x80, 0x80)
        self.assertEqual(
            self.harness.read_bytes("wSpriteSet", 11),
            [
                sprites["SPRITE_MONSTER"],
                sprites["SPRITE_BLUE"],
                sprites["SPRITE_YOUNGSTER"],
                sprites["SPRITE_GIRL"],
                sprites["SPRITE_FISHER"],
                sprites["SPRITE_COOLTRAINER_M"],
                sprites["SPRITE_GAMBLER"],
                sprites["SPRITE_SEEL"],
                sprites["SPRITE_OAK"],
                sprites["SPRITE_POKE_BALL"],
                sprites["SPRITE_GAMBLER_ASLEEP"],
            ],
        )
        expected_bases = [4, 4, 4, 4, 7, 11, 11, 11, 11, 7, 4, 4]
        for slot, expected in enumerate(expected_bases, start=1):
            self.assertEqual(
                self.harness.read8(f"wSprite{slot:02d}StateData2ImageBaseOffset"),
                expected,
                f"Route 1 slot {slot} used the wrong fixed-set image base",
            )
        self.assertEqual(
            self.harness.read8("wSprite15StateData1PictureID"),
            sprites["SPRITE_MONSTER"],
        )
        self.assertEqual(self.harness.read8("wSprite15StateData2ImageBaseOffset"), 2)

        movement_flags = self.harness.read8("wMovementFlags")
        player_walk_anim = self.harness.read8(
            "wSpritePlayerStateData2WalkAnimationCounter"
        )
        update_enabled = self.harness.read8("hUpdateSpritesEnabled")
        player_image_base = self.harness.read8(
            "wSpritePlayerStateData2ImageBaseOffset"
        )
        self.assertEqual(
            player_image_base,
            1,
            "Route 1 fixed-set loading cleared the player's image base",
        )
        update_calls = self.harness.hook_flag("UpdateSprites")
        update_loop_calls = self.harness.hook_flag("_UpdateSprites")
        player_updates = self.harness.hook_flag("UpdatePlayerSprite")

        start = (self.harness.read8("wYCoord"), self.harness.read8("wXCoord"))
        player_images = []
        walk_counters = []
        intra_frames = []
        anim_frames = []
        self.harness.pyboy.button_press("left")
        for _ in range(36):
            self.harness.tick(1)
            player_images.append(
                self.harness.read8("wSpritePlayerStateData1ImageIndex")
            )
            walk_counters.append(self.harness.read8("wWalkCounter"))
            intra_frames.append(
                self.harness.read8("wSpritePlayerStateData1IntraAnimFrameCounter")
            )
            anim_frames.append(
                self.harness.read8("wSpritePlayerStateData1AnimFrameCounter")
            )
        self.harness.pyboy.button_release("left")
        self.harness.wait_until(
            lambda: self.harness.read8("wWalkCounter") == 0,
            "Route 1 player movement completion",
            120,
        )
        self.harness.tick(4)
        end = (self.harness.read8("wYCoord"), self.harness.read8("wXCoord"))
        self.assertNotEqual(end, start, "Route 1 player step did not complete")
        self.assertEqual(self.harness.read8("wWalkCounter"), 0)
        self.assertGreaterEqual(
            len({image & 3 for image in player_images}),
            2,
            "Route 1 player walking frames did not animate at 60 FPS: "
            f"images={player_images} walk={walk_counters} "
            f"intra={intra_frames} anim={anim_frames} "
            f"movement_flags={movement_flags:#04x} "
            f"player_walk_anim={player_walk_anim:#04x} "
            f"update_enabled={update_enabled:#04x} "
            f"player_image_base={player_image_base:#04x} "
            f"update_calls={update_calls['count']} "
            f"update_loop_calls={update_loop_calls['count']} "
            f"player_updates={player_updates['count']}",
        )

        collision_position = None
        for _ in range(16):
            before = (self.harness.read8("wYCoord"), self.harness.read8("wXCoord"))
            self.harness.move_tile("left")
            self.harness.wait_until(
                lambda: self.harness.read8("wWalkCounter") == 0,
                "Route 1 westward movement completion",
                120,
            )
            after = (self.harness.read8("wYCoord"), self.harness.read8("wXCoord"))
            if after == before:
                collision_position = after
                break
        self.assertIsNotNone(
            collision_position,
            "could not reach a Route 1 west-wall collision fixture",
        )
        self.harness.move_tile("right")
        self.harness.wait_until(
            lambda: self.harness.read8("wWalkCounter") == 0,
            "Route 1 post-collision recovery step",
            120,
        )
        self.assertNotEqual(
            (self.harness.read8("wYCoord"), self.harness.read8("wXCoord")),
            collision_position,
            "player remained stuck after a Route 1 wall collision",
        )


if __name__ == "__main__":
    unittest.main()
