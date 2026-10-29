"""Transform fails if the user or the target has already transformed. Found
by the autoplay bot (2026-10-20): two Dittos that only knew Transform copied
each other forever, since each Transform refills the user's PP to 5 and an
enemy never runs out of PP, so no one Struggled and the trainer battle could
not be fled. Also: every bridge
gift description fits its two-line box, since a third line made the gift menu
wait for A/B mid-redraw (directions did nothing, the first A only scrolled)."""
import re
import unittest

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

MOVES = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
TRANSFORMED = 1 << 3  # wPlayerBattleStatus3 / wEnemyBattleStatus3
GIFT_DESC_WIDTH = 19  # the description box's text width, in tiles
PLAYER_TURN = 0


class TransformAgainstTransformedTest(HarnessTestCase):
    def _player_transforms(self, enemy_transformed: bool = False,
                           player_transformed: bool = False) -> tuple[bool, bool]:
        """(the player's Transform ran, it failed)."""
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        # The enemy FIGHT 2 rolls follows VBlank-time RNG, so its moves drift with engine
        # timing (an Arbok's Wrap kept the player from ever acting). Pin it to Splash.
        for i in range(4):
            h.write8("wEnemyMonMoves", MOVES["SPLASH"] if i == 0 else 0, offset=i)
            h.write8("wEnemyMonPP", 30 if i == 0 else 0, offset=i)
        h.write8("wEnemySelectedMove", MOVES["SPLASH"])  # the AI picks before the menu opens
        h.write8("wBattleMonMoves", MOVES["TRANSFORM"])
        h.write8("wBattleMonPP", 10)
        for slot in range(1, 4):
            h.write8("wBattleMonMoves", 0, offset=slot)
            h.write8("wBattleMonPP", 0, offset=slot)
        if enemy_transformed:
            h.write8("wEnemyBattleStatus3", h.read8("wEnemyBattleStatus3") | TRANSFORMED)
        if player_transformed:
            h.write8("wPlayerBattleStatus3", h.read8("wPlayerBattleStatus3") | TRANSFORMED)
        ran, failed = [], []
        for label, record in (("TransformEffect_", ran), ("TransformEffect_.failed", failed)):
            h.register_hook(label, lambda _c, record=record: record.append(h.read8("hWhoseTurn")))
        for _ in range(3):  # as test_body_armor: the first presses may meet battle text
            h.tap("a", 3)  # FIGHT
            h.tick(40)
            h.tap("a", 3)  # TRANSFORM, the only move
            h.tick(240)
            if PLAYER_TURN in ran:
                break
            for _ in range(10):
                h.tap("a", 3)
                h.tick(20)
        return PLAYER_TURN in ran, PLAYER_TURN in failed

    def test_fails_against_a_transformed_target(self) -> None:
        ran, failed = self._player_transforms(enemy_transformed=True)
        self.assertTrue(ran, "the player's Transform never ran")
        self.assertTrue(failed)
        self.assertFalse(self.harness.read8("wPlayerBattleStatus3") & TRANSFORMED)

    def test_fails_when_the_user_has_transformed(self) -> None:
        ran, failed = self._player_transforms(player_transformed=True)
        self.assertTrue(ran, "the player's Transform never ran")
        self.assertTrue(failed)

    def test_still_works_between_untransformed_mons(self) -> None:
        ran, failed = self._player_transforms()
        self.assertTrue(ran, "the player's Transform never ran")
        self.assertFalse(failed)
        self.assertTrue(self.harness.read8("wPlayerBattleStatus3") & TRANSFORMED)


class GiftDescriptionsFitTest(unittest.TestCase):
    def test_two_lines_that_fit_the_box(self) -> None:
        source = (REPO_ROOT / "text/bridge_gifts.asm").read_text(encoding="utf-8")
        descriptions = re.findall(r"^(_\w+Desc)::\n((?:\t.*\n)+?)\t(?:done|text_end)", source, re.M)
        self.assertGreater(len(descriptions), 30)
        for name, body in descriptions:
            # Rendered lines, not command shapes: `text "@"` + `text_ram
            # wNameBuffer` + `text " with"` is still one line. The name is the
            # resolved species (BridgePrintGiftDesc), so count it at its cap.
            lines, opened = [], False
            for command, arg in re.findall(r'^\t(\w+)(?:\s+"([^"]*)"|\s+\w+)?', body, re.M):
                if command == "text_ram":
                    lines[-1] += "X" * 10  # NAME_LENGTH - 1
                    continue
                if command == "text" and opened:
                    lines[-1] += arg  # `text` after a command continues the line
                    continue
                self.assertIn(command, ("text", "line"), f"{name}: {command}")
                lines.append(arg)
                opened = True
            self.assertLessEqual(len(lines), 2, f"{name}: {lines}")
            for line in lines:
                shown = line.replace("@", "").replace("#", "POKé")  # '#' prints as POKé
                self.assertLessEqual(len(shown), GIFT_DESC_WIDTH, f"{name}: {shown!r}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
