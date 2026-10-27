#!/usr/bin/env python3
"""Drop new art for an existing sprite into the tree.

Checks the art against the rules the engine depends on, converts it to this
tree's PNG convention (8-bit greyscale using exactly 0 / 85 / 170 / 255), and
overwrites the tree's PNG. `make` then rebuilds the .2bpp / .lz / .dim from it.

Standard library only, so it runs from Windows Python, which can read the
K: drive (WSL can't, and WSL Python is where Pillow lives).

Kinds (--kind, default pokemon) and the files they write:
  pokemon    --front gfx/pokemon/front/<name>.png   --back gfx/pokemon/back/<name>b.png
  trainer    --front gfx/trainers/<name>.png
  player     --front gfx/player/<name>.png          --back gfx/player/<name>b.png
  overworld  --sheet gfx/sprites/<name>.png
  icon       --sheet gfx/icons/<name>.png

Rules enforced (see the LZ pic pipeline and 28x28 back memories):
  front      pokemon: square 40, 48 or 56 px; trainer/player: 56x56. A
             non-square pic draws scrambled, because picdims writes w<<4|h and
             the loader reads the low nybble as width.
  back       32x32, art in the top-left 28x28 only. ScaleSpriteByTwo drops the
             right 4 columns and bottom 4 rows, so art there is invisible.
             A 28x28 input is padded to 32x32 with white.
  overworld  16 wide; 16x96 (stand down/up/left, walk down/up/left), 16x48
             (standing only: must never walk, see data/sprites/facings.asm) or
             16x16 (prop: STAY, NONE). White is transparent on objects.
  icon       8x32 category icon or 16x32 species icon (two 16x16 frames).
             Colour-indexed icons the Makefile builds with preserved indices
             (yellow_legacy_menu_icons) are refused: greying them changes how
             they build.
  all        at most 4 shades after compositing any transparency over white.

New sprites: --new allows a destination that doesn't exist yet and prints the
files that still need wiring by hand.

Shade mapping: with exactly 4 colours they are ranked by Rec.601 luminance,
lightest -> 255, 170, 85, 0 (same as convert_gold_trainer_pics.py). With fewer,
each snaps to the nearest grey level, and two colours landing on the same level
is an error rather than a silent merge. The mapping is always printed: rgbgfx
builds a shade-swapped pic without complaint, so check it.

Full workflow:
  1. Import (repo root, Windows Python, which can read K:):
       python tools/import_pic.py octillery --front "K:/.../front.png" --back "K:/.../back.png"
       python tools/import_pic.py octillery --back back.png --check   # validate only
       python tools/import_pic.py hiker --kind overworld --sheet hiker.png
  2. Build (WSL, repo root). The next step reads the ROM, so build first:
       make
  Steps 3-5 are for pics (pokemon, trainer, player). Overworld sprites and
  icons aren't in the golden test: go straight to step 6.
  3. Refresh the sprite test's saved hashes (WSL):
       python3 tools/pyboy_smoke/sprite_decompression.py --write-golden
  4. Check that only this species' pics changed:
       git diff tools/pyboy_smoke/sprite_decompression_golden.json
     Expect <Name>PicFront/0, /1 and <Name>PicBack/0, /1 for each pic replaced.
     Any other label changing means something else moved: don't keep it.
  5. Run the sprite tests (WSL). The quotes and .* matter, it takes a glob:
       make smoke TEST='test_sprite_decompression.*'
  6. Look at it in BGB: the Pokedex entry, and a battle for the back. For an
     overworld sheet, every facing and a walk; for an icon, the party menu
     (it animates).
"""
from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
FRONT_SIZES = (40, 48, 56)
TRAINER_SIZES = (56,)
BACK_SIZE = 32
BACK_VISIBLE = 28
OVERWORLD_HEIGHTS = (16, 48, 96)
ICON_SIZES = ((8, 32), (16, 32))
LEVELS = (255, 170, 85, 0)  # white, light, dark, black

# kind -> role -> destination, relative to the repo root
KINDS = {
    "pokemon": {"front": "gfx/pokemon/front/{}.png", "back": "gfx/pokemon/back/{}b.png"},
    "trainer": {"front": "gfx/trainers/{}.png"},
    "player": {"front": "gfx/player/{}.png", "back": "gfx/player/{}b.png"},
    "overworld": {"sheet": "gfx/sprites/{}.png"},
    "icon": {"sheet": "gfx/icons/{}.png"},
}
PIC_KINDS = ("pokemon", "trainer", "player")

