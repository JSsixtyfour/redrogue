"""Minimal SoundFont 2.01 writer, no dependencies.

Used by make_sample_pack.py to give MuseScore, FL Studio (Fruity SoundFont
Player / DirectWave) and any other SF2 host the Game Boy channels. Supports
exactly what the kit needs: 16-bit mono samples (looped or one-shot), one
sample per instrument zone with a key range, and presets by bank/program.

    sf = SF2("Red Rogue Game Boy")
    s = sf.sample("sq50", pcm, 48000, root_key=69, loop=(0, 1200))
    i = sf.instrument("Square 50", [Zone(s, 36, 127, loop=True)])
    sf.preset("Square 50", bank=0, program=2, instrument=i)
    sf.write("gb.sf2")
"""

import struct

# generator operators (SF2 spec 8.1.2)
GEN_ATTACK_VOL_ENV = 34
GEN_RELEASE_VOL_ENV = 38
GEN_INSTRUMENT = 41
GEN_KEY_RANGE = 43
GEN_INITIAL_ATTENUATION = 48
GEN_SAMPLE_ID = 53
GEN_SAMPLE_MODES = 54
GEN_OVERRIDING_ROOT_KEY = 58

PAD = 46  # the spec wants 46 zero points after every sample


class Zone:
    def __init__(self, sample, lo, hi, loop=False, root=None, attenuation=0, release=-7973):
        # release is in timecents: -7973 = 10 ms, so a note-off doesn't click
        self.sample, self.lo, self.hi, self.loop = sample, lo, hi, loop
        self.root, self.attenuation, self.release = root, attenuation, release


def _name(s):
    b = s.encode("ascii")
    if len(b) > 19:
        raise ValueError("SF2 names are 19 characters at most: %r" % s)
    return b + b"\0" * (20 - len(b))


def _chunk(tag, payload):
    assert len(payload) % 2 == 0
    return tag + struct.pack("<I", len(payload)) + payload


def _list(tag, *chunks):
    return _chunk(b"LIST", tag + b"".join(chunks))


def _gen(oper, amount):
    """One 4-byte generator. amount: int (signed), or (lo, hi) bytes for ranges."""
    if isinstance(amount, tuple):
        return struct.pack("<HBB", oper, amount[0], amount[1])
    return struct.pack("<Hh", oper, amount)


class SF2:
    def __init__(self, name, comment=""):
        self.name, self.comment = name, comment
        self.pcm = bytearray()
        self.samples = []      # (name, start, end, loop_start, loop_end, rate, root)
        self.instruments = []  # (name, [Zone])
        self.presets = []      # (name, bank, program, instrument index)

    def sample(self, name, data, rate, root_key, loop=None):
        """data: iterable of ints in -32768..32767. loop=(start, end) in sample
        points relative to the sample start; end is exclusive (the point after
        the loop) and the audio there must continue the loop, so we append a
        copy of the loop's head after the sample."""
        data = list(data)
        start = len(self.pcm) // 2
        self.pcm += struct.pack("<%dh" % len(data), *data)
        end = start + len(data)
        if loop:
            ls, le = start + loop[0], start + loop[1]
            tail = data[loop[0]:loop[0] + PAD]
            tail += [0] * (PAD - len(tail))
        else:
            ls = le = start
            tail = [0] * PAD
        self.pcm += struct.pack("<%dh" % PAD, *tail)
        self.samples.append((name, start, end, ls, le, rate, root_key))
        return len(self.samples) - 1

    def instrument(self, name, zones):
        self.instruments.append((name, zones))
        return len(self.instruments) - 1

    def preset(self, name, bank, program, instrument):
        self.presets.append((name, bank, program, instrument))

    def _pdta(self):
        phdr, pbag, pgen = b"", b"", b""
        for name, bank, prog, inst in sorted(self.presets, key=lambda p: (p[1], p[2])):
            phdr += _name(name) + struct.pack("<HHHIII", prog, bank, len(pbag) // 4, 0, 0, 0)
            pbag += struct.pack("<HH", len(pgen) // 4, 0)
            pgen += _gen(GEN_INSTRUMENT, inst)
        phdr += _name("EOP") + struct.pack("<HHHIII", 0, 0, len(pbag) // 4, 0, 0, 0)
        pbag += struct.pack("<HH", len(pgen) // 4, 0)
        pgen += _gen(0, 0)

        inst, ibag, igen = b"", b"", b""
        for name, zones in self.instruments:
            inst += _name(name) + struct.pack("<H", len(ibag) // 4)
            for z in zones:
                ibag += struct.pack("<HH", len(igen) // 4, 0)
                igen += _gen(GEN_KEY_RANGE, (z.lo, z.hi))
                if z.attenuation:
                    igen += _gen(GEN_INITIAL_ATTENUATION, z.attenuation)
                igen += _gen(GEN_RELEASE_VOL_ENV, z.release)
                if z.loop:
                    igen += _gen(GEN_SAMPLE_MODES, 1)
                if z.root is not None:
                    igen += _gen(GEN_OVERRIDING_ROOT_KEY, z.root)
                igen += _gen(GEN_SAMPLE_ID, z.sample)  # must be the zone's last generator
        inst += _name("EOI") + struct.pack("<H", len(ibag) // 4)
        ibag += struct.pack("<HH", len(igen) // 4, 0)
        igen += _gen(0, 0)

        shdr = b""
        for name, start, end, ls, le, rate, root in self.samples:
            shdr += _name(name) + struct.pack("<IIIIIBbHH", start, end, ls, le, rate, root, 0, 0, 1)
        shdr += _name("EOS") + struct.pack("<IIIIIBbHH", 0, 0, 0, 0, 0, 0, 0, 0, 0)

        mod = b"\0" * 10  # the terminal (empty) modulator record
        return _list(b"pdta", _chunk(b"phdr", phdr), _chunk(b"pbag", pbag), _chunk(b"pmod", mod),
                     _chunk(b"pgen", pgen), _chunk(b"inst", inst), _chunk(b"ibag", ibag),
                     _chunk(b"imod", mod), _chunk(b"igen", igen), _chunk(b"shdr", shdr))

    def write(self, path):
        def z(s):  # zero-terminated, even length
            b = s.encode("ascii") + b"\0"
            return b + (b"\0" if len(b) % 2 else b"")
        info = [_chunk(b"ifil", struct.pack("<HH", 2, 1)), _chunk(b"isng", z("EMU8000")),
                _chunk(b"INAM", z(self.name))]
        if self.comment:
            info.append(_chunk(b"ICMT", z(self.comment)))
        body = b"sfbk" + _list(b"INFO", *info) + _list(b"sdta", _chunk(b"smpl", bytes(self.pcm))) + self._pdta()
        with open(path, "wb") as f:
            f.write(b"RIFF" + struct.pack("<I", len(body)) + body)
