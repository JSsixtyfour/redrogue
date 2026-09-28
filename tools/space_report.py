#!/usr/bin/env python3
"""Per-bank free space across the Red, Blue and Debug link maps.

Automates ROM_BIBLE.md section 6 and the WRAM Bible's `.map` cross-checks: for
every bank of every region (ROM0, ROMX, WRAM0, HRAM, SRAM, VRAM) it reports the
total free bytes and the largest single gap, for each ROM and as the minimum
across them. The largest gap matters as much as the total: a SECTION has to fit
in one contiguous hole, so 40 B free as 20 + 20 does not hold a 30 B section.

    python3 tools/space_report.py pokered.map pokeblue.map pokeblue_debug.map
    python3 tools/space_report.py *.map --compare builds/space_last.json --save builds/space_last.json
    python3 tools/space_report.py *.map --min-free ROM0=64 --min-free WRAM0=100

Only a fresh map is evidence. The report refuses a map older than its ROM,
which is what a failed or interrupted link leaves behind.
"""
from __future__ import annotations

from pathlib import Path
import argparse
import json
import re
import sys


BANK_RE = re.compile(r"^(ROM0|ROMX|VRAM|SRAM|WRAM0|WRAMX|HRAM) bank #(\d+):")
EMPTY_RE = re.compile(r"^\s+EMPTY: \$([0-9a-fA-F]+)(?:-\$([0-9a-fA-F]+))? \(\$([0-9a-fA-F]+) bytes?\)")
TOTAL_RE = re.compile(r"^\s+TOTAL EMPTY: \$([0-9a-fA-F]+) bytes?")

# Regions shown in full; ROMX rows are shown only when tight, or changed, or with --all.
ALWAYS_SHOWN = ("ROM0", "WRAM0", "HRAM")
TIGHT_BYTES = 64
REGION_ORDER = {"ROM0": 0, "ROMX": 1, "WRAM0": 2, "WRAMX": 3, "HRAM": 4, "SRAM": 5, "VRAM": 6}


def parse_map(path: Path) -> dict[str, dict[str, int]]:
    """{"ROMX:0e": {"free": n, "gap": largest}, ...} for every bank the map lists."""
    banks: dict[str, dict[str, int]] = {}
    key = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = BANK_RE.match(line)
        if m:
            key = f"{m.group(1)}:{int(m.group(2)):02x}"
            # A bank the linker filled exactly prints no EMPTY lines at all.
            banks[key] = {"free": 0, "gap": 0}
            continue
        if key is None:
            continue
        m = TOTAL_RE.match(line)
        if m:
            banks[key]["free"] = int(m.group(1), 16)
            continue
        m = EMPTY_RE.match(line)
        if m:
            banks[key]["gap"] = max(banks[key]["gap"], int(m.group(3), 16))
    if not banks:
        raise SystemExit(f"{path}: no bank headers found; is this an rgblink .map?")
    return banks


def check_fresh(map_path: Path) -> None:
    rom = map_path.with_suffix(".gbc")
    if rom.exists() and map_path.stat().st_mtime + 2 < rom.stat().st_mtime:
        raise SystemExit(f"{map_path} is older than {rom}: stale map, rebuild before measuring")


def sort_key(key: str) -> tuple[int, int]:
    region, bank = key.split(":")
    return REGION_ORDER.get(region, 99), int(bank, 16)


def label(key: str) -> str:
    region, bank = key.split(":")
    if region == "ROM0":
        return "ROM0/HOME"
    if region in ("ROMX", "SRAM", "VRAM"):
        return f"{region} ${int(bank, 16):02X}"
    return region


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("maps", nargs="+", type=Path)
    parser.add_argument("--compare", type=Path, help="earlier --save output to diff against")
    parser.add_argument("--save", type=Path, help="write this report as JSON")
    parser.add_argument("--all", action="store_true", help="show every ROMX bank, not just tight or changed ones")
    parser.add_argument("--min-free", action="append", default=[], metavar="BANK=N",
                        help="fail if min free is below N, e.g. ROM0=64, WRAM0=100, ROMX:0e=256")
    args = parser.parse_args()

    per_rom: dict[str, dict[str, dict[str, int]]] = {}
    for path in args.maps:
        check_fresh(path)
        per_rom[path.stem] = parse_map(path)
    roms = list(per_rom)

    keys = sorted({k for banks in per_rom.values() for k in banks}, key=sort_key)
    report = {}
    for key in keys:
        rows = [per_rom[r].get(key, {"free": 0, "gap": 0}) for r in roms]
        report[key] = {
            "free": {r: row["free"] for r, row in zip(roms, rows)},
            "gap": {r: row["gap"] for r, row in zip(roms, rows)},
            "min_free": min(row["free"] for row in rows),
            "min_gap": min(row["gap"] for row in rows),
        }

    previous = {}
    if args.compare and args.compare.exists():
        previous = json.loads(args.compare.read_text()).get("banks", {})

    name_w = max(len(r) for r in roms)
    print(f"{'bank':<12}" + "".join(f"{r:>{max(name_w, 8) + 2}}" for r in roms)
          + f"{'min free':>10}{'min gap':>9}{'delta':>8}")
    hidden = 0
    for key in keys:
        row = report[key]
        delta = None
        if key in previous:
            delta = row["min_free"] - previous[key]["min_free"]
        region = key.split(":")[0]
        # VRAM "sections" are placeholder labels the linker always reports as full.
        shown = args.all or (region != "VRAM" and (
            region in ALWAYS_SHOWN or row["min_free"] < TIGHT_BYTES or delta))
        if not shown:
            hidden += 1
            continue
        delta_text = "" if delta is None else ("0" if delta == 0 else f"{delta:+d}")
        print(f"{label(key):<12}"
              + "".join(f"{row['free'][r]:>{max(name_w, 8) + 2}}" for r in roms)
              + f"{row['min_free']:>10}{row['min_gap']:>9}{delta_text:>8}")
    if hidden:
        print(f"({hidden} roomier unchanged banks hidden; --all shows them)")

    rom_rows = [k for k in keys if k.split(":")[0] == "ROMX"]
    print(f"\nROMX total min free: {sum(report[k]['min_free'] for k in rom_rows)} B "
          f"across {len(rom_rows)} banks (does not solve a single-bank overflow)")
    if args.compare and not previous:
        print(f"(no baseline at {args.compare}; deltas start next run)")

    if args.save:
        args.save.parent.mkdir(parents=True, exist_ok=True)
        args.save.write_text(json.dumps({"roms": roms, "banks": report}, indent=1) + "\n")

    failures = []
    for spec in args.min_free:
        name, _, floor = spec.partition("=")
        key = name if ":" in name else f"{name}:00"
        if key not in report:
            raise SystemExit(f"--min-free: unknown bank {name!r}")
        if report[key]["min_free"] < int(floor, 0):
            failures.append(f"{label(key)} has {report[key]['min_free']} B free, floor is {floor}")
    for failure in failures:
        print(f"FLOOR: {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
