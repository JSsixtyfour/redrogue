"""Measure where the cave subroom's two ladders down could go (PROCEDURAL_SUBROOMS_PLAN Phase 4).

A warp's ARRIVAL tile is fixed in ROM, so a ladder the player climbs back out
onto must sit on a site declared at build time. This script generates real
caves (fresh boot per layout, through the real warp-in) and, for every block,
asks whether a ladder could go there:

  * the block is plain floor (PC_BLOCK_FLOOR); the ladder is block 40, whose
    only ladder quadrant is the bottom-right one, so its other three stay floor;
  * the 5 quadrants outside the block that ring the ladder quadrant (E block's
    left column, S block's top row, SE's top-left) are walkable, so any route
    through the ladder can go round it (stepping on it leaves the cave);
  * nothing within one block: the entrance, the exit, the boss or a ball; and
    not within two of the stage-event hideout (its villains see 4 tiles, and a
    battle started on a warp tile takes the warp afterwards);
  * and, checked rather than assumed, a flood from the entrance with the ladder
    quadrant removed still reaches everything else it reached.

Walkability is a quadrant's BOTTOM-LEFT tile against Cavern_Coll (the tile the
engine tests, measured in the forest; see tools/forest_clearings.py).

It then picks K fixed sites greedily so the most layouts get TWO valid sites at
least --min-distance blocks apart (Manhattan), and reports coverage per K on
the sample and on a held-out set.

    python3 tools/pyboy_smoke/audit_cave_ladder_sites.py --layouts 200 --held-out 100

--runtime checks what the ROM actually did against this model, per layout: each
drawn ladder is a shipped site the model accepts (judged on the map before the
ladders were stamped), the two are CAVE_LADDER_MIN_DISTANCE apart, a single
ladder only when no far partner exists, none only when no site exists, and
exactly their warps are armed. It exits non-zero on any problem.

    python3 tools/pyboy_smoke/audit_cave_ladder_sites.py --runtime --layouts 300
"""

from __future__ import annotations

import argparse
import random
import re
import sys
from itertools import combinations
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
PC_SIZE, PC_STRIDE, PC_BASE = 20, 26, 81
FLOOR, LADDER = 1, 40
ENTRANCE_BLOCK = (9, 19)
RNG_STATE_BYTES = 10
TAIL = 81 + 19 * 26 + 20     # CAVESUB_TAIL: ladder A, ladder B
RUNTIME = []                 # what the ROM stored and armed, for the last sample
ROOM_WARPS = [tuple(int(v) for v in m) for m in re.findall(
    r"^\tcave_subroom_room \w+,\s*\d+,\s*\d+,\s*(\d+),\s*(\d+),",
    (REPO_ROOT / "custom_functions/cave_subroom.asm").read_text(encoding="utf-8"), re.M)]
_SITE_TEXT = (REPO_ROOT / "constants" / "cave_ladder_site_constants.asm").read_text(encoding="utf-8")
SITES = [(int(x), int(y)) for x, y in re.findall(r"^\tladder_site\s+(\d+),\s*(\d+)", _SITE_TEXT, re.M)]
FIRST_WARP = int(re.search(r"CAVE_FIRST_LADDER_WARP EQU (\d+)", _SITE_TEXT).group(1))
MIN_DISTANCE = int(re.search(r"CAVE_LADDER_MIN_DISTANCE EQU (\d+)", _SITE_TEXT).group(1))
NONE = 0xFF
UNREACHED = [0]   # sites a walkable-only rule would accept but the flood rejects
QUADRANT = (4, 6, 12, 14)   # bottom-left tile of TL, TR, BL, BR


def passable_tiles() -> set:
    text = (REPO_ROOT / "data" / "tilesets" / "collision_tile_ids.asm").read_text()
    line = text[text.index("Cavern_Coll::"):].split("\n")[1]
    return {int(tok.strip().lstrip("$"), 16) for tok in line.split("coll_tiles")[1].split(",")}


