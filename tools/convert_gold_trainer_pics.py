#!/usr/bin/env python3
"""Convert pret/pokegold trainer pics to this tree's Red trainer-pic format.

One-shot importer, run by hand; its PNG output is committed. Not wired into
`make` (same arrangement as tools/gen_event_constants.py).

Why a script rather than an image editor: pokegold stores trainer pics as 8-bit
COLORMAPPED PNGs whose palette is per-file and in colour (Falkner's mid-dark is
blue, Karen's is dark red), while this tree's trainer pics are 2-bit-equivalent
mode-L greyscale using exactly 0 / 85 / 170 / 255. Getting the shade order wrong
does not fail the build - rgbgfx happily produces an inverted or shade-swapped
pic - so the mapping is derived from measured luminance rather than assumed from
palette index order.

Mapping: the file's four palette entries are sorted by Rec.601 luminance,
lightest first, and assigned 255, 170, 85, 0. That is equivalent to pokegold's
usual index order (0=white .. 3=black) but does not depend on it.

Usage:
    python3 tools/convert_gold_trainer_pics.py            # convert
    python3 tools/convert_gold_trainer_pics.py --check    # report, write nothing
    python3 tools/convert_gold_trainer_pics.py --sheet out.png   # contact sheet
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = REPO_ROOT / "tmp" / "pokegold" / "gfx" / "trainers"
DST_DIR = REPO_ROOT / "gfx" / "trainers"

# The 11 classes the gym-leader expansion adds. Source stem -> destination stem.
# Kept explicit rather than globbed so an unrelated pokegold pic can never be
# swept in, and so the destination naming stays this tree's convention.
PICS = {
    "falkner": "falkner",
    "bugsy": "bugsy",
    "whitney": "whitney",
    "morty": "morty",
    "chuck": "chuck",
    "jasmine": "jasmine",
    "pryce": "pryce",
    "clair": "clair",
    "janine": "janine",
    "will": "will",
    "karen": "karen",
}

EXPECTED_SIZE = (56, 56)
RED_SHADES = (255, 170, 85, 0)  # lightest -> darkest, this tree's mode-L values


def luminance(rgb: tuple[int, int, int]) -> float:
    r, g, b = rgb
    return 0.299 * r + 0.587 * g + 0.114 * b


def convert(path: Path) -> tuple[Image.Image, list[str]]:
    """Return (converted mode-L image, notes)."""
    notes: list[str] = []
    im = Image.open(path)

    if im.size != EXPECTED_SIZE:
        raise SystemExit(f"{path.name}: expected {EXPECTED_SIZE}, got {im.size}")

    if im.mode != "P":
        raise SystemExit(f"{path.name}: expected a colormapped PNG, got mode {im.mode}")

    used = sorted({px for px in im.getdata()})
    if len(used) > 4:
        raise SystemExit(f"{path.name}: uses {len(used)} colours, max 4")
    if len(used) < 4:
        notes.append(f"only {len(used)} of 4 shades used")

    raw = im.getpalette()
    palette = {i: (raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2]) for i in used}

    # Rank the USED indices by luminance, lightest first, then map onto the
    # matching number of Red shades taken from the light end. A pic using only
    # 3 shades must not have its darkest shade promoted to black by accident,
    # so anchor black explicitly when a pure-black entry exists.
    order = sorted(used, key=lambda i: luminance(palette[i]), reverse=True)
    mapping: dict[int, int] = {}
    for rank, idx in enumerate(order):
        mapping[idx] = RED_SHADES[rank] if rank < len(RED_SHADES) else 0
    for idx, rgb in palette.items():
        if rgb == (0, 0, 0):
            mapping[idx] = 0
        elif rgb == (255, 255, 255):
            mapping[idx] = 255

    out = Image.new("L", im.size)
    out.putdata([mapping[px] for px in im.getdata()])

    detail = ", ".join(
        f"{idx}{palette[idx]}->{mapping[idx]}" for idx in order
    )
    notes.append(detail)
    return out, notes


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="report only, write nothing")
    ap.add_argument("--sheet", metavar="PATH", help="also write a comparison sheet")
    args = ap.parse_args()

    if not SRC_DIR.is_dir():
        raise SystemExit(f"source not found: {SRC_DIR}")

    converted: list[tuple[str, Image.Image, Image.Image]] = []
    for src_stem, dst_stem in PICS.items():
        src = SRC_DIR / f"{src_stem}.png"
        if not src.is_file():
            raise SystemExit(f"missing source pic: {src}")
        out, notes = convert(src)
        print(f"{dst_stem:<9} {'; '.join(notes)}")
        converted.append((dst_stem, Image.open(src).convert("RGB"), out))

        if not args.check:
            dst = DST_DIR / f"{dst_stem}.png"
            # Save as 4-shade greyscale; rgbgfx reads mode-L fine, and this
            # matches every existing trainer pic in the tree.
            out.save(dst, optimize=True)
            print(f"          -> {dst.relative_to(REPO_ROOT)}")

    if args.sheet:
        scale = 3
        pad = 6
        cell_w = EXPECTED_SIZE[0] * scale
        cell_h = EXPECTED_SIZE[1] * scale
        cols = len(converted)
        sheet = Image.new(
            "RGB",
            (cols * (cell_w + pad) + pad, 2 * (cell_h + pad) + pad),
            (128, 128, 128),
        )
        for i, (_stem, original, out) in enumerate(converted):
            x = pad + i * (cell_w + pad)
            sheet.paste(original.resize((cell_w, cell_h), Image.NEAREST), (x, pad))
            sheet.paste(
                out.convert("RGB").resize((cell_w, cell_h), Image.NEAREST),
                (x, pad + cell_h + pad),
            )
        sheet.save(args.sheet)
        print(f"\nsheet -> {args.sheet}  (top row = pokegold source, bottom = converted)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
