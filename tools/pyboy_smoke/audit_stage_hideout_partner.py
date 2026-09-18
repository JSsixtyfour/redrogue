"""Audit: the second stage-event NPC stands on a walkable tile beside the first.

Since 2026-09-17 every wild area places the pair the same way: slot N on the
hideout block's TOP-LEFT quadrant, slot N+1 one STEP right, in the same block's
top-right quadrant. That replaced three different "step one cell inward"
schemes which moved a whole BLOCK (two steps, or four in the forest, where a
cell is two blocks) and which on a top or bottom edge stepped VERTICALLY, so
Jessie and James were not side by side and sometimes not even on the same row.

Standing them inside the hideout block is only safe if the block's top-right
quadrant is actually floor. `audit_cave_hideout.py` measured that for the CAVE
at 200/200, but the forest and facility use different blocksets and different
hideout semantics, so that result does not transfer:

  cave      hideout = a dead-end maze cell
  forest    hideout = a dead-end maze cell, but cells are 2 blocks apart
  facility  hideout = a room CENTER, and the block beside it can be the room's
                      wall ring - the one case where the old "step a whole
                      block" scheme was most likely to land in a wall, and the
                      main reason this audit exists

WHAT IS MEASURED, and why it is reachability rather than block id: the autotile
passes rewrite floor-adjacent blocks into edge and corner variants that are
still perfectly walkable, so `block == FLOOR` condemns correct placements. The
cave learned this the hard way - by block id the same 400 caves read 96.2%, by
reachability 400/400. What the player actually needs is to be able to walk up
to the NPC and talk to it, so the test is: is the partner's exact TILE in the
flood fill from the player's spawn.

THE COLLISION MODEL, and its self-check. A movement step is a 2x2 patch of
tiles, and _GetTileAndCoordsInFrontOfPlayer reads screen tile (8,9) for the
player's own square and (8,11)/(8,7)/(6,9)/(10,9) for the four neighbours -
all of them the TOP-LEFT tile of the step. So the tile that decides a step is
blockset[block * 16 + (qy * 2) * 4 + (qx * 2)], which is what this script uses
and what audit_cave_hideout.py validated over 400 layouts.

`audit_facility_stranded_quadrants.py` models the same thing with indexes
(5, 7, 13, 15), the BOTTOM-RIGHT tile of each quadrant. The two cannot both be
the engine's rule, so this script evaluates both on every layout and reports
any disagreement rather than quietly assuming its own is right. If they never
disagree the distinction does not matter for these blocksets; if they do, the
other audit needs a look.

NEGATIVE CONTROL: change the partner's `add a, 5` back to `add a, 4` in the
area's placement routine. The partner then shares the leader's tile, and this
script must report every layout as a stacked pair.

Usage:
    python3 tools/pyboy_smoke/audit_stage_hideout_partner.py [--layouts N]
                                                             [--areas forest,facility]
"""

from __future__ import annotations

import argparse
import random
import re
import sys
import time
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

GRID_SIZE = 20          # blocks per side, all four procedural areas
GRID_STRIDE = 26        # 20 playable + a 3-block border each side
GRID_BASE = 81          # 3 * 26 + 3
STEP_SIZE = GRID_SIZE * 2
RNG_STATE_BYTES = 10
HIDEOUT_SRAM_BANK = 0   # sStageEvent* lives in "Sprite Buffers", bank 0
STAGE_EVENT_NO_HIDEOUT = 0xFF

# name -> (map constant, preload label, blockset, collision label, base slot,
#          how many sprite slots harness.sprite_positions must return)
AREAS = {
    "cave": ("PROCEDURAL_CAVE_1", "Procedural Cave", "cavern.bst", "Cavern_Coll", 6, 7),
    "forest": ("PROCEDURAL_FOREST", "Procedural Forest", "forest.bst", "Forest_Coll", 6, 7),
    "facility": ("PROCEDURAL_FACILITY", "Procedural Facility", "facility.bst",
                 "Facility_Coll", 10, 11),
}


def stage_const(name):
    text = (REPO_ROOT / "constants" / "ram_constants.asm").read_text()
    m = re.search(r"^DEF %s\s+EQU\s+(%%[01]+|\$[0-9a-fA-F]+|\d+)" % name, text, re.M)
    if m is None:
        raise SystemExit("could not find DEF %s" % name)
    raw = m.group(1)
    if raw.startswith("%"):
        return int(raw[1:], 2)
    if raw.startswith("$"):
        return int(raw[1:], 16)
    return int(raw)


