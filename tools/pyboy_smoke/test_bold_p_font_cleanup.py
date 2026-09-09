from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class BoldPFontCleanupContractTest(unittest.TestCase):
    def test_bold_p_is_owned_by_the_composite_font(self) -> None:
        charmap = (REPO_ROOT / "constants" / "charmap.asm").read_text(encoding="utf-8")
        status = (REPO_ROOT / "engine" / "pokemon" / "status_screen.asm").read_text(encoding="utf-8")

        self.assertEqual(charmap.count('charmap "<BOLD_P>",  $72'), 1)
        self.assertNotIn('charmap "『"', charmap)
        self.assertNotIn("PTile", status)
        self.assertFalse((REPO_ROOT / "gfx" / "font" / "P.png").exists())
        self.assertIn("ld a, '<BOLD_P>'", status)
        self.assertIn("call StatusScreen_PrintPP", status)

    def test_composite_tile_72_contains_the_bold_p(self) -> None:
        graphics = (REPO_ROOT / "gfx" / "font" / "font_battle_extra.2bpp").read_bytes()
        tile_72 = graphics[16 * 16:17 * 16]
        self.assertEqual(
            tile_72,
            bytes.fromhex("00 00 fc fc c6 c6 c6 c6 c6 c6 fc fc c0 c0 c0 c0"),
        )

    def test_exp_bar_aliases_and_all_reload_sites_remain(self) -> None:
        charmap = (REPO_ROOT / "constants" / "charmap.asm").read_text(encoding="utf-8")
        exp_bar = (REPO_ROOT / "engine" / "battle" / "exp_bar.asm").read_text()
        battle = (REPO_ROOT / "engine" / "battle" / "core.asm").read_text()

        self.assertIn('charmap "<EXP_BAR_PARTIAL>", $70', charmap)
        self.assertIn('charmap "<EXP_BAR_FULL>",    $72', charmap)
        self.assertIn("ld [hl], '<EXP_BAR_FULL>'", exp_bar)
        self.assertIn("ld [hl], '<EXP_BAR_PARTIAL>'", exp_bar)
        self.assertEqual(battle.count("callfar CalcAndLoadExpBarDynamicTile"), 5)


if __name__ == "__main__":
    unittest.main()
