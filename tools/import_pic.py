#!/usr/bin/env python3
"""Drop a new front and/or back sprite for an existing species into the tree.

Checks the art against the rules the engine depends on, converts it to this
tree's PNG convention (8-bit greyscale using exactly 0 / 85 / 170 / 255), and
overwrites gfx/pokemon/front/<name>.png and/or gfx/pokemon/back/<name>b.png.
`make` then rebuilds the .lz / .dim from the PNG on its own.

Standard library only, so it runs from Windows Python, which can read the
K: drive (WSL can't, and WSL Python is where Pillow lives).

Rules enforced (see the LZ pic pipeline and 28x28 back memories):
  front  square 40, 48 or 56 px. A non-square pic draws scrambled, because
         picdims writes w<<4|h and the loader reads the low nybble as width.
  back   32x32, art in the top-left 28x28 only. ScaleSpriteByTwo drops the
         right 4 columns and bottom 4 rows, so art there is invisible.
         A 28x28 input is padded to 32x32 with white.
  both   at most 4 shades after compositing any transparency over white.

Shade mapping: with exactly 4 colours they are ranked by Rec.601 luminance,
lightest -> 255, 170, 85, 0 (same as convert_gold_trainer_pics.py). With fewer,
each snaps to the nearest grey level, and two colours landing on the same level
is an error rather than a silent merge. The mapping is always printed: rgbgfx
builds a shade-swapped pic without complaint, so check it.

Usage (repo root, Windows Python):
    python tools/import_pic.py octillery --front "K:/.../front.png" --back "K:/.../back.png"
    python tools/import_pic.py octillery --back back.png --check   # validate only
"""
from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
FRONT_SIZES = (40, 48, 56)
BACK_SIZE = 32
BACK_VISIBLE = 28
LEVELS = (255, 170, 85, 0)  # white, light, dark, black

PNG_SIG = b"\x89PNG\r\n\x1a\n"
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class PicError(Exception):
    pass


