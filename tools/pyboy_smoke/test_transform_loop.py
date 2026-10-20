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
        descriptions = re.findall(r"^(_\w+Desc)::\n((?:\t.*\n)+?)\tdone", source, re.M)
        self.assertGreater(len(descriptions), 30)
        for name, body in descriptions:
            commands = re.findall(r"^\t(\w+)", body, re.M)
            self.assertLessEqual(commands, ["text", "line"], f"{name}: {commands}")
            for line in re.findall(r'"([^"]*)"', body):
                shown = line.replace("#", "POKé")  # '#' prints as POKé
                self.assertLessEqual(len(shown), GIFT_DESC_WIDTH, f"{name}: {shown!r}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
