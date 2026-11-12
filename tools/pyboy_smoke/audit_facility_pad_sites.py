#!/usr/bin/env python3
"""Measure and check Facility warp-pad sites (PROCEDURAL_SUBROOMS_PLAN Phases 0 and 2).

Warp arrival coordinates are fixed in ROM (LoadDestinationWarpPosition reads
the def_warps_to table), so a pad can only land on one of K pre-declared
warp_events. This audit applies the SAME validity rule PFacPlacePads uses at
runtime, so the rates it reports are the rates the game produces.

A site block is valid when:
  1. it and all 8 neighbouring blocks are plain floor (PFAC_FLOOR). Blocking
     the middle of a 3x3 floor patch can never cut a path: any route through
     it can go round on the ring of 8. (A pad teleports whoever steps on it,
     so for walking it is a wall.) The flood fill below verifies this claim
     on every layout instead of trusting it;
  2. no real ball, fake ball or the boss lies in the 3x3 blocks centred on the
     site, and the stage-event hideout is not within two blocks (its villains
     see 4 tiles; a battle started on a warp tile takes the warp afterwards);
  3. it is not inside the exit (boss) room, room 11, so a pad cannot skip the
     stage.
A pair needs two valid sites at least PAD_MIN_DISTANCE blocks apart
(Manhattan), so a pad is a shortcut and not a hop across one room.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/audit_facility_pad_sites.py [--seeds N] [--k K]
    python3 tools/pyboy_smoke/audit_facility_pad_sites.py --evaluate [--prefix N]
    python3 tools/pyboy_smoke/audit_facility_pad_sites.py --scan-block 0x2F
"""

from __future__ import annotations

