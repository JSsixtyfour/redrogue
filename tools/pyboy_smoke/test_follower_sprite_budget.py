"""Source-level prerequisites for the planned compact follower sprite loader.

These checks do not execute a loader or prove VRAM transfers. They count all
authored actors, including hidden ones, rather than a camera-visible subset.
Runtime picture replacements require the separate lifecycle/loader audit.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
COMPLETED_CUTS = {
    "PowerPlant": "POWERPLANT_VOLTORB4",
    "MtMoon1F": "MTMOON1F_ESCAPE_ROPE",
    "VictoryRoad1F": "VICTORYROAD1F_RARE_CANDY",
}


def sprite_sizes():
    constants = (ROOT / "constants/sprite_constants.asm").read_text()
    names = re.findall(r"^\s*const (SPRITE_\w+)\s*(?:;.*)?$", constants, re.M)
    assert names[0] == "SPRITE_NONE"
    entries = re.findall(
        r"^\s*overworld_sprite\s+\w+,\s*(\d+)\s*(?:;.*)?$",
        (ROOT / "data/sprites/sprites.asm").read_text(), re.M,
    )
    assert len(entries) == len(names) - 1, "Unparsed sprite table entry"
    return dict(zip(names[1:], map(int, entries)))


def map_pictures():
    result = {}
    for path in sorted((ROOT / "data/maps/objects").glob("*.asm")):
        pictures = []
        for line in path.read_text().splitlines():
            code = line.partition(";")[0].strip()
            if not re.match(r"object_event\b", code):
                continue
            fields = code.split(None, 1)[1].split(",")
            assert len(fields) >= 6, f"Unparsed object: {path}: {line}"
            picture = fields[2].strip()
            assert re.fullmatch(r"SPRITE_\w+", picture), (path, picture)
            pictures.append(picture)
        result[path.stem] = pictures
    assert result, "No object maps found"
    return result


class FollowerSpriteBudgetTests(unittest.TestCase):
    def test_extra_options_toggle_uses_inverted_disabled_bit(self):
        constants = (ROOT / "constants/ram_constants.asm").read_text()
        menu = (ROOT / "engine/menus/extra_options.asm").read_text()
        init = (ROOT / "custom_functions/relocated_home.asm").read_text()

        self.assertIn("DEF BIT_FOLLOWER_DISABLED EQU 3", constants)
        self.assertIn("DEF ROW_FOLLOWER EQU 3", menu)
        self.assertIn("DEF NUM_EXTRA_OPTION_ROWS EQU 6", menu)
        toggle = menu[menu.index("\n.toggleFollower\n"):
                      menu.index("\n.toggle60FPS\n")]
        self.assertIn("1 << BIT_FOLLOWER_DISABLED", toggle)
        draw = menu[menu.index("\n.drawFollowerValue\n"):
                    menu.index("\n.draw60FPSValue\n")]
        self.assertRegex(
            draw,
            r"bit BIT_FOLLOWER_DISABLED, a\s+jr z, \.placeBinaryValue",
        )
        defaults = init[init.index("InitOptions_::"):
                        init.index("ldh a, [hGBC]")]
        self.assertNotIn("1 << BIT_FOLLOWER_DISABLED", defaults)

    def test_all_authored_pictures_have_supported_sheet_sizes(self):
        sizes = sprite_sizes()
        for name, pictures in map_pictures().items():
            for picture in pictures:
                with self.subTest(map=name, picture=picture):
                    self.assertIn(picture, sizes)
                    self.assertIn(sizes[picture], (4, 12))

    def test_compact_authored_sheet_budget_outside_known_lobby_blocker(self):
        sizes = sprite_sizes()
        for name, pictures in map_pictures().items():
            with self.subTest(map=name):
                unique = set(pictures)
                walking = {p for p in unique if sizes[p] == 12}
                still = {p for p in unique if sizes[p] == 4}
                # Slot 1 belongs to the player, 2 is reserved even when OFF.
                # Slots 3..10 hold eight walking sheets; 11..12 two stills.
                if name != "IndigoPlateauLobby":
                    # Lobby walking capacity has its own expected failure.
                    self.assertLessEqual(len(walking), 8, sorted(walking))
                self.assertLessEqual(len(still), 2, sorted(still))

    def test_lobby_compact_pose_loader_replaces_full_sheet_failure(self):
        sizes = sprite_sizes()
        pictures = set(map_pictures()["IndigoPlateauLobby"])
        walking = {p for p in pictures if sizes[p] == 12}
        self.assertGreater(len(walking), 8, sorted(walking))

        pose = (ROOT / "engine/overworld/lobby_pose.asm").read_text()
        follower = (ROOT / "engine/overworld/follower.asm").read_text()
        self.assertIn("LobbyPoseLoadMapGraphics::", pose)
        self.assertIn("LobbyPoseUpdate::", pose)
        self.assertRegex(
            pose,
            r"(?s)\.imageBases\s+db 4.*?db 5.*?db 5.*?db 6.*?db 7.*?"
            r"db 8.*?db 9.*?db 10.*?db 3.*?db 10.*?db 10",
        )
        self.assertIn("db $6c, 1 ; channeler", pose)
        self.assertIn("db $70, 1 ; super nerd", pose)
        self.assertIn("db $74, 1 ; Game Boy kid", pose)
        self.assertRegex(
            follower,
            r"call LobbyPoseLoadMapGraphics\s+jr nc, \.ordinaryMap",
        )

    def test_lobby_async_publish_uses_vblank_mailbox_before_dma(self):
        pose = (ROOT / "engine/overworld/lobby_pose.asm").read_text()
        update = pose[pose.index("LobbyPoseUpdate::"):
                      pose.index("LobbyPoseCacheActor:")]
        self.assertIn("ldh a, [hVBlankCopySize]", update)
        self.assertIn("di", update)
        self.assertRegex(
            update,
            r"(?s)ldh \[hVBlankCopyDest \+ 1\], a.*?"
            r"ld \[hl\], a.*?ld a, 4\s+ldh \[hVBlankCopySize\], a",
        )
        vblank = (ROOT / "home/vblank.asm").read_text()
        self.assertLess(vblank.index("call VBlankCopy"),
                        vblank.index("call hDMARoutine"))

    def test_object_slot_budget_after_exact_approved_cuts(self):
        for name, pictures in map_pictures().items():
            with self.subTest(map=name):
                self.assertLessEqual(len(pictures), 14)
        for name, removed in COMPLETED_CUTS.items():
            with self.subTest(map=name, removed=removed):
                self.assertEqual(len(map_pictures()[name]), 14)
                source = (ROOT / f"data/maps/objects/{name}.asm").read_text()
                self.assertNotRegex(
                    source,
                    rf"(?m)^\s*const_export\s+{removed}\s*$",
                )

    def test_compact_loader_reserves_slot_two_and_uses_current_map(self):
        source = (ROOT / "engine/overworld/map_sprites.asm").read_text()
        follower = (ROOT / "engine/overworld/follower.asm").read_text()
        init = source[source.index("InitMapSprites::"):
                      source.index("LoadMapSpriteTilePatterns:")]
        self.assertNotIn("call InitOutsideMapSprites", init)
        self.assertIn("ld b, 2 ; slot 1 player, slot 2 reserved", source)
        self.assertIn("farcall FollowerLoadMapGraphics", source)
        # Until the dedicated lobby cache publisher replaces the full-sheet
        # allocator, the lobby must keep slot 2 available to its authored set
        # and suppress follower publication there.
        self.assertRegex(
            source,
            r"cp INDIGO_PLATEAU_LOBBY\s+jr nz, \.findNextVRAMSlotLoop\s+dec b",
        )
        loader = follower[follower.index("FollowerLoadMapGraphics::"):
                          follower.index("FollowerShouldSpawn::")]
        self.assertRegex(
            loader,
            r"cp INDIGO_PLATEAU_LOBBY\s+jr nz, \.ordinaryMap",
        )
        lobby_branch = loader[loader.index("cp INDIGO_PLATEAU_LOBBY"):
                              loader.index("\n.ordinaryMap")]
        self.assertRegex(
            lobby_branch,
            r"ld hl, wLobbyPoseCacheState\s+call LobbyPoseCacheReset",
        )
        ordinary_loader = loader[loader.index("\n.ordinaryMap"):]
        self.assertEqual(ordinary_loader.count("call FarCopyData3"), 2)
        self.assertNotIn("call FarCopyData2", ordinary_loader)

    def test_follower_category_map_uses_only_twelve_tile_sheets(self):
        sizes = sprite_sizes()
        source = (ROOT / "engine/overworld/follower.asm").read_text()
        block = source[source.index(".table\n", source.index("FollowerCategoryToSprite::")):
                       source.index("assert @ - .table", source.index("FollowerCategoryToSprite::"))]
        names = re.findall(r"\bSPRITE_[A-Z0-9_]+\b", block)
        self.assertEqual(len(names), 9)
        for name in names:
            with self.subTest(sprite=name):
                self.assertEqual(sizes[name], 12)

    def test_four_tile_items_keep_their_fixed_vram_region(self):
        source = (ROOT / "engine/overworld/map_sprites.asm").read_text()
        # Reward balls, fossils, boulders, and other still objects do not use
        # the player/follower/authored walking-sheet sequence. They retain the
        # two fixed four-tile bases selected by image offsets 11 and 12.
        self.assertIn("add 11", source)
        self.assertIn("cp 11 ; is it a 4-tile sprite?", source)
        self.assertIn("ld hl, vSprites tile $78", source)
        self.assertIn("ld hl, vSprites tile $7c", source)

        sizes = sprite_sizes()
        self.assertEqual(sizes["SPRITE_POKE_BALL"], 4)
        self.assertEqual(sizes["SPRITE_FOSSIL"], 4)
        self.assertEqual(sizes["SPRITE_BOULDER"], 4)

    def test_scripted_actor_images_use_live_compact_loader_bases(self):
        checks = {
            "scripts/PewterCity.asm": (
                "wSprite03StateData2ImageBaseOffset",
                "wSprite05StateData2ImageBaseOffset",
            ),
            "scripts/PewterPokecenter.asm": (
                "wSprite03StateData2ImageBaseOffset",
            ),
            "engine/events/pokecenter.asm": (
                "wSprite01StateData2ImageBaseOffset",
            ),
        }
        for relative, symbols in checks.items():
            source = (ROOT / relative).read_text()
            for symbol in symbols:
                with self.subTest(file=relative, symbol=symbol):
                    self.assertIn(symbol, source)
            self.assertNotRegex(source, r"\(\$[0-9a-fA-F]+ << 4\)")

    def test_ordinary_overworld_hooks_target_dedicated_slot(self):
        overworld = (ROOT / "home/overworld.asm").read_text()
        updater = (ROOT / "engine/overworld/sprite_collisions.asm").read_text()
        self.assertIn("farcall FollowerUpdate", overworld)
        self.assertIn("ld [wFollowerLoadAction], a ; consumed by the next FollowerUpdate", overworld)
        self.assertIn("farcall FollowerApplyCameraScroll", overworld)
        self.assertRegex(
            updater,
            r"ld a, c\s+cp \$f0\s+jr z, \.skipSprite",
        )
        self.assertRegex(
            updater,
            r"ldh \[hCollidingSpriteOffset\], a\s+cp 15\s+jp z, \.next",
        )


if __name__ == "__main__":
    unittest.main()
