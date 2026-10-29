"""Every MUSIC_* ID starts the song its pointer-table row names (Crystal audio port, Phase 2).

The Music table (crysaudio/music_pointers_red.asm) is indexed by the MUSIC_* constants in
constants/music_constants.asm, so a row inserted or dropped on one side silently shifts every
later song. For each ID this starts the song through the real HOME PlayMusic and checks, at
PlayMusic's own .end (before the engine bank is restored), that the engine loaded exactly that
song's header: music ID, song bank, and every channel's start address and on-flag, read from
the song header in the ROM file."""
import io
import re
import unittest

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

POINTERS = REPO_ROOT / "crysaudio/music_pointers_red.asm"
MUSIC = parse_rgbds_constants(REPO_ROOT / "constants/music_constants.asm")
SOUND_CHANNEL_ON = 1 << 0


def song_labels() -> list[str]:
    text = POINTERS.read_text()
    body = text[text.index("Music:"):]
    return re.findall(r"^\s*dba\s+(\w+)", body, re.MULTILINE)


class SongTableTest(HarnessTestCase):
    def test_table_matches_constants(self) -> None:
        # NUM_MUSIC_SONGS is const_value after the song block (const_def 1, so +1 for row 0).
        text = (REPO_ROOT / "constants/music_constants.asm").read_text()
        block = text[:text.index("DEF NUM_MUSIC_SONGS")]
        block = block[block.index("const_def 1"):]
        songs = len(re.findall(r"^\s*const\s+MUSIC_\w+", block, re.MULTILINE))
        self.assertEqual(len(song_labels()), songs + 1, "Music table rows != NUM_MUSIC_SONGS")

    def test_every_song_id_loads_its_own_header(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        baseline = io.BytesIO()
        h.save_state(baseline)
        rom = h.rom_path.read_bytes()
        labels = song_labels()
        song_id = {"value": 0}
        captured = {}

        def set_id(_):
            h.pyboy.register_file.A = song_id["value"]

        def at_end(_):
            captured["id"] = h.read8("wMusicID")
            captured["bank"] = h.read8("wMusicBank")
            captured["channels"] = [
                (h.read8(f"wChannel{n}Flags1") & SOUND_CHANNEL_ON,
                 h.read8(f"wChannel{n}MusicBank"),
                 h.read8(f"wChannel{n}MusicAddress") | h.read8(f"wChannel{n}MusicAddress", 1) << 8)
                for n in range(1, 5)
            ]

        h.register_hook("PlayMusic", set_id)
        h.register_hook("PlayMusic.end", at_end)
        for index in range(1, len(labels)):  # 0 is Music_Nothing: PlayMusic stops instead
            label = labels[index]
            with self.subTest(song=label, id=index):
                bank, address = h.symbols.get(label)
                header = bank * 0x4000 + address - 0x4000 if address >= 0x4000 else address
                count = (rom[header] >> 6) + 1
                expected = {}
                for record in range(count):
                    at = header + 3 * record
                    channel = rom[at] & 0x0F
                    self.assertLess(channel, 4, f"{label} header names a non-music channel")
                    expected[channel + 1] = rom[at + 1] | rom[at + 2] << 8
                h.load_state(baseline)
                song_id["value"] = index
                captured.clear()
                h.call_routine("PlayMusic", limit=600)
                self.assertEqual(captured.get("id"), index)
                self.assertEqual(captured["bank"], bank)
                for n, (on, channel_bank, start) in enumerate(captured["channels"], start=1):
                    if n in expected:
                        self.assertTrue(on, f"{label}: channel {n} not started")
                        self.assertEqual(channel_bank, bank, f"{label}: channel {n} bank")
                        self.assertEqual(start, expected[n], f"{label}: channel {n} start")
                    else:
                        self.assertFalse(on, f"{label}: channel {n} should be silent")

    def test_credits_song_loops_on_every_channel(self) -> None:
        # Red Rogue's credits roll outlasts the song, so its three channels end in
        # `sound_loop 0` back to their own starts. Measured 2026-10-28: one pass is 5880
        # frames and all three loop within one frame of each other; channel 1 runs its
        # setup commands in the same frame, so it reappears 18 bytes past its start.
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.register_hook("PlayMusic",
                        lambda _c: setattr(h.pyboy.register_file, "A", MUSIC["MUSIC_CREDITS"]))
        h.call_routine("PlayMusic", limit=600)
        starts = {n: h.symbols.get(f"Music_RBYCredits_Ch{n}")[1] for n in (1, 2, 3)}

        def address(n):
            return h.read8(f"wChannel{n}MusicAddress") | h.read8(f"wChannel{n}MusicAddress", 1) << 8

        prev = {n: address(n) for n in starts}
        looped = {}
        for frame in range(1, 6200):
            h.tick(1)
            for n, start in starts.items():
                now = address(n)
                if n not in looped and now < prev[n] and 0 <= now - start < 32 and prev[n] - start > 64:
                    looped[n] = frame
                prev[n] = now
            if len(looped) == 3:
                break
        self.assertEqual(sorted(looped), [1, 2, 3], f"channels that looped: {looped}")
        self.assertLessEqual(max(looped.values()) - min(looped.values()), 2, looped)
        self.assertEqual(h.read8("wMusicID"), MUSIC["MUSIC_CREDITS"])


if __name__ == "__main__":
    unittest.main()
