"""Prove two kit test ROMs play the same music (song_optimize.py's real check).

    python3 tools/music_kit/song_audio_compare.py A.gbc B.gbc [--frames N]

Boots each ROM headless in PyBoy with no input (the kit plays its song on the
title screen) and compares, after every frame:
  1. each music channel's engine state (wChannel1-4, read from the ROM's .map),
     except the song's own address and bank, which a different layout moves;
  2. the sound registers NR10-NR51 ($FF10-$FF25).
Equal on every frame = the same notes, envelopes, frequencies and timing.

Raw samples are reported but not required to match. Different song bytes make
the engine finish a few hundred cycles sooner or later inside the frame, so a
channel 3 trigger lands on another wave-RAM byte (wave RAM reads back the byte
being played; measured 2026-11-26 on SuicuneBattle: every register equal, only
$FF30-$FF3F differed). Inaudible, but it breaks sample equality.
"""

import argparse
import hashlib
import os
import re
import sys

os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
from pyboy import PyBoy  # noqa: E402

# channel_struct offsets (macros/ram.asm) that describe how the song is stored, not
# what it sounds like:
#   2 MusicBank, 6-7 MusicAddress, 8-9 LastMusicAddress (layout);
#   41 NoteLength: the speed, which the optimizer re-chooses on purpose. Only
#      SetNoteDuration reads it (low byte of speed * length), and NoteDuration and
#      NoteDurationModifier, which are compared, are that product's result;
#   21 LoopCount: finite-loop bookkeeping, read only by Music_Loop.
# Flags1 (offset 3) is compared without bits 1-2 (in a subroutine, in a loop).
LAYOUT_FIELDS = {2, 6, 7, 8, 9, 21, 41}
FLAGS1, FLAGS1_FLOW_BITS = 3, 0b110


def channel_bases(rom):
    mp = os.path.splitext(rom)[0] + ".map"
    text = open(mp).read()
    bases = [int(re.search(r"\$([0-9a-f]{4}) = wChannel%d\b" % i, text).group(1), 16) for i in (1, 2, 3, 4, 5)]
    return bases[:4], bases[1] - bases[0]


def capture(rom, frames):
    bases, stride = channel_bases(rom)
    pb = PyBoy(rom, window="null", sound_emulated=True, sound_volume=0)
    out, first_sound = [], None
    for f in range(frames):
        pb.tick(1, False, True)
        mem = pb.memory
        chans = tuple(bytes((mem[b + i] & ~FLAGS1_FLOW_BITS & 0xFF) if i == FLAGS1 else mem[b + i]
                            for i in range(stride) if i not in LAYOUT_FIELDS) for b in bases)
        regs = bytes(mem[a] for a in range(0xFF10, 0xFF26))
        buf = bytes(pb.sound.ndarray.tobytes())
        if first_sound is None and any(buf):
            first_sound = f
        out.append((chans, regs, hashlib.blake2b(buf, digest_size=12).digest()))
    pb.stop(save=False)
    return out, first_sound


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--frames", type=int, default=12000)
    a = ap.parse_args()
    ra, sa = capture(a.a, a.frames)
    rb, sb = capture(a.b, a.frames)
    bad_state = [f for f in range(a.frames) if ra[f][0] != rb[f][0]]
    bad_regs = [f for f in range(a.frames) if ra[f][1] != rb[f][1]]
    samples = sum(ra[f][2] != rb[f][2] for f in range(a.frames))
    print("frames %d, first sound A=%s B=%s, raw-sample frames differing: %d (informational)"
          % (a.frames, sa, sb, samples))
    if not bad_state and not bad_regs:
        print("SAME MUSIC: channel state and NR10-NR51 equal on all %d frames" % a.frames)
        return 0
    if bad_state:
        f = bad_state[0]
        for c in range(4):
            if ra[f][0][c] != rb[f][0][c]:
                print("channel %d state differs first at frame %d" % (c + 1, f))
                break
    if bad_regs:
        f = bad_regs[0]
        diffs = [(hex(0xFF10 + i), ra[f][1][i], rb[f][1][i]) for i in range(0x16) if ra[f][1][i] != rb[f][1][i]]
        print("registers differ first at frame %d: %s" % (f, diffs))
    print("DIFFERENT MUSIC (%d state frames, %d register frames)" % (len(bad_state), len(bad_regs)))
    return 1


if __name__ == "__main__":
    sys.exit(main())
