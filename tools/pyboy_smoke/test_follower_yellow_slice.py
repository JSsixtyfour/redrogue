"""Source gates for the contained Yellow-derived follower slice.

These checks prevent the rejected generalized draft and stationary publisher
from returning. Emulator acceptance is still required for choreography.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]


class YellowFollowerSliceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = (ROOT / "engine/overworld/follower_yellow_test.asm").read_text()
        cls.main = (ROOT / "main.asm").read_text()
        cls.loader = (ROOT / "engine/overworld/map_sprites.asm").read_text()
        cls.update = (ROOT / "engine/overworld/sprite_collisions.asm").read_text()
        cls.overworld = (ROOT / "home/overworld.asm").read_text()
        cls.home = (ROOT / "home.asm").read_text()
        cls.predef_text = (ROOT / "data/text_predef_pointers.asm").read_text()
        cls.wram = (ROOT / "ram/wram.asm").read_text()
        cls.ram_constants = (ROOT / "constants/ram_constants.asm").read_text()
        cls.extra_options = (ROOT / "engine/menus/extra_options.asm").read_text()

    def test_only_scoped_core_is_included(self):
        self.assertIn('INCLUDE "engine/overworld/follower_yellow_test.asm"', self.main)
        self.assertNotIn('INCLUDE "engine/overworld/follower.asm"', self.main)
        self.assertNotIn("follower_baseline.asm", self.main)

    def test_scope_resolves_lead_only_on_explicit_test_maps(self):
        self.assertIn("cp SILPH_CO_B1F", self.core)
        self.assertIn("cp SILPH_CO_DORM", self.core)
        self.assertIn("cp OAKS_LAB", self.core)
        self.assertIn("cp ROUTE_1", self.core)
        self.assertIn("cp POWER_PLANT", self.core)
        self.assertIn("cp MT_MOON_1F", self.core)
        self.assertIn("cp VICTORY_ROAD_1F", self.core)
        self.assertIn("FollowerResolveLeadPicture:", self.core)
        self.assertIn("farcall PCGetPokemonSpriteCategory", self.core)
        self.assertIn("ld a, [wPartySpecies]", self.core)
        for forbidden in (
            "INDIGO_PLATEAU_LOBBY",
            "FollowerStartIdleAction",
        ):
            self.assertNotIn(forbidden, self.core)

    def test_first_crowded_indoor_group_reserves_follower_base_two(self):
        for map_name in ("POWER_PLANT", "MT_MOON_1F", "VICTORY_ROAD_1F"):
            with self.subTest(map=map_name):
                self.assertRegex(
                    self.loader,
                    rf"(?m)^\s*cp {map_name}\s*$",
                )

    def test_yellow_queue_sentinel_contract(self):
        self.assertIn("DEF FOLLOWER_COMMAND_EMPTY      EQU $ff", self.core)
        self.assertRegex(
            self.wram,
            r"wFollowerCommandBufferSize:: db\s+wFollowerCommandBuffer:: ds 16",
        )
        self.assertRegex(
            self.core,
            r"(?ms)FollowerDequeueCommand:.*?cp FOLLOWER_COMMAND_EMPTY.*?and a.*?jr z, \.empty",
        )

    def test_yellow_transition_spawn_states_are_explicit(self):
        self.assertRegex(
            self.wram,
            r"(?s)wFollowerCommandBuffer:: ds 16\s+.*?wFollowerSpawnState:: db\s+"
            r".*?wFollowerLedgeLatch:: db\s+ds 128 - 19",
        )
        warp = self.overworld.split("WarpFound2::", 1)[1].split(
            "ContinueCheckWarpsNoCollisionLoop::", 1
        )[0]
        self.assertRegex(
            warp,
            r"(?s)xor a\s+ld \[wFollowerSpawnState\], a\s+"
            r"ldh a, \[hCurMap\]\s+ld \[wWarpedFromWhichMap\], a.*?"
            r"cp INDIGO_PLATEAU_LOBBY",
        )
        connection = self.overworld.split(
            ".loadNewMap ; load the connected map that was entered", 1
        )[1].split(".didNotEnterConnectedMap", 1)[0]
        self.assertRegex(
            connection,
            r"(?s)call LoadMapHeader.*?farcall FollowerInitConnectedMapSprites",
        )
        connected_wrapper = self.core.split(
            "FollowerInitConnectedMapSprites::", 1
        )[1].split("FollowerPrepareMap::", 1)[0]
        self.assertRegex(
            connected_wrapper,
            r"(?s)ld a, 2\s+ld \[wFollowerSpawnState\], a\s+farjp InitMapSprites",
        )
        transition_setters = self.core.split(
            "FollowerSetWarpSpawnStateAndCheck::", 1
        )[1].split("FollowerPrepareMap::", 1)[0]
        self.assertRegex(
            warp,
            r"(?s)cp ROGUE_MAP\s+jr z, \.randomStage\s+"
            r".*?farcall FollowerSetWarpSpawnStateAndCheck\s+"
            r"call CheckIfInOutsideMap",
        )
        self.assertIn("cp LAST_MAP", transition_setters)
        self.assertIn("call CheckIfInOutsideMap", transition_setters)
        self.assertIn("farjp IsPlayerStandingOnWarpPadOrHole", transition_setters)
        self.assertIn("FollowerSetSpawnOutside::", transition_setters)
        self.assertIn("FollowerSetSpawnWarpPad::", transition_setters)
        self.assertIn("FollowerSetSpawnBackOutside::", transition_setters)
        for map_name in (
            "OAKS_LAB",
            "ROUTE_22_GATE",
            "MT_MOON_B1F",
            "ROCK_TUNNEL_1F",
        ):
            self.assertIn(f"cp {map_name}", transition_setters)
        self.assertIn("cp VIRIDIAN_FOREST_NORTH_GATE", transition_setters)
        self.assertIn("cp VIRIDIAN_FOREST_SOUTH_GATE", transition_setters)
        for map_name in (
            "VICTORY_ROAD_2F",
            "ROUTE_7_GATE",
            "ROUTE_8_GATE",
            "ROUTE_16_GATE_1F",
            "ROUTE_18_GATE_1F",
            "ROUTE_15_GATE_1F",
            "ROUTE_11_GATE_1F",
            "CERULEAN_BADGE_HOUSE",
            "CERULEAN_TRASHED_HOUSE",
            "VERMILION_DOCK",
            "CELADON_MANSION_1F",
            "ROUTE_2_GATE",
            "FUCHSIA_GOOD_ROD_HOUSE",
            "VIRIDIAN_FOREST",
            "SAFARI_ZONE_CENTER_REST_HOUSE",
            "SAFARI_ZONE_WEST_REST_HOUSE",
            "SAFARI_ZONE_EAST_REST_HOUSE",
            "SAFARI_ZONE_NORTH_REST_HOUSE",
            "SAFARI_ZONE_SECRET_HOUSE",
            "SILPH_CO_ELEVATOR",
            "CELADON_MART_ELEVATOR",
            "CINNABAR_LAB_TRADE_ROOM",
            "CINNABAR_LAB_METRONOME_ROOM",
            "CINNABAR_LAB_FOSSIL_ROOM",
        ):
            self.assertIn(f"db {map_name}", transition_setters)
        self.assertRegex(
            transition_setters,
            r"(?s)FollowerSetSpawnBackOutside::.*?cp ROUTE_22_GATE.*?"
            r"cp ROUTE_2_GATE.*?cp SPRITE_FACING_UP.*?ld a, 3.*?ld a, 1.*?"
            r"ld \[wFollowerSpawnState\], a\s+ret",
        )
        prepare = self.core.split("FollowerPrepareMap::", 1)[1].split(
            "FollowerClearState:", 1
        )[0]
        self.assertIn("ld a, [wFollowerSpawnState]", prepare)
        self.assertIn("cp 1", prepare)
        self.assertIn("cp 2", prepare)
        for state in range(3, 8):
            self.assertIn(f"cp {state}", prepare)
        self.assertRegex(
            prepare,
            r"(?s)call FollowerIsTestMap\s+jr c, \.enabledMap\s+"
            r".*?xor a\s+ld \[wFollowerSpawnState\], a\s+ret",
        )
        self.assertRegex(
            prepare,
            r"(?s)\.spawnRight\s+inc c\s+jr \.storeSpawnCoords",
        )
        self.assertRegex(
            prepare,
            r"(?s)\.spawnBelow\s+inc b\s+jr \.storeSpawnCoords",
        )
        self.assertRegex(
            prepare,
            r"(?s)\.spawnAbove\s+dec b\s+jr \.storeSpawnCoords",
        )
        self.assertRegex(
            prepare,
            r"(?s)\.spawnLeft\s+dec c\s+jr \.storeSpawnCoords",
        )
        self.assertRegex(
            prepare,
            r"(?s)\.spawnAhead.*?SPRITE_FACING_UP.*?SPRITE_FACING_LEFT.*?"
            r"jr \.spawnRight",
        )
        self.assertRegex(prepare, r"(?s)\.faceDown\s+ld a, SPRITE_FACING_DOWN")
        self.assertRegex(prepare, r"(?s)\.faceOpposite.*?xor 4")
        self.assertRegex(prepare, r"(?s)\.computeFacing\s+call FollowerComputeFacing")
        self.assertRegex(prepare, r"xor a\s+ld \[wFollowerSpawnState\], a")

    def test_battle_return_preserves_slot_15_before_spawn_scheduling(self):
        prepare = self.core.split("FollowerPrepareMap::", 1)[1].split(
            "FollowerClearState:", 1
        )[0]
        battle_guard = prepare.index("bit BIT_BATTLE_OVER_OR_BLACKOUT, a")
        picture_check = prepare.index("SPRITESTATEDATA1_PICTUREID")
        clear_state = prepare.index("call FollowerClearState", battle_guard)
        self.assertLess(battle_guard, picture_check)
        self.assertLess(battle_guard, clear_state)

    def test_enqueue_is_at_accepted_step_seam(self):
        self.assertRegex(
            self.overworld,
            r"(?ms)\.setWalkCounter\s+ld \[wWalkCounter\], a\s+.*?farcall FollowerQueuePlayerStep\s+jr \.moveAhead2",
        )

    def test_yellow_ledge_latch_and_two_tile_command_contract(self):
        queue = self.core.split("FollowerQueuePlayerStep::", 1)[1].split(
            "; Yellow AppendPikachuFollowCommandToBuffer", 1
        )[0]
        self.assertIn("bit BIT_LEDGE_OR_FISHING, a", queue)
        self.assertIn("ld [wFollowerLedgeLatch], a", queue)
        self.assertRegex(queue, r"(?s)\.firstLedgeHalf.*?add 4.*?call FollowerAppendCommand")
        self.assertIn("DEF FOLLOWER_STATUS_TWO_STEP EQU 4", self.core)
        self.assertIn("DEF FOLLOWER_COMMAND_LEDGE_DOWN  EQU 5", self.core)
        self.assertIn("DEF FOLLOWER_COMMAND_LEDGE_RIGHT EQU 8", self.core)
        start = self.core.split("FollowerStartCommand:", 1)[1].split(
            "FollowerCommandData:", 1
        )[0]
        self.assertRegex(start, r"(?s)\.twoStep.*?FOLLOWER_NORMAL_FRAMES.*?FOLLOWER_STATUS_TWO_STEP")
        self.assertIn("call z, FollowerAddStepVector", start)
        advance = self.core.split("FollowerAdvanceStep:", 1)[1].split(
            "FollowerWait:", 1
        )[0]
        self.assertEqual(advance.count("cp FOLLOWER_STATUS_TWO_STEP"), 2)
        seed = self.core.split("FollowerComputeSeedCommand:", 1)[1].split(
            "FollowerInitializeScreenPosition:", 1
        )[0]
        self.assertRegex(seed, r"(?s)\.magnitude.*?cp 2.*?jr c, \.command.*?add 4")

    def test_slot15_owns_update_dispatch(self):
        self.assertRegex(
            self.update,
            r"(?ms)\.updateCurrentSprite.*?cp \$f0.*?farjp FollowerUpdate.*?\.ordinarySprite.*?jp UpdateNonPlayerSprite",
        )

    def test_slot15_is_not_a_collision_target(self):
        self.assertNotIn("\tnop\n\n\tld h, HIGH(wSpriteStateData1)", self.update)
        self.assertRegex(
            self.update,
            r"(?ms)\.loop\s+ldh \[hCollidingSpriteOffset\], a\s+cp NUM_SPRITESTATEDATA_STRUCTS - 1\s+jp z, \.next",
        )

    def test_font_path_uses_yellow_overlap_only_hide_and_recovers(self):
        self.assertRegex(
            self.core,
            r"(?ms)and a\s+ret z\s+call FollowerCheckVisibility\s+ret c\s+"
            r"ld hl, wSprite15StateData1 \+ SPRITESTATEDATA1_MOVEMENTSTATUS\s+"
            r"bit BIT_FACE_PLAYER, \[hl\]\s+jp nz, FollowerFacePlayer\s+ld a, \[wFontLoaded\]",
        )
        self.assertRegex(
            self.core,
            r"(?ms)FollowerUpdate::.*?ld a, \[wFontLoaded\]\s+bit BIT_FONT_LOADED, a\s+jr z, \.notFontLoaded\s+jp FollowerRefreshAfterText",
        )
        image_update = self.core.split("FollowerUpdateImage:", 1)[1].split(
            "FollowerHideIfOverlappingPlayer:", 1
        )[0]
        self.assertRegex(
            image_update,
            r"(?ms)ld a, \[wFontLoaded\]\s+bit BIT_FONT_LOADED, a\s+jr z, \.normalImage\s+push bc\s+call FollowerHideIfOverlappingPlayer\s+pop bc\s+ret c\s+ld a, b\s+jr \.store",
        )
        refresh = self.core.split("FollowerRefreshAfterText:", 1)[1].split(
            "FollowerRefreshQueue:", 1
        )[0]
        self.assertIn("jp FollowerUpdateImage", refresh)

    def test_yellow_interaction_scans_slot15_without_changing_collision_count(self):
        self.assertRegex(
            self.home,
            r"(?ms)FollowerInteraction::\s+farjp FollowerFindInteraction",
        )
        self.assertIn("call FollowerInteraction", self.overworld)
        interaction = self.core.split("FollowerFindInteraction::", 1)[1].split(
            "FollowerPikachuText:", 1
        )[0]
        self.assertRegex(
            interaction,
            r"(?ms)call IsSpriteOrSignInFrontOfPlayer.*?"
            r"ld a, \[wNumSprites\]\s+push af\s+"
            r"ld a, NUM_SPRITESTATEDATA_STRUCTS - 1\s+"
            r"ld \[wNumSprites\], a\s+call IsSpriteInFrontOfPlayer\s+"
            r"pop af\s+ld \[wNumSprites\], a",
        )
        self.assertRegex(
            interaction,
            r"(?ms)cp NUM_SPRITESTATEDATA_STRUCTS - 1.*?"
            r"call UpdateSprites.*?ldh \[hNoWaitAfterText\], a\s+"
            r"tx_pre FollowerPokemonText.*?xor a\s+"
            r"ldh \[hNoWaitAfterText\], a\s+ldh \[hTextID\], a\s+ret",
        )
        collision = self.overworld.split("CollisionCheckOnLand::", 1)[1].split(
            "CheckTilePassable::", 1
        )[0]
        self.assertIn("call IsSpriteInFrontOfPlayer", collision)
        self.assertNotIn("FollowerInteraction", collision)
        self.assertRegex(
            self.core,
            r"(?ms)FollowerPokemonText::?.*?ld \[wNamedObjectIndex\], a.*?"
            r"call GetMonName.*?call PlayCry.*?text_ram wNameBuffer\s+"
            r"text \"!\"\s+prompt",
        )
        self.assertIn("add_tx_pre FollowerPokemonText", self.predef_text)
        self.assertNotIn("add_tx_pre UnusedPredefText", self.predef_text)

    def test_lead_sheet_refresh_preserves_pose_and_uses_yellow_speed_values(self):
        prepare = self.core.split("FollowerPrepareMap::", 1)[1].split(
            "FollowerClearState:", 1
        )[0]
        self.assertRegex(
            prepare,
            r"(?ms)cp e\s+jr z, \.samePicture\s+and a\s+jr z, \.newSpawn.*?"
            r"bit BIT_FONT_LOADED, a\s+jr z, \.newSpawn.*?"
            r"ld \[wSprite15StateData1 \+ SPRITESTATEDATA1_PICTUREID\], a.*?"
            r"jp FollowerRefreshAfterText",
        )
        speed = self.core.split("FollowerGetAnimationTicks:", 1)[1].split(
            "FollowerWait:", 1
        )[0]
        self.assertIn("ld b, FOLLOWER_ANIM_TICKS", speed)
        self.assertIn("cp SPRITE_PIKACHU", speed)
        self.assertIn("ld b, 5", speed)

    def test_persistent_follower_toggle_uses_unused_options2_bit(self):
        self.assertIn("DEF BIT_FOLLOWER_DISABLED EQU 3", self.ram_constants)
        self.assertRegex(
            self.core,
            r"(?ms)\.enabledMap\s+ld a, \[wOptions2\]\s+"
            r"bit BIT_FOLLOWER_DISABLED, a\s+jr z, \.enabledOption\s+"
            r"call FollowerClearState",
        )
        self.assertIn("DEF ROW_FOLLOWER EQU 4", self.extra_options)
        self.assertIn("DEF NUM_EXTRA_OPTION_ROWS EQU 6", self.extra_options)
        self.assertIn("xor [hl]", self.extra_options)
        self.assertIn("ExtraOptionsFollowerLabelText:", self.extra_options)

    def test_yellow_visibility_precedes_font_and_checks_four_tiles(self):
        visibility = self.core.split("FollowerCheckVisibility:", 1)[1].split(
            "; Yellow UpdatePikachuWalkingSprite", 1
        )[0]
        self.assertIn("call .getCurrentTile", visibility)
        self.assertIn("ld d, MAP_TILESET_SIZE", visibility)
        self.assertGreaterEqual(visibility.count("cp d"), 4)
        self.assertIn("ld [wSprite15StateData2 + SPRITESTATEDATA2_GRASSPRIORITY], a", visibility)
        trainer_info = (ROOT / "engine" / "menus" / "start_sub_menus.asm").read_text()
        self.assertRegex(
            trainer_info,
            r"(?ms)StartMenu_TrainerInfo::\s+call GBPalWhiteOut\s+call ClearScreen\s+call UpdateSprites",
        )

    def test_donor_movement_draws_before_ready_facing(self):
        advance = self.core.split("FollowerAdvanceStep:", 1)[1].split(
            "FollowerWait:", 1
        )[0]
        self.assertLess(advance.index("call FollowerUpdateImage"), advance.index("dec [hl]"))
        self.assertLess(advance.index("call FollowerComputeFacing"), advance.index("FOLLOWER_STATUS_READY"))
        self.assertIn("DEF FOLLOWER_ANIM_TICKS    EQU 2", self.core)
        self.assertIn("call Check60FPS", advance)

    def test_camera_hook_is_only_in_actual_scroll_branch(self):
        advancement = self.overworld.split("AdvancePlayerSprite::", 1)[1]
        before_scroll, scroll = advancement.split(".scrollBackgroundAndSprites", 1)
        self.assertNotIn("FollowerApplyCameraScroll", before_scroll)
        self.assertRegex(
            scroll,
            r"(?ms)\.done\s+.*?ld d, b\s+ld e, c\s+farcall FollowerApplyCameraScroll",
        )

    def test_loader_forces_reserved_base_two_for_slot15(self):
        self.assertIn("farcall FollowerPrepareMap", self.loader)
        self.assertRegex(
            self.loader,
            r"(?s)cp SILPH_CO_B1F.*?cp SILPH_CO_DORM.*?cp OAKS_LAB.*?\.reserveFollowerVRAMSlot",
        )
        self.assertRegex(
            self.loader,
            r"(?ms)cp LOW\(wSprite15StateData2 \+ SPRITESTATEDATA2_IMAGEBASEOFFSET\).*?\.followerVRAMSlot\s+ld a, 2",
        )

    def test_route1_uses_yellow_fixed_set_reservation(self):
        outside = self.loader.split("InitOutsideMapSprites:", 1)[1].split(
            "; Chooses the correct sprite set ID", 1
        )[0]
        self.assertRegex(
            outside,
            r"(?s)cp ROUTE_1\s+jr z, \.loadSpriteSet.*?"
            r"cp SPRITESET_PALLET_VIRIDIAN.*?ld a, \[wSpriteSet\]\s+"
            r"cp SPRITE_BLUE\s+jr nz, \.loadSpriteSet",
        )
        self.assertRegex(
            outside,
            r"(?s)cp ROUTE_1\s+call z, \.insertFollowerIntoSpriteSet.*?"
            r"\.insertFollowerIntoSpriteSet.*?ld hl, wSpriteSet \+ 7.*?"
            r"ld de, wSpriteSet \+ 8.*?ld b, 8.*?"
            r"ld a, \[wSprite15StateData1 \+ SPRITESTATEDATA1_PICTUREID\]\s+"
            r"ld \[wSpriteSet\], a",
        )

    def test_species_categories_translate_to_walking_sheets(self):
        outside = self.loader.split("InitOutsideMapSprites:", 1)[1].split(
            "; Chooses the correct sprite set ID", 1
        )[0]
        resolver = self.core.split("FollowerResolveLeadPicture:", 1)[1].split(
            "; Called by InitMapSprites", 1
        )[0]
        self.assertIn("cp NUM_POKEMON_INDEXES + 1", resolver)
        self.assertRegex(
            resolver,
            r"(?s)\.categoryToWalkingSprite\s+"
            r"db SPRITE_MONSTER\s+db SPRITE_BIRD\s+db SPRITE_SEEL\s+"
            r"db SPRITE_FAIRY\s+db SPRITE_VOLTORB_DECO\s+"
            r"db SPRITE_SNORLAX_DECO\s+db SPRITE_OMANYTE_DECO\s+"
            r"db SPRITE_PIKACHU\s+db SPRITE_CHANSEY",
        )
        self.assertRegex(
            outside,
            r"(?s)ld hl, wSprite01StateData2PictureID\s+"
            r"ld de, wSpriteSet\s+ld b, SPRITE_SET_LENGTH.*?"
            r"\.copyAdjustedSet.*?ld \[hl\], a\s+dec b\s+ret z\s+"
            r"ld a, SPRITESTATEDATA2_LENGTH",
        )
        generic_loader = self.loader.split("LoadMapSpriteTilePatterns:", 1)[1].split(
            "InitOutsideMapSprites:", 1
        )[0]
        self.assertNotIn("cp ROUTE_1", generic_loader)


if __name__ == "__main__":
    unittest.main()
