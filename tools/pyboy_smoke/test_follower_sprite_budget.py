"""Source-level prerequisites for the planned compact follower sprite loader.

These checks do not execute a loader or prove VRAM transfers. They count all
authored actors, including hidden ones, rather than a camera-visible subset.
Runtime picture replacements require the separate lifecycle/loader audit.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
APPROVED_CUTS = {
    "PowerPlant": "POWERPLANT_VOLTORB4",
    "MtMoon1F": "MTMOON1F_ESCAPE_ROPE",
    "VictoryRoad1F": "VICTORYROAD1F_RARE_CANDY",
}
def sprite_sizes():
    constants = (ROOT / "constants/sprite_constants.asm").read_text()
    names = re.findall(r"^\s*const (SPRITE_\w+)\s*(?:;.*)?$", constants, re.M)
    assert names[0] == "SPRITE_NONE"
    table = (ROOT / "data/sprites/sprites.asm").read_text()
    entries = []
    for line in table.splitlines():
        match = re.match(
            r"^\s*overworld_sprite\s+\w+,\s*(\d+)\s*(?:;.*)?$", line
        )
        if match:
            entries.append(match.group(1))
            continue
        match = re.match(
            r"^\s*overworld_sprite_slice\s+\w+,\s*\d+,\s*(\d+)\s*(?:;.*)?$",
            line,
        )
        if match:
            entries.append(match.group(1))
    assert len(entries) == len(names) - 1, "Unparsed sprite table entry"
    sizes = dict(zip(names[1:], map(int, entries)))
    for alias, target in re.findall(
        r"^\s*DEF (SPRITE_\w+)\s+EQU\s+(SPRITE_\w+)\s*$", constants, re.M
    ):
        sizes[alias] = sizes[target]
    return sizes


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


def outdoor_sprite_contracts():
    source = (ROOT / "data/maps/sprite_sets.asm").read_text()
    sprite_sets = {}
    for match in re.finditer(
        r"; (SPRITESET_\w+)\n((?:\s*db SPRITE_\w+\n){11})", source
    ):
        sprite_sets[match.group(1)] = re.findall(
            r"db (SPRITE_\w+)", match.group(2)
        )

    split_sets = {}
    split_source = source.split("SplitMapSpriteSets:", 1)[1].split(
        "assert_table_length", 1
    )[0]
    for line in split_source.splitlines():
        match = re.search(
            r"db \w+,\s*\d+,\s*(SPRITESET_\w+),\s*(SPRITESET_\w+)\s*; (SPLITSET_\w+)",
            line,
        )
        if match:
            split_sets[match.group(3)] = (match.group(1), match.group(2))

    map_sets = {}
    map_source = source.split("MapSpriteSets:", 1)[1].split(
        "assert_table_length", 1
    )[0]
    for line in map_source.splitlines():
        match = re.search(r"db (\w+)\s*; (\w+)", line)
        if match:
            map_sets[match.group(2)] = split_sets.get(
                match.group(1), (match.group(1),)
            )

    pictures_by_constant = {}
    paths_by_constant = {}
    for path in sorted((ROOT / "data/maps/objects").glob("*.asm")):
        text = path.read_text()
        match = re.search(r"def_warps_to (\w+)", text)
        if match:
            pictures_by_constant[match.group(1)] = set(
                re.findall(
                    r"^\s*object_event\s+[^,]+,\s*[^,]+,\s*(SPRITE_\w+)",
                    text,
                    re.M,
                )
            )
            paths_by_constant[match.group(1)] = path
    return sprite_sets, map_sets, pictures_by_constant, paths_by_constant


class FollowerSpriteBudgetTests(unittest.TestCase):
    def test_every_outdoor_set_has_an_unused_walking_entry_for_follower(self):
        sizes = sprite_sizes()
        sprite_sets, map_sets, pictures_by_map, paths_by_map = (
            outdoor_sprite_contracts()
        )
        for map_name, set_names in map_sets.items():
            pictures = pictures_by_map[map_name]
            walking = {picture for picture in pictures if sizes[picture] == 12}
            still = {picture for picture in pictures if sizes[picture] == 4}
            for set_name in set_names:
                with self.subTest(map=map_name, sprite_set=set_name):
                    entries = sprite_sets[set_name]
                    # Split sets intentionally omit actors belonging to the
                    # other half. The live loader scans only active state1
                    # picture IDs, so the authored union is a safe upper bound
                    # for capacity but not a required subset of either half.
                    unused = set(entries[:9]) - (walking & set(entries[:9]))
                    self.assertTrue(
                        unused,
                        f"{map_name} reaches the follower walking-sheet limit; "
                        f"add a FOLLOWER SPRITE LIMIT warning to "
                        f"{paths_by_map[map_name]}",
                    )

    def test_checkpoint_c_reservation_is_contained_to_safe_maps(self):
        loader = (ROOT / "engine/overworld/map_sprites.asm").read_text()
        self.assertIn(
            "inc b ; reserve follower-era image base 2",
            loader,
        )
        self.assertRegex(
            loader,
            r"(?ms)^\.loadTilePatternLoop\s*$.*?^\s*and a ; unused sprite slot\?\s*$.*?^\s*jp z, \.nextSpriteSlot\s*$",
        )

        sizes = sprite_sizes()
        pictures_by_map = map_pictures()
        for map_name, pictures in pictures_by_map.items():
            with self.subTest(map=map_name):
                walking = {
                    picture
                    for picture in pictures
                    if sizes[picture] == 12
                }
                self.assertLessEqual(len(walking), 8, sorted(walking))

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
                self.assertLessEqual(len(walking), 8, sorted(walking))
                self.assertLessEqual(len(still), 2, sorted(still))

    def test_lobby_fixed_pose_layout_fits_follower_budget(self):
        sizes = sprite_sizes()
        pictures = set(map_pictures()["IndigoPlateauLobby"])
        walking = {p for p in pictures if sizes[p] == 12}
        still = {p for p in pictures if sizes[p] == 4}
        self.assertEqual(len(walking), 8, sorted(walking))
        self.assertEqual(
            still,
            {"SPRITE_LOBBY_MOVE_RELEARNER", "SPRITE_LOBBY_DAYCARE_LADY"},
        )

    def test_object_slot_budget_after_explicit_approved_cuts(self):
        for name, pictures in map_pictures().items():
            with self.subTest(map=name):
                self.assertLessEqual(len(pictures), 14)

        source = "\n".join(
            path.read_text()
            for path in (
                ROOT / "data/maps/objects/PowerPlant.asm",
                ROOT / "data/maps/objects/MtMoon1F.asm",
                ROOT / "data/maps/objects/VictoryRoad1F.asm",
            )
        )
        for symbol in APPROVED_CUTS.values():
            with self.subTest(removed=symbol):
                self.assertNotIn(symbol, source)

        toggles = (ROOT / "data/maps/toggleable_objects.asm").read_text()
        self.assertIn("Retired TOGGLE_MT_MOON_1F_ITEM_4", toggles)
        self.assertIn("Retired TOGGLE_VICTORY_ROAD_1F_ITEM_2", toggles)


if __name__ == "__main__":
    unittest.main()
