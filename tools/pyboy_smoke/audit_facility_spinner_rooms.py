#!/usr/bin/env python3
"""Corpus check of Facility spinner decor (PROCEDURAL_SUBROOMS_PLAN Phase 3).

For each generated layout:
  * at most one of item rooms 1-4 carries spinner bits (Type bits 2-3), and no
    other room does; a spinner room is also marked decor-owned (bit 6) and is
    not a full-room template (bit 7);
  * the piece is stamped block for block, centred in the room's interior,
    exactly as PFacSpinnerDescriptor recomputes it;
  * the room's real ball stands on the piece's ball tile;
  * no fake ball, hideout or warp-pad end lies in the room (ring included).
Prints how often a layout gets spinner decor.

Usage (from the repo root, inside WSL):
    python3 tools/pyboy_smoke/audit_facility_spinner_rooms.py [--seeds N]
"""

from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from harness import RedRogueHarness  # noqa: E402
import audit_facility_pad_sites as pads  # noqa: E402
import facility_spinners as spin  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
SPIN_MASK = 0b1100


def shipped_pieces(debug: bool = True) -> list:
    """Pieces in PFacSpinnerRooms order (the order the tool emits them)."""
    pieces, errors = spin.load()
    assert not errors, errors
    return [p for p in pieces if debug or not p.debug]


def check_layout(seed, playable, scratch, balls, hideout, pieces) -> tuple[bool, list[str]]:
    problems = []
    # Item rooms 1-4 may host it (room 1's X/Y are gone after generation, its
    # Type byte is not), so the ROM keeps the piece position in scratch 2-5.
    spinner_rooms = [rid for rid in range(1, 5) if scratch[rid * 6 + 5] & SPIN_MASK]
    for rid in range(5, 12):
        if scratch[rid * 6 + 5] & SPIN_MASK:
            problems.append(f"room {rid} has spinner bits")
    if len(spinner_rooms) > 1:
        problems.append(f"{len(spinner_rooms)} spinner rooms: {spinner_rooms}")
    ox, oy, key, ball = scratch[2:6]
    live = bool(key & 0x80)
    if live != bool(spinner_rooms):
        problems.append(f"record live={live} but spinner rooms {spinner_rooms}")
    for rid in spinner_rooms:
        typ = scratch[rid * 6 + 5]
        if typ & 0x80 or not typ & 0x40:
            problems.append(f"room {rid}: Type {typ:02X} should be decor-owned and not a template")
        index = ((typ & SPIN_MASK) >> 2) - 1
        piece = pieces[index]
        if key != 0x80 | index or ball != rid - 1:
            problems.append(f"room {rid}: record key {key:02X} ball {ball}, want {0x80 | index:02X} ball {rid - 1}")
        if rid >= 2:  # room 1's record X/Y no longer exist to compare with
            x, y, w, h = scratch[rid * 6: rid * 6 + 4]
            if (ox, oy) != (x + (w - piece.w) // 2, y + (h - piece.h) // 2):
                problems.append(f"room {rid}: piece at {(ox, oy)} is not centred in {w}x{h} at {(x, y)}")
        for by in range(piece.h):
            for bx in range(piece.w):
                got = playable[(oy + by) * 20 + ox + bx]
                want = piece.blocks[by * piece.w + bx]
                if got != want:
                    problems.append(f"room {rid} piece block ({bx},{by}) is {got:02X}, payload {want:02X}")
        got_ball = (balls[2 * ball + 1], balls[2 * ball])
        want_ball = (2 * ox + piece.ball[0] + 4, 2 * oy + piece.ball[1] + 4)
        if got_ball != want_ball:
            problems.append(f"room {rid} ball at {got_ball}, piece wants {want_ball}")

        def inside(block):
            return ox - 1 <= block[0] <= ox + piece.w and oy - 1 <= block[1] <= oy + piece.h

        def on_piece(block):
            return ox <= block[0] < ox + piece.w and oy <= block[1] < oy + piece.h

        # Fakes may stand in a doorway of the room (intended: memory
        # "Facility doorway balls are intended"), so only the piece itself is
        # off limits to them; pads keep the one-block margin the ROM uses.
        for i in range(4):
            fy, fx = scratch[72 + 2 * i], scratch[72 + 2 * i + 1]
            if on_piece(((fx - 4) // 2, (fy - 4) // 2)):
                problems.append(f"fake ball {i} on the spinner piece")
        if hideout[0] != pads.NO_HIDEOUT and on_piece((hideout[0], hideout[1])):
            problems.append("hideout on the spinner piece")
        if scratch[0] < len(pads.PAD_SITES):
            for site in scratch[:2]:
                if inside(pads.PAD_SITES[site]):
                    problems.append(f"pad site {site} next to the spinner piece")
    for line in problems:
        print(f"seed {seed}: {line}")
    return bool(spinner_rooms), problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seeds", type=int, default=200)
    parser.add_argument("--seed-state", type=lambda s: int(s, 0), default=0x6A09E667)
    args = parser.parse_args()

    pieces = shipped_pieces()
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    harness.boot_to_lobby()
    harness.call_routine("PFacPreload", limit=60000)
    baseline = io.BytesIO()
    harness.save_state(baseline)

    state = args.seed_state
    with_spinner = problems = 0
    for _ in range(args.seeds):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        seed = [(state >> shift) & 0xFF for shift in (0, 8, 16, 24)]
        playable, scratch, balls, _boss, hideout, _warps = pads.layout(harness, seed, 0, baseline)
        has, found = check_layout(seed, playable, scratch, balls, hideout, pieces)
        with_spinner += has
        problems += len(found)
    print(f"layouts {args.seeds}: with spinner decor {with_spinner} "
          f"({100 * with_spinner / args.seeds:.0f}%), problems {problems}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
