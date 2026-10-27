"""CGB retains its own palette restoration when START closes."""
import unittest
import test_start_menu_sgb_palette


class CGBStartMenuSGBPaletteTest(unittest.TestCase):
    def test_cgb_close_skips_sgb_recovery_even_with_sgb_flag(self):
        test_start_menu_sgb_palette.StartMenuSGBPaletteTest.check_close(self, sgb=True, cgb=True)
