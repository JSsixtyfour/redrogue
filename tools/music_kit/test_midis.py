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


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    drumtest(os.path.join(out, "drumtest.mid"))
    pitchtest(os.path.join(out, "pitchtest.mid"))


if __name__ == "__main__":
    main()
