#!/usr/bin/env python3
"""What moved between two builds, from their rgblink .sym files.

Answers the question behind several layout-sensitive bug classes (a cross-bank
call whose symptom changes between commits, a HOME shift, a WRAM address that
old notes or save states still point at):

- labels that changed BANK (a plain `call`/pointer into one is now cross-bank);
- per region and bank, runs of labels that shifted by the same amount, e.g.
  "HOME +3 from Foo ($1234) onward";
- labels added and removed.

    python3 tools/sym_diff.py builds/space_last_debug.sym pokeblue_debug.sym
    python3 tools/sym_diff.py old.sym new.sym --locals   # include .local labels

The builds/ archive keeps a .sym beside every linked ROM, so any two builds can
be compared after the fact.
"""
from __future__ import annotations

from pathlib import Path
import argparse
import re


SYM_RE = re.compile(r"^([0-9a-fA-F]{2}):([0-9a-fA-F]{4}) (\S+)")
MAX_RUNS = 12
MAX_LISTED = 25


def region(bank: int, addr: int) -> str:
    if addr < 0x4000:
        return "HOME"
    if addr < 0x8000:
        return f"ROMX ${bank:02X}"
    if addr < 0xA000:
        return f"VRAM{bank}"
    if addr < 0xC000:
        return f"SRAM ${bank:02X}"
    if addr < 0xE000:
        return "WRAM"
    return "HRAM"


def load(path: Path, with_locals: bool) -> dict[str, tuple[int, int]]:
    out = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = SYM_RE.match(line)
        if not m:
            continue
        name = m.group(3)
        if not with_locals and "." in name:
            continue
        # The first definition wins; rgblink lists a label once per address it has.
        out.setdefault(name, (int(m.group(1), 16), int(m.group(2), 16)))
    return out


def shift_runs(moves: list[tuple[int, int, str]]) -> list[tuple[int, str, int, int]]:
    """Collapse (old_addr, delta, name) sorted by address into runs of equal delta.

    Returns (delta, first_label, first_old_addr, count) for every nonzero run.
    """
    runs = []
    for old_addr, delta, name in moves:
        if runs and runs[-1][0] == delta:
            d, first, first_addr, count = runs[-1]
            runs[-1] = (d, first, first_addr, count + 1)
        else:
            runs.append((delta, name, old_addr, 1))
    return [run for run in runs if run[0] != 0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("old", type=Path)
    parser.add_argument("new", type=Path)
    parser.add_argument("--locals", action="store_true", help="include .local labels")
    args = parser.parse_args()

    if not args.old.exists():
        print(f"sym_diff: no baseline at {args.old}; nothing to compare yet")
        return 0
    old = load(args.old, args.locals)
    new = load(args.new, args.locals)

    bank_moves = []
    by_region: dict[str, list[tuple[int, int, str]]] = {}
    for name, (old_bank, old_addr) in old.items():
        if name not in new:
            continue
        new_bank, new_addr = new[name]
        old_region = region(old_bank, old_addr)
        new_region = region(new_bank, new_addr)
        if old_region != new_region:
            bank_moves.append((name, old_bank, old_addr, new_bank, new_addr))
            continue
        by_region.setdefault(old_region, []).append((old_addr, new_addr - old_addr, name))

    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))

    print(f"sym_diff {args.old.name} -> {args.new.name}: "
          f"{len(bank_moves)} changed bank/region, {len(added)} added, {len(removed)} removed")

    if bank_moves:
        print("\nChanged bank or region (check every plain call/jp/pointer into these):")
        for name, ob, oa, nb, na in sorted(bank_moves, key=lambda m: (m[3], m[4]))[:MAX_LISTED]:
            print(f"  {name:<40} {ob:02X}:{oa:04X} -> {nb:02X}:{na:04X}")
        if len(bank_moves) > MAX_LISTED:
            print(f"  ... and {len(bank_moves) - MAX_LISTED} more")

    def region_order(name: str) -> tuple[int, str]:
        order = ["HOME", "WRAM", "HRAM"]
        return (order.index(name), name) if name in order else (len(order), name)

    shifted_any = False
    for name in sorted(by_region, key=region_order):
        moves = sorted(by_region[name])
        runs = shift_runs(moves)
        if not runs:
            continue
        if not shifted_any:
            print("\nShifted within the same bank (runs of equal shift, by old address):")
            shifted_any = True
        moved = sum(count for *_, count in runs)
        print(f"  {name}: {moved} of {len(moves)} labels moved")
        for delta, first, first_addr, count in runs[:MAX_RUNS]:
            print(f"    {delta:+6d} B  from {first} (${first_addr:04X}), {count} label(s)")
        if len(runs) > MAX_RUNS:
            print(f"    ... {len(runs) - MAX_RUNS} more runs")
    if not shifted_any and not bank_moves:
        print("No label moved.")
    else:
        # The tight fixed regions are the usual question; say so when they held still.
        still = [r for r in ("HOME", "WRAM", "HRAM")
                 if r in by_region and not shift_runs(sorted(by_region[r]))]
        if still:
            print(f"\nUnmoved: {', '.join(still)}")

    for title, names in (("Added", added), ("Removed", removed)):
        if names:
            shown = ", ".join(names[:MAX_LISTED])
            more = f", ... +{len(names) - MAX_LISTED}" if len(names) > MAX_LISTED else ""
            print(f"\n{title}: {shown}{more}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
