"""Record title-screen audio out of a music-kit test ROM with PyBoy.

    python3 tools/music_kit/record_title.py drums <test.gbc> <test.map> <out_dir>
    python3 tools/music_kit/record_title.py wav   <test.gbc> <test.map> <seconds> <out.wav> [--stereo]
    python3 tools/music_kit/record_title.py kitswitch <test.gbc> <test.map>
    python3 tools/music_kit/record_title.py pitch <test.gbc> <test.map>

We hook HOME PlayMusic and start the clock when it's called with the
preview song's id (its row in the Music table, read from the ROM), so timing
is anchored to the engine, not guessed from audio.

drums: the ROM must be a kit build of test_midis.py's drumtest.mid (drum k
  one bar after drum k-1). Each slice starts at its first audible sample and
  ends after 60 ms of silence.
kitswitch: the ROM must be a kit build of test_midis.py's kitswitch.mid; counts
  the drum hits over two loop passes and compares the passes (proves the
  drum kit is back at kit 0 at every loop and subroutine boundary).
wav: mono (L+R) by default; --stereo writes the 2-channel recording.
pitch: the ROM must be a kit build of pitchtest.mid; prints the measured
  frequency of each test note against what its MIDI number means.

Runs under WSL (PyBoy 2.x).
"""

import math
import os
import re
import sys
import wave

import numpy as np
from pyboy import PyBoy

RATE = 48000  # PyBoy requires a multiple of 60
THRESH = 3    # in mono units (L+R int8); silence is exactly 0
TAIL_SILENCE_S = 0.06


def map_symbols(path):
    """Return {name: (bank, addr)} from an rgblink map. WRAM symbols get
    bank "wram" (WRAM0) or "wram<N>" (WRAMX)."""
    syms, bank = {}, None
    with open(path) as f:
        for line in f:
            m = re.match(r"^(ROM0|ROMX|WRAM0|WRAMX) bank #(\d+):", line)
            if m:
                kind = m.group(1)
                bank = {"ROM0": 0, "WRAM0": "wram"}.get(kind, int(m.group(2)) if kind == "ROMX" else "wram" + m.group(2))
                continue
            if re.match(r"^\S", line):
                bank = None
                continue
            m = re.match(r"^\s+\$([0-9a-f]{4}) = (\S+)$", line)
            if m and bank is not None:
                syms[m.group(2)] = (bank, int(m.group(1), 16))
    return syms


def music_id(rom, syms, label):
    """The song id whose Music table row (bank, address) is `label`.

    Crystal engine (crysaudio/music_pointers_red.asm): ids index a table of
    3-byte `dba` rows, so the id is the row, read back from the ROM itself."""
    bank, addr = syms[label]
    table_bank, table = syms["Music"]
    with open(rom, "rb") as f:
        data = f.read()
    base = table_bank * 0x4000 + table - 0x4000
    row = bytes((bank, addr & 0xFF, addr >> 8))
    for song in range(256):
        if data[base + 3 * song: base + 3 * song + 3] == row:
            return song
    sys.exit("%s is not in the Music table" % label)


def record(rom, mapfile, seconds, label="Music_KitPreview", stereo=False):
    """Return int16 samples starting at the PlayMusic for `label`: mono (L+R), or
    an (n, 2) left/right array with stereo=True."""
    syms = map_symbols(mapfile)
    song = music_id(rom, syms, label)
    pm_bank, pm_addr = syms["PlayMusic"]

    pyboy = PyBoy(rom, window="null", sound_emulated=True, sound_sample_rate=RATE, sound_volume=100)
    pyboy.set_emulation_speed(0)
    started = []

    # HOME PlayMusic takes the song id in a (home/audio.asm).
    def on_playmusic(_):
        if not started and pyboy.register_file.A == song:
            started.append(True)

    pyboy.hook_register(pm_bank, pm_addr, on_playmusic, None)
    frames = 0
    while not started:
        pyboy.tick(1, False, True)
        frames += 1
        if frames > 60 * 120:
            sys.exit("%s never started (no PlayMusic with id %#x within 120 s)" % (label, song))

    # The hook fired during the last tick; the song's first engine update is
    # in the next VBlank, so recording from the next buffer loses nothing.
    chunks, got, need = [], 0, int(seconds * RATE)
    while got < need:
        pyboy.tick(1, False, True)
        buf = pyboy.sound.ndarray.copy()
        chunks.append(buf)
        got += len(buf)
    pyboy.stop(save=False)
    audio = np.concatenate(chunks).astype(np.int16)
    return audio if stereo else audio[:, 0] + audio[:, 1]


