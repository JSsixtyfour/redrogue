"""Render a region of a generated cave to a PNG, from real tileset graphics.

Built to answer "what does this actually look like?" about a one-block
difference, which neither a block-ID dump nor a live screenshot answers well: a
dump is unreadable, and a screenshot cannot show the same spot in two states at
once because only one of them exists in any given build.

This renders straight from the assets the ROM is built out of -
`gfx/blocksets/cavern.bst` (16 tile indices per block, 4x4) and
`gfx/tilesets/cavern.2bpp` (8x8 tiles, 2 bits per pixel) - so what comes out is
what the Game Boy draws, at 4 tiles = 32 pixels per block, with no emulator
positioning needed.

`--patch X,Y=ID` overrides a block before rendering, which is what makes the A/B
possible: render the cave as it is, then render it again with one block forced
back to the value an earlier pass had left there, and put the two side by side.

Usage:
    python3 tools/pyboy_smoke/render_cave_region.py --seed 4 --centre 14,9 \\
        --radius 3 --out before.png --patch 14,9=24
    python3 tools/pyboy_smoke/render_cave_region.py --seed 4 --centre 14,9 \\
        --radius 3 --out after.png
"""

from __future__ import annotations

import argparse
import random
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    print("needs Pillow: pip install pillow")
    raise

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

PC_SIZE = 20
PC_STRIDE = 26
PC_BASE = 81
RNG_STATE_BYTES = 10

BLOCKSET = REPO_ROOT / "gfx" / "blocksets" / "cavern.bst"
TILESET = REPO_ROOT / "gfx" / "tilesets" / "cavern.2bpp"

# The DMG greys, darkest first, as the cave's palette orders them.
SHADES = ((255, 255, 255), (168, 168, 168), (88, 88, 88), (0, 0, 0))

SCALE = 4        # each Game Boy pixel becomes a 4x4 block, so the tile is legible
TILE_PX = 8
BLOCK_TILES = 4
BLOCK_PX = TILE_PX * BLOCK_TILES


def load_tiles() -> list[list[list[int]]]:
    """Each tile as 8 rows of 8 palette indices."""
    raw = TILESET.read_bytes()
    tiles = []
    for base in range(0, len(raw), 16):
        rows = []
        for y in range(TILE_PX):
            low, high = raw[base + y * 2], raw[base + y * 2 + 1]
            rows.append(
                [
                    ((low >> (7 - x)) & 1) | (((high >> (7 - x)) & 1) << 1)
                    for x in range(TILE_PX)
                ]
            )
        tiles.append(rows)
    return tiles


def load_blocks() -> list[list[int]]:
    raw = BLOCKSET.read_bytes()
    return [list(raw[i : i + 16]) for i in range(0, len(raw), 16)]


def read_grid(harness: RedRogueHarness) -> list[list[int]]:
    origin = harness.address("wOverworldMap") + PC_BASE
    return [
        [harness.pyboy.memory[origin + y * PC_STRIDE + x] for x in range(PC_SIZE)]
        for y in range(PC_SIZE)
    ]


def generate(map_id: int, seed: int) -> list[list[int]]:
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
        return read_grid(harness)
    finally:
        try:
            harness.close()
        except Exception:
            pass


def render(grid, x0, y0, x1, y1, tiles, blocks, mark=None) -> Image.Image:
    width = (x1 - x0 + 1) * BLOCK_PX
    height = (y1 - y0 + 1) * BLOCK_PX
    image = Image.new("RGB", (width, height))
    pixels = image.load()
    for by in range(y0, y1 + 1):
        for bx in range(x0, x1 + 1):
            block = grid[by][bx]
            definition = blocks[block] if block < len(blocks) else [0] * 16
            for ty in range(BLOCK_TILES):
                for tx in range(BLOCK_TILES):
                    tile = tiles[definition[ty * BLOCK_TILES + tx] % len(tiles)]
                    ox = (bx - x0) * BLOCK_PX + tx * TILE_PX
                    oy = (by - y0) * BLOCK_PX + ty * TILE_PX
                    for py in range(TILE_PX):
                        for px in range(TILE_PX):
                            pixels[ox + px, oy + py] = SHADES[tile[py][px]]
    image = image.resize((width * SCALE, height * SCALE), Image.NEAREST)
    if mark is not None:
        mx, my = mark
        draw = ImageDraw.Draw(image)
        left = (mx - x0) * BLOCK_PX * SCALE
        top = (my - y0) * BLOCK_PX * SCALE
        draw.rectangle(
            [left, top, left + BLOCK_PX * SCALE - 1, top + BLOCK_PX * SCALE - 1],
            outline=(255, 0, 0),
            width=3,
        )
    return image


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--centre", required=True, help="block X,Y to centre on")
    parser.add_argument("--radius", type=int, default=3)
    parser.add_argument("--out", required=True)
    parser.add_argument(
        "--patch",
        action="append",
        default=[],
        help="X,Y=ID - force a block before rendering, e.g. 14,9=24",
    )
    parser.add_argument("--no-mark", action="store_true")
    args = parser.parse_args()

    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]
    cx, cy = (int(v) for v in args.centre.split(","))
    grid = generate(map_id, args.seed)

    for patch in args.patch:
        coords, value = patch.split("=")
        px, py = (int(v) for v in coords.split(","))
        print("patch (%d,%d): %d -> %d" % (px, py, grid[py][px], int(value)))
        grid[py][px] = int(value)

    x0, x1 = max(0, cx - args.radius), min(PC_SIZE - 1, cx + args.radius)
    y0, y1 = max(0, cy - args.radius), min(PC_SIZE - 1, cy + args.radius)

    print("block grid around (%d,%d):" % (cx, cy))
    for y in range(y0, y1 + 1):
        print("   " + " ".join("%3d" % grid[y][x] for x in range(x0, x1 + 1)))

    image = render(
        grid, x0, y0, x1, y1, load_tiles(), load_blocks(),
        mark=None if args.no_mark else (cx, cy),
    )
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print("wrote %s (%dx%d)" % (out, image.width, image.height))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