def passable_tiles(label: str) -> set:
    text = (REPO_ROOT / "data" / "tilesets" / "collision_tile_ids.asm").read_text()
    line = text[text.index(label + "::"):].split("\n")[1]
    return {int(tok.strip().lstrip("$"), 16)
            for tok in line.split("coll_tiles")[1].split(",")}


def step_walkable(blockset, passable, block, qx, qy, bottom_right=False):
    if block * 16 + 15 >= len(blockset):
        return False
    if bottom_right:
        index = (qy * 2 + 1) * 4 + (qx * 2 + 1)
    else:
        index = (qy * 2) * 4 + (qx * 2)
    return blockset[block * 16 + index] in passable


def walkable_grid(grid, blockset, passable, bottom_right=False):
    return [
        [step_walkable(blockset, passable, grid[sy // 2][sx // 2],
                       sx % 2, sy % 2, bottom_right)
         for sx in range(STEP_SIZE)]
        for sy in range(STEP_SIZE)
    ]


def reachable_steps(walkable, start) -> set:
    seen = set()
    if not (0 <= start[0] < STEP_SIZE and 0 <= start[1] < STEP_SIZE):
        return seen
    if not walkable[start[1]][start[0]]:
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


def sample(area, seed):
    map_name, entry_name, _, _, _, sprite_slots = AREAS[area]
    map_id = parse_map_constants(
        REPO_ROOT / "constants" / "map_constants.asm")[map_name]

    # A fresh harness per layout: boot_to_lobby is not re-entrant.
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        harness.boot_to_lobby()
        rng = random.Random(seed)
        base = harness.address("wRandomTable")
        for offset in range(RNG_STATE_BYTES):
            harness.pyboy.memory[base + offset] = rng.randrange(1, 256)
        # Armed AND already HIDING, so the placement takes the hideout branch.
        # Without the phase the pair would be placed on the arrival cells and
        # this script would silently be measuring the entrance block.
        # Type 1 is Jessie & James, the paired event.
        harness.write8("wStageEvent",
                       stage_const("STAGE_EVENT_JESSIE_JAMES")
                       | (1 << stage_const("STAGE_EVENT_PHASE_SHIFT")))
        harness.preload_and_enter_wild_area(map_id, entry_name)
        origin = harness.address("wOverworldMap") + GRID_BASE
        grid = [
            [harness.pyboy.memory[origin + y * GRID_STRIDE + x]
             for x in range(GRID_SIZE)]
            for y in range(GRID_SIZE)
        ]
        player = (harness.read8("wXCoord"), harness.read8("wYCoord"))
        sprites = [tuple(p) for p in harness.sprite_positions(sprite_slots)]
        hx = harness.read_sram_bytes("sStageEventHideoutX", 1,
                                     bank=HIDEOUT_SRAM_BANK)[0]
        return grid, player, sprites, hx
    finally:
        try:
            harness.close()
        except Exception:
            pass


def run_area(area, layouts):
    _, _, blockset_name, coll_label, base_slot, _ = AREAS[area]
    blockset = (REPO_ROOT / "gfx" / "blocksets" / blockset_name).read_bytes()
    passable = passable_tiles(coll_label)

    print()
    print("=== %s (slots %d-%d, %s / %s) ==="
          % (area.upper(), base_slot, base_slot + 1, blockset_name, coll_label))

    partner_ok = 0
    partner_bad = []
    leader_bad = []
    unreachable = []
    stacked = []
    not_same_row = []
    spawn_unwalkable = []
    model_disagreements = []
    no_hideout = 0
    errors = 0
    started = time.time()

    for seed in range(layouts):
        try:
            grid, player, sprites, hx = sample(area, seed)
        except Exception as exc:
            errors += 1
            print("  seed %d: %s: %s" % (seed, type(exc).__name__, exc))
            continue

        if hx == STAGE_EVENT_NO_HIDEOUT:
            # Every candidate landed on the boss; the pair parks on the
            # entrance block instead. A legitimate outcome and not what this
            # script is measuring, so count it and move on.
            no_hideout += 1
            continue

        walkable = walkable_grid(grid, blockset, passable)
        other = walkable_grid(grid, blockset, passable, bottom_right=True)
        if walkable != other:
            differing = sum(
                1 for sy in range(STEP_SIZE) for sx in range(STEP_SIZE)
                if walkable[sy][sx] != other[sy][sx])
            model_disagreements.append((seed, differing))

        # sprite_positions has already removed the +4 bias, so these are
        # player steps. It is indexed by slot - 1.
        leader_y, leader_x = sprites[base_slot - 1]
        partner_y, partner_x = sprites[base_slot]

        if not walkable[player[1]][player[0]]:
            # Self-check on the collision model: the player is standing here,
            # so the model calling it wall means the model is wrong.
            spawn_unwalkable.append((seed, player))

        seen = reachable_steps(walkable, player)

        if (leader_x, leader_y) == (partner_x, partner_y):
            stacked.append((seed, (leader_x, leader_y)))
        if leader_y != partner_y:
            not_same_row.append((seed, (leader_x, leader_y), (partner_x, partner_y)))

        # TWO criteria, because they mean different things.
        #
        # STRICT: the NPC's own tile is walkable and reachable. This is what
        # you want - the villain is standing on the floor.
        #
        # TALKABLE: the own tile OR any orthogonal neighbour is reachable. An
        # NPC is solid to the player anyway, so you talk to it by standing
        # beside it; audit_cave_hideout.py uses exactly this bar for the
        # hideout. An NPC that fails STRICT but passes TALKABLE is standing
        # inside scenery - it looks wrong and it is worth fixing, but the
        # encounter still works. Failing TALKABLE means the encounter is
        # simply unavailable, which is a different order of problem.
        def talkable(step):
            if step in seen:
                return True
            return any((step[0] + dx, step[1] + dy) in seen
                       for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)))

        if (leader_x, leader_y) not in seen:
            leader_bad.append((seed, (leader_x, leader_y),
                               grid[leader_y // 2][leader_x // 2]))
        if (partner_x, partner_y) in seen:
            partner_ok += 1
        else:
            partner_bad.append((seed, (partner_x, partner_y),
                                grid[partner_y // 2][partner_x // 2]))

        for who, step in (("leader", (leader_x, leader_y)),
                          ("partner", (partner_x, partner_y))):
            if not talkable(step):
                unreachable.append((seed, who, step,
                                    grid[step[1] // 2][step[0] // 2]))

    elapsed = time.time() - started
    measured = layouts - errors - no_hideout
    n = max(1, measured)
    print("  %d layouts, %d measured, %d no-hideout, %d harness errors, %.0fs"
          % (layouts, measured, no_hideout, errors, elapsed))
    print("  STRICT  partner TILE walkable and reachable: %d/%d (%.1f%%)"
          % (partner_ok, n, 100.0 * partner_ok / n))
    print("  TALKABLE both NPCs reachable or adjacent to reachable: %d/%d"
          % (n - len({s for s, _, _, _ in unreachable}), n))
    for seed, step, block_id in partner_bad[:10]:
        print("    PARTNER ON SCENERY seed %d: step %s, block id %d"
              % (seed, step, block_id))
    for seed, step, block_id in leader_bad[:10]:
        print("    LEADER ON SCENERY seed %d: step %s, block id %d"
              % (seed, step, block_id))
    for seed, who, step, block_id in unreachable[:10]:
        print("    UNREACHABLE seed %d: %s at step %s, block id %d - the "
              "player cannot stand next to it, so the encounter is lost"
              % (seed, who, step, block_id))
    for seed, step in stacked[:10]:
        print("    STACKED seed %d: both NPCs on step %s" % (seed, step))
    for seed, a, b in not_same_row[:10]:
        print("    NOT SIDE BY SIDE seed %d: %s and %s" % (seed, a, b))
    for seed, player in spawn_unwalkable[:10]:
        print("    MODEL BROKEN seed %d: the player's own spawn step %s reads "
              "as wall" % (seed, player))
    if model_disagreements:
        print("  top-left vs bottom-right collision model disagreed on %d "
              "layouts (worst %d steps): %s"
              % (len(model_disagreements),
                 max(d for _, d in model_disagreements),
                 [s for s, _ in model_disagreements[:10]]))
    else:
        print("  top-left and bottom-right collision models agree on every "
              "step of every layout")

    return (len(partner_bad) + len(leader_bad) + len(stacked)
            + len(not_same_row) + len(spawn_unwalkable) + errors)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=int, default=64)
    parser.add_argument("--areas", default="forest,facility",
                        help="comma-separated subset of: " + ", ".join(AREAS))
    args = parser.parse_args()

    wanted = [a.strip() for a in args.areas.split(",") if a.strip()]
    for a in wanted:
        if a not in AREAS:
            raise SystemExit("unknown area %r; known: %s" % (a, ", ".join(AREAS)))

    failures = Counter()
    for area in wanted:
        failures[area] = run_area(area, args.layouts)

    print()
    total = sum(failures.values())
    if total:
        print("FAIL: %d problems (%s)"
              % (total, ", ".join("%s=%d" % kv for kv in failures.items() if kv[1])))
        return 1
    print("PASS: on %s, both stage NPCs stand on walkable, reachable tiles, "
          "side by side in the same row" % ", ".join(wanted))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
