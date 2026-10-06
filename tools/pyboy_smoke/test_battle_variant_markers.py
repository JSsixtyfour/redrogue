from pathlib import Path
import unittest

from harness import RedRogueHarness


REPO_ROOT = Path(__file__).resolve().parents[2]


class BattleVariantMarkerContractTest(unittest.TestCase):
    def test_hud_hook_and_marker_priority(self) -> None:
        hud = (REPO_ROOT / "engine" / "battle" / "draw_hud_pokeball_gfx.asm").read_text()
        core = (REPO_ROOT / "engine" / "battle" / "core.asm").read_text()
        shiny = (REPO_ROOT / "custom_functions" / "func_shiny.asm").read_text()

        self.assertNotIn("farcall DrawBattleVariantMarker", hud)
        self.assertEqual(core.count("farcall DrawBattleVariantMarker"), 2)
        self.assertLess(shiny.index("bit BIT_TYPE_VARIANT, a"), shiny.index("bit BIT_GHOST_VARIANT, a"))
        self.assertLess(shiny.index("bit BIT_GHOST_VARIANT, a"), shiny.index("bit BIT_SHINY, a"))
        self.assertIn("hlcoord 9, 1", shiny)
        self.assertIn("hlcoord 13, 8", shiny)
        for marker in ("GHOST", "WATER", "ROCK", "DRAGON", "SHINY", "VARIANT"):
            self.assertIn(f"<HUD_{marker}>", shiny)

    def test_marker_font_tiles_are_distinct_and_populated(self) -> None:
        font = (REPO_ROOT / "gfx" / "font" / "font.1bpp").read_bytes()
        tiles = [font[index * 8:(index + 1) * 8] for index in range(0x50, 0x56)]

        self.assertEqual(len(set(tiles)), 6)
        self.assertTrue(all(any(tile) for tile in tiles))

    def test_evolution_preserves_type_variant_secondary_type(self) -> None:
        source = (REPO_ROOT / "engine" / "pokemon" / "evos_moves.asm").read_text()

        self.assertIn("bit BIT_TYPE_VARIANT, [hl]", source)
        self.assertIn("ld bc, MON_TYPE2", source)
        self.assertIn("predef SetPartyMonTypes", source)
        self.assertIn("ld [hl], a", source)
        self.assertLess(source.index("push af"), source.index("predef SetPartyMonTypes"))
        self.assertLess(source.index("pop af"), source.index(".evolutionTypesSet"))


class BattleVariantMarkerRuntimeTest(unittest.TestCase):
    """Party-ball frames must not inspect stale active-mon flag bytes."""

    def setUp(self) -> None:
        self.h = RedRogueHarness(REPO_ROOT, Path(__file__).parent / "artifacts")
        self.h.boot_to_lobby()

    def tearDown(self) -> None:
        self.h.close()

    def capture_tiles(self, routine: str, seam: str, player: int, enemy: int) -> list[int]:
        h = self.h
        h.write8("wBattleMonCatchRate", player)
        h.write8("wEnemyMonCatchRate", enemy)
        h.write8("wPartyCount", 1)
        h.write8("wEnemyPartyCount", 1)
        tiles = h.address("wTileMap")
        h.pyboy.memory[tiles:tiles + 360] = [0x7F] * 360
        captured = []
        bank, address = h.symbols.get(seam)

        def capture(_context) -> None:
            captured.append(list(h.pyboy.memory[tiles:tiles + 360]))

        h.pyboy.hook_register(bank, address, capture, None)
        try:
            h.probe_routine_until(routine, lambda: bool(captured), limit=200)
        finally:
            h.pyboy.hook_deregister(bank, address)
        return captured[0]

    def test_enemy_party_balls_ignore_stale_ghost_flags(self) -> None:
        tiles = self.capture_tiles("SetupEnemyPartyPokeballs", "WritePokeballOAMData", 1, 1)
        self.assertEqual(tiles[1 * 20 + 9], 0x7F)
        self.assertEqual(tiles[8 * 20 + 13], 0x7F)

    def test_player_party_balls_ignore_stale_ghost_flags(self) -> None:
        tiles = self.capture_tiles("SetupOwnPartyPokeballs", "WritePokeballOAMData", 1, 1)
        self.assertEqual(tiles[1 * 20 + 9], 0x7F)
        self.assertEqual(tiles[8 * 20 + 13], 0x7F)

    def test_player_ghost_marks_only_player_hud(self) -> None:
        tiles = self.capture_tiles("DrawPlayerHUDAndHPBar", "CenterMonName", 1, 0)
        self.assertEqual(tiles[8 * 20 + 13], 0xD0)  # <HUD_GHOST>
        self.assertEqual(tiles[1 * 20 + 9], 0x7F)

    def test_enemy_ghost_marks_only_enemy_hud(self) -> None:
        tiles = self.capture_tiles("DrawEnemyHUDAndHPBar", "CenterMonName", 0, 1)
        self.assertEqual(tiles[1 * 20 + 9], 0xD0)  # <HUD_GHOST>
        self.assertEqual(tiles[8 * 20 + 13], 0x7F)


if __name__ == "__main__":
    unittest.main()
