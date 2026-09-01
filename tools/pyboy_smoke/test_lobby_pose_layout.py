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
        cls.healing = (ROOT / "engine/overworld/healing_machine.asm").read_text()
        cls.pokecenter = (ROOT / "engine/events/pokecenter.asm").read_text()
        cls.loader = (ROOT / "engine/overworld/map_sprites.asm").read_text()

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

    def test_two_fixed_south_services_use_the_four_tile_slots(self):
        self.assertIn("SPRITE_LOBBY_MOVE_RELEARNER, STAY, DOWN", self.objects)
        self.assertIn("SPRITE_LOBBY_DAYCARE_LADY, STAY, DOWN", self.objects)
        self.assertIn("SPRITE_GAMEBOY_KID, STAY, RIGHT", self.objects)
        self.assertIn(
            "overworld_sprite_slice SilphPresidentSprite, 0, 4",
            self.sprites,
        )
        self.assertIn(
            "overworld_sprite_slice GrannySprite, 0, 4",
            self.sprites,
        )

    def test_gameboy_kid_keeps_directional_oam(self):
        self.assertNotIn("SPRITE_GAMEBOY_KID_STILL", self.oam)
        self.assertNotIn("SpriteFacingAndAnimationTableFixedRight", self.oam)

    def test_object_file_records_exact_budget(self):
        self.assertIn("FOLLOWER SPRITE LIMIT", self.objects)
        self.assertIn("exactly eight authored 12-tile", self.objects)
        self.assertIn("both 4-tile slots", self.objects)

    def test_healing_hides_before_freeze_and_restores_through_update(self):
        hide = self.healing.index(
            "ld [wSprite15StateData1 + SPRITESTATEDATA1_IMAGEINDEX], a"
        )
        freeze = self.healing.index("ld [hl], $ff")
        restore = self.healing.index("jp UpdateSprites")
        self.assertLess(hide, freeze)
        self.assertLess(freeze, restore)

    def test_nurse_healing_poses_use_reserved_base_three(self):
        self.assertIn("ld a, $28", self.pokecenter)
        self.assertIn("ld a, $24", self.pokecenter)
        self.assertNotIn("ld a, $18", self.pokecenter)
        self.assertRegex(
            self.loader,
            r"wSprite01StateData1 \+ SPRITESTATEDATA1_PICTUREID\]\s+"
            r"cp SPRITE_NURSE\s+jr nz, \.findNextVRAMSlotLoop\s+"
            r"\.reserveFollowerVRAMSlot\s+inc b",
        )


if __name__ == "__main__":
    unittest.main()
