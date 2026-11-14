"""Lobby exit-door heal reminder (custom_functions/lobby_heal_warning.asm).

The routine only reads wXCoord/wYCoord/wWalkCounter, the party and one latch
bit, so the player is placed by writing coordinates rather than walking through
the lobby's NPCs. hWY is the text window's on-screen signal: DisplayTextIDInit
writes 0, CloseTextDisplay writes $90.
"""
from test_smoke import HarnessTestCase

BIT_LOBBY_HEAL_HANDLED = 1 << 1  # wStatusFlags4
WINDOW_OFF = 0x90
DOOR1_X, DOOR2_X, DOOR_ROW = 8, 10, 1


class LobbyHealWarningTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        h = self.harness
        h.boot_to_lobby()
        # Let any arrival text settle so hWY reflects only this test.
        for _ in range(4):
            h.tap("b", 4)
            h.tick(20)
        self.assertEqual(h.read8("hWY"), WINDOW_OFF, "lobby still had a text box open")
        self.assertGreater(h.read8("wPartyCount"), 0)
        self.stride = h.address("wPartyMon2") - h.address("wPartyMon1")
        self.shown = h.hook_flag("LobbyHealWarning.warn")

    def heal_party(self) -> None:
        h = self.harness
        for i in range(h.read8("wPartyCount")):
            base = i * self.stride
            h.write8("wPartyMon1HP", h.read8("wPartyMon1MaxHP", base), base)
            h.write8("wPartyMon1HP", h.read8("wPartyMon1MaxHP", base + 1), base + 1)
            h.write8("wPartyMon1Status", 0, base)

    def hurt_lead(self) -> None:
        self.heal_party()
        self.harness.write8("wPartyMon1HP", 0)
        self.harness.write8("wPartyMon1HP", 1, 1)

    def set_latch(self, value: bool) -> None:
        h = self.harness
        flags = h.read8("wStatusFlags4") & ~BIT_LOBBY_HEAL_HANDLED & 0xFF
        h.write8("wStatusFlags4", flags | (BIT_LOBBY_HEAL_HANDLED if value else 0))

    def stand(self, x: int, y: int = DOOR_ROW) -> None:
        h = self.harness
        h.write8("wXCoord", x)
        h.write8("wYCoord", y)
        h.tick(30)

    def assert_silent(self, why: str) -> None:
        h = self.harness
        self.assertEqual(self.shown["count"], 0, why)
        self.assertEqual(h.read8("hWY"), WINDOW_OFF, why)
        self.assertFalse(h.read8("wStatusFlags4") & BIT_LOBBY_HEAL_HANDLED, why)

    def test_hurt_party_below_door_warns_once_then_closes(self) -> None:
        h = self.harness
        self.hurt_lead()
        self.set_latch(False)
        self.stand(DOOR1_X)
        self.assertEqual(self.shown["count"], 1)
        self.assertEqual(h.read8("hWY"), 0, "warning window not on screen")
        self.assertTrue(h.read8("wStatusFlags4") & BIT_LOBBY_HEAL_HANDLED)
        for _ in range(4):
            h.tap("a", 4)
            h.tick(20)
            if h.read8("hWY") == WINDOW_OFF:
                break
        self.assertEqual(h.read8("hWY"), WINDOW_OFF, "warning did not close on A")
        # Latched: standing there again (or at the other door) stays quiet.
        self.stand(DOOR1_X)
        self.stand(DOOR2_X)
        self.assertEqual(self.shown["count"], 1)
        self.assertEqual(h.read8("hWY"), WINDOW_OFF)

    def test_status_alone_counts_as_hurt(self) -> None:
        self.heal_party()
        self.harness.write8("wPartyMon1Status", 1 << 3)  # poisoned, full HP
        self.set_latch(False)
        self.stand(DOOR1_X)
        self.assertEqual(self.shown["count"], 1)

    def test_fit_party_is_not_warned(self) -> None:
        self.heal_party()
        self.set_latch(False)
        self.stand(DOOR1_X)
        self.assert_silent("full HP, no status: nothing to heal")

    def test_nurse_heal_latch_suppresses_warning(self) -> None:
        h = self.harness
        self.hurt_lead()
        self.set_latch(True)
        self.stand(DOOR1_X)
        self.assertEqual(self.shown["count"], 0)
        self.assertEqual(h.read8("hWY"), WINDOW_OFF)

    def test_tile_beside_door_is_not_a_trigger(self) -> None:
        self.hurt_lead()
        self.set_latch(False)
        self.stand(DOOR1_X + 1)  # the notepad column between the doors
        self.stand(DOOR1_X, DOOR_ROW + 1)  # one row lower
        self.assert_silent("only the tile directly below a door triggers")


if __name__ == "__main__":
    import unittest

    unittest.main()
