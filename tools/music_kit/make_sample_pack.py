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
import copy
import os
import re
import shutil
import struct
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sf2  # noqa: E402
import dls  # noqa: E402

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


NUM_WAVES = 15  # crysaudio/wave_samples.asm: "only indices 0-E are valid"


def read_waves(repo):
    """{index: [32 nibbles]} for waves 0-14 in crysaudio/wave_samples.asm: one
    uncommented `dn` row of 32 nibbles per wave (0-4 are Red's five). convert.ps1
    clamps Ch3 to 0-14; 15 means "keep the loaded wave"."""
    text = open(os.path.join(repo, "crysaudio", "wave_samples.asm")).read()
    rows = re.findall(r"^\s*dn([^\n;]*)", text, re.M)
    waves = {}
    for idx, row in enumerate(rows):
        nibs = [int(x) for x in re.findall(r"\d+", row)]
        if len(nibs) != 32:
            sys.exit("wave %d has %d points, expected 32" % (idx, len(nibs)))
        waves[idx] = nibs
    if sorted(waves) != list(range(NUM_WAVES)):
        sys.exit("expected waves 0-%d in wave_samples.asm, found %s" % (NUM_WAVES - 1, sorted(waves)))
    return waves


def wave_preset(idx):
    """Waves 0-4 keep kit v1's presets 4-8 (Drums stays 9); 5-14 are 10-19."""
    return 4 + idx if idx < 5 else 5 + idx


def sfz_looped(path, sample, keys, wave_voice=False):
    with open(path, "w", newline="\r\n") as f:
        f.write("// Red Rogue music kit. Load in any SFZ player (e.g. free sfizz plugin).\n")
        for lo, hi, db in ([(1, 42, -12.0412), (43, 84, -6.0206), (85, 127, 0)] if wave_voice else [(1, 127, 0)]):
            f.write("<region> sample=%s lokey=%d hikey=%d pitch_keycenter=%d lovel=%d hivel=%d volume=%s\n" % (sample, keys[0], keys[1], KEY_A4, lo, hi, db))
            f.write("loop_mode=loop_continuous loop_start=0 loop_end=%d amp_veltrack=%d ampeg_release=0.01\n" % (LOOP_LEN - 1, 0 if wave_voice else 100))


