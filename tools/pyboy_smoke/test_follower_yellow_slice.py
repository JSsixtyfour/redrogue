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
        cls.wram = (ROOT / "ram/wram.asm").read_text()

    def test_only_scoped_core_is_included(self):
        self.assertIn('INCLUDE "engine/overworld/follower_yellow_test.asm"', self.main)
        self.assertNotIn('INCLUDE "engine/overworld/follower.asm"', self.main)
        self.assertNotIn("follower_baseline.asm", self.main)

    def test_scope_is_fixed_pikachu_on_two_maps(self):
        self.assertIn("cp SILPH_CO_B1F", self.core)
        self.assertIn("cp SILPH_CO_DORM", self.core)
        self.assertIn("cp SPRITE_PIKACHU", self.core)
        for forbidden in (
            "INDIGO_PLATEAU_LOBBY",
            "wPartySpecies",
            "BIT_FOLLOWER_DISABLED",
            "PCGetPokemonSpriteCategory",
            "FollowerStartIdleAction",
        ):
            self.assertNotIn(forbidden, self.core)

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

    def test_enqueue_is_at_accepted_step_seam(self):
        self.assertRegex(
            self.overworld,
            r"(?ms)\.setWalkCounter\s+ld \[wWalkCounter\], a\s+.*?farcall FollowerQueuePlayerStep\s+jr \.moveAhead2",
        )

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
            r"(?ms)cp SPRITE_PIKACHU\s+ret nz\s+call FollowerCheckVisibility\s+ret c\s+ld a, \[wFontLoaded\]",
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
            r"(?ms)cp LOW\(wSprite15StateData2 \+ SPRITESTATEDATA2_IMAGEBASEOFFSET\).*?\.followerVRAMSlot\s+ld a, 2",
        )


if __name__ == "__main__":
    unittest.main()