import argparse
import io
import re
import sys
from collections import Counter
from itertools import combinations
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402
from audit_facility_stranded_quadrants import (  # noqa: E402
    BLOCKSET, ENTRANCE, flood, passable,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
SITE_CONSTANTS = REPO_ROOT / "constants" / "facility_pad_site_constants.asm"

PFAC_FLOOR = 0x0E
ROOM_STRIDE = 6
EXIT_ROOM = 11
FAKE_BALL_OFFSET = 72  # sProcFacilityGenScratch bytes 72-79: fake-ball Y/X pairs
NO_HIDEOUT = 0xFF      # STAGE_EVENT_NO_HIDEOUT
PAD_MIN_DISTANCE = 8   # blocks, Manhattan; keep equal to FACILITY_PAD_MIN_DISTANCE


def load_pad_sites() -> tuple[tuple[int, int], ...]:
    """The shipped site list, from the one constants file the ROM also uses."""
    if not SITE_CONSTANTS.exists():
        return ()
    text = SITE_CONSTANTS.read_text(encoding="utf-8")
    return tuple((int(x), int(y)) for x, y in re.findall(r"^\s*pad_site\s+(\d+),\s*(\d+)", text, re.M))


PAD_SITES = load_pad_sites()
FIRST_PAD_WARP = 3   # FACILITY_FIRST_PAD_WARP
PAD_BLOCK = 0x2F
PAD_NONE = 0xFF
SUBROOM_MAP = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")["PROCEDURAL_FACILITY_SUBROOM"]

# Dynamic pads (FOLLOWUPS #71, constants/facility_pad_site_constants.asm): a
# fresh Facility names each pad by its ORDINAL, the k-th PAD_BLOCK in row order
# on the baked map, and byte 0 carries the tag. A Facility saved earlier names
# sites. Every reader goes through these three, so both kinds keep working.
PAD_DYN = 0x80       # FACILITY_PAD_DYN: byte 0 = PAD_DYN | the first ordinal
PAD_DYN_NONE = 0xFD  # FACILITY_PAD_DYN_NONE: dynamic, no pair


def pads_dynamic(scratch) -> bool:
    """PFacPadsDynamic."""
    return scratch[0] == PAD_DYN_NONE or scratch[0] & 0xF0 == PAD_DYN


def pad_pair(scratch):
    """The pair's two pads as the ROM names them (ordinals or sites), or None."""
    if pads_dynamic(scratch):
        return None if scratch[0] == PAD_DYN_NONE else (scratch[0] & 0x0F, scratch[1])
    if scratch[0] >= len(PAD_SITES) or scratch[1] >= len(PAD_SITES):
        return None
    return scratch[0], scratch[1]


def pad_block(scratch, pad, playable):
    """PFacPadSiteXY: the (block x, block y) of a pad named the ROM's way.
    `playable` is the 400 player-area blocks, or the 601-byte wOverworldMap."""
    if not pads_dynamic(scratch):
        return PAD_SITES[pad]
    if len(playable) != 400:
        playable = [playable[81 + r * 26 + c] for r in range(20) for c in range(20)]
    blocks = [(i % 20, i // 20) for i, b in enumerate(playable) if b == PAD_BLOCK]
    return blocks[pad]


def layout(harness, seed, edge, baseline):
    harness.load_state(baseline)
    harness.write_sram_bytes("sProcFacilityExitEdge", [edge])
    harness.seed_rng(seed)
    harness.call_routine("PFacFinalize", limit=4000)
    buf = harness.read_bytes("wOverworldMap", 601)
    playable = tuple(buf[81 + r * 26 + c] for r in range(20) for c in range(20))
    scratch = harness.read_sram_bytes("sProcFacilityGenScratch", 81)
    balls = harness.read_sram_bytes("sProcFacilityBallXY", 8)
    boss = harness.read_bytes("wSprite01StateData2MapY", 2)
    hideout = harness.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
    warps = harness.read_bytes("wWarpEntries", 4 * (FIRST_PAD_WARP + len(PAD_SITES)))
    return playable, scratch, balls, boss, hideout, warps


def object_blocks(scratch, balls, boss, hideout) -> set[tuple[int, int]]:
    """Block coords of every ball and the boss (the hideout has its own,
    wider rule in valid_sites)."""
    blocks = set()
    for i in range(4):
        y, x = balls[2 * i], balls[2 * i + 1]
        blocks.add(((x - 4) // 2, (y - 4) // 2))
        y, x = scratch[FAKE_BALL_OFFSET + 2 * i], scratch[FAKE_BALL_OFFSET + 2 * i + 1]
        blocks.add(((x - 4) // 2, (y - 4) // 2))
    blocks.add(((boss[1] - 4) // 2, (boss[0] - 4) // 2))
    return blocks


def near_hideout(hideout, bx, by) -> bool:
    """PFacPadSiteValid: within two blocks of the stage-event hideout. The
    villains there see 4 tiles; two blocks keeps a pad's tile 5 away."""
    return hideout[0] != NO_HIDEOUT and abs(hideout[0] - bx) <= 2 and abs(hideout[1] - by) <= 2


RULE = "quad"  # set by --rule; "quad" is what the ROM does

# Spinner pieces' W/H, in data/maps/facility_spinner_rooms.asm's order (the
# first two bytes of each descriptor row).
SPINNER_SIZES = [tuple(map(int, m)) for m in re.findall(
    r"^\tdb (\d+), (\d+), \d+, \d+, \d+, \d+$",
    (REPO_ROOT / "data/maps/facility_spinner_rooms.asm").read_text(encoding="utf-8"), re.M)]


def in_spinner_room(scratch, bx, by) -> bool:
    """PFacBlockInSpinnerRoom: scratch 2/3 = piece X/Y, 4 = $80 | descriptor;
    the room is the piece plus a one-block ring."""
    key = scratch[4]
    if not key & 0x80 or (key & 0x7F) >= len(SPINNER_SIZES):
        return False
    w, h = SPINNER_SIZES[key & 0x7F]
    x, y = scratch[2], scratch[3]
    return x - 1 <= bx <= x + w and y - 1 <= by <= y + h


def ring_joined(cells, bx, by) -> bool:
    """PFacPadBlockValid's ring test (2026-11-11): blocking the warp quadrant
    strands nothing when its walkable 4-neighbours are all connected through
    walkable cells of its 8-ring. Written as the general search, not as the
    ROM's two closed-form conditions, so the runtime check compares the two."""
    qx, qy = 2 * bx + 1, 2 * by + 1
    ring = {(qx + dx, qy + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - {(qx, qy)}
    live = ring & cells
    near = [n for n in ((qx, qy - 1), (qx - 1, qy), (qx + 1, qy), (qx, qy + 1)) if n in cells]
    if not near:
        return False
    seen, stack = {near[0]}, [near[0]]
    while stack:
        c = stack.pop()
        for n in ((c[0] - 1, c[1]), (c[0] + 1, c[1]), (c[0], c[1] - 1), (c[0], c[1] + 1)):
            if n in live and n not in seen:
                seen.add(n)
                stack.append(n)
    return all(n in seen for n in near)


def valid_sites(playable, scratch, balls, boss, hideout, blockset=None):
    """Runtime rule. The pad is block $2F, whose only non-floor quadrant is the
    bottom-right one (the warp tile), so for walking only THAT quadrant is a
    wall. If the 8 quadrants around it are walkable, any route through it can
    go round, so nothing is stranded.
      ring:  the site block is PFAC_FLOOR and the blocks to its E, S and SE
             are PFAC_FLOOR (block-id test, what the asm does)
      quad:  the site block is PFAC_FLOOR and the five outside ring quadrants
             are walkable per the blockset (precise, for comparison)
      3x3:   the site and all 8 neighbouring blocks are PFAC_FLOOR"""
    occupied = object_blocks(scratch, balls, boss, hideout)
    ex, ey, ew, eh = scratch[EXIT_ROOM * ROOM_STRIDE: EXIT_ROOM * ROOM_STRIDE + 4]
    cells = passable(blockset, playable) if RULE == "quad" else None
    sites = set()
    for by in range(1, 19):
        for bx in range(1, 19):
            if playable[by * 20 + bx] != PFAC_FLOOR:
                continue
            if RULE == "3x3":
                patch = [(bx + dx, by + dy) for dy in (-1, 0, 1) for dx in (-1, 0, 1)]
            else:
                patch = [(bx, by), (bx + 1, by), (bx, by + 1), (bx + 1, by + 1)]
            if RULE in ("3x3", "ring"):
                if any(playable[y * 20 + x] != PFAC_FLOOR for x, y in patch):
                    continue
            elif not ring_joined(cells, bx, by):
                continue
            # Objects: the 3x3 blocks centred on the site (PFacPadObjectsClear).
            if any((bx + dx, by + dy) in occupied for dy in (-1, 0, 1) for dx in (-1, 0, 1)):
                continue
            if near_hideout(hideout, bx, by):
                continue
            if ex <= bx < ex + ew and ey <= by < ey + eh:
                continue
            if in_spinner_room(scratch, bx, by):
                continue
            sites.add((bx, by))
    return sites


def strands_nothing(blockset, playable, site) -> bool:
    cells = passable(blockset, playable)
    reachable = flood(cells, ENTRANCE)
    bx, by = site
    pad = {(2 * bx + 1, 2 * by + 1)}  # the only non-floor quadrant of block $2F
    return flood(cells - pad, ENTRANCE) == reachable - pad


SUBROOM_PAD = 7  # sProcFacilityGenScratch byte 7: the subroom pad's site (Phase 4)
SUBROOM_PIECE = 6  # byte 6: the room piece, or $80 | X for the Super Nerd's fallback block


def unstamp(playable, scratch):
    """The map as it was before the pads were stamped (the model judges blocks
    on that map; a stamped block is no longer PFAC_FLOOR)."""
    pads = [(i % 20, i // 20) for i, b in enumerate(playable) if b == PAD_BLOCK]
    stamped = []
    pair = pad_pair(scratch)
    if pair and pads_dynamic(scratch):
        stamped += [pads[k] for k in pair if k < len(pads)]
    if scratch[SUBROOM_PAD] < len(PAD_SITES) and scratch[SUBROOM_PAD] < len(pads):
        stamped.append(pads[scratch[SUBROOM_PAD]])
    before = list(playable)
    for x, y in stamped:
        before[y * 20 + x] = PFAC_FLOOR
    return tuple(before)


def pad_blocks(playable):
    """Every $2F block in row order: the ROM's ordinals index this list."""
    return [(i % 20, i // 20) for i, b in enumerate(playable) if b == PAD_BLOCK]


def valid_rows3(*args):
    """valid_sites on the dynamic range (rows 3-18, PFAC_DYN_TOP)."""
    return {s for s in valid_sites(*args) if s[1] >= 3}


def unstamp_blocks(playable, blocks):
    before = list(playable)
    for x, y in blocks:
        before[y * 20 + x] = PFAC_FLOOR
    return tuple(before)


def check_runtime(seed, playable, scratch, balls, boss, hideout, warps, tally) -> int:
    """Compare what PFacPlacePads/PFacPlaceSubroomPad/PFacArmPads did with this
    audit's own model. Pads are named by ordinal among the map's $2F blocks."""
    blockset = BLOCKSET.read_bytes()
    bad = []
    b0, b1, b7 = scratch[0], scratch[1], scratch[SUBROOM_PAD]
    pads = pad_blocks(playable)
    if not pads_dynamic(scratch):
        bad.append(f"byte 0 {b0:#x} is not the dynamic format")
    pair = None
    if b0 != PAD_DYN_NONE:
        oa, ob = b0 & 0x0F, b1
        if oa >= len(pads) or ob >= len(pads):
            bad.append(f"pair ordinals {oa},{ob} past {len(pads)} pad blocks")
        else:
            pair = (oa, ob)
    elif b1 != PAD_NONE:
        bad.append(f"no pair but byte 1 = {b1:#x}")
    sub = b7 if b7 < len(PAD_SITES) else None
    if sub is not None and sub >= len(pads):
        bad.append(f"subroom ordinal {sub} past {len(pads)} pad blocks")
        sub = None
    ours = set()
    if pair:
        ours |= {pads[pair[0]], pads[pair[1]]}
    if sub is not None:
        ours.add(pads[sub])
    # The pair was judged on the map before any pad of ours, the subroom pad
    # with the pair already in it.
    possible = valid_rows3(unstamp_blocks(playable, ours), scratch, balls, boss, hideout, blockset)
    pair_possible = any(abs(a[0] - b[0]) + abs(a[1] - b[1]) >= PAD_MIN_DISTANCE
                        for a, b in combinations(possible, 2))
    tally["possible"] += pair_possible
    if pair:
        tally["placed"] += 1
        tally["placed_when_possible"] += pair_possible
        a, b = pads[pair[0]], pads[pair[1]]
        for end in (a, b):
            if end not in possible:
                bad.append(f"pair end {end} fails the model")
        if abs(a[0] - b[0]) + abs(a[1] - b[1]) < PAD_MIN_DISTANCE:
            bad.append(f"pair {a} {b} too close")
    elif pair_possible:
        bad.append("no pair although one was possible")
    with_pair = unstamp_blocks(playable, {pads[sub]} if sub is not None else set())
    sub_possible = valid_rows3(with_pair, scratch, balls, boss, hideout, blockset) - (
        {pads[pair[0]], pads[pair[1]]} if pair else set())
    tally["subroom_possible"] += bool(sub_possible)
    if sub is not None:
        tally["subroom_placed"] += 1
        if pads[sub] not in sub_possible:
            bad.append(f"subroom pad {pads[sub]} fails the model")
    elif sub_possible:
        bad.append("no subroom pad although one was possible")
    # Nothing stranded with every pad of ours in place.
    clean = unstamp_blocks(playable, ours)
    cells = passable(blockset, clean)
    reach = flood(cells, ENTRANCE)
    holes = {(2 * x + 1, 2 * y + 1) for x, y in ours}
    if flood(cells - holes, ENTRANCE) != reach - holes:
        bad.append("pads strand floor")
    # Warps: slot FIRST + ordinal armed for ours, every other pad slot disarmed.
    armed = {}
    if pair:
        armed[pair[0]] = ("pair", pair[1])
        armed[pair[1]] = ("pair", pair[0])
    if sub is not None:
        armed[sub] = ("sub", None)
    for k in range(len(PAD_SITES)):
        e = warps[4 * (FIRST_PAD_WARP + k): 4 * (FIRST_PAD_WARP + k) + 4]
        if k in armed:
            x, y = pads[k]
            if e[:2] != [2 * y + 1, 2 * x + 1]:
                bad.append(f"slot {FIRST_PAD_WARP + k} tile {e[:2]} != pad {pads[k]}")
            kind, partner = armed[k]
            if kind == "pair" and e[2] != FIRST_PAD_WARP + partner:
                bad.append(f"slot {FIRST_PAD_WARP + k} dest {e[2]} != {FIRST_PAD_WARP + partner}")
            if kind == "sub" and e[3] != SUBROOM_MAP:
                bad.append(f"subroom slot {FIRST_PAD_WARP + k} map {e[3]:#x}")
        elif e[0] != PAD_NONE:
            bad.append(f"slot {FIRST_PAD_WARP + k} not disarmed: {e}")
    for line in bad:
        print(f"seed {seed}: {line}")
    return len(bad)


def has_pair(sites) -> bool:
    return any(abs(a[0] - b[0]) + abs(a[1] - b[1]) >= PAD_MIN_DISTANCE
               for a, b in combinations(sites, 2))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=200)
    parser.add_argument("--k", type=int, default=27, help="site-set size to pick")
    parser.add_argument("--seed-state", type=lambda s: int(s, 0), default=0x1234_5678,
                        help="xorshift start state; change it for an out-of-sample corpus")
    parser.add_argument("--evaluate", action="store_true",
                        help="score the shipped PAD_SITES instead of picking a new set")
    parser.add_argument("--prefix", type=int, default=0,
                        help="with --evaluate: score only the first N sites")
    parser.add_argument("--scan-block", type=lambda s: int(s, 0), default=None,
                        help="report every layout that contains this block id, then stop")
    parser.add_argument("--rule", choices=("ring", "quad", "3x3"), default="quad")
    parser.add_argument("--runtime", action="store_true",
                        help="check the pair PFacPlacePads actually placed on each layout")
    args = parser.parse_args()
    global RULE
    RULE = args.rule

    blockset = BLOCKSET.read_bytes()
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    harness.boot_to_lobby()
    harness.call_routine("PFacPreload", limit=60000)
    baseline = io.BytesIO()
    harness.save_state(baseline)

    state = args.seed_state
    per_layout_sites = []
    heat: Counter = Counter()
    scan_hits = 0
    stranding = 0
    problems = 0
    runtime = Counter()
    for _ in range(args.seeds):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        seed = [(state >> shift) & 0xFF for shift in (0, 8, 16, 24)]
        # Exit edge 0 (north) only: W/E are debug-only per sram.asm.
        playable, scratch, balls, boss, hideout, warps = layout(harness, seed, 0, baseline)
        if args.runtime:
            problems += check_runtime(seed, playable, scratch, balls, boss, hideout, warps, runtime)
            continue
        if args.scan_block is not None:
            hits = [i for i, b in enumerate(playable) if b == args.scan_block]
            if hits:
                scan_hits += 1
            continue
        playable = unstamp(playable, scratch)
        sites = valid_sites(playable, scratch, balls, boss, hideout, blockset)
        for site in sites:
            if not strands_nothing(blockset, playable, site):
                stranding += 1
                print(f"seed {seed}: site {site} strands floor - the 3x3 rule is wrong")
        per_layout_sites.append(sites)
        heat.update(sites)
    if args.scan_block is not None:
        print(f"{scan_hits} of {args.seeds} layouts contain block ${args.scan_block:02X}")
        return 0
    if args.runtime:
        print(f"layouts {args.seeds}: pads placed {runtime['placed']}, "
              f"model says a pair was possible {runtime['possible']}, "
              f"placed when possible {runtime['placed_when_possible']}, "
              f"subroom pad placed {runtime['subroom_placed']} "
              f"(possible {runtime['subroom_possible']}), "
              f"problems {problems}")
        return 1 if problems else 0

    total = len(per_layout_sites)
    counts = [len(s) for s in per_layout_sites]
    print(f"layouts {total}; valid blocks per layout min {min(counts)} max {max(counts)} "
          f"mean {sum(counts) / total:.1f}; stranding sites {stranding}")

    if args.evaluate:
        fixed = set(PAD_SITES[: args.prefix or len(PAD_SITES)])
        hit = sum(1 for s in per_layout_sites if has_pair(s & fixed))
        print(f"shipped set of {len(fixed)} sites: a pad pair is possible in "
              f"{100 * hit / total:.0f}% of layouts")
        return 1 if stranding else 0

    candidates = [b for b, _ in heat.most_common(60)]
    chosen: list[tuple[int, int]] = []
    for _ in range(args.k):
        best = max((c for c in candidates if c not in chosen),
                   key=lambda c: sum(1 for s in per_layout_sites if has_pair(s & (set(chosen) | {c}))))
        chosen.append(best)
        hit = sum(1 for s in per_layout_sites if has_pair(s & set(chosen)))
        print(f"K={len(chosen)} add block {best}: pair possible {100 * hit / total:.0f}%")
    print("chosen blocks:", chosen)
    return 1 if stranding else 0


if __name__ == "__main__":
    raise SystemExit(main())
