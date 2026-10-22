"""Record title-screen audio out of a music-kit test ROM with PyBoy.

    python3 tools/music_kit/record_title.py drums <test.gbc> <test.map> <out_dir>
    python3 tools/music_kit/record_title.py wav   <test.gbc> <test.map> <seconds> <out.wav>
    python3 tools/music_kit/record_title.py pitch <test.gbc> <test.map>

We hook HOME PlaySound and start the clock when it's called with the
title-music id, so timing is anchored to the engine, not guessed from audio.

drums: the ROM must be a kit build of test_midis.py's drumtest.mid (drum k
  one bar after drum k-1). Each slice starts at its first audible sample and
  ends after 60 ms of silence.
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
    """Return {name: (bank, addr)} from an rgblink map."""
    syms, bank = {}, None
    with open(path) as f:
        for line in f:
            m = re.match(r"^(ROM0|ROMX) bank #(\d+):", line)
            if m:
                bank = 0 if m.group(1) == "ROM0" else int(m.group(2))
                continue
            if re.match(r"^\S", line):
                bank = None
                continue
            m = re.match(r"^\s+\$([0-9a-f]{4}) = (\S+)$", line)
            if m and bank is not None:
                syms[m.group(2)] = (bank, int(m.group(1), 16))
    return syms


def record(rom, mapfile, seconds):
    """Return mono int16 samples (L+R) starting at the title song's PlaySound."""
    syms = map_symbols(mapfile)
    music_id = (syms["Music_TitleScreen"][1] - syms["SFX_Headers_1"][1]) // 3
    ps_bank, ps_addr = syms["PlaySound"]

    pyboy = PyBoy(rom, window="null", sound_emulated=True, sound_sample_rate=RATE, sound_volume=100)
    pyboy.set_emulation_speed(0)
    started = []

    def on_playsound(_):
        if not started and pyboy.register_file.A == music_id:
            started.append(True)

    pyboy.hook_register(ps_bank, ps_addr, on_playsound, None)
    frames = 0
    while not started:
        pyboy.tick(1, False, True)
        frames += 1
        if frames > 60 * 120:
            sys.exit("title music never started (no PlaySound with id %#x in 120 s)" % music_id)

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
    return audio[:, 0] + audio[:, 1]


def write_wav(path, mono):
    pcm = np.clip(mono.astype(np.int32) * 128, -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def sounding_spans(mono):
    """[(start, end)] of audible regions separated by >= TAIL_SILENCE_S of silence."""
    loud = np.nonzero(np.abs(mono) > THRESH)[0]
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
    """Fundamental from autocorrelation: the shortest lag that repeats the
    waveform almost as well as the best lag does. Zero-crossing counts are
    fooled by pulse and wave shapes with several crossings per period."""
    seg = seg.astype(np.float64) - seg.mean()
    n = len(seg)
    spec = np.fft.rfft(seg, 2 * n)
    ac = np.fft.irfft(spec * np.conj(spec))[:n]
    ac /= ac[0]
    lo, hi = int(RATE / 4000), int(RATE / 30)
    win = ac[lo:hi]
    best = win.max()
    lag = lo + int(np.nonzero(win >= 0.9 * best)[0][0])
    # refine to the local peak around that lag, with parabolic interpolation
    while lag + 1 < hi and ac[lag + 1] > ac[lag]:
        lag += 1
    a, b, c = ac[lag - 1], ac[lag], ac[lag + 1]
    shift = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) else 0.0
    return RATE / (lag + shift)


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


def main():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    cmd = sys.argv[1]
    if cmd == "drums":
        cmd_drums(*sys.argv[2:5])
    elif cmd == "wav":
        rom, mapfile, seconds, out = sys.argv[2:6]
        write_wav(out, record(rom, mapfile, float(seconds)))
    elif cmd == "pitch":
        cmd_pitch(*sys.argv[2:4])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
