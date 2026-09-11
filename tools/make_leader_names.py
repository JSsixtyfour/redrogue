#!/usr/bin/env python3
"""Generate gfx/trainer_card/leader_names.png: one 3-tile name strip per card block.

ONE-SHOT, BY HAND, like tools/make_placeholder_badges.py. The PNG it writes is
the committed source asset; the .2bpp is built by rgbgfx as usual.

WHY GENERATED RATHER THAN DRAWN. Shin Red restores the Japanese trainer card's
leader names, but only for the Kanto eight, and its sheet packs them end to end
at variable widths (tmp/shinpokered-reference/gfx/leader_names.png, with the
tile runs in its DrawBadges LeaderNameList). This tree needs seventeen names,
one per trainer-card block, and needs them at a FIXED three-tile stride so the
per-slot blit can compute a source address from a block index the same way
RogueBlitCardBadges does for the badges. Retypesetting is the only way to get
both.

THE FONT IS THE REFERENCE'S OWN. Glyphs are extracted pixel for pixel from Shin
Red's sheet rather than redrawn, so the Kanto names keep exactly the look they
have there. Segmentation is self-checking: a name that does not split into
exactly its own letter count is reported and the run aborts.

Five letters could not be extracted because no Kanto name contains them (F, H,
J, P) or because the only name that does packs its glyphs with no separating
column (V, in GIOVANNI). Those five are drawn here in the same 3x6, 1px-stroke
style. Everything else comes from the reference.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
REFERENCE = REPO_ROOT / "tmp" / "shinpokered-reference" / "gfx" / "leader_names.png"
OUT_PNG = REPO_ROOT / "gfx" / "trainer_card" / "leader_names.png"

TILE = 8
NAME_TILES = 3                      # the badge cell is 4 columns: number + 3
NAME_W = NAME_TILES * TILE          # 24px
GLYPH_H = 6                         # rows 1..6 of each 8px tile row
TOP_PAD = 1
GAP = 1                             # blank columns between glyphs

# (name, first tile, last tile) in the reference sheet. GIOVANNI is listed for
# completeness but is NOT a usable extraction source: its glyphs touch.
REFERENCE_RUNS = [
    ("BROCK", 0, 2), ("MISTY", 3, 5), ("SURGE", 6, 8), ("ERIKA", 9, 10),
    ("KOGA", 11, 12), ("SABRINA", 13, 15), ("BLAINE", 16, 18),
]

# Drawn here, in the reference's style. See the module docstring for why.
#
# The reference font is PROPORTIONAL (M is 5 wide, I is 1, E/L/S are 2), so
# these widths are chosen to fit the 24px budget rather than picked for looks:
# F and J are 2 so FALKNER and JASMINE land on exactly 24px. W is 5 to match M,
# which it shares a shape family with - a 3-wide W is indistinguishable from U.
HAND_DRAWN = {
    "F": ("##", "#.", "##", "#.", "#.", "#."),
    "H": ("#.#", "#.#", "###", "#.#", "#.#", "#.#"),
    "J": (".#", ".#", ".#", ".#", ".#", "##"),
    "P": ("##.", "#.#", "##.", "#..", "#..", "#.."),
    "V": ("#.#", "#.#", "#.#", "#.#", "#.#", ".#."),
    "W": ("#...#", "#...#", "#...#", "#.#.#", "#.#.#", ".#.#."),
    ".": (".", ".", ".", ".", ".", "#"),
}

# Two names cannot fit 24px at this font's natural 1px letter spacing, and
# closing the spacing to 0 makes them a solid block of pixels rather than a
# word. They are abbreviated instead, with a trailing period so the truncation
# reads as deliberate.
#
#   GIOVANNI  27px -> GIOVAN.  23px
#   WHITNEY   26px -> WHITNE.  24px
#
# Everything else fits as written. Change these here, not in BLOCK_NAMES, so
# the block map keeps naming the real leader.
ABBREVIATIONS = {
    "GIOVANNI": "GIOVAN.",
    "WHITNEY": "WHITNE.",
}

# Trainer-card block order, per constants/trainer_constants.asm and
# tools/make_placeholder_badges.py. Block 17 (CARD_BLOCK_UNKNOWN) gets a blank
# strip: an unrevealed slot must not leak a name beside its "?".
BLOCK_NAMES = [
    "BROCK", "MISTY", "SURGE", "ERIKA", "KOGA", "SABRINA", "BLAINE", "GIOVANNI",
    "FALKNER", "BUGSY", "WHITNEY", "MORTY", "CHUCK", "JASMINE", "PRYCE",
    "CLAIR", "JANINE",
    "",
]


def extract(path: Path) -> dict[str, tuple[str, ...]]:
    im = Image.open(path).convert("L")
    cols = im.size[0] // TILE
    glyphs: dict[str, tuple[str, ...]] = {}
    for name, first, last in REFERENCE_RUNS:
        width = (last - first + 1) * TILE
        strip = [
            [
                1 if im.getpixel(((t % cols) * TILE + x, (t // cols) * TILE + y)) < 128 else 0
                for t in range(first, last + 1)
                for x in range(TILE)
            ]
            for y in range(TILE)
        ]
        inked = [any(strip[y][x] for y in range(TILE)) for x in range(width)]
        segments, start = [], None
        for x in range(width):
            if inked[x] and start is None:
                start = x
            elif not inked[x] and start is not None:
                segments.append((start, x))
                start = None
        if start is not None:
            segments.append((start, width))
        if len(segments) != len(name):
            raise SystemExit(
                f"error: {name} segmented into {len(segments)} glyphs, expected "
                f"{len(name)}; the reference sheet is not what this expects"
            )
        for (lo, hi), char in zip(segments, name):
            rows = tuple(
                "".join("#" if strip[y][x] else "." for x in range(lo, hi))
                for y in range(1, 1 + GLYPH_H)
            )
            if char in glyphs and glyphs[char] != rows:
                raise SystemExit(f"error: conflicting forms extracted for {char!r}")
            glyphs[char] = rows
    return glyphs


def measure(name: str, font: dict[str, tuple[str, ...]], gap: int = GAP) -> int:
    if not name:
        return 0
    return sum(len(font[c][0]) for c in name) + gap * (len(name) - 1)


def spacing(name: str, font: dict[str, tuple[str, ...]]) -> int | None:
    """Widest letter spacing this name fits in, or None if it never does.

    Adaptive rather than fixed so that only the names that have to be squeezed
    are: GIOVANNI and WHITNEY are the only two that need 0, and letting them
    force every other name to 0 would make the whole card harder to read.
    """
    for gap in (GAP, 0):
        if measure(name, font, gap) <= NAME_W:
            return gap
    return None


def render(name: str, font: dict[str, tuple[str, ...]], gap: int) -> Image.Image:
    cell = Image.new("L", (NAME_W, TILE), color=255)
    if not name:
        return cell
    pixels = cell.load()
    x = 0
    for index, char in enumerate(name):
        glyph = font[char]
        for row, bits in enumerate(glyph):
            for column, bit in enumerate(bits):
                if bit == "#" and x + column < NAME_W:
                    pixels[x + column, TOP_PAD + row] = 0
        x += len(glyph[0]) + (gap if index + 1 < len(name) else 0)
    return cell


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not REFERENCE.exists():
        print(f"error: {REFERENCE} not found", file=sys.stderr)
        return 1
    font = extract(REFERENCE)
    print(f"extracted {len(font)} glyphs from the reference: "
          f"{''.join(sorted(font))}")
    for char, rows in HAND_DRAWN.items():
        if char in font:
            print(f"  note: {char} extracted after all; keeping the reference form")
            continue
        font[char] = rows
    print(f"  hand-drawn: {''.join(sorted(c for c in HAND_DRAWN if font[c] == HAND_DRAWN[c]))}")

    drawn = [ABBREVIATIONS.get(name, name) for name in BLOCK_NAMES]

    missing = {c for name in drawn for c in name} - set(font)
    if missing:
        print(f"error: no glyph for {sorted(missing)}", file=sys.stderr)
        return 1

    # Every strip must fit at the font's natural spacing. A name that needs the
    # 0px fallback is a name that will render as an unreadable block, so it is
    # an error telling the author to add an abbreviation, not a silent squeeze.
    bad = [n for n in drawn if measure(n, font, GAP) > NAME_W]
    for name in bad:
        print(f"  OVERFLOW {name}: {measure(name, font, GAP)}px into {NAME_W}px; "
              f"add an ABBREVIATIONS entry", file=sys.stderr)
    if bad:
        return 1

    sheet = Image.new("L", (NAME_W, len(BLOCK_NAMES) * TILE), color=255)
    for index, (name, text) in enumerate(zip(BLOCK_NAMES, drawn)):
        sheet.paste(render(text, font, GAP), (0, index * TILE))
        label = name or "(blank: CARD_BLOCK_UNKNOWN)"
        note = f"  abbreviated from {name}" if text != name else ""
        print(f"  block {index:2d}  {label:<28} "
              f"{measure(text, font, GAP):2d}px{note}")

    print(f"{len(BLOCK_NAMES)} strips, {len(BLOCK_NAMES) * NAME_TILES} tiles, "
          f"{len(BLOCK_NAMES) * NAME_TILES * 16} bytes of .2bpp")
    if args.dry_run:
        print("--dry-run: not written")
        return 0
    sheet.save(OUT_PNG)
    print(f"wrote {OUT_PNG}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
