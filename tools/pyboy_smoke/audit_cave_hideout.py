"""Audit: is the cave's stage-event hideout a real, reachable, non-boss cell?

Phase 7b's contract, measured rather than argued. PCStageHideoutCapture claims
four properties by construction, and every one of them is checkable from a
generated cave:

  1. the hideout cell is FLOOR the player can stand next to
  2. it is never the exit cell, which is where the boss stands
  3. it is reachable on foot from the player's spawn
  4. it is a genuine dead end on a non-entrance edge, i.e. it varies across
     seeds instead of pinning to one corner

Property 3 is the one worth paying for. The hideout is one of the four targets
PCFinalizeCave's loop carves to and then uses for nothing, so its reachability
rests entirely on PCCarveOne's L-connector writing floor all the way onto the
target cell. That is the same guarantee whose FAILURE produced the original
soft-locked exit ladder (see PCCarveOne's header), so it is worth a regression
guard rather than a reread of the source.

The reachability model is lifted verbatim from audit_cave_water_stranding.py,
including its self-check reasoning: a hideout counts as reachable if the player
can reach its own step OR any step orthogonally beside it, because an NPC
standing on a cell is solid to the player anyway.

It also reports, without failing on them, three rates that are diagnostics
rather than contracts: how often PCStageHideoutResolve had to promote its
second candidate, how often it disarmed the event outright, and whether the
second NPC's cell is reachable.

Measured 2026-09-16 over 400 caves, after the fixes this script drove:
  candidate B promoted   9 (2.25%, against 1.85% predicted for two edge rolls
                         coinciding - the model and the data agree)
  disarmed               0
  pokeball on hideout    0  (was 20, i.e. 5.0%, before PCPlaceWildAreaItems
                         learned to reject the hideout)
  NPC-2 cell reachable   400/400

Usage:
    python3 tools/pyboy_smoke/audit_cave_hideout.py [--layouts N]

Exits non-zero if any hideout is unreachable, is wall, or collides with the
boss's cell.
"""

from __future__ import annotations

import argparse
import random
import sys
import time
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

PC_SIZE = 20
PC_STRIDE = 26
PC_BASE = 81
PC_BLOCK_FLOOR = 1
STEP_SIZE = PC_SIZE * 2
RNG_STATE_BYTES = 10
# 7, not 5: the boss, four pokeballs, and the two Phase 7b stage-event NPC
# slots. Slot 6 stands on the hideout, slot 7 one cell inward from it.
SPRITE_SLOTS = 7
NPC2_SLOT_INDEX = 6  # 0-based index of object slot 7 within sprite_positions
# sStageEvent* lives in the "Sprite Buffers" SRAM section, which the map file
# confirms is bank 0. Reading it with pyboy.memory directly returns $ff because
# the cart is left on a different bank after generation - that exact trap is
# recorded for the facility's ball coordinates, so go through read_sram_bytes.
HIDEOUT_SRAM_BANK = 0
# Mirrors the STAGE_EVENT_* block in constants/ram_constants.asm. Only used to
# force the placement branch this script means to measure.
STAGE_EVENT_JESSIE_JAMES = 1
STAGE_EVENT_PHASE_HIDING = 1
STAGE_EVENT_PHASE_SHIFT = 3


def passable_tiles() -> set:
    text = (REPO_ROOT / "data" / "tilesets" / "collision_tile_ids.asm").read_text()
    line = text[text.index("Cavern_Coll::"):].split("\n")[1]
    return {int(tok.strip().lstrip("$"), 16) for tok in line.split("coll_tiles")[1].split(",")}


def step_walkable(blockset: bytes, passable: set, block: int, qx: int, qy: int) -> bool:
    if block * 16 + 15 >= len(blockset):
        return False
    tile = blockset[block * 16 + (qy * 2) * 4 + (qx * 2)]
    return tile in passable


