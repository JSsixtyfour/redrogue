"""Visible BG palette sanity check against the real CGB runtime hook.

Split from test_autoplay_cgb.py (2026-10-22): run_smoke.py picks a module's
hardware mode from its name (test_cgb_* runs CGB), so the one test that boots a
CGB harness needs a test_cgb_ module of its own.
"""
from __future__ import annotations

import unittest

import autoplay
from harness import RedRogueHarness
from test_smoke import ARTIFACTS, REPO_ROOT


class VisiblePaletteHookCGBTest(unittest.TestCase):
    def test_flattened_visible_bg_palettes_are_reported_by_the_runtime_hook(self) -> None:
        harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=True)
        try:
            harness.boot_to_lobby()
            agent = autoplay.AutoplayAgent(harness, seed=1)
            screen = agent.checks.screen
            self.assertEqual(len(agent.checks.sp_copy_windows), 4,
                             "all source-verified CGB stack-copy windows should resolve")
            memory = harness.pyboy.memory
            indices = screen._visible_bg_palette_indices(memory[0xFF40])
            self.assertTrue(indices, "the lobby's visible BG map should use a palette")
            map_id = harness.read8("hCurMap")
            load_key = (map_id, screen.palette_reload)

            for _ in range(240):
                if load_key in screen.palette_checked:
                    break
                harness.tick(1)

            self.assertIn(load_key, screen.palette_checked)
            self.assertEqual(screen.palette_counts["passed"], 1,
                             "the unmodified lobby palette should pass the real hook")
            screen.palette_checked.remove(load_key)

            # Corrupt every BG palette used by the displayed map to one color.
            # Set an ordinary non-fade rBGP mapping so the hook reaches palette RAM.
            for palette in indices:
                memory[0xFF68] = 0x80 | palette * 8
                for _ in range(4):
                    memory[0xFF69] = 0x1F
                    memory[0xFF69] = 0
            memory[0xFF47] = 0xE4
            memory[0xFF68] = 0x25
            bgpi_sentinel = memory[0xFF68]
            memory[0xFF4F] = 0

            for _ in range(240):
                if load_key in screen.palette_checked:
                    break
                harness.tick(1)

            self.assertIn(load_key, screen.palette_checked)
            self.assertEqual(screen.palette_counts["samples"], 2)
            self.assertEqual(screen.palette_counts["passed"], 1)
            self.assertEqual(screen.palette_counts["failed"], 1)
            self.assertTrue(any(item["check"] == "screen_palette"
                                for item in agent.checks.anomalies))
            self.assertEqual(memory[0xFF68], bgpi_sentinel,
                             "BGPI must be restored after sampling")
            self.assertEqual(memory[0xFF4F] & 1, 0, "VBK must be restored after attribute reads")
            self.assertEqual(screen.summary()["maps_checked"], [map_id])
        finally:
            harness.close()


if __name__ == "__main__":
    unittest.main()
