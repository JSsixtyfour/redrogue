"""Focused PyBoy smoke for the contained Yellow-derived follower slice."""

from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