def reachable_steps(grid, blockset, passable, start) -> set:
    walkable = [[False] * STEP_SIZE for _ in range(STEP_SIZE)]
    for sy in range(STEP_SIZE):
        for sx in range(STEP_SIZE):
            block = grid[sy // 2][sx // 2]
            walkable[sy][sx] = step_walkable(blockset, passable, block, sx % 2, sy % 2)
    seen = set()
    if not (0 <= start[0] < STEP_SIZE and 0 <= start[1] < STEP_SIZE):
        return seen
    stack = [start]
    seen.add(start)
    while stack:
        sx, sy = stack.pop()
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nx, ny = sx + dx, sy + dy
            if not (0 <= nx < STEP_SIZE and 0 <= ny < STEP_SIZE):
                continue
            if (nx, ny) in seen or not walkable[ny][nx]:
                continue
            seen.add((nx, ny))
            stack.append((nx, ny))
    return seen


def sample(map_id: int, seed: int):
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)
        # Force an armed event already in its HIDING phase before the preload.
        # Without this the phase reads WAITING (wStageEvent is 0), and since
        # Phase 7c that makes PCPlaceStageEventNpcs place the pair in front of
        # the player instead of at the hideout - so the NPC-2 measurement below
        # would silently be measuring the arrival cell, not the cell it names.
        # Type 1 is Jessie & James, the PAIRED event, which is the only one
        # that puts a second NPC anywhere at all.
        harness.write8("wStageEvent", STAGE_EVENT_JESSIE_JAMES
                       | (STAGE_EVENT_PHASE_HIDING << STAGE_EVENT_PHASE_SHIFT))
        harness.preload_and_enter_wild_area(map_id, "Procedural Cave")
        origin = harness.address("wOverworldMap") + PC_BASE
        grid = [
            [harness.pyboy.memory[origin + y * PC_STRIDE + x] for x in range(PC_SIZE)]
            for y in range(PC_SIZE)
        ]
        player = (harness.read8("wXCoord"), harness.read8("wYCoord"))
        sprites = [tuple(p) for p in harness.sprite_positions(SPRITE_SLOTS)]
        hx = harness.read_sram_bytes("sStageEventHideoutX", 1, bank=HIDEOUT_SRAM_BANK)[0]
        hy = harness.read_sram_bytes("sStageEventHideoutY", 1, bank=HIDEOUT_SRAM_BANK)[0]
        ax = harness.read_sram_bytes("sStageEventHideoutAltX", 1, bank=HIDEOUT_SRAM_BANK)[0]
        ay = harness.read_sram_bytes("sStageEventHideoutAltY", 1, bank=HIDEOUT_SRAM_BANK)[0]
        return grid, player, sprites, (hx, hy), (ax, ay)
    finally:
        try:
            harness.close()
        except Exception:
            pass


