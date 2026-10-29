"""The AUDIO option's four modes pan the music exactly as the pre-port engine did.

Measured 2026-10-28 with PyBoy sound emulation in the lobby, pre-port engine (037d6540) vs the
Crystal audio port: once the song (re)starts in a mode, NR51 holds MONO $77, EARPHONE 1 $65,
EARPHONE 2 $25, EARPHONE 3 $43 in both engines. The Crystal engine applies a mode's masks when a
channel starts (GetLRTracks), so changing the option restarts the playing song
(OptAudioHook, as pokecrystal's Options_Sound calls RestartMapMusic). Without the hook a
change mid-song stayed at $77 until the next song: this test calls the hook, as the menu does."""
import io
import unittest

from test_smoke import HarnessTestCase, REPO_ROOT
from harness import RedRogueHarness
from test_smoke import ARTIFACTS

SOUND_MASK2 = 0x30
EXPECTED = {0: 0x77, 1: 0x65, 2: 0x25, 3: 0x43}  # mono, earphone 1-3
NR51 = 0xFF25


class PanningTest(HarnessTestCase):
    def setUp(self) -> None:
        # NR51 only reads back with the APU emulated.
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, sound_emulated=True)

    def test_each_audio_mode_pans_like_the_old_engine(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_to_lobby()
        h.tick(120)
        baseline = io.BytesIO()
        h.save_state(baseline)
        song = h.read8("wChannel1MusicID")
        for mode, want in EXPECTED.items():
            with self.subTest(mode=mode):
                h.load_state(io.BytesIO(baseline.getvalue()))
                h.write8("wOptions2", (h.read8("wOptions2") & ~SOUND_MASK2) | mode << 4)
                h.call_routine("OptAudioHook", limit=600)
                self.assertEqual(h.read8("wChannel1MusicID"), song, "the hook restarted a different song")
                seen = set()
                for _ in range(300):
                    h.tick(1)
                    seen.add(h.pyboy.memory[NR51])
                self.assertEqual(seen, {want}, f"NR51 values {sorted(map(hex, seen))}")


if __name__ == "__main__":
    unittest.main()
