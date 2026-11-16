"""Regression checks for drum pitch aliases and DLS pool/loop addressing.

Run: python -m unittest discover -s tools/music_kit -p test_dls.py
"""
import pathlib
import struct
import tempfile
import unittest

import make_sample_pack as pack


def chunks(data, start=0):
    while start < len(data):
        tag, size = struct.unpack_from('<4sI', data, start)
        end = start + 8 + size
        assert end <= len(data)
        yield tag, data[start + 8:end], start
        start = end + size % 2
    assert start == len(data)


def child(data, tag):
    return next(body for kind, body, _ in chunks(data) if kind == tag)


class DLSExportTest(unittest.TestCase):
    def test_roundtrip_regions_and_pool(self):
        with tempfile.TemporaryDirectory() as tmp:
            sf = pathlib.Path(tmp) / 'test.sf2'
            # Unique PCM identifies each drum independently of names/indices.
            drums = [[k + 1] * 48 for k in range(19)]
            pack.build_soundfont(str(sf), {k: list(range(16)) * 2 for k in range(15)}, drums)
            data = sf.with_suffix('.dls').read_bytes()
            self.assertEqual(data[:4], b'RIFF')
            self.assertEqual(struct.unpack_from('<I', data, 4)[0], len(data) - 8)
            self.assertEqual(data[8:12], b'DLS ')
            top = list(chunks(data, 12))
            lists = {b[:4]: b[4:] for t, b, _ in top if t == b'LIST'}
            pool = child(data[12:], b'ptbl')
            size, count = struct.unpack_from('<II', pool)
            self.assertEqual((size, count), (8, 38))
            offsets = struct.unpack_from('<38I', pool, 8)
            waves = list(chunks(lists[b'wvpl']))
            self.assertEqual(tuple(p for _, _, p in waves), offsets)
            instruments = list(chunks(lists[b'lins']))
            self.assertEqual(len(instruments), 21)
            aliases = dict(enumerate(range(19))) | pack.GM_DRUMS
            drum_count = 0
            for _, ins, _ in instruments:
                self.assertEqual(ins[:4], b'ins ')
                count, bank, program = struct.unpack('<III', child(ins[4:], b'insh'))
                regions = next(b[4:] for t, b, _ in chunks(ins[4:]) if t == b'LIST' and b[:4] == b'lrgn')
                self.assertEqual(len(list(chunks(regions))), count)
                is_drum = program == 9 or bank == 0x80000000
                if is_drum:
                    drum_count += 1
                    self.assertEqual(count, len(aliases))
                for _, region, _ in chunks(regions):
                    lo, hi, vlo, vhi, _, _ = struct.unpack('<6H', child(region[4:], b'rgnh'))
                    self.assertEqual((vlo, vhi), (0, 127))
                    options = child(region[4:], b'wsmp')
                    _, root, _, _, _, loops = struct.unpack_from('<IHhiII', options)
                    sample = struct.unpack('<HHII', child(region[4:], b'wlnk'))[3]
                    pcm = child(waves[sample][1][4:], b'data')
                    if is_drum:
                        self.assertEqual((lo, hi, root, loops), (lo, lo, lo, 0))
                        self.assertEqual(struct.unpack('<48h', pcm), tuple(drums[aliases[lo]]))
                    else:
                        self.assertEqual(root, 69)
                        self.assertEqual(loops, 1)
                        self.assertEqual(struct.unpack_from('<IIII', options, 20), (16, 0, 0, 1200))
            self.assertEqual(drum_count, 2)


if __name__ == '__main__':
    unittest.main()
