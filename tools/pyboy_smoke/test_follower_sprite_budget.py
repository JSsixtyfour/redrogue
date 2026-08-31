"""Source-level prerequisites for the planned compact follower sprite loader.

These checks do not execute a loader or prove VRAM transfers. They count all
authored actors, including hidden ones, rather than a camera-visible subset.
Runtime picture replacements require the separate lifecycle/loader audit.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
PENDING_CUTS = {
    "PowerPlant": "POWERPLANT_VOLTORB4",
    "MtMoon1F": "MTMOON1F_ESCAPE_ROPE",
    "VictoryRoad1F": "VICTORYROAD1F_RARE_CANDY",
}
RESERVATION_TEST_MAPS = {"SilphCoB1F", "SilphCoDorm"}


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
    def test_checkpoint_c_reservation_is_contained_to_safe_maps(self):
        loader = (ROOT / "engine/overworld/map_sprites.asm").read_text()
        for map_name in ("SILPH_CO_B1F", "SILPH_CO_DORM"):
            with self.subTest(map=map_name):
                self.assertRegex(
                    loader,
                    rf"(?m)^\s*cp {map_name}\s*$",
                )
        self.assertIn(
            "inc b ; reserve image base 2 for enabled follower maps",
            loader,
        )
        self.assertRegex(
            loader,
            r"(?ms)^\.loadTilePatternLoop\s*$.*?^\s*and a ; unused sprite slot\?\s*$.*?^\s*jp z, \.nextSpriteSlot\s*$",
        )

        sizes = sprite_sizes()
        pictures_by_map = map_pictures()
        for map_name in RESERVATION_TEST_MAPS:
            with self.subTest(map=map_name):
                walking = {
                    picture
                    for picture in pictures_by_map[map_name]
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

    def test_object_slot_budget_with_only_explicit_pending_cuts(self):
        for name, pictures in map_pictures().items():
            with self.subTest(map=name):
                if len(pictures) > 14:
                    self.assertIn(name, PENDING_CUTS)
                    self.assertEqual(len(pictures), 15)
                    source = (ROOT / f"data/maps/objects/{name}.asm").read_text()
                    self.assertRegex(
                        source,
                        rf"(?m)^\s*const_export\s+{PENDING_CUTS[name]}\s*$",
                    )


if __name__ == "__main__":
    unittest.main()
