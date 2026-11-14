"""Hardware-duty regression against recordings, not an engine reimplementation.

Reference: pre-Crystal 2d9dd17d, debug ROM SHA256
8a0e89df99c5ac06448b0fc555e0cdb7f738438d2561c1fb0ce78d55a031a42f.
The old and new engine both use their normal battle-entry PlayCry and VBlank
updates; only the species argument is replaced. Golden pulse duties cover
Ponyta's complete 43/41-frame sounding tracks, including every note boundary.

Lifecycle correspondence: old duty command -> red_duty_cycle_pattern (raw
pattern and initial duty); PlayNextNote -> NOTE_NOISE_SAMPLING (initial duty,
no rotation); ApplyDutyCyclePattern -> HandleTrackVibrato between notes;
channel reset -> ChannelInit clears SOUND_RED_DUTY. Crystal's $de is unchanged.
"""
import unittest

from harness import RedRogueHarness
from test_smoke import ARTIFACTS, REPO_ROOT, HarnessTestCase
from source_constants import parse_rgbds_constants


SPECIES = parse_rgbds_constants(REPO_ROOT / 'constants/pokemon_constants.asm')


class LegacyDutyTest(HarnessTestCase):
    def setUp(self):
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS, sound_emulated=True)

    def _battle_trace(self, species, sfx=None):
        h = self.harness
        start, rows, replaced = [], [], []
        tick = h.tick

        def trace_tick(frames=1, *, render=False):
            for _ in range(frames):
                tick(1, render=render)
                if start and len(rows) < 160:
                    rows.append((h.pyboy.memory[0xFF11] >> 6,
                                 h.pyboy.memory[0xFF16] >> 6))

        def cry(_):
            if h.read8('wIsTrainerBattle') and not start:
                h.pyboy.register_file.A = species
                start.append(h.pyboy.frame_count)

        def substitute_sfx(_):
            if start and not replaced:
                replaced.append(True)
                rf = h.pyboy.register_file
                rf.D, rf.E = 0, sfx
                rf.PC = h.address('_PlaySFX')

        h.tick = trace_tick
        h.register_hook('PlayCry', cry)
        if sfx is not None:
            h.register_hook('_PlayCry', substitute_sfx)
        try:
            h.boot_fight2(seed=1)
        finally:
            h.tick = tick
            h.unregister_hook('PlayCry', cry)
            if sfx is not None:
                h.unregister_hook('_PlayCry', substitute_sfx)
        self.assertFalse(h.hook_errors)
        self.assertGreaterEqual(len(rows), 44)
        # The PlayCry entry frame precedes the first sound-engine update.
        return rows[1:]

    def test_ponyta_matches_pre_crystal_full_pulse_tracks(self):
        rows = self._battle_trace(SPECIES['PONYTA'])
        self.assertEqual(''.join(str(r[0]) for r in rows[:43]),
                         '2211221212211221122112221122211221212211221')
        self.assertEqual(''.join(str(r[1]) for r in rows[:41]),
                         '13131311313131313131313113113131131313131')

    def test_rhydon_matches_red_pattern(self):
        rows = self._battle_trace(SPECIES['RHYDON'])
        self.assertEqual(''.join(str(r[0]) for r in rows[:40]),
                         '3300330303300330303303033003300330033300')
        self.assertEqual(''.join(str(r[1]) for r in rows[:40]),
                         '0022000220020200220020200202002200220022')

    def test_rapidash_matches_red_pattern(self):
        # Donor fraction normalized to zero: old SFX init retained 0x40 from a prior sound.
        rows = self._battle_trace(SPECIES['RAPIDASH'])
        self.assertEqual(''.join(str(r[0]) for r in rows[:40]),
                         '2211221122211221122112211221212211222112')
        self.assertEqual(''.join(str(r[1]) for r in rows[:40]),
                         '1313131311313131313131313131131311313131')

    def test_psybeam_matches_red_pattern(self):
        rows = self._battle_trace(SPECIES['PONYTA'], parse_rgbds_constants(REPO_ROOT / 'constants/music_constants.asm')['SFX_PSYBEAM'])
        self.assertEqual(''.join(str(r[0]) for r in rows[:40]),
                         '2201220122021220122012220122012202201220')
        self.assertEqual(''.join(str(r[1]) for r in rows[:40]),
                         '2303230323023230323203230323032303230323')

    def test_crobat_retains_crystal_pattern(self):
        # Pre-fix Crystal ROM SHA256 4d209b5bd8376e87fe6d9097768b5493a3caa9009f3ca1f44a0b7cbd2cf6361b.
        rows = self._battle_trace(SPECIES['CROBAT'])
        self.assertEqual(''.join(str(r[0]) for r in rows[:40]),
                         '3310331033103310331033103310331033103310')
        self.assertEqual(''.join(str(r[1]) for r in rows[:40]),
                         '0202020202020202020202020202020202020202')

    def test_chikorita_retains_crystal_pattern(self):
        # Pre-fix Crystal ROM SHA256 4d209b5bd8376e87fe6d9097768b5493a3caa9009f3ca1f44a0b7cbd2cf6361b.
        rows = self._battle_trace(SPECIES['CHIKORITA'])
        self.assertEqual(''.join(str(r[0]) for r in rows[:40]),
                         '0201020102010200000333333333333333333333')
        self.assertEqual(''.join(str(r[1]) for r in rows[:40]),
                         '0201020102010200003000000000000000333333')

    def test_legacy_flag_does_not_leak_into_native_cries(self):
        h = self.harness
        h.boot_fight2(seed=1)
        for species, legacy in ((SPECIES['PONYTA'], True), (SPECIES['CROBAT'], False), (SPECIES['PONYTA'], True), (SPECIES['CHIKORITA'], False)):
            with self.subTest(species=species):
                h.write8('wSFXDontWait', 1)

                def entry(_):
                    rf = h.pyboy.register_file
                    rf.A, rf.B, rf.C = species, 0, 0

                h.register_hook('PlayCryWithOffsets', entry)
                try:
                    h.call_routine('PlayCryWithOffsets', limit=600)
                finally:
                    h.unregister_hook('PlayCryWithOffsets', entry)
                h.tick(2)
                for channel in (5, 6):
                    self.assertEqual(bool(h.read8(f'wChannel{channel}Flags2') & 0x20), legacy)
        self.assertFalse(h.hook_errors)


if __name__ == '__main__':
    unittest.main()
