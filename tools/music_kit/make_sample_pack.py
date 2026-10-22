"""Build the composer's DAW sample pack: WAVs + SFZ instruments that sound like
the four Game Boy channels as our engine plays them.

    python3 tools/music_kit/make_sample_pack.py <repo_root> <drum_wav_dir> <out_dir>

Ch1/Ch2: the 4 duty cycles as looped square waves (generated: a square is a square).
Ch3:     our 5 real wave instruments (0-4), read straight from audio/wave_samples.asm.
Ch4:     the 19 drums, recorded out of the running game by record_title.py drums.

Pitch: every channel sounds at the written MIDI pitch. Squares measured +5
cents in PyBoy (2026-10-21). Ch3: the wave channel's period is twice the
squares' for the same register value, and pokemid compensates by writing Ch3
an octave up (measured: MIDI 69 -> x=1899 on Ch3 vs 1750 on Ch1, both 439.8
Hz). So Ch3 is in tune, but its range is an octave lower (MIDI 24-119).
"""

import json
import os
import re
import shutil
import struct
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sf2  # noqa: E402

RATE = 48000
# 11 cycles of A4 (440 Hz) fit exactly in 1200 samples, so the loop is seamless
# and pitch_keycenter is exact with no tune correction.
LOOP_LEN = 1200
LOOP_CYCLES = 11
KEY_A4 = 69
# playable MIDI range per channel (pokemid octave 1-8; outside it is garbage)
SQUARE_KEYS = (36, 127)
WAVE_KEYS = (24, 119)
AMP = 0.45

DUTIES = [("12", 0.125), ("25", 0.25), ("50", 0.5), ("75", 0.75)]  # duty_cycle 0-3
DRUM_NAMES = [
    "snare1", "snare2", "snare3", "snare4", "snare5", "triangle1", "triangle2",
    "snare6", "snare7", "snare8", "snare9", "cymbal1", "cymbal2", "cymbal3",
    "mutedsnare1", "triangle3", "mutedsnare2", "mutedsnare3", "mutedsnare4",
]
# General MIDI percussion note -> Game Boy drum (0-18), in gm_drums.json.
# MuseScore's drumset and most DAW drum kits speak GM, the Game Boy has 19
# noises and no real kick, so the table is a by-ear first guess from the
# recordings (lowest/shortest noise for kick and toms, short high ticks for
# hats, long bright ones for cymbals). convert.ps1 applies it to Ch4 and the
# SoundFont's drum kit plays the same mapping, so what you hear in the DAW is
# what the game plays. Edit gm_drums.json to change both.
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "gm_drums.json")) as _f:
    GM_DRUMS = {int(k): v for k, v in json.load(_f).items()}
SF2_NAME = "Red Rogue Game Boy.sf2"
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def note_name(n):
    return "%s%d" % (NOTE_NAMES[n % 12], n // 12 - 1)


def write_wav(path, samples, loop=None):
    """16-bit mono WAV; with loop=(start, end) also writes a 'smpl' chunk so
    samplers that ignore SFZ still loop it."""
    pcm = b"".join(struct.pack("<h", max(-32768, min(32767, int(round(s * 32767))))) for s in samples)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm)
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / RATE), KEY_A4, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, loop[0], loop[1], 0, 0)
        with open(path, "r+b") as f:
            data = f.read()
            data += b"smpl" + struct.pack("<I", len(smpl)) + smpl
            data = data[:4] + struct.pack("<I", len(data) - 8) + data[8:]
            f.seek(0)
            f.write(data)
            f.truncate()


def looped(fn):
    """LOOP_LEN samples of a periodic shape fn(phase 0..1)."""
    return [fn((i * LOOP_CYCLES / LOOP_LEN) % 1.0) for i in range(LOOP_LEN)]


def read_waves(repo):
    """{index: [32 nibbles]} for .wave0-.wave4 in audio/wave_samples.asm.
    .wave5 has no data of its own (reads the SFX bytes after it, different per
    audio bank), so convert.ps1 clamps to 0-4 and there's nothing to sample."""
    text = open(os.path.join(repo, "audio", "wave_samples.asm")).read()
    waves = {}
    for m in re.finditer(r"^\.wave(\d+)\s*\n((?:\s*dn[^\n]*\n)+)", text, re.M):
        nibs = [int(x) for x in re.findall(r"\d+", "".join(re.findall(r"dn([^\n;]*)", m.group(2))))]
        if len(nibs) != 32:
            sys.exit(".wave%s has %d points, expected 32" % (m.group(1), len(nibs)))
        waves[int(m.group(1))] = nibs
    if sorted(waves) != list(range(5)):
        sys.exit("expected .wave0-.wave4 in wave_samples.asm, found %s" % sorted(waves))
    return waves


def sfz_looped(path, sample, keys):
    with open(path, "w", newline="\r\n") as f:
        f.write("// Red Rogue music kit. Load in any SFZ player (e.g. free sfizz plugin).\n")
        f.write("<region> sample=%s lokey=%d hikey=%d pitch_keycenter=%d\n" % (sample, keys[0], keys[1], KEY_A4))
        f.write("loop_mode=loop_continuous loop_start=0 loop_end=%d amp_veltrack=100 ampeg_release=0.01\n" % (LOOP_LEN - 1))


