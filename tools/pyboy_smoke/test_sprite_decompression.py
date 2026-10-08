"""Bit-exact contract for UncompressSpriteData (SPRITE_DECOMPRESSION_PLAN.md).

Two independent checks over every compressed pic, flipped and unflipped:
  * golden: sha256 of sSpriteBuffer1-2 matches what the vanilla decoder left;
  * source art: the buffers ARE the pic's .2bpp (rgbgfx output of its PNG),
    so the contract holds even without trusting the old decoder:
      sSpriteBuffer1 = low bit plane, sSpriteBuffer2 = high plane, both
      column-major (byte [x*h*8 + y] = 8 pixels of tile column x, pixel row y),
      zero past w*h*8; flipped = each byte with both nybbles bit-reversed.
sSpriteBuffer0 is deliberately unchecked: it is decoder scratch (see
sprite_decompression.py's docstring for the caller audit).
"""

import struct
import unittest
from pathlib import Path

from sprite_decompression import SPRITEBUFFERSIZE, load_golden, pic_labels, run_all
from test_smoke import HarnessTestCase, REPO_ROOT

REVERSE_NYBBLE = [int(f"{n:04b}"[::-1], 2) for n in range(16)]


def nybble_reverse(byte: int) -> int:
    return (REVERSE_NYBBLE[byte >> 4] << 4) | REVERSE_NYBBLE[byte & 15]


def png_tiles(path):
    """(width, height) in 8x8 tiles, from the PNG's IHDR (independent of the pic format)."""
    header = path.read_bytes()[16:24]
    width, height = struct.unpack(">II", header)
    return width // 8, height // 8


class SpriteDecompressionTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        self.harness.tick(120)

    def test_every_pic_matches_golden(self) -> None:
        results = run_all(self.harness)
        golden = load_golden()
        self.assertEqual(sorted(results), sorted(golden), "pic set changed; regenerate golden")
        mismatched = [k for k, v in results.items() if v["sha256"] != golden[k]]
        self.assertEqual(mismatched, [], f"{len(mismatched)} pics decode differently")

    def test_every_pic_matches_its_source_art(self) -> None:
        results = run_all(self.harness)
        size = SPRITEBUFFERSIZE
        failures = []
        for label, path in pic_labels():
            # string concat, not with_suffix: names like "mr.mime" contain dots
            stem = str(REPO_ROOT / path[: -len(".pic")])
            width, height = png_tiles(Path(stem + ".png"))
            art = Path(stem + ".2bpp").read_bytes()
            expected_lo = bytearray(size)
            expected_hi = bytearray(size)
            for ty in range(height):
                for tx in range(width):
                    for row in range(8):
                        source = (ty * width + tx) * 16 + row * 2
                        dest = tx * height * 8 + ty * 8 + row
                        expected_lo[dest] = art[source]
                        expected_hi[dest] = art[source + 1]
            plain = results[f"{label}/0"]["buffers"][size:]
            flipped = results[f"{label}/1"]["buffers"][size:]
            if plain != bytes(expected_lo + expected_hi):
                failures.append(f"{label}: unflipped != source art")
            if flipped != bytes(nybble_reverse(b) for b in expected_lo + expected_hi):
                failures.append(f"{label}: flipped != nybble-reversed art")
        self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main()