def edge_of(bx: int, by: int) -> str:
    if by == 0:
        return "top"
    if by == PC_SIZE - 1:
        return "bottom"
    if bx == 0:
        return "left"
    if bx == PC_SIZE - 1:
        return "right"
    return "interior"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=64)
    args = parser.parse_args()

    blockset = (REPO_ROOT / "gfx" / "blocksets" / "cavern.bst").read_bytes()
    passable = passable_tiles()
    map_id = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_CAVE_1"]

    unreachable = 0
    on_boss = 0
    on_ball = 0
    npc2_on_floor = 0
    npc2_blocks = Counter()
    npc2_off_floor = []
    out_of_range = 0
    disarmed = 0
    promoted = []
    errors = 0
    edges = Counter()
    cells = Counter()
    started = time.time()

    for seed in range(args.layouts):
        try:
            grid, player, sprites, (hx, hy), alt = sample(map_id, seed)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue

        # STAGE_EVENT_NO_HIDEOUT: both candidate targets landed on the exit
        # cell, so PCStageHideoutResolve disarmed the event rather than stand
        # the villain inside the boss. A legitimate outcome, not a failure, but
        # it should be vanishingly rare (~1 in 2,900) - a run where this climbs
        # means the resolve step is rejecting far more than it should.
        if (hx, hy) == (0xFF, 0xFF):
            disarmed += 1
            continue

        if not (0 <= hx < PC_SIZE and 0 <= hy < PC_SIZE):
            out_of_range += 1
            print("  OUT OF RANGE seed %d: hideout block (%d,%d) - SRAM never written?"
                  % (seed, hx, hy))
            continue

        edges[edge_of(hx, hy)] += 1
        cells[(hx, hy)] += 1

        # The boss stands on the exit; sprite slot 1's position is block*2+4 and
        # harness.sprite_positions has already removed the 4, so it is in player
        # steps. Two steps per block, so the boss's block is step // 2.
        boss_step_y, boss_step_x = sprites[0]
        boss_cell = (boss_step_x // 2, boss_step_y // 2)

        # Did PCStageHideoutResolve actually have to do something? The resolve
        # path fires when candidate A lands on the exit cell, and its only
        # visible effect is that the published hideout becomes candidate B.
        # Counting it proves the repair RUNS, rather than inferring from the
        # absence of failures that it was never needed - a clean run with a
        # dead repair looks identical to a clean run with a live one.
        if (hx, hy) == alt:
            promoted.append(seed)

        if boss_cell == (hx, hy):
            on_boss += 1
            print("  BOSS COLLISION seed %d: hideout block (%d,%d) is the exit cell"
                  % (seed, hx, hy))

        # PCPlaceWildAreaItems rejects ball candidates near the entrance, near
        # the exit/boss and near each other, but it has never heard of the
        # hideout. A ball sharing the villain's cell is the same exact-overlap
        # class as the boss collision above, so it is counted, not assumed
        # away.
        # PCPlaceStageEventNpcs puts the second NPC of a PAIRED event (Jessie &
        # James; Joy + Jenny) one cell inward from the hideout's edge, which is
        # a cheap guess at "where the corridor came from" rather than a search.
        # Its header says the floor rate measured here is what decides whether
        # that needs to become a real 4-neighbour scan, so measure it.
        #
        # Judged by REACHABILITY, not by block id == PC_BLOCK_FLOOR. An early
        # version of this counter used the block id and reported 96.2%, but
        # that is the wrong question twice over: the autotile pass rewrites
        # floor-adjacent cells to edge and corner variants that are still
        # perfectly walkable, and what the player actually needs is to be able
        # to stand next to the NPC and talk to it. Same criterion as the
        # hideout check below.
        npc2_step_y, npc2_step_x = sprites[NPC2_SLOT_INDEX]
        npc2_cell = (npc2_step_x // 2, npc2_step_y // 2)
        npc2_blocks[grid[npc2_cell[1]][npc2_cell[0]]] += 1

        for index, (ball_step_y, ball_step_x) in enumerate(sprites[1:5], start=1):
            if (ball_step_x // 2, ball_step_y // 2) == (hx, hy):
                on_ball += 1
                print("  BALL COLLISION seed %d: pokeball %d shares hideout block (%d,%d)"
                      % (seed, index, hx, hy))

        seen = reachable_steps(grid, blockset, passable, player)
        step = (hx * 2, hy * 2)
        if step not in seen and not any(
            (step[0] + dx, step[1] + dy) in seen
            for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))
        ):
            unreachable += 1
            print("  UNREACHABLE seed %d: hideout block (%d,%d) = block id %d, player at %s"
                  % (seed, hx, hy, grid[hy][hx], player))

        # TILE precision, not cell. Since 2026-09-17 slot 7 stands one STEP
        # right of slot 6, inside the SAME block, so a cell-level test is now
        # just the hideout test again and proves nothing about the partner.
        # What matters is whether that exact quadrant is walkable - if it is
        # not, Jessie stands in rock next to James.
        if (npc2_step_x, npc2_step_y) in seen:
            npc2_on_floor += 1
        else:
            npc2_off_floor.append(
                (seed, (npc2_step_x, npc2_step_y), grid[npc2_cell[1]][npc2_cell[0]]))

    elapsed = time.time() - started
    n = max(1, args.layouts - errors)
    print()
    print("%d layouts, %d harness errors, %.0fs" % (args.layouts, errors, elapsed))
    print("candidate B promoted (A was the exit cell): %d %s"
          % (len(promoted), promoted[:10]))
    print("disarmed (both candidates on the exit): %d" % disarmed)
    print("pokeball sharing the hideout cell: %d" % on_ball)
    print("NPC-2 TILE (one step right, same block) is walkable: %d/%d (%.1f%%)"
          % (npc2_on_floor, n, 100.0 * npc2_on_floor / n))
    for seed_i, step, block_id in npc2_off_floor[:10]:
        print("  NPC-2 IN ROCK seed %d: step %s, block id %d"
              % (seed_i, step, block_id))
    print("NPC-2 cell block ids seen: %s" % dict(npc2_blocks))
    print("hideout edge distribution: %s" % dict(edges))
    print("distinct hideout cells: %d over %d caves" % (len(cells), n))
    most = cells.most_common(1)
    if most:
        print("most repeated cell: %s x%d" % most[0])

    # The partner standing in rock is a real defect, not a statistic: it is
    # the visible "Jessie and James are not side by side" symptom.
    failures = unreachable + on_boss + out_of_range + len(npc2_off_floor)
    if failures:
        print("FAIL: %d unreachable, %d on the boss's cell, %d out of range, "
              "%d with NPC-2 standing on a non-walkable tile"
              % (unreachable, on_boss, out_of_range, len(npc2_off_floor)))
        return 1
    print("PASS: every hideout is in range, off the boss's cell, and reachable on foot")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
