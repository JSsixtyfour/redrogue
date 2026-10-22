"""Minimal Standard MIDI File (format 1) writer, no dependencies.

Used by the music test kit to generate Template.mid and acceptance-test MIDIs.
Times are in ticks at PPQ ticks per quarter note.
"""

import struct

PPQ = 480


def _varlen(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append(0x80 | (n & 0x7F))
        n >>= 7
    return bytes(reversed(out))


class Track:
    def __init__(self, name=None):
        self.events = []  # (abs_tick, order, bytes)
        if name is not None:
            self.meta(0, 0x03, name.encode("ascii"))

    def _add(self, tick, data, order):
        self.events.append((tick, order, len(self.events), data))

    def meta(self, tick, kind, payload):
        self._add(tick, bytes([0xFF, kind]) + _varlen(len(payload)) + payload, 1)

    def text(self, tick, s):
        self.meta(tick, 0x01, s.encode("ascii"))

    def tempo(self, tick, bpm):
        us = round(60_000_000 / bpm)
        self.meta(tick, 0x51, us.to_bytes(3, "big"))

    def note(self, tick, length, pitch, velocity=100, channel=0):
        # note-offs sort before note-ons and text at the same tick
        self._add(tick, bytes([0x90 | channel, pitch, velocity]), 2)
        self._add(tick + length, bytes([0x80 | channel, pitch, 0]), 0)

    def encode(self):
        body = bytearray()
        last = 0
        for tick, _order, _seq, data in sorted(self.events):
            body += _varlen(tick - last) + data
            last = tick
        body += _varlen(0) + b"\xFF\x2F\x00"
        return b"MTrk" + struct.pack(">I", len(body)) + bytes(body)


def write(path, tracks, ppq=PPQ):
    with open(path, "wb") as f:
        f.write(b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), ppq))
        for t in tracks:
            f.write(t.encode())
