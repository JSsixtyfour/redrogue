#!/usr/bin/env python3
"""Expand gfx/trainer_card/badges.png to its full block count.

ONE-SHOT, BY HAND. Not wired into `make`. The PNG it writes is the committed
source asset; `badges.2bpp` is gitignored and built by rgbgfx as usual. Run it
once, commit the PNG, then hand-edit the PNG when real art arrives. Re-running
it would overwrite any real Johto art with Kanto placeholders again, so it
refuses to touch a file that already has all blocks unless --force is given.

Sheet geometry (do not change without changing DrawBadges):
  16 px wide = 2 tiles. Each leader block is 4 image rows = 8 tiles:
  tiles 0-3 are the 2x2 FACE, tiles 4-7 are the 2x2 BADGE. `DrawBadges`
  encodes exactly that with `add 4` ("Badge graphics are after each face")
  and a per-block stride of 8 in .FaceBadgeTiles.

Block order is the trainer-card block index, which is NOT the trainer class id.
Blocks 0-7 are the vanilla Kanto eight, in wObtainedBadges BIT order
(BIT_BOULDERBADGE..BIT_EARTHBADGE, constants/ram_constants.asm), because
DrawBadges walks that bitfield LSB-first and indexes this sheet with the same
counter. Blocks 8-16 are appended by this script, then block 17, the "?":

  8..15  the 8 Johto leaders -> PLACEHOLDER copies of blocks 0..7, index for
         index. Index order rather than a thematic type match, deliberately:
         it keeps all 8 placeholders visually DISTINCT, which is what makes the
         Phase 4 per-slot blit testable (you can tell which slot drew what).
         A type match would have collided (Whitney and Jasmine both -> Boulder).
  16     Janine -> copy of block 4 (Koga). For the badge half this is not a
         placeholder but the final intent: Janine carries her father's Soul
         Badge, so the leader blocks hold 16 unique badge graphics. Duplicating
         8 tiles of art buys zero special-casing in the drawing code. Her FACE
         half is still a placeholder.
  17     CARD_BLOCK_UNKNOWN, the "?" glyph. See UNKNOWN_BLOCK below.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
BADGES_PNG = REPO_ROOT / "gfx" / "trainer_card" / "badges.png"

TILE = 8
BLOCK_W_TILES = 2
BLOCK_H_TILES = 4
BLOCK_H_PX = BLOCK_H_TILES * TILE  # 32
SHEET_W_PX = BLOCK_W_TILES * TILE  # 16

KANTO_BLOCKS = 8

# (destination block, source block, label). Source blocks are the Kanto eight.
APPENDED = [
    (8, 0, "FALKNER  (placeholder: Brock / Boulder)"),
    (9, 1, "BUGSY    (placeholder: Misty / Cascade)"),
    (10, 2, "WHITNEY  (placeholder: Lt. Surge / Thunder)"),
    (11, 3, "MORTY    (placeholder: Erika / Rainbow)"),
    (12, 4, "CHUCK    (placeholder: Koga / Soul)"),
    (13, 5, "JASMINE  (placeholder: Sabrina / Marsh)"),
    (14, 6, "PRYCE    (placeholder: Blaine / Volcano)"),
    (15, 7, "CLAIR    (placeholder: Giovanni / Earth)"),
    (16, 4, "JANINE   (badge INTENTIONALLY Koga's Soul Badge; face placeholder)"),
]

# The dedicated "unknown leader" block, CARD_BLOCK_UNKNOWN. Added 2026-09-11.
#
# This used to be block 7: Giovanni was vanilla's hidden eighth leader, so his
# FACE half is the "?" glyph and DrawBadges got the behaviour for free. That
# conflates two meanings the moment Giovanni gets a real portrait, which the
# next-gym-leader reveal needs, so "?" now has a block of its own.
#
# Its art comes from unknown_face.png, NOT from block 7, precisely so that
# dropping a real Giovanni face into block 7 cannot silently overwrite the "?".
#
# BOTH halves are the glyph. The badge half is reachable: RogueCardBlockForSlot
# falls back here when a recorded class is not in CardLeaderClasses, and that
# slot IS earned, so DrawBadges would draw the badge half. Better a "?" than a
# spurious Earth Badge.
UNKNOWN_BLOCK = KANTO_BLOCKS + len(APPENDED)  # 17
UNKNOWN_FACE_PNG = REPO_ROOT / "gfx" / "trainer_card" / "unknown_face.png"

TOTAL_BLOCKS = UNKNOWN_BLOCK + 1  # 18


def block_box(index: int) -> tuple[int, int, int, int]:
    top = index * BLOCK_H_PX
    return (0, top, SHEET_W_PX, top + BLOCK_H_PX)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--force", action="store_true",
                    help="overwrite even if the sheet already has all blocks")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    src = Image.open(BADGES_PNG)
    if src.mode != "L":
        # The build's rgbgfx invocation uses --colors dmg on a 4-shade greyscale
        # sheet; a mode change here would silently reshuffle the shades.
        print(f"error: {BADGES_PNG} is mode {src.mode}, expected L", file=sys.stderr)
        return 1
    if src.width != SHEET_W_PX:
        print(f"error: width {src.width}px, expected {SHEET_W_PX}px "
              f"({BLOCK_W_TILES} tiles)", file=sys.stderr)
        return 1

    have_blocks, remainder = divmod(src.height, BLOCK_H_PX)
    if remainder:
        print(f"error: height {src.height}px is not a whole number of "
              f"{BLOCK_H_PX}px blocks", file=sys.stderr)
        return 1

    if have_blocks == TOTAL_BLOCKS and not args.force:
        print(f"{BADGES_PNG.name} already has {TOTAL_BLOCKS} blocks; nothing to do.")
        print("Pass --force only if you mean to discard real Johto art.")
        return 0
    if have_blocks < KANTO_BLOCKS:
        print(f"error: only {have_blocks} blocks present, need at least "
              f"{KANTO_BLOCKS} Kanto source blocks", file=sys.stderr)
        return 1

    out = Image.new("L", (SHEET_W_PX, TOTAL_BLOCKS * BLOCK_H_PX), color=255)
    # Kanto eight copied through byte for byte: the current 64-tile blit in
    # DrawTrainerInfo must stay pixel-identical, so this cannot be a regression.
    out.paste(src.crop((0, 0, SHEET_W_PX, KANTO_BLOCKS * BLOCK_H_PX)), (0, 0))

    for dst, srcblk, label in APPENDED:
        out.paste(src.crop(block_box(srcblk)), (0, dst * BLOCK_H_PX))
        print(f"  block {dst:2d} <- block {srcblk}  {label}")

    glyph = Image.open(UNKNOWN_FACE_PNG)
    if glyph.mode != "L" or glyph.size != (SHEET_W_PX, BLOCK_H_PX // 2):
        print(f"error: {UNKNOWN_FACE_PNG.name} is {glyph.mode} {glyph.size}, "
              f"expected L {(SHEET_W_PX, BLOCK_H_PX // 2)}", file=sys.stderr)
        return 1
    top = UNKNOWN_BLOCK * BLOCK_H_PX
    out.paste(glyph, (0, top))                      # face half
    out.paste(glyph, (0, top + BLOCK_H_PX // 2))    # badge half, see above
    print(f"  block {UNKNOWN_BLOCK:2d} <- {UNKNOWN_FACE_PNG.name}  "
          f"CARD_BLOCK_UNKNOWN (both halves)")

    print(f"{have_blocks} blocks -> {TOTAL_BLOCKS} blocks "
          f"({out.height}px tall, {TOTAL_BLOCKS * 8} tiles, "
          f"{TOTAL_BLOCKS * 8 * 16} bytes of .2bpp)")

    if args.dry_run:
        print("--dry-run: not written")
        return 0

    out.save(BADGES_PNG)
    print(f"wrote {BADGES_PNG}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
