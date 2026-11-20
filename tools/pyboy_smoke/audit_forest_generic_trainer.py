#!/usr/bin/env python3
"""Audit: the Forest's generic route trainer (GENERIC_TRAINER_TRIAL_SPEC.md).

For each Forest (real warp-in, one fresh boot per seed, like
audit_forest_house.py) with GENERIC_TRAINER_ODDS at 256, this checks that the
trainer, object FOREST_GENERIC, is:

  * present (a picture and a cell), apart from the rare Forest with no usable
    dead end, whose rate is reported and held under MAX_NO_CELL;
  * on a maze cell that is not a tree, a ball, the boss, the entrance block
    (9, 17) or within two blocks of the stage event's hideout;
  * facing an open block, so his one-tile sight covers the way in;
  * never wearing the villain's picture (slot 6 or 7), and carrying a roster
    class from the table.

Usage:
    python3 tools/pyboy_smoke/audit_forest_generic_trainer.py [--seeds 300]
"""

from __future__ import annotations

import argparse
import random
import re
from collections import Counter
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
SLOT = 9
PF_STRIDE, PF_BASE, PF_TREE = 26, 81, 2
FACING = {0: (0, 1), 4: (0, -1), 8: (-1, 0), 12: (1, 0)}
MAX_NO_CELL = 0.05


def table_classes() -> list[str]:
    """The Forest pool's (OPP, SPRITE) pairs: WGTForestPool's indices into
    WGTClasses, whose rows are in `const WGT_*` order."""
    text = (REPO_ROOT / "custom_functions/forest_generic_trainer.asm").read_text(encoding="utf-8")
    order = re.findall(r"^\s*const (WGT_\w+)", text, re.M)
    body = text.split("WGTClasses:")[1].split("ASSERT")[0]
    rows = re.findall(r"wgt_class\s+(OPP_\w+),\s*(SPRITE_\w+)", body)
    pool = re.search(r"^WGTForestPool:\s*\n\s*db \d+, ([^\n;]+)", text, re.M).group(1)
    return [rows[order.index(name.strip())] for name in pool.split(",")]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=300)
    parser.add_argument("--start", type=int, default=0, help="first seed (to split a long run)")
    args = parser.parse_args()

    maps = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")
    sprites = parse_rgbds_constants(REPO_ROOT / "constants/sprite_constants.asm")
    forest = maps["PROCEDURAL_FOREST"]
    rows = table_classes()
    row_sprites = {sprites[s] for _, s in rows}
    used: Counter = Counter()
    problems = absent = errors_run = 0
    for seed in range(args.start, args.start + args.seeds):
        h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby()
            rng = random.Random(seed)
            base = h.address("wRandomTable")
            for offset in range(10):
                h.pyboy.memory[base + offset] = rng.randrange(1, 256)
            h.preload_and_enter_wild_area(forest, "Procedural Forest")
        except Exception as exc:
            errors_run += 1
            print(f"seed {seed}: harness {type(exc).__name__}: {exc}")
            h.close()
            continue

        def pos(slot: int) -> tuple[int, int]:
            return (h.read8(f"wSprite{slot:02d}StateData2MapX") - 4,
                    h.read8(f"wSprite{slot:02d}StateData2MapY") - 4)

        picture = h.read8(f"wSprite{SLOT:02d}StateData1PictureID")
        facing = h.read8(f"wSprite{SLOT:02d}StateData1FacingDirection")
        tx, ty = pos(SLOT)
        blocks = h.read_bytes("wOverworldMap", PF_BASE + 20 * PF_STRIDE)
        others = {slot: (pos(slot), h.read8(f"wSprite{slot:02d}StateData1PictureID"))
                  for slot in (1, 2, 3, 4, 5, 6, 7)}
        hx, hy = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
        h.close()

        found = []
        if not picture:
            absent += 1
        else:
            used[picture] += 1
            bx, by = tx // 2, ty // 2
            if (tx % 2, ty % 2) != (0, 0) or (bx % 2, by % 2) != (1, 1):
                found.append(f"not on a maze cell: ({tx}, {ty})")
            elif blocks[PF_BASE + by * PF_STRIDE + bx] == PF_TREE:
                found.append(f"in a tree at block ({bx}, {by})")
            else:
                dx, dy = FACING.get(facing, (0, 0))
                if (dx, dy) == (0, 0):
                    found.append(f"facing byte {facing:#x}")
                elif blocks[PF_BASE + (by + dy) * PF_STRIDE + bx + dx] == PF_TREE:
                    found.append(f"faces a tree from ({bx}, {by})")
            if picture not in row_sprites:
                found.append(f"picture {picture:#x} is not a table sprite")
            for slot, (cell, pic) in others.items():
                if pic and cell == (tx, ty):
                    found.append(f"stands on slot {slot}")
                if slot in (6, 7) and pic and pic == picture:
                    found.append(f"wears slot {slot}'s picture {pic:#x}")
            if (bx, by) == (9, 17):
                found.append("on the entrance block")
            if hx != 0xFF and abs(hx - bx) <= 2 and abs(hy - by) <= 2:
                found.append(f"within two blocks of the hideout ({hx}, {hy})")
        for line in found:
            problems += 1
            print(f"seed {seed}: {line}")

    ran = args.seeds - errors_run
    print(f"forests {ran}, trainers {sum(used.values())}, none {absent}, problems {problems}, "
          f"harness errors {errors_run}")
    print("pictures:", dict(used))
    if ran and absent / ran > MAX_NO_CELL:
        print(f"FAIL: {absent}/{ran} Forests had no trainer (> {MAX_NO_CELL:.0%})")
        return 1
    return 1 if problems or errors_run else 0


if __name__ == "__main__":
    raise SystemExit(main())