# What --new still leaves to do by hand, per kind.
WIRING = {
    "pokemon": [
        "gfx/pics.asm: <Name>PicFront:: / <Name>PicBack:: INCBIN the .lz, both in ONE section",
        "base stats (or data/pokemon/forms/<name>.asm): INCBIN the front .dim, dw Front, Back",
        "forms only: db BANK(<Name>PicFront) in the record",
        "CGB palette: data/pokemon/palettes.asm, or the form record's PAL_*MON byte",
    ],
    "trainer": [
        "gfx/pics.asm: <Name>Pic:: INCBIN \"gfx/trainers/<name>.lz\" in a Trainer Pics section",
        "data/trainers/pic_pointers_money.asm: pic_money row, in class-constant order",
        "the class constant itself",
    ],
    "player": [
        "front: <Name>Pic in SECTION \"Trainer Pics\"; back: INCBIN the .lz in \"Player Back Pics\"",
        "data/player/appearance.asm: point the roster row at it (the row's ASSERTs check banks)",
    ],
    "overworld": [
        "gfx/sprites.asm: <Name>Sprite:: INCBIN the .2bpp (player sheets: \"Player Sprites\")",
        "data/sprites/sprites.asm: overworld_sprite <Name>Sprite, 12 (or 4 for a prop)",
        "constants/sprite_constants.asm: SPRITE_* const in the same position as that row",
    ],
    "icon": [
        "8x32 category: a const in constants/icon_constants.asm (nybble: 16 max) + engine work",
        "16x32 species icon: INCBIN in gfx/unique_party_icons.asm + a branch in engine/gfx/mon_icons.asm",
    ],
}

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


def check_front(grey, w, h, sizes=FRONT_SIZES) -> list[str]:
    if w != h or w not in sizes:
        raise PicError(f"front is {w}x{h}; it must be square, one of "
                       + ", ".join(f"{s}x{s}" for s in sizes))
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


def _frame(grey, index) -> list[list[int]]:
    return grey[index * 16:(index + 1) * 16]


def check_overworld(grey, w, h) -> list[str]:
    if w != 16 or h not in OVERWORLD_HEIGHTS:
        raise PicError(f"overworld sheet is {w}x{h}; it must be 16 wide and "
                       + ", ".join(str(n) for n in OVERWORLD_HEIGHTS) + " tall")
    warnings = ["white is transparent on objects; anything meant to read as white must be light grey"]
    if h == 16:
        warnings.append("4-tile prop: every object_event using it must be STAY, NONE")
    elif h == 48:
        warnings.append("standing frames only: it must never walk (no WALK, no scripted "
                        "movement), or the loader reads the next sheet as its walk frames")
    else:
        # facings.asm draws step 3 of walking down/up as step 1 mirrored, so a
        # symmetric walk frame makes both steps the same pose.
        for name, stand, walk in (("down", 0, 3), ("up", 1, 4)):
            if all(row == row[::-1] for row in _frame(grey, walk)):
                warnings.append(f"walk-{name} frame is mirror-symmetric, so both steps are the "
                                "same pose (fine for a bobbing mon or a robe; a person needs one "
                                "leg forward)")
            if _frame(grey, walk) == _frame(grey, stand):
                warnings.append(f"walk-{name} frame is identical to stand-{name}")
        if _frame(grey, 5) == _frame(grey, 2):
            warnings.append("walk-left frame is identical to stand-left")
    return warnings


def preserved_index_icons() -> set[str]:
    """Icons the Makefile builds from their own palette indices, not greys."""
    for line in (REPO_ROOT / "Makefile").read_text().splitlines():
        if line.startswith("yellow_legacy_menu_icons :="):
            return set(line.split(":=", 1)[1].split())
    return set()


def check_icon(grey, w, h, name) -> list[str]:
    if (w, h) not in ICON_SIZES:
        raise PicError(f"icon is {w}x{h}; it must be "
                       + " or ".join(f"{a}x{b}" for a, b in ICON_SIZES))
    if name in preserved_index_icons():
        raise PicError(f"{name} is in the Makefile's yellow_legacy_menu_icons, built from its "
                       "palette indices; edit it with an indexed-colour editor instead")
    warnings = ["white is transparent on objects; anything meant to read as white must be light grey"]
    if w == 16 and _frame(grey, 0) == _frame(grey, 1):
        warnings.append("both 16x16 frames are identical: the icon won't animate")
    return warnings


