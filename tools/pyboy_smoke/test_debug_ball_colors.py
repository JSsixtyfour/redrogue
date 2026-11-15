"""CGB debug tuner: real menu input, live palette ports, reset and exit."""
from pathlib import Path
import os
import unittest

from harness import RedRogueHarness

ROOT = Path(__file__).resolve().parents[2]
TUNER_ROM = os.environ.get("REDROGUE_BALL_COLORS_ROM")


@unittest.skipUnless(TUNER_ROM, "optional tuner: run make test_ball_colors")
class DebugBallColorsTest(unittest.TestCase):
    def test_live_edit_gamma_reset_and_return(self):
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts", cgb_mode=True, rom=TUNER_ROM)
        try:
            entered = h.hook_flag("DebugMenu")
            h.tick(240)
            h.pyboy.button_press("select")
            for _ in range(300):
                h.tap("start", 1)
                if entered["count"]:
                    break
            h.pyboy.button_release("select")
            h.tick(30)
            self.assertTrue(entered["count"], "debug menu did not open")
            saved = (h.read8("wOptions2"), h.read8("wOptions3"), h.read8("hUpdateSpritesEnabled"))
            ui_flags = h.read8("hUILayoutFlags")
            for _ in range(5):
                h.tap("down", 6)
            h.tap("a", 6)
            h.tick(30)
            initial = h.read_bytes("wTileMapBackup", 3)
            # Labels must occupy the SAME consecutive rows as values/cursor.
            # The title menu's double-spaced NEXT used to put G beside B's
            # value and B under the gamma text, while help ran offscreen.
            for row, glyph in ((7, 0x91), (8, 0x86), (9, 0x81)):
                self.assertEqual(h.read8("wTileMap", offset=row * 20 + 5), glyph)
            self.assertEqual(h.read8("wTileMap", offset=16 * 20 + 1), 0x81)
            self.assertEqual(h.read8("hUILayoutFlags"), ui_flags)

            def rgb(pal):
                h.pyboy.memory[0xFF6A] = pal * 8 + 4
                lo = h.pyboy.memory[0xFF6B]
                h.pyboy.memory[0xFF6A] = pal * 8 + 5
                v = lo | h.pyboy.memory[0xFF6B] << 8
                return (v & 31, (v >> 5) & 31, v >> 10 & 31)

            self.assertEqual(rgb(0), (2, 8, 31))
            self.assertEqual(rgb(1), (5, 5, 5))
            self.assertEqual(rgb(2), tuple(initial))
            h.tap("right", 6)
            self.assertEqual(rgb(2), ((initial[0] + 1) % 32, initial[1], initial[2]))
            self.assertEqual(rgb(0), (2, 8, 31), "reference blue changed")
            h.tap("down", 6)
            h.tap("left", 6)
            self.assertEqual(rgb(2)[1], (initial[1] - 1) % 32)
            h.tap("start", 6)
            self.assertEqual(rgb(2), tuple(initial))
            h.tap("a", 6)
            self.assertEqual(rgb(0), (11, 20, 29), "reference must use real game gamma")
            h.tap("a", 6)
            self.assertEqual(rgb(0), (2, 8, 31))
            self.assertEqual(rgb(2), tuple(initial))
            h.tick(10, render=True)
            h.pyboy.screen.image.save(str(ROOT / "tools/pyboy_smoke/artifacts/debug_ball_colors.png"))
            h.tap("b", 6)
            h.tick(20)
            self.assertEqual((h.read8("wOptions2"), h.read8("wOptions3"), h.read8("hUpdateSpritesEnabled")), saved)
            self.assertEqual(h.read8("wMaxMenuItem"), 5)
            # Reopening starts from the ROM palette, not the last experiment.
            for _ in range(5):
                h.tap("down", 6)
            h.tap("a", 6)
            h.tick(20)
            self.assertEqual(rgb(2), tuple(initial))
            self.assertEqual(h.read8("wTileMapBackup", offset=4), 0)
        finally:
            h.close()


if __name__ == "__main__":
    unittest.main()
