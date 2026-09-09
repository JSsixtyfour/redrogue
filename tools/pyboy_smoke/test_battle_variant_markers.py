from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class BattleVariantMarkerContractTest(unittest.TestCase):
    def test_hud_hook_and_marker_priority(self) -> None:
        hud = (REPO_ROOT / "engine" / "battle" / "draw_hud_pokeball_gfx.asm").read_text()
        shiny = (REPO_ROOT / "custom_functions" / "func_shiny.asm").read_text()

        self.assertEqual(hud.count("farcall DrawBattleVariantMarker"), 1)
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


if __name__ == "__main__":
    unittest.main()
