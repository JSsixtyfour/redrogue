#!/usr/bin/env python3
"""Runtime check of dynamic Facility pads (FOLLOWUPS #71) on real generated layouts.

Spec for porting audit_facility_pad_sites.py --runtime to ordinals; run from WSL:
    python3 tools/pyboy_smoke/check_facility_dynamic_pads.py --repo "$PWD" [--seeds N]
"""
import argparse, io, sys
from collections import Counter
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("--repo", default="/mnt/c/Users/justi/redrogue_dynpads")
ap.add_argument("--seeds", type=int, default=300)
ap.add_argument("--seed-state", type=lambda s: int(s, 0), default=0x2545F491)
args = ap.parse_args()
REPO = Path(args.repo)
sys.path.insert(0, str(REPO / "tools" / "pyboy_smoke"))
import audit_facility_pad_sites as A  # noqa: E402
from harness import RedRogueHarness  # noqa: E402
from audit_facility_stranded_quadrants import ENTRANCE, flood, passable  # noqa: E402

DYN, DYN_NONE, NONE = 0x80, 0xFD, 0xFF
FIRST = A.FIRST_PAD_WARP
NSITES = len(A.PAD_SITES)


def pad_blocks(playable):
    return [(i % 20, i // 20) for i, b in enumerate(playable) if b == A.PAD_BLOCK]


def valid3(*a):
    return {s for s in A.valid_sites(*a) if s[1] >= 3}


def unstamp(playable, blocks):
    m = list(playable)
    for x, y in blocks:
        m[y * 20 + x] = A.PFAC_FLOOR
    return tuple(m)


def main():
    blockset = A.BLOCKSET.read_bytes()
    h = RedRogueHarness(REPO, A.ARTIFACTS)
    h.boot_to_lobby()
    h.call_routine("PFacPreload", limit=60000)
    base = io.BytesIO()
    h.save_state(base)
    t = Counter()
    problems = 0
    state = args.seed_state
    for _ in range(args.seeds):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        seed = [(state >> s) & 0xFF for s in (0, 8, 16, 24)]
        playable, scratch, balls, boss, hideout, warps = A.layout(h, seed, 0, base)
        warps = h.read_bytes("wWarpEntries", 4 * 32)
        bad = []
        b0, b1, b7 = scratch[0], scratch[1], scratch[A.SUBROOM_PAD]
        pads = pad_blocks(playable)
        t["pad_blocks_max"] = max(t["pad_blocks_max"], len(pads))
        if not (b0 == DYN_NONE or b0 & 0xF0 == DYN):
            bad.append(f"byte 0 {b0:#x} is not dynamic")
        pair = None
        if b0 != DYN_NONE:
            oa, ob = b0 & 0x0F, b1
            if ob >= len(pads) or oa >= len(pads):
                bad.append(f"pair ordinals {oa},{ob} past {len(pads)} pad blocks")
            else:
                pair = (oa, ob)
        elif b1 != NONE:
            bad.append(f"no pair but byte 1 = {b1:#x}")
        sub = b7 if b7 < NSITES else None
        if sub is not None and sub >= len(pads):
            bad.append(f"subroom ordinal {sub} past {len(pads)} pad blocks")
            sub = None
        ours = set()
        if pair:
            ours |= {pads[pair[0]], pads[pair[1]]}
        if sub is not None:
            ours.add(pads[sub])
        # Model: the pair was chosen on the map with no pad of ours, the subroom pad with the pair in.
        clean = unstamp(playable, ours)
        possible = valid3(clean, scratch, balls, boss, hideout, blockset)
        pair_possible = any(abs(a[0] - b[0]) + abs(a[1] - b[1]) >= A.PAD_MIN_DISTANCE
                            for a in possible for b in possible)
        t["pair_possible"] += pair_possible
        if pair:
            t["pair"] += 1
            a, b = pads[pair[0]], pads[pair[1]]
            for e in (a, b):
                if e not in possible:
                    bad.append(f"pair end {e} fails the model")
            if abs(a[0] - b[0]) + abs(a[1] - b[1]) < A.PAD_MIN_DISTANCE:
                bad.append(f"pair {a} {b} too close")
        elif pair_possible:
            bad.append("no pair although one was possible")
        with_pair = unstamp(playable, {pads[sub]} if sub is not None else set())
        sub_possible = valid3(with_pair, scratch, balls, boss, hideout, blockset) - (
            {pads[pair[0]], pads[pair[1]]} if pair else set())
        t["sub_possible"] += bool(sub_possible)
        if sub is not None:
            t["sub"] += 1
            if pads[sub] not in sub_possible:
                bad.append(f"subroom pad {pads[sub]} fails the model")
        elif sub_possible:
            bad.append("no subroom pad although one was possible")
        # Nothing stranded with every pad of ours in place.
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
        for k in range(NSITES):
            e = warps[4 * (FIRST + k): 4 * (FIRST + k) + 4]
            if k in armed:
                x, y = pads[k]
                if e[:2] != [2 * y + 1, 2 * x + 1]:
                    bad.append(f"slot {FIRST + k} tile {e[:2]} != pad {pads[k]}")
                kind, partner = armed[k]
                if kind == "pair" and e[2] != FIRST + partner:
                    bad.append(f"slot {FIRST + k} dest {e[2]} != {FIRST + partner}")
                if kind == "sub" and e[3] != A.SUBROOM_MAP:
                    bad.append(f"subroom slot {FIRST + k} map {e[3]:#x}")
            elif e[0] != NONE:
                bad.append(f"slot {FIRST + k} armed {e}")
        for line in bad:
            print(f"seed {seed}: {line}")
        problems += bool(bad)
    n = args.seeds
    print(f"layouts {n}: pair {t['pair']} (possible {t['pair_possible']}), subroom pad {t['sub']} "
          f"(possible {t['sub_possible']}), most pad blocks in one map {t['pad_blocks_max']}, "
          f"layouts with problems {problems}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