def read_wav(path):
    with wave.open(path) as w:
        raw = w.readframes(w.getnframes())
    return list(struct.unpack("<%dh" % (len(raw) // 2), raw))


def build_soundfont(path, waves, drums):
    """waves {0-4: 32 nibbles}, drums [19 lists of int16]. Presets (bank 0 unless
    noted): 0-3 Square 12.5/25/50/75, 4-8 Wave 0-4, 9 Drums (keys 0-18 plus the
    GM notes in GM_DRUMS); bank 128 program 0 is the same drum kit for hosts that
    play General MIDI percussion."""
    sf = sf2.SF2("Red Rogue Game Boy", "The four Game Boy channels as the Red Rogue music engine plays them.")

    def pcm(samples):
        return [max(-32768, min(32767, int(round(v * 32767)))) for v in samples]

    for i, (name, duty) in enumerate(DUTIES):
        label = "12.5" if name == "12" else name
        smp = sf.sample("sq" + name, pcm(looped(lambda p: AMP if p < duty else -AMP)), RATE, KEY_A4, (0, LOOP_LEN))
        inst = sf.instrument("Square " + label, [sf2.Zone(smp, SQUARE_KEYS[0], SQUARE_KEYS[1], loop=True)])
        sf.preset("Square " + label, 0, i, inst)
    for idx in range(5):
        nibs = waves[idx]
        smp = sf.sample("wave%d" % idx, pcm(looped(lambda p: AMP * (7.5 - nibs[int(p * 32)]) / 7.5)), RATE, KEY_A4, (0, LOOP_LEN))
        inst = sf.instrument("Wave %d" % idx, [sf2.Zone(smp, WAVE_KEYS[0], WAVE_KEYS[1], loop=True)])
        sf.preset("Wave %d" % idx, 0, 4 + idx, inst)
    smps = [sf.sample("drum%02d" % k, d, RATE, 60) for k, d in enumerate(drums)]
    zones = [sf2.Zone(smps[k], k, k) for k in range(19)]
    zones += [sf2.Zone(smps[k], g, g) for g, k in sorted(GM_DRUMS.items())]
    kit = sf.instrument("Game Boy Drums", zones)
    sf.preset("Drums", 0, 9, kit)
    sf.preset("Game Boy Drums", 128, 0, kit)
    sf.write(path)


def build(repo, drum_dir, out):
    if os.path.exists(out):
        shutil.rmtree(out)
    for d in ("Ch1 Ch2 - Square", "Ch3 - Wave", "Ch4 - Drums"):
        os.makedirs(os.path.join(out, d))

    sq = os.path.join(out, "Ch1 Ch2 - Square")
    for name, duty in DUTIES:
        base = "square_duty%s" % name
        write_wav(os.path.join(sq, base + ".wav"), looped(lambda p: AMP if p < duty else -AMP), (0, LOOP_LEN - 1))
        sfz_looped(os.path.join(sq, base + ".sfz"), base + ".wav", SQUARE_KEYS)

    wv = os.path.join(out, "Ch3 - Wave")
    for idx, nibs in read_waves(repo).items():
        base = "wave%d" % idx
        # GB DAC: nibble 0..15 -> +1..-1 (sign doesn't matter for timbre); keep stair steps
        write_wav(os.path.join(wv, base + ".wav"), looped(lambda p: AMP * (7.5 - nibs[int(p * 32)]) / 7.5), (0, LOOP_LEN - 1))
        sfz_looped(os.path.join(wv, base + ".sfz"), base + ".wav", WAVE_KEYS)

    dr = os.path.join(out, "Ch4 - Drums")
    raw = []
    for k in range(len(DRUM_NAMES)):
        src = os.path.join(drum_dir, "drum_%02d.wav" % k)
        if not os.path.exists(src):
            sys.exit("missing %s (run record_title.py drums first)" % src)
        raw.append(read_wav(src))
    # the recordings peak at about -20 dB; bring the loudest up to the squares' level
    gain = AMP * 32767 / max(abs(v) for d in raw for v in d)
    drums = [[max(-32768, min(32767, int(round(v * gain)))) for v in d] for d in raw]
    lines = ["// Red Rogue music kit: the 19 Game Boy drums on MIDI notes 0-18, recorded from the game."]
    for k, name in enumerate(DRUM_NAMES):
        dst = "%02d_%s_%s.wav" % (k, note_name(k).replace("#", "s"), name)
        write_wav(os.path.join(dr, dst), [v / 32767 for v in drums[k]])
        lines.append("<region> sample=%s key=%d loop_mode=one_shot amp_veltrack=0" % (dst, k))
    with open(os.path.join(dr, "GameBoy_Drums.sfz"), "w", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")

    build_soundfont(os.path.join(out, SF2_NAME), read_waves(repo), drums)

    print("sample pack: %s" % out)


def main():
    build(*sys.argv[1:4])


if __name__ == "__main__":
    main()
