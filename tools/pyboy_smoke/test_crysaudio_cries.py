"""Every species' cry reaches the Crystal engine with its own row (Crystal audio port, Phase 2).

PokemonCries (crysaudio/red_rogue_cries.asm) is in INTERNAL species order, one row per id
1-NUM_POKEMON_INDEXES. For each id this plays the cry through the real HOME PlayCryWithOffsets
and checks, at _PlayCry's entry, the cry id (de), wCryPitch and wCryLength against the row,
and that the cry then holds an SFX channel with SOUND_CRY set. Out-of-range ids must play
nothing (pokecrystal's GetCryIndex guard). Growl's move offsets ($00 pitch, $c0 length, from
data/moves/sfx.asm) use the old 8-bit wrapping math on Red-format rows and pokecrystal's 16-bit
BattleAnimCmd_Cry math (anim_cry $0 = +$0000/+$00C0) on authentic Crystal rows."""
import io
import re
import unittest

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

CRIES = parse_rgbds_constants(REPO_ROOT / "crysaudio/cry_constants.asm")
SOUND_CHANNEL_ON, SOUND_CRY = 1 << 0, 1 << 5
GROWL_PITCH, GROWL_LENGTH = 0x00, 0xC0


def cry_rows() -> list[tuple[int, int, int]]:
    text = (REPO_ROOT / "crysaudio/red_rogue_cries.asm").read_text(encoding="utf-8")
    rows = re.findall(r"^\s*mon_cry\s+(CRY_\w+),\s*(-?\d+),\s*(\d+)", text, re.MULTILINE)
    return [(CRIES[name], int(pitch) & 0xFFFF, int(length)) for name, pitch, length in rows]


def with_growl(pitch: int, length: int) -> tuple[int, int]:
    if pitch < 0x100 and 0x80 <= length < 0x180:  # Red-format row: old 8-bit adds
        return (pitch + GROWL_PITCH) & 0xFF, ((length - 0x80 + GROWL_LENGTH) & 0xFF) + 0x80
    return (pitch + GROWL_PITCH) & 0xFFFF, (length + GROWL_LENGTH) & 0xFFFF


class CryTableTest(HarnessTestCase):
    def _play(self, species: int, offsets: tuple[int, int] = (0, 0)):
        """Play one cry from the saved park; return (_PlayCry args or None, channels after)."""
        h = self.harness
        assert h is not None
        h.load_state(io.BytesIO(self.baseline))
        h.write8("wSFXDontWait", 1)  # WaitSFX returns at once: no frame wait inside call_routine
        seen = {}

        def entry(_):
            rf = h.pyboy.register_file
            rf.A, rf.B, rf.C = species, offsets[0], offsets[1]

        def at_play(_):
            rf = h.pyboy.register_file
            seen["args"] = (rf.D << 8 | rf.E,
                            h.read8("wCryPitch") | h.read8("wCryPitch", 1) << 8,
                            h.read8("wCryLength") | h.read8("wCryLength", 1) << 8)

        h.register_hook("PlayCryWithOffsets", entry)
        h.register_hook("_PlayCry", at_play)
        try:
            h.call_routine("PlayCryWithOffsets", limit=600)
        finally:
            h.unregister_hook("PlayCryWithOffsets", entry)
            h.unregister_hook("_PlayCry", at_play)
        flags = [h.read8(f"wChannel{n}Flags1") for n in range(5, 9)]
        return seen.get("args"), flags

    def setUp(self) -> None:
        super().setUp()
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        state = io.BytesIO()
        h.save_state(state)
        self.baseline = state.getvalue()

    def test_every_species_plays_its_own_row(self) -> None:
        rows = cry_rows()
        self.assertEqual(len(rows), 253)
        for species, (cry, pitch, length) in enumerate(rows, start=1):
            with self.subTest(species=species):
                args, flags = self._play(species)
                self.assertEqual(args, (cry, pitch, length))
                self.assertTrue(any(f & SOUND_CHANNEL_ON and f & SOUND_CRY for f in flags),
                                f"no SFX channel holds the cry: {flags}")

    def test_out_of_range_species_play_nothing(self) -> None:
        for species in (0, len(cry_rows()) + 1, 0xFF):
            with self.subTest(species=species):
                args, _ = self._play(species)
                self.assertIsNone(args)

    def test_growl_offsets_match_each_engines_math(self) -> None:
        rows = cry_rows()
        def red_format(p, l):
            return p < 0x100 and 0x80 <= l < 0x180
        # A Red row whose old 8-bit length add wraps is where the two maths disagree.
        red = next(i for i, (_, p, l) in enumerate(rows, 1)
                   if red_format(p, l) and l - 0x80 + GROWL_LENGTH > 0xFF)
        crystal = next(i for i, (_, p, l) in enumerate(rows, 1) if not red_format(p, l))
        for species in (red, crystal):
            cry, pitch, length = rows[species - 1]
            with self.subTest(species=species):
                args, _ = self._play(species, (GROWL_PITCH, GROWL_LENGTH))
                self.assertEqual(args, (cry, *with_growl(pitch, length)))


if __name__ == "__main__":
    unittest.main()
