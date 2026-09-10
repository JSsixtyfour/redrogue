#!/usr/bin/env python3
"""Decode .2bpp trainer/mon pics back to a PNG contact sheet.

Verification tool, run by hand. The point is to check the whole PNG -> rgbgfx
-> .2bpp pipeline rather than just the input PNG: a shade-inverted or
shade-swapped import produces a perfectly valid 784-byte .2bpp that the build
accepts silently, and the only way to catch it is to look at the decoded result.

Game Boy 2bpp layout: 16 bytes per 8x8 tile, two bytes per row, low bit-plane
first; pixel value = (hi<<1)|lo, 0 = lightest. Tiles are stored
ROW-major for this tree's pics. Verified 2026-09-10 by decoding the existing,
known-good gfx/trainers/brock.2bpp both ways: row-major reproduces Brock
exactly, column-major is scrambled. Keep brock as the control when reusing this.

Usage:
    python3 tools/preview_2bpp_pic.py -o sheet.png gfx/trainers/falkner.2bpp ...
    python3 tools/preview_2bpp_pic.py -o sheet.png --labels a,b,c f1.2bpp f2.2bpp
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

SHADES = (255, 170, 85, 0)  # 2bpp value -> greyscale, 0 = lightest


def decode(data: bytes, tiles_w: int, tiles_h: int, column_major: bool) -> Image.Image:
    im = Image.new("L", (tiles_w * 8, tiles_h * 8), 255)
    px = im.load()
    n = tiles_w * tiles_h
    if len(data) < n * 16:
        raise SystemExit(f"expected >= {n * 16} bytes, got {len(data)}")
    for t in range(n):
        if column_major:
            tx, ty = divmod(t, tiles_h)
        else:
            ty, tx = divmod(t, tiles_w)
        base = t * 16
        for row in range(8):
            lo = data[base + row * 2]
            hi = data[base + row * 2 + 1]
            for col in range(8):
                bit = 7 - col
                val = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1)
                px[tx * 8 + col, ty * 8 + row] = SHADES[val]
    return im


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--tiles", default="7x7", help="tile dimensions, default 7x7")
    ap.add_argument("--scale", type=int, default=3)
    ap.add_argument("--labels", help="comma-separated labels")
    ap.add_argument(
        "--column-major",
        action="store_true",
        help="decode tiles column-major (default is row-major, see module docstring)",
    )
    args = ap.parse_args()

    tw, th = (int(v) for v in args.tiles.lower().split("x"))
    labels = args.labels.split(",") if args.labels else [
        Path(f).stem for f in args.files
    ]

    imgs = [
        decode(Path(f).read_bytes(), tw, th, column_major=args.column_major)
        for f in args.files
    ]

    cw, ch = tw * 8 * args.scale, th * 8 * args.scale
    pad, label_h = 8, 14
    sheet = Image.new(
        "RGB", (len(imgs) * (cw + pad) + pad, ch + pad * 2 + label_h), (120, 120, 120)
    )
    draw = ImageDraw.Draw(sheet)
    for i, (im, label) in enumerate(zip(imgs, labels)):
        x = pad + i * (cw + pad)
        sheet.paste(im.convert("RGB").resize((cw, ch), Image.NEAREST), (x, pad))
        draw.text((x + 2, pad + ch + 2), label, fill=(255, 255, 255))
    sheet.save(args.out)
    print(f"{len(imgs)} pic(s) -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
