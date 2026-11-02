"""Pack the approved 32x32 tree pixels into 14 private FOREST tile slots.

Source PNGs remain exact opaque RGB originals. The shared ground corner slots
are retained from FOREST; no transparency, rescaling, or new art is inferred.
Run in WSL with Pillow. --check verifies the packed PNGs without writing.
"""
from pathlib import Path
import argparse
import hashlib
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    'cherry': 'db6642bbe0e1dc50fc0958d1aaba92c08b648f269d433542e06f01a3e129232d',
    'winter': '4f2a6aa55912ec707a8b4b56b0869cc931c1eff4df728e5c692a9fd27cd8c782',
}
SHADE = (255, 170, 85, 0)
POSITIONS = tuple(i for i in range(16) if i not in (12, 15))


def packed_tree(name):
    path = ROOT / f'gfx/tilesets/forest_{name}_tree.png'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == SOURCES[name], path
    source = Image.open(path)
    assert source.mode == 'RGB' and source.size == (32, 32)
    colors = source.getcolors()
    assert colors is not None and len(colors) == 4
    colors = [c for _, c in sorted(colors, key=lambda pair: sum(a*b for a,b in zip(pair[1], (.299,.587,.114))), reverse=True)]
    mapping = dict(zip(colors, SHADE))
    output = Image.new('L', (8, len(POSITIONS)*8))
    for n, q in enumerate(POSITIONS):
        for y in range(8):
            for x in range(8):
                output.putpixel((x,n*8+y), mapping[source.getpixel((q%4*8+x,q//4*8+y))])
    return output, mapping


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    for name in SOURCES:
        packed, mapping = packed_tree(name)
        destination = ROOT / f'gfx/tilesets/forest_{name}.png'
        if args.check:
            actual = Image.open(destination)
            assert actual.mode == 'L' and actual.size == packed.size and actual.tobytes() == packed.tobytes(), destination
        else:
            packed.save(destination)
        print(name, mapping, '14 tiles / 224 bytes; shared ground corners retained')


if __name__ == '__main__':
    main()
