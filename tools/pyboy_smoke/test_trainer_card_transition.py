from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class TrainerCardTransitionSourceContractTest(unittest.TestCase):
    def setUp(self) -> None:
        source = (REPO_ROOT / "engine" / "menus" / "start_sub_menus.asm").read_text()
        start = source.index("StartMenu_TrainerInfo::")
        end = source.index("; loads tile patterns and draws everything except", start)
        self.flow = source[start:end]

    def test_dmg_waits_for_entry_and_exit_tile_transfers(self) -> None:
        dmg_wait = "ld a, [wOnSGB]\n\tand a\n\tcall z, Delay3"
        self.assertEqual(self.flow.count(dmg_wait), 2)
        self.assertRegex(
            self.flow,
            r"(?ms)call RunPaletteCommand\s+"
            r"ld a, \[wOnSGB\]\s+and a\s+call z, Delay3\s+"
            r"call GBPalNormal",
        )
        self.assertRegex(
            self.flow,
            r"(?ms)call RunDefaultPaletteCommand\s+call ReloadMapData\s+"
            r"ld a, \[wOnSGB\]\s+and a\s+call z, Delay3\s+"
            r"call LoadGBPal",
        )

    def test_existing_card_state_lifecycle_is_preserved(self) -> None:
        anchors = (
            "call GBPalWhiteOut",
            "call ClearScreen",
            "call UpdateSprites",
            "ldh a, [hTileAnimations]",
            "ldh [hTileAnimations], a",
            "call DrawTrainerInfo",
            "predef DrawBadges",
            "call WaitForTextScrollButtonPress",
            "call LoadFontTilePatterns",
            "call LoadScreenTilesFromBuffer2",
            "call ReloadMapData",
            "jp RedisplayStartMenu",
        )
        for anchor in anchors:
            self.assertIn(anchor, self.flow)
        self.assertLess(self.flow.index("push af"), self.flow.index("call DrawTrainerInfo"))
        self.assertLess(self.flow.index("call LoadGBPal"), self.flow.index("pop af"))


if __name__ == "__main__":
    unittest.main()