def preview(grey) -> str:
    chars = {255: ".", 170: "-", 85: "o", 0: "#"}
    return "\n".join("    " + "".join(chars[v] for v in row) for row in grey)


def convert(kind: str, role: str, name: str, src: Path):
    """Return (grey rows to write, w, h, mapping, warnings); raise PicError if rejected."""
    w, h, rows = read_png(src)
    grey, mapping = to_grey(rows)
    if role == "front":
        warnings = check_front(grey, w, h, FRONT_SIZES if kind == "pokemon" else TRAINER_SIZES)
    elif role == "back":
        grey, warnings = check_back(grey, w, h), []
    elif kind == "overworld":
        warnings = check_overworld(grey, w, h)
    else:
        warnings = check_icon(grey, w, h, name)
    return grey, w, h, mapping, warnings


def validate(kind: str, role: str, name: str, src: Path, dest: Path):
    """Print the report; return the rows to write, or None if rejected."""
    print(f"{role}: {src}")
    try:
        grey, w, h, mapping, warnings = convert(kind, role, name, src)
    except PicError as e:
        print(f"  REJECTED: {e}")
        return None
    print(f"  {w}x{h}, shade mapping (source colour -> grey):")
    for colour, level in mapping.items():
        print(f"    {colour} -> {level}")
    for warning in warnings:
        print(f"  warning: {warning}")
    print(preview(grey))
    print(f"  ok -> {dest.relative_to(REPO_ROOT)}")
    return grey


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("name", help="tree file stem, e.g. octillery")
    parser.add_argument("--kind", choices=KINDS, default="pokemon", help="what the art is")
    parser.add_argument("--front", type=Path, help="new front PNG (pokemon, trainer, player)")
    parser.add_argument("--back", type=Path, help="new back PNG (pokemon, player)")
    parser.add_argument("--sheet", type=Path, help="new sheet PNG (overworld, icon)")
    parser.add_argument("--new", action="store_true",
                        help="allow a destination that doesn't exist yet (needs wiring by hand)")
    parser.add_argument("--check", action="store_true", help="validate only, write nothing")
    args = parser.parse_args()

    roles = KINDS[args.kind]
    given = {role: getattr(args, role) for role in ("front", "back", "sheet") if getattr(args, role)}
    if not given:
        parser.error(f"--kind {args.kind} takes " + " and/or ".join(f"--{r}" for r in roles))
    for role in given:
        if role not in roles:
            parser.error(f"--kind {args.kind} has no --{role}; it takes "
                         + " and/or ".join(f"--{r}" for r in roles))

    jobs = []
    for role, src in given.items():
        dest = REPO_ROOT / roles[role].format(args.name)
        if not dest.is_file() and not args.new:
            print(f"{dest.relative_to(REPO_ROOT)} doesn't exist. Check the name, or pass --new "
                  "for a new sprite (it then needs wiring by hand).")
            return 1
        jobs.append((role, src, dest))

    # Validate everything before writing anything, so a bad back can't leave
    # a half-imported species with only the new front in place.
    results = [validate(args.kind, role, args.name, src, dest) for role, src, dest in jobs]
    if any(grey is None for grey in results):
        return 1
    if args.check:
        return 0
    created = []
    for (role, src, dest), grey in zip(jobs, results):
        if not dest.is_file():
            created.append(dest)
        write_grey_png(dest, grey)
        print(f"wrote {dest.relative_to(REPO_ROOT)}")
    if created:
        print("\nNew file(s); still to wire by hand:")
        for item in WIRING[args.kind]:
            print(f"  - {item}")
    print("\nNext:\n  make                      (all three ROMs)")
    if args.kind in PIC_KINDS:
        print("  wsl: python3 tools/pyboy_smoke/sprite_decompression.py --write-golden\n"
              "  git diff tools/pyboy_smoke/sprite_decompression_golden.json\n"
              f"      -> only {args.name} pic lines should change\n"
              "  make smoke TEST='test_sprite_decompression.*'")
    else:
        print("  not in the golden test: check it in BGB (every facing, a walk / the party menu)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
