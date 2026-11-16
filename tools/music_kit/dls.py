"""Small DLS Level 1 exporter for the sample pack's SF2 model.

Writes PCM and region roots directly, without an external SF2 converter.
RIFF layout reference: OpenJDK DLSSoundbank (writeSoundbank/writeRegion).
DLS1 has no portable velocity-layer support; square dynamics are approximate.
"""
import struct


def chunk(tag, data):
    return tag + struct.pack('<I', len(data)) + data + b'\0' * (len(data) % 2)


def listing(tag, *children):
    return chunk(b'LIST', tag + b''.join(children))


def info(name):
    return listing(b'INFO', chunk(b'INAM', name.encode('ascii') + b'\0'))


def wsmp(root, loop=None):
    data = struct.pack('<IHhiII', 20, root, 0, 0, 0, int(loop is not None))
    if loop is not None:
        data += struct.pack('<IIII', 16, 0, loop[0], loop[1] - loop[0])
    return chunk(b'wsmp', data)


def articulation(fixed_volume, drum):
    # source, control, destination, transform, signed 16.16 scale.
    # Override default velocity -> gain for wave/drum voices. Instant attack,
    # full sustain; drums finish their recorded tail even after a short note.
    connections = [(0, 0, 0x206, 0, -32768 * 65536),
                   (0, 0, 0x209, 0, (3986 if drum else -7973) * 65536)]
    if fixed_volume:
        connections.append((2, 0, 1, 1, 0))
    data = struct.pack('<II', 8, len(connections))
    data += b''.join(struct.pack('<HHHHi', *c) for c in connections)
    return listing(b'lart', chunk(b'art1', data))


def write(path, sf):
    waves, offsets, offset = [], [], 0
    for name, start, end, ls, le, rate, root in sf.samples:
        wave = listing(b'wave',
                       chunk(b'fmt ', struct.pack('<HHIIHHH', 1, 1, rate, rate * 2, 2, 16, 0)),
                       wsmp(root), chunk(b'data', bytes(sf.pcm[start * 2:end * 2])), info(name))
        offsets.append(offset)
        waves.append(wave)
        offset += len(wave)
    instruments = []
    for name, bank, program, instrument in sf.presets:
        _, zones = sf.instruments[instrument]
        drum = name in ('Drums', 'Game Boy Drums')
        regions = []
        for z in zones:
            _, start, end, ls, le, rate, root = sf.samples[z.sample]
            regions.append(listing(b'rgn ',
                chunk(b'rgnh', struct.pack('<6H', z.lo, z.hi, 0, 127, 0, 1 if drum else 0)),
                chunk(b'wlnk', struct.pack('<HHII', 0, 0, 1, z.sample)),
                wsmp(z.root if z.root is not None else root,
                     (ls - start, le - start) if z.loop else None)))
        instruments.append(listing(b'ins ',
            chunk(b'insh', struct.pack('<III', len(regions), 0x80000000 if bank == 128 else bank, program)),
            listing(b'lrgn', *regions), articulation(drum or name.startswith('Wave'), drum), info(name)))
    body = b'DLS ' + chunk(b'colh', struct.pack('<I', len(instruments)))
    body += listing(b'lins', *instruments)
    body += chunk(b'ptbl', struct.pack('<II', 8, len(offsets)) + struct.pack('<%dI' % len(offsets), *offsets))
    body += listing(b'wvpl', *waves) + info(sf.name)
    with open(path, 'wb') as f:
        f.write(chunk(b'RIFF', body))
