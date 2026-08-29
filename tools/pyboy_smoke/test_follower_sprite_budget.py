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

    @unittest.expectedFailure
    def test_lobby_full_sheet_layout_requires_compact_pose_loader(self):
        # The old full-sheet model still cannot fit this roster. User chose
        # to preserve all services/art and investigate stationary-pose packing.
        # Replace this expected failure with actual compact-loader coverage
        # when implemented; do not cut actors merely to satisfy this model.
        sizes = sprite_sizes()
        pictures = set(map_pictures()["IndigoPlateauLobby"])
        walking = {p for p in pictures if sizes[p] == 12}
        self.assertLessEqual(len(walking), 8, sorted(walking))

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


if __name__ == "__main__":
    unittest.main()