def write_wav(path, mono):
    # mono is L+R (two int8 channels summed); stereo keeps each side, so it scales by 256.
    pcm = np.clip(mono.astype(np.int32) * (128 if mono.ndim == 1 else 256), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1 if mono.ndim == 1 else 2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def sounding_spans(mono):
    """[(start, end)] of audible regions separated by >= TAIL_SILENCE_S of silence."""
    # PyBoy can emit a lone one-sample spike once per frame (measured 2026-10-29 after
    # the engine's sfx-channel skip: same buffer index at 48 and 240 kHz, so it isn't
    # CPU-timed, and the pre-skip engine shows it at 240 kHz too). It made the drum
    # test hear one 39 s "hit". No real sound is one sample long, so drop lone samples.
    mask = np.abs(mono) > THRESH
    lone = mask & ~np.concatenate(([False], mask[:-1])) & ~np.concatenate((mask[1:], [False]))
    loud = np.nonzero(mask & ~lone)[0]
    if len(loud) == 0:
        return []
    gap = int(TAIL_SILENCE_S * RATE)
    breaks = np.nonzero(np.diff(loud) > gap)[0]
    starts = np.concatenate(([loud[0]], loud[breaks + 1]))
    ends = np.concatenate((loud[breaks], [loud[-1]]))
    return list(zip(starts, ends))


def cmd_drums(rom, mapfile, out, count=19):
    os.makedirs(out, exist_ok=True)
    mono = record(rom, mapfile, count * 2.0 + 1)
    spans = sounding_spans(mono)
    if len(spans) != count:
        sys.exit("expected %d separate drum hits, heard %d: %s" % (count, len(spans), [(s / RATE, e / RATE) for s, e in spans]))
    gap = int(TAIL_SILENCE_S * RATE)
    print("drum  start_s  length_s")
    for k, (s, e) in enumerate(spans):
        write_wav(os.path.join(out, "drum_%02d.wav" % k), mono[s:e + gap])
        print("%4d  %7.3f  %8.3f" % (k, s / RATE, (e + gap - s) / RATE))


def measure_hz(seg):
    """Fundamental from the spectrum: the lowest peak that is at least half as
    strong as the strongest one. Autocorrelation (used before 2026-10-29) read
    Ch3's wave shapes up to +108 cents sharp and failed outright on some
    notes, while the spectrum matches the frequency the engine wrote
    (CRYSTAL_AUDIO_PHASE3_SPEC.md B7). Returns None if there is no peak."""
    seg = seg.astype(np.float64) - seg.mean()
    size = 1 << 18
    sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), size))
    fr = np.fft.rfftfreq(size, 1.0 / RATE)
    band = np.nonzero((fr >= 30) & (fr <= 4000))[0]
    peak = sp[band].max()
    if not np.isfinite(peak) or peak <= 0:
        print("measure_hz: silent or non-finite segment")
        return None
    for i in band:
        if sp[i] >= 0.5 * peak and sp[i] >= sp[i - 1] and sp[i] >= sp[i + 1]:
            a, b, c = sp[i - 1], sp[i], sp[i + 1]
            shift = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) else 0.0
            return float(fr[i] + shift * (fr[1] - fr[0]))
    print("measure_hz: no spectral peak")
    return None


def cmd_pitch(rom, mapfile):
    from test_midis import PITCH_NOTES
    mono = record(rom, mapfile, len(PITCH_NOTES) * 2.0 + 1)
    spans = sounding_spans(mono)
    if len(spans) != len(PITCH_NOTES):
        sys.exit("expected %d notes, heard %d" % (len(PITCH_NOTES), len(spans)))
    print("track  midi  expected_hz  measured_hz  offset")
    for (ch, note), (s, e) in zip(PITCH_NOTES, spans):
        # skip attack, measure the steady middle
        mid = mono[s + (e - s) // 4: e - (e - s) // 4]
        hz = measure_hz(mid)
        exp = 440.0 * 2 ** ((note - 69) / 12)
        cents = 1200 * math.log2(hz / exp) if hz else float("nan")
        print("%5s  %4d  %11.2f  %11.2f  %+7.0f cents" % (ch, note, exp, hz or 0, cents))


def cmd_kitswitch(rom, mapfile):
    """kitswitch.mid: two loop passes must give 2 * KITSWITCH_HITS hits, and
    pass 2 must sound like pass 1 hit for hit. A subroutine entered or left on
    the wrong drum kit would drop or change hits."""
    from test_midis import KITSWITCH_HITS
    pass_s = 8.0  # 4 bars at 120 BPM
    mono = record(rom, mapfile, 2 * pass_s - 0.2)  # the loop is 8.01 s: stop before pass 3's first hit
    spans = sounding_spans(mono)
    want = 2 * KITSWITCH_HITS
    print("hit  start_s  length_s")
    for k, (s, e) in enumerate(spans):
        print("%3d  %7.3f  %8.3f" % (k, s / RATE, (e - s) / RATE))
    if len(spans) != want:
        sys.exit("kitswitch: expected %d hits over two passes, heard %d" % (want, len(spans)))
    for k in range(KITSWITCH_HITS):
        a, b = spans[k], spans[k + KITSWITCH_HITS]
        la, lb = (a[1] - a[0]) / RATE, (b[1] - b[0]) / RATE
        if abs(la - lb) > 0.06:
            sys.exit("kitswitch: hit %d is %.3f s in pass 1 but %.3f s in pass 2" % (k, la, lb))
    print("kitswitch: %d hits per pass, passes agree" % KITSWITCH_HITS)


def main():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    cmd = sys.argv[1]
    if cmd == "drums":
        cmd_drums(*sys.argv[2:5])
    elif cmd == "wav":
        rom, mapfile, seconds, out = sys.argv[2:6]
        write_wav(out, record(rom, mapfile, float(seconds), stereo="--stereo" in sys.argv[6:]))
    elif cmd == "kitswitch":
        cmd_kitswitch(*sys.argv[2:4])
    elif cmd == "pitch":
        cmd_pitch(*sys.argv[2:4])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