def read_wav(path):
    with wave.open(path) as w:
        raw = w.readframes(w.getnframes())
    return list(struct.unpack("<%dh" % (len(raw) // 2), raw))


def build_soundfont(path, waves, drums):
    """waves {0-14: 32 nibbles}, drums [19 lists of int16]. Presets (bank 0 unless
    noted): 0-3 Square 12.5/25/50/75, 4-8 Wave 0-4, 9 Drums (keys 0-18 plus the
    GM notes in GM_DRUMS), 10-19 Wave 5-14; bank 128 program 0 is the same drum
    kit for hosts that play General MIDI percussion. Synth previews are
    approximate; the game preview is authoritative."""
    sf = sf2.SF2("Red Rogue Game Boy", "The four Game Boy channels as the Red Rogue music engine plays them.")

    def pcm(samples):
        return [max(-32768, min(32767, int(round(v * 32767)))) for v in samples]

    for i, (name, duty) in enumerate(DUTIES):
        label = "12.5" if name == "12" else name
        smp = sf.sample("sq" + name, pcm(looped(lambda p: AMP if p < duty else -AMP)), RATE, KEY_A4, (0, LOOP_LEN))
        inst = sf.instrument("Square " + label, [sf2.Zone(smp, SQUARE_KEYS[0], SQUARE_KEYS[1], loop=True)])
        sf.preset("Square " + label, 0, i, inst)
    for idx in range(NUM_WAVES):
        nibs = waves[idx]
        smp = sf.sample("wave%d" % idx, pcm(looped(lambda p: AMP * (7.5 - nibs[int(p * 32)]) / 7.5)), RATE, KEY_A4, (0, LOOP_LEN))
        inst = sf.instrument("Wave %d" % idx, [
            sf2.Zone(smp, *WAVE_KEYS, loop=True, velocity=(lo, hi),
                     attenuation=atten, fixed_velocity=True)
            for lo, hi, atten in [(1, 42, 120), (43, 84, 60), (85, 127, 0)]])
        sf.preset("Wave %d" % idx, 0, wave_preset(idx), inst)
    smps = [sf.sample("drum%02d" % k, d, RATE, 60) for k, d in enumerate(drums)]
    # Each alias must play the recording at its original pitch, not transpose
    # it from the sample's arbitrary root (60).
    zones = [sf2.Zone(smps[k], k, k, root=k) for k in range(19)]
    zones += [sf2.Zone(smps[k], g, g, root=g) for g, k in sorted(GM_DRUMS.items())]
    kit = sf.instrument("Game Boy Drums", zones)
    sf.preset("Drums", 0, 9, kit)
    sf.preset("Game Boy Drums", 128, 0, kit)
    sf.write(path)
    # DLS1 ignores velocity ranges: never export stacked SF2 velocity zones.
    # Keep the original full-volume wave presets and add fixed-level choices.
    ds = copy.deepcopy(sf)
    for idx in range(NUM_WAVES):
        inst_id = 4 + idx
        name, zones = ds.instruments[inst_id]
        zone = copy.deepcopy(zones[-1])
        zone.velocity = (0, 127)
        ds.instruments[inst_id] = (name, [zone])
        _, start, end, ls, le, rate, root = ds.samples[zone.sample]
        source = struct.unpack('<%dh' % (end-start), ds.pcm[start*2:end*2])
        for offset, percent in enumerate((25, 50)):
            sample = ds.sample('w%d_%d' % (idx, percent),
                               [round(v * percent / 100) for v in source],
                               rate, root, (ls-start, le-start))
            label = 'Wave %d %d%%' % (idx, percent)
            inst = ds.instrument(label, [sf2.Zone(sample, *WAVE_KEYS, loop=True)])
            ds.preset(label, 0, 20 + idx * 2 + offset, inst)
    dls.write(os.path.splitext(path)[0] + '.dls', ds)


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
        sfz_looped(os.path.join(wv, base + ".sfz"), base + ".wav", WAVE_KEYS, wave_voice=True)

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
    write_dls_guide(os.path.join(out, 'DLS QUICK START.txt'))

    print("sample pack: %s" % out)


def write_dls_guide(path):
    guide = '''RED ROGUE DLS: FL STUDIO QUICK START

Load Fruity LSD in a Mixer effect slot. Browse to Red Rogue Game Boy.dls.
Set LSD's port to 1; set each MIDI Out channel to port 1 too.
Use MIDI channels 1, 2, 3 for melody and channel 10 for drums.
Select instruments by NAME in LSD: two Squares, one Wave, Game Boy Drums.
The melodic Drums preset is also available for hosts using a normal channel.
Keep the DLS alongside your project: FL stores its path, not the bank itself.

Name exported tracks Ch1 Square 50, Ch2 Square 25, Ch3 Wave 6, Ch4,
substituting your chosen square duties/wave. Program changes are discarded
by the tester: choosing an LSD patch does not set the game's timbre.
Retain the Template.mid Loop track for looping. Export MIDI and use the
existing DROP YOUR SONG HERE tester. This is a sample-bank add-on, not a ROM.

VOLUME IN THE GAME (ordinary MIDI notes, without custom envelope commands)
Ch1/Ch2 use floor(MIDI velocity / 8), volume values 0 through 15:
'''
    for level in range(16):
        guide += '  %3d-%3d -> %2d%s\n' % (max(1, level * 8), level * 8 + 7,
                                             level, ' (silent)' if level == 0 else '')
    guide += '''Velocity 0 is note-off. These are MIDI 0-127 values, not FL percentages.
Ch3 in kit version 4: MIDI 1-42 = 25%, 43-84 = 50%, 85-127 = 100%.
Older testers forced Ch3 to 100%. Use the NEW tester, not just this DLS.
Existing MIDI may now sound quieter: set Ch3 notes to 85-127 to retain the
old full-volume sound. These percentages are amplitude, not perceived loudness.
Ch4 uses each recorded drum's fixed envelope, regardless of velocity.
When drum hits overlap, the tester keeps the highest-velocity simultaneous
hit (lowest MIDI note breaks ties) and cuts a hit at the next hit.
Mixer faders and MIDI CC volume automation do not become game dynamics.

DLS Level 1 square dynamics are continuous and only approximate the game's
steps. DLS1 cannot reliably select velocity layers. Its Wave N presets stay
at 100%; choose Wave N 25% or Wave N 50% manually to preview quieter notes.
These patches do not set exported velocity: also set the MIDI velocity band.
SF2/SFZ waves switch the three bands automatically (SF2 attenuation rounded
to 0.1 dB). Drum patches override velocity loudness. All previews still
differ from the Game Boy's mixing, envelopes, filtering and single-voice
retrigger behavior. Check final balance and rapid drum sequences in the
tester. Do not compensate by altering the composition to match a DAW mixer.

DRUMS: USE MIDI NUMBERS, NOT OCTAVE LABELS
Hosts disagree on octave names. Native keys 0-18 select the 19 GB sounds;
GM keys 35-81 are aliases using exactly the tester's gm_drums.json mapping.
Keys 19-34 and 82-127 are unsupported. There is no acoustic kick drum.
Every mapped key plays the recording at its original pitch.

  MIDI   GB sound          GM aliases
'''
    for key, name in enumerate(DRUM_NAMES):
        aliases = ', '.join(str(g) for g, k in sorted(GM_DRUMS.items()) if k == key)
        guide += '  %3d    %-17s %s\n' % (key, name, aliases)
    guide += '''
PROGRAMS (zero-based; some hosts display these as 1-20)
0-3: Square 12.5/25/50/75; 4-8: Wave 0-4; 9: Drums;
10-19: Wave 5-14. Percussion bank: program 0 = Game Boy Drums.
20-49: pairs Wave 0 25%/50% through Wave 14 25%/50% (DLS only).
Squares support MIDI 36-127; waves support MIDI 24-119.

ACCEPTANCE IN FL (not automated here)
Load the bank; verify squares sustain until note-off and all waves sound.
Compare native snare key 0 with GM key 38: same sound, same pitch.
Compare native key 3 with GM keys 35/36: same sound, same pitch.
Audition all 19 native keys against the tester, then a rapid drum sequence.
Compare Ch1 velocities 7/8, 63/64, 119/120 in the tester. For Ch3 compare
42/43 and 84/85, then loop through quiet/loud notes using the same wave.
Drums should not change loudness with velocity. Check exported MIDI values.

FL reference:
https://www.image-line.com/fl-studio-learning/fl-studio-beta-online-manual/html/plugins/Fruity%20LSD.htm
'''
    with open(path, 'w', newline='\r\n') as f:
        f.write(guide)


def main():
    build(*sys.argv[1:4])


if __name__ == "__main__":
    main()
