"""Debug sound test through the real debug menu: it is reached by farcall in
its own section (engine/debug/debug2_config.asm), names each imported song
from DebugSongNames, and returns to the debug menu on B."""
import unittest

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

MUSIC = parse_rgbds_constants(REPO_ROOT / "constants/music_constants.asm")
# the parser leaves NUM_MUSIC_SONGS (EQU const_value) out; the last id is the highest
LAST_SONG = max(v for k, v in MUSIC.items() if k.startswith("MUSIC_"))
NAME_ROW, NAME_COL, SCREEN_WIDTH = 5, 1, 20


def encode(text: str) -> list[int]:
    codes = {" ": 0x7F, "-": 0xE3, "!": 0xE7}
    out = []
    for ch in text:
        if ch in codes:
            out.append(codes[ch])
        elif ch.isdigit():
            out.append(0xF6 + int(ch))
        else:
            out.append(0x80 + ord(ch) - ord("A"))
    return out


class DebugSoundTestTest(HarnessTestCase):
    def name_on_screen(self, length: int) -> list[int]:
        return self.harness.read_bytes("wTileMap", length, NAME_ROW * SCREEN_WIDTH + NAME_COL)

    def test_newest_songs_are_named_and_play(self) -> None:
        h = self.harness
        assert h is not None
        entered = h.hook_flag("DebugMenu")
        sound_test = h.hook_flag("DebugSoundTest")
        h.tick(240)
        h.pyboy.button_press("select")
        for _ in range(300):
            h.tap("start", 1)
            if entered["count"]:
                break
        h.pyboy.button_release("select")
        h.tick(30)
        self.assertTrue(entered["count"], "debug menu did not open")
        for _ in range(4):  # FIGHT, FIGHT 2, DEBUG, DEBUG 2, MUSIC
            h.tap("down", 6)
        h.tap("a", 6)
        h.tick(20)
        self.assertEqual(sound_test["count"], 1, "MUSIC did not reach DebugSoundTest")
        self.assertEqual(h.read8("wItemQuantity"), 1)
        # LEFT from song 1 wraps to the last song, so the newest come first.
        expected = [
            (LAST_SONG, MUSIC["MUSIC_PIKA_CUP_BATTLE"], "PIKA CUP 1-3"),
            (LAST_SONG - 1, MUSIC["MUSIC_PETIT_CUP_BATTLE"], "PETIT CUP 1-3"),
            (LAST_SONG - 2, MUSIC["MUSIC_POKE_CUP_BATTLE"], "POKE CUP 4-6"),
            (LAST_SONG - 3, MUSIC["MUSIC_HO_OH_BATTLE"], "BATTLE! HO-OH"),
        ]
        for song_id, const, name in expected:
            with self.subTest(song=name):
                h.tap("left", 6)
                h.tick(20)
                self.assertEqual(song_id, const)
                self.assertEqual(h.read8("wItemQuantity"), song_id)
                # the name, then blanks: no leftover of a longer earlier name
                self.assertEqual(self.name_on_screen(len(name) + 1), encode(name) + [0x7F])
                self.assertEqual(h.read8("wMusicID"), song_id, "the song did not start")
        h.tap("b", 6)
        h.tick(30)
        self.assertEqual(h.read8("wMusicID"), 0, "B should stop the music")
        self.assertGreater(entered["count"], 0)
        self.assertEqual(h.read8("wMaxMenuItem"), 4, "B should return to the debug menu")


if __name__ == "__main__":
    unittest.main()