def cells_of(grid, blockset, passable) -> set:
    cells = set()
    for by in range(PC_SIZE):
        for bx in range(PC_SIZE):
            for q, i in enumerate(QUADRANT):
                if blockset[grid[by][bx] * 16 + i] in passable:
                    cells.add((2 * bx + q % 2, 2 * by + q // 2))
    return cells


def flood(cells, start) -> set:
    if start not in cells:
        return set()
    seen, todo = {start}, [start]
    while todo:
        x, y = todo.pop()
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if n in cells and n not in seen:
                seen.add(n)
                todo.append(n)
    return seen


def sample(harness_seed: int, map_id: int):
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        h.boot_to_lobby()
        rng = random.Random(harness_seed)
        base = h.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            h.pyboy.memory[base + offset] = rng.randrange(1, 256)
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(map_id, "Procedural Cave")
        origin = h.address("wOverworldMap") + PC_BASE
        grid = [[h.pyboy.memory[origin + y * PC_STRIDE + x] for x in range(PC_SIZE)]
                for y in range(PC_SIZE)]
        player = (h.read8("wXCoord"), h.read8("wYCoord"))
        sprites = [(x, y) for y, x in h.sprite_positions(5)]          # boss, 4 balls (steps)
        exit_yx = h.read_sram_bytes("sProcCaveStagingExitY", 2, bank=0)
        hideout = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
        RUNTIME[:] = [h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 4, bank=0)[TAIL:],
                      h.warp_entries()]
        return grid, player, sprites, (exit_yx[1], exit_yx[0]), hideout
    finally:
        try:
            h.close()
        except Exception:
            pass


def valid_sites(grid, player, sprites, exit_block, hideout, blockset, passable):
    cells = cells_of(grid, blockset, passable)
    reach = flood(cells, player)
    occupied = {(sx // 2, sy // 2) for sx, sy in sprites} | {ENTRANCE_BLOCK, exit_block}
    sites, strand = set(), 0
    for by in range(1, PC_SIZE - 1):
        for bx in range(1, PC_SIZE - 1):
            if grid[by][bx] != FLOOR:
                continue
            qx, qy = 2 * bx + 1, 2 * by + 1
            ring = [(qx + 1, qy - 1), (qx + 1, qy), (qx + 1, qy + 1), (qx, qy + 1), (qx - 1, qy + 1)]
            if any(q not in reach for q in ring):
                if all(q in cells for q in ring) and not any(
                        (bx + dx, by + dy) in occupied for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                    UNREACHED[0] += 1             # walkable but cut off: the ROM can't flood
                continue
            if any((bx + dx, by + dy) in occupied for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                continue
            # The hideout: two blocks, not one (the villains there see 4 tiles).
            if hideout[0] != 0xFF and abs(hideout[0] - bx) <= 2 and abs(hideout[1] - by) <= 2:
                continue
            ladder = (qx, qy)
            if flood(cells - {ladder}, player) != reach - {ladder}:
                strand += 1                           # the ring rule was wrong here
                continue
            sites.add((bx, by))
    return sites, strand


def has_pair(sites, distance) -> bool:
    return any(abs(a[0] - b[0]) + abs(a[1] - b[1]) >= distance for a, b in combinations(sites, 2))


def check_runtime(seed, grid, player, sprites, exit_block, hideout, blockset, passable, map_ids, tally) -> int:
    (a, b, _state, room_byte), warps = RUNTIME
    # The subroom room this cave rolled names the two warps its ladders lead to
    # (CaveSubRooms in custom_functions/cave_subroom.asm; past the table = the first).
    room_warps = ROOM_WARPS[room_byte & 3] if room_byte & 3 < len(ROOM_WARPS) else ROOM_WARPS[0]
    unstamped = [row[:] for row in grid]
    for site in (a, b):
        if site < len(SITES):
            x, y = SITES[site]
            if unstamped[y][x] == LADDER:
                unstamped[y][x] = FLOOR
    model, _ = valid_sites(unstamped, player, sprites, exit_block, hideout, blockset, passable)
    shipped = [n for n, s in enumerate(SITES) if s in model]
    problems = []
    def far(m, n):
        (x1, y1), (x2, y2) = SITES[m], SITES[n]
        return abs(x1 - x2) + abs(y1 - y2) >= MIN_DISTANCE
    if a >= len(SITES):
        if shipped:
            problems.append(f"no ladder although {len(shipped)} sites were valid")
        # The resident's fallback: a block of the model's (all blocks, not only
        # the sites), stored as $80 | X, $40 | Y; $FF in both when none.
        if a == NONE and b == NONE:
            if model:
                problems.append(f"no fallback although {len(model)} blocks were valid")
        else:
            tally["fallback"] = tally.get("fallback", 0) + 1
            spot = (a & 0x7F, b & 0x3F)
            if a & 0x80 == 0 or b & 0xC0 != 0x40 or spot not in model:
                problems.append(f"fallback {a:#x}/{b:#x} fails the model")
        a = b = NONE                  # no ladder: every site warp must be disarmed
    else:
        tally["one"] += 1
        if a not in shipped:
            problems.append(f"ladder A {SITES[a]} fails the model")
        if b == NONE:
            if any(far(a, n) for n in shipped):
                problems.append("one ladder although a far partner was valid")
        else:
            tally["two"] += 1
            if b not in shipped or not far(a, b):
                problems.append(f"ladder B {SITES[b]} fails the model or is too close")
        for site in (a, b):
            if site < len(SITES):
                x, y = SITES[site]
                if grid[y][x] != LADDER:
                    problems.append(f"no ladder drawn at {SITES[site]}")
    for n, (x, y) in enumerate(SITES):
        entry = warps[FIRST_WARP + n]
        if n == a or n == b:
            if entry != [2 * y + 1, 2 * x + 1, room_warps[0 if n == a else 1], map_ids["PROCEDURAL_CAVE_SUBROOM"]]:
                problems.append(f"site {n} armed as {entry}")
        elif entry[0] != NONE:
            problems.append(f"site {n} not disarmed: {entry}")
    for line in problems:
        print(f"seed {seed}: {line}")
    return len(problems)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--layouts", type=int, default=200)
    ap.add_argument("--held-out", type=int, default=100)
    ap.add_argument("--min-distance", type=int, default=10)
    ap.add_argument("--max-sites", type=int, default=30)
    ap.add_argument("--runtime", action="store_true")
    args = ap.parse_args()
    blockset = (REPO_ROOT / "gfx" / "blocksets" / "cavern.bst").read_bytes()
    passable = passable_tiles()
    map_ids = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
    map_id = map_ids["PROCEDURAL_CAVE_1"]

    if args.runtime:
        tally = {"one": 0, "two": 0}
        problems = 0
        for seed in range(args.layouts):
            sample_ = sample(seed, map_id)
            problems += check_runtime(seed, *sample_, blockset, passable, map_ids, tally)
        print(f"layouts {args.layouts}: a ladder in {tally['one']}, two ladders in {tally['two']}, "
              f"resident fallback in {tally.get('fallback', 0)}, problems {problems}")
        return 1 if problems else 0

    def collect(seeds):
        out, strands = [], 0
        for seed in seeds:
            grid, player, sprites, exit_block, hideout = sample(seed, map_id)
            sites, strand = valid_sites(grid, player, sprites, exit_block, hideout, blockset, passable)
            strands += strand
            out.append(sites)
        return out, strands

    train, s1 = collect(range(args.layouts))
    test, s2 = collect(range(10000, 10000 + args.held_out))
    counts = [len(s) for s in train]
    print(f"layouts {len(train)}: valid blocks per layout min {min(counts)} "
          f"mean {sum(counts) / len(counts):.1f} max {max(counts)}; ring rule wrong {s1 + s2} times")
    print(f"sites walkable but unreachable (a walkable-only rule would take them): {UNREACHED[0]}")
    print(f"any valid pair (no fixed sites) at distance >= {args.min_distance}: "
          f"{100 * sum(has_pair(s, args.min_distance) for s in train) / len(train):.0f}%")

    chosen = []
    for k in range(1, args.max_sites + 1):
        best, best_hits = None, -1
        candidates = set().union(*train) - set(chosen)
        for c in candidates:
            pick = set(chosen) | {c}
            hits = sum(has_pair(s & pick, args.min_distance) for s in train)
            if hits > best_hits:
                best, best_hits = c, hits
        if best is None:
            break
        chosen.append(best)
        pick = set(chosen)
        held = sum(has_pair(s & pick, args.min_distance) for s in test)
        print(f"K={k:2} add {best}: pair in-sample {100 * best_hits / len(train):.0f}%, "
              f"held-out {100 * held / len(test):.0f}%")
    pick = set(chosen)
    print(f"held-out with at least one chosen site: {100 * sum(bool(s & pick) for s in test) / len(test):.0f}%")
    print("chosen:", chosen)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
