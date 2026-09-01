"""Source contract for the lobby's follower-compatible sprite layout.

Runtime loading and visual orientation remain emulator acceptance items.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class LobbyPoseLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.objects = (ROOT / "data/maps/objects/IndigoPlateauLobby.asm").read_text()
        cls.sprites = (ROOT / "data/sprites/sprites.asm").read_text()
        cls.oam = (ROOT / "engine/gfx/sprite_oam.asm").read_text()

    def test_roster_is_preserved_and_only_salesman_walks(self):
        actors = [
            line.partition(";")[0].split(",")
            for line in self.objects.splitlines()
            if line.strip().startswith("object_event ")
        ]
        self.assertEqual(len(actors), 11)
        for actor in actors:
            picture, movement = actor[2].strip(), actor[3].strip()
            expected = "WALK" if picture == "SPRITE_MIDDLE_AGED_MAN" else "STAY"
            self.assertEqual(movement, expected, picture)

    def test_clerks_keep_their_full_directional_sheet(self):
        self.assertEqual(self.objects.count("SPRITE_CLERK"), 2)
        self.assertNotIn("SPRITE_LOBBY_CLERK", self.objects)

    def test_two_single_pose_services_use_the_four_tile_slots(self):
        self.assertIn("SPRITE_LOBBY_MOVE_RELEARNER, STAY, DOWN", self.objects)
        self.assertIn("SPRITE_GAMEBOY_KID_STILL, STAY, RIGHT", self.objects)
        self.assertIn(
            "overworld_sprite_slice SilphPresidentSprite, 0, 4",
            self.sprites,
        )
        self.assertIn(
            "overworld_sprite_slice GameboyKidSprite, 8, 4",
            self.sprites,
        )

    def test_gameboy_kid_uses_fixed_right_oam(self):
        self.assertIn("cp SPRITE_GAMEBOY_KID_STILL", self.oam)
        self.assertIn("SpriteFacingAndAnimationTableFixedRight", self.oam)

    def test_object_file_records_exact_budget(self):
        self.assertIn("FOLLOWER SPRITE LIMIT", self.objects)
        self.assertIn("exactly eight authored 12-tile", self.objects)
        self.assertIn("both 4-tile slots", self.objects)


if __name__ == "__main__":
    unittest.main()