def read_png(path: Path) -> tuple[int, int, list[list[tuple[int, int, int, int]]]]:
    """Decode any non-interlaced PNG to rows of 8-bit RGBA tuples."""
    data = path.read_bytes()
    if not data.startswith(PNG_SIG):
        raise PicError(f"{path}: not a PNG")
    pos = len(PNG_SIG)
    idat = b""
    palette: list[tuple[int, int, int, int]] = []
    trns = b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = [(body[i], body[i + 1], body[i + 2], 255) for i in range(0, len(body), 3)]
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if interlace:
        raise PicError(f"{path}: interlaced PNG; re-save it without interlacing")
    for i, alpha in enumerate(trns if ctype == 3 else b""):
        palette[i] = palette[i][:3] + (alpha,)

    raw = zlib.decompress(idat)
    channels = CHANNELS[ctype]
    bits_pp = channels * depth
    stride = (width * bits_pp + 7) // 8
    bpp = max(1, bits_pp // 8)
    rows = []
    prev = bytearray(stride)
    i = 0
    for _ in range(height):
        ftype = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 0xFF
            elif ftype == 2:
                line[x] = (line[x] + b) & 0xFF
            elif ftype == 3:
                line[x] = (line[x] + (a + b) // 2) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 0xFF
        prev = line
        rows.append(_unpack_row(line, width, depth, ctype, palette, trns))
    return width, height, rows


def _unpack_row(line, width, depth, ctype, palette, trns):
    if depth < 8:
        per_byte = 8 // depth
        mask = (1 << depth) - 1
        samples = [(line[x // per_byte] >> (8 - depth * (x % per_byte + 1))) & mask
                   for x in range(width)]
        if ctype == 3:
            return [palette[s] for s in samples]
        scale = 255 // mask
        key = struct.unpack(">H", trns)[0] if trns else None
        return [(s * scale,) * 3 + (0 if s == key else 255,) for s in samples]
    step = depth // 8
    vals = [line[j] for j in range(0, len(line), step)]  # high byte of 16-bit samples
    n = CHANNELS[ctype]
    out = []
    for x in range(width):
        px = vals[x * n:(x + 1) * n]
        if ctype == 0:
            out.append((px[0],) * 3 + (255,))
        elif ctype == 3:
            out.append(palette[px[0]])
        elif ctype == 4:
            out.append((px[0],) * 3 + (px[1],))
        elif ctype == 2:
            out.append(tuple(px) + (255,))
        else:
            out.append(tuple(px))
    return out


def write_grey_png(path: Path, rows: list[list[int]]) -> None:
    """8-bit greyscale, filter 0: the format most of the tree already uses."""
    height, width = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(kind, body):
        return (struct.pack(">I", len(body)) + kind + body
                + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))

    path.write_bytes(PNG_SIG
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9))
                     + chunk(b"IEND", b""))


def to_grey(rows) -> tuple[list[list[int]], dict[tuple[int, int, int], int]]:
    """Composite over white, then map each colour to one of the 4 grey levels."""
    flat = [[tuple((ch * a + 255 * (255 - a)) // 255 for ch in (r, g, b)) for r, g, b, a in row]
            for row in rows]
    colours = sorted({c for row in flat for c in row}, key=_luma, reverse=True)
    if len(colours) > 4:
        raise PicError(f"{len(colours)} colours after flattening; the Game Boy has 4. "
                       "Reduce it to white / light / dark / black.")
    if len(colours) == 4:
        mapping = dict(zip(colours, LEVELS))
    else:
        mapping = {c: min(LEVELS, key=lambda lv: abs(lv - _luma(c))) for c in colours}
        if len(set(mapping.values())) < len(mapping):
            raise PicError("two different colours snap to the same grey level: "
                           + ", ".join(f"{c}->{v}" for c, v in mapping.items()))
    return [[mapping[c] for c in row] for row in flat], mapping


def _luma(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def check_front(grey, w, h) -> list[str]:
    if w != h or w not in FRONT_SIZES:
        raise PicError(f"front is {w}x{h}; it must be square, one of "
                       + ", ".join(f"{s}x{s}" for s in FRONT_SIZES))
    warnings = []
    if all(v == 255 for v in grey[-1]):
        warnings.append("bottom row is blank; fronts normally sit on the bottom edge")
    return warnings


def check_back(grey, w, h) -> list[list[int]]:
    if (w, h) == (BACK_VISIBLE, BACK_VISIBLE):
        grey = [row + [255] * 4 for row in grey] + [[255] * BACK_SIZE for _ in range(4)]
    elif (w, h) != (BACK_SIZE, BACK_SIZE):
        hint = (" (a Gen 2 back: it needs redrawing at Gen 1 size)" if (w, h) == (48, 48) else "")
        raise PicError(f"back is {w}x{h}{hint}; it must be 32x32 or 28x28")
    dead = [(x, y) for y in range(BACK_SIZE) for x in range(BACK_SIZE)
            if (x >= BACK_VISIBLE or y >= BACK_VISIBLE) and grey[y][x] != 255]
    if dead:
        raise PicError(f"back has {len(dead)} non-white pixels in the right/bottom 4px strip "
                       f"(first at x={dead[0][0]}, y={dead[0][1]}); battle cuts that strip off. "
                       "Move the art to the top-left 28x28.")
    return grey


def preview(grey) -> str:
    chars = {255: ".", 170: "-", 85: "o", 0: "#"}
    return "\n".join("    " + "".join(chars[v] for v in row) for row in grey)


def validate(kind: str, src: Path, dest: Path) -> bool:
    print(f"{kind}: {src}")
    try:
        w, h, rows = read_png(src)
        grey, mapping = to_grey(rows)
        if kind == "front":
            warnings = check_front(grey, w, h)
        else:
            grey, warnings = check_back(grey, w, h), []
    except PicError as e:
        print(f"  REJECTED: {e}")
        return False
    print(f"  {w}x{h}, shade mapping (source colour -> grey):")
    for colour, level in mapping.items():
        print(f"    {colour} -> {level}")
    for warning in warnings:
        print(f"  warning: {warning}")
    print(preview(grey))
    print(f"  ok -> {dest.relative_to(REPO_ROOT)}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("name", help="tree file stem, e.g. octillery")
    parser.add_argument("--front", type=Path, help="new front PNG")
    parser.add_argument("--back", type=Path, help="new back PNG")
    parser.add_argument("--check", action="store_true", help="validate only, write nothing")
    args = parser.parse_args()
    if not (args.front or args.back):
        parser.error("give --front and/or --back")

    jobs = []
    for kind, src, dest in (("front", args.front, f"gfx/pokemon/front/{args.name}.png"),
                            ("back", args.back, f"gfx/pokemon/back/{args.name}b.png")):
        if src is None:
            continue
        dest = REPO_ROOT / dest
        if not dest.is_file():
            print(f"{dest.relative_to(REPO_ROOT)} doesn't exist. This tool only replaces "
                  "existing pics; a new species or form needs wiring in gfx/pics.asm.")
            return 1
        jobs.append((kind, src, dest))

    # Validate everything before writing anything, so a bad back can't leave
    # a half-imported species with only the new front in place.
    if not all([validate(kind, src, dest) for kind, src, dest in jobs]):
        return 1
    if args.check:
        return 0
    for kind, src, dest in jobs:
        write_grey_png(dest, to_grey_checked(kind, src))
        print(f"wrote {dest.relative_to(REPO_ROOT)}")
    print("\nNext:\n"
          "  make                      (all three ROMs)\n"
          "  wsl: python3 tools/pyboy_smoke/sprite_decompression.py --write-golden\n"
          "  git diff tools/pyboy_smoke/sprite_decompression_golden.json\n"
          f"      -> only {args.name} pic lines should change\n"
          "  make smoke TEST=sprite_decompression")
    return 0


def to_grey_checked(kind: str, src: Path) -> list[list[int]]:
    w, h, rows = read_png(src)
    grey, _ = to_grey(rows)
    return check_back(grey, w, h) if kind == "back" else grey


if __name__ == "__main__":
    sys.exit(main())
