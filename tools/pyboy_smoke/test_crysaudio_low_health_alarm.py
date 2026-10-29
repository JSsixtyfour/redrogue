"""Red Rogue's low-HP alarm policy on the Crystal engine (audio/low_health_alarm.asm).

Kept by user decision 2026-10-28 (Shin Red import Phase 2.10): the alarm plays three high/low
tone pairs and then stays quiet while the HP bar stays red; once the bar leaves red (alarm
idle, in battle) the allotment is topped up again. DISABLE_LOW_HEALTH_ALARM ($ff), which the
faint path writes, keeps its Red meaning, "off": Crystal's PlayDanger alone would read $ff as on.
Both engines use a 30-frame pair."""
import unittest

from test_smoke import HarnessTestCase

DANGER_ON = 0x80
HP_BAR_GREEN, HP_BAR_RED = 0, 2
PAIR_FRAMES = 30


class LowHealthAlarmTest(HarnessTestCase):
    def _fresh_pairs(self, frames: int) -> list[int]:
        """Frames on which a new tone pair starts (the alarm's timer bits are 0 with it on)."""
        h = self.harness
        assert h is not None
        starts, frame = [], {"n": 0}

        def at_alarm(_):
            value = h.read8("wLowHealthAlarm")
            if value != 0xFF and value & DANGER_ON and not value & ~DANGER_ON & 0xFF:
                starts.append(frame["n"])

        h.register_hook("RedRogueLowHealthAlarm", at_alarm)
        try:
            for frame["n"] in range(frames):
                h.tick(1)
        finally:
            h.unregister_hook("RedRogueLowHealthAlarm", at_alarm)
        return starts

    def _arm(self, color: int) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.write8("wPlayerHPBarColor", color)
        h.write8("wLowHealthTonePairs", 3 + 1)
        h.write8("wLowHealthAlarm", DANGER_ON)

    def test_three_pairs_then_quiet_while_red(self) -> None:
        h = self.harness
        assert h is not None
        self._arm(HP_BAR_RED)
        starts = self._fresh_pairs(8 * PAIR_FRAMES)
        # Three pair starts spend the allotment 4 -> 1; the fourth start finds it exhausted
        # and turns the alarm off instead of playing. Each is one 30-frame pair apart.
        self.assertEqual(len(starts), 4, f"pair starts {starts}")
        self.assertEqual([b - a for a, b in zip(starts, starts[1:])], [PAIR_FRAMES] * 3, starts)
        self.assertEqual(h.read8("wLowHealthAlarm"), 0, "alarm still on after its three pairs")
        self.assertEqual(h.read8("wLowHealthTonePairs"), 0)
        self.assertEqual(self._fresh_pairs(4 * PAIR_FRAMES), [], "alarm came back while still red")

    def test_rearms_once_the_bar_leaves_red(self) -> None:
        h = self.harness
        assert h is not None
        self._arm(HP_BAR_RED)
        self._fresh_pairs(8 * PAIR_FRAMES)
        self.assertEqual(h.read8("wLowHealthTonePairs"), 0)
        h.write8("wPlayerHPBarColor", HP_BAR_GREEN)
        h.tick(2)
        self.assertEqual(h.read8("wLowHealthTonePairs"), 3 + 1)

    def test_disable_value_turns_it_off(self) -> None:
        h = self.harness
        assert h is not None
        self._arm(HP_BAR_RED)
        h.write8("wLowHealthAlarm", 0xFF)  # RemoveFaintedPlayerMon's DISABLE_LOW_HEALTH_ALARM
        h.tick(2)
        self.assertEqual(h.read8("wLowHealthAlarm"), 0)
        self.assertEqual(self._fresh_pairs(3 * PAIR_FRAMES), [])


if __name__ == "__main__":
    unittest.main()
