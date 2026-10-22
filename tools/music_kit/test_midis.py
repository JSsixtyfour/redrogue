"""Generate the MIDIs the music kit uses for sample capture and acceptance tests.

    python3 tools/music_kit/test_midis.py <out_dir>

drumtest.mid: Ch4 plays drums 0-18 (MIDI notes) one per bar at 120 BPM, so
drum k starts exactly 2*k seconds after the song starts. Capture slices on
that grid. No begin/end: plays once.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import smf  # noqa: E402

Q = smf.PPQ
BAR = 4 * Q
DRUM_SPACING_S = 2.0  # one 4/4 bar at 120 BPM


def drumtest(path):
    t0 = smf.Track()
    t0.tempo(0, 120)
    ch4 = smf.Track("Ch4")
    for k in range(19):
        ch4.note(k * BAR, Q // 4, k)
    ch4.text(19 * BAR, "end")
    smf.write(path, [t0, ch4])


# (track, MIDI note) played one per bar, for record_title.py pitch.
PITCH_NOTES = [("Ch1", 69), ("Ch1", 45), ("Ch2", 69), ("Ch3", 69), ("Ch3", 45), ("Ch3", 81)]


def pitchtest(path):
    """pitchtest.mid: each PITCH_NOTES entry for 2 beats, one per bar, full velocity."""
    t0 = smf.Track()
    t0.tempo(0, 120)
    tracks = {ch: smf.Track(ch) for ch in ("Ch1", "Ch2", "Ch3")}
    for k, (ch, note) in enumerate(PITCH_NOTES):
        tracks[ch].note(k * BAR, 2 * Q, note, 127)
    for t in tracks.values():
        t.text(len(PITCH_NOTES) * BAR, "end")
    smf.write(path, [t0] + list(tracks.values()))


def template(path):
    """Template.mid: the composer's starting point. 4 looping bars at 120 BPM
    (19200/120 = 160, exact), all four tracks named and playing, with one
    effect marker per square track so he can see how markers look.

    Ch3 sounds an octave below written (see make_sample_pack.py), so the bass
    is written an octave up from where it should sound."""
    C, D, E, F, G, A, B = 0, 2, 4, 5, 7, 9, 11

    def n(name, octave):  # MIDI note, C4 = 60
        return 12 * (octave + 1) + name

    t0 = smf.Track()
    t0.tempo(0, 120)
    ch1, ch2, ch3, ch4 = (smf.Track("Ch%d" % i) for i in range(1, 5))
    for t in (ch1, ch2, ch3, ch4):
        t.text(0, "begin")
        t.text(4 * BAR, "end")
    ch1.text(0, "duty_cycle 2")
    ch2.text(0, "duty_cycle 1")

    # Ch1 melody: (note, start beat, length beats)
    melody = [(n(E, 5), 0, 1), (n(G, 5), 1, 1), (n(C, 6), 2, 2),
              (n(B, 5), 4, 1), (n(G, 5), 5, 1), (n(A, 5), 6, 2),
              (n(F, 5), 8, 1), (n(A, 5), 9, 1), (n(D, 6), 10, 2),
              (n(C, 6), 12, 1), (n(B, 5), 13, 1), (n(G, 5), 14, 2)]
    for note, start, length in melody:
        ch1.note(start * Q, length * Q - Q // 8, note, 112)
    # Ch2 harmony: one held chord tone per bar, quieter
    for bar, note in enumerate([n(C, 5), n(E, 5), n(F, 5), n(D, 5)]):
        ch2.note(bar * BAR, BAR - Q // 4, note, 80)
    # Ch3 bass: roots on eighth notes (written an octave up)
    for bar, root in enumerate([n(C, 4), n(E, 4), n(F, 4), n(G, 4)]):
        for k in range(8):
            ch3.note(bar * BAR + k * Q // 2, Q // 2 - Q // 16, root if k % 2 == 0 else root + 12, 100)
    # Ch4 drums: mutedsnare1 (14) on 1 and 3, snare1 (0) on 2 and 4, triangle1 (5) on off-beats
    for bar in range(4):
        for beat in range(4):
            ch4.note(bar * BAR + beat * Q, Q // 4, 14 if beat % 2 == 0 else 0, 100)
            ch4.note(bar * BAR + beat * Q + Q // 2, Q // 4, 5, 100)
    smf.write(path, [t0, ch1, ch2, ch3, ch4])


def write_all(out):
    os.makedirs(out, exist_ok=True)
    drumtest(os.path.join(out, "drumtest.mid"))
    pitchtest(os.path.join(out, "pitchtest.mid"))
    template(os.path.join(out, "Template.mid"))


def main():
    write_all(sys.argv[1])


if __name__ == "__main__":
    main()
