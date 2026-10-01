#!/usr/bin/env python3
"""Turn a debug-build crash screen into labels.

The crash screen (engine/debug/crash_screen.asm) shows the build ID, the
crashing PC as bank:address, and the stack. Type them in:

    python3 tools/crash_lookup.py 9dba3ff3 1F:5A3C 5A12 0C4E 39A0 21F3 0000 0000

The first argument picks the archived build in builds/ (`9dba3ff3`, or with
`-dirty`). If several archived builds share it, add the screen's date and time
(`--built "2026-10-01 13:10"`); otherwise the newest is used, with a warning.
Or pass a .sym path instead of an ID.

Stack words are return addresses, so each names the routine that made a call
(the `call` itself sits just before). A stack word in $4000-$7FFF carries no
bank: it is resolved in the crash's bank, which is right for calls made within
that bank and wrong for a farcall's return, so treat those as a lead. Words
outside ROM are data or saved registers, not calls.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

REPO = Path(__file__).resolve().parents[1]
SYM_LINE = re.compile(r"^([0-9a-fA-F]{2}):([0-9a-fA-F]{4})\s+(\S+)$")


def load_symbols(path: Path) -> Dict[int, List[Tuple[int, str]]]:
    """bank -> sorted [(address, label)] for ROM labels only."""
    by_bank: Dict[int, List[Tuple[int, str]]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = SYM_LINE.match(line.strip())
        if not match:
            continue
        bank, address = int(match.group(1), 16), int(match.group(2), 16)
        if address < 0x8000:
            by_bank.setdefault(bank, []).append((address, match.group(3)))
    for entries in by_bank.values():
        entries.sort()
    return by_bank


def nearest(symbols: Dict[int, List[Tuple[int, str]]], bank: int, address: int) -> Optional[str]:
    found = None
    for symbol_address, label in symbols.get(bank, ()):
        if symbol_address > address:
            break
        found = (symbol_address, label)
    if found is None:
        return None
    offset = address - found[0]
    return found[1] if offset == 0 else f"{found[1]}+${offset:x}"


def find_sym(build: str, built: Optional[str], builds_dir: Path) -> Path:
    as_path = Path(build)
    if as_path.suffix == ".sym" and as_path.is_file():
        return as_path
    build = build.lower()
    matches = sorted(builds_dir.glob(f"pokeblue_debug_*_{build}*.sym"))
    matches = [m for m in matches if m.stem.endswith(build) or m.stem.endswith(build + "-dirty")]
    if built:
        date, _, clock = built.partition(" ")
        stamp = f"{date}_{clock.replace(':', '')}"
        matches = [m for m in matches if stamp in m.stem]
    if not matches:
        sys.exit(f"no archived debug build matching {build!r} in {builds_dir}"
                 + (f" built {built}" if built else ""))
    if len(matches) > 1:
        print(f"note: {len(matches)} archived builds match; using the newest, {matches[-1].name}. "
              "Pass --built with the screen's date and time to pick one.", file=sys.stderr)
    return matches[-1]


def parse_pc(text: str) -> Tuple[int, int]:
    bank, _, address = text.partition(":")
    if not address:
        raise argparse.ArgumentTypeError(f"PC must be bank:address, like 1F:5A3C (got {text!r})")
    return int(bank, 16), int(address, 16)


def rom_byte(sym: Path, bank: int, address: int) -> Optional[int]:
    """The byte at bank:address in the .gbc archived beside the .sym, if present."""
    rom = sym.with_suffix(".gbc")
    if not rom.is_file():
        return None
    offset = address if address < 0x4000 else bank * 0x4000 + (address - 0x4000)
    data = rom.read_bytes()
    return data[offset] if offset < len(data) else None


def describe_pc(symbols, sym: Path, bank: int, pc: int) -> str:
    if pc == 0:
        return "jumped to $0000 (NULL): a call or jump through a zeroed pointer"
    if pc >= 0x8000:
        return f"${pc:04x} is RAM: executing a $FF byte there, so a jump through a garbage pointer"
    where_bank = 0 if pc < 0x4000 else bank
    label = nearest(symbols, where_bank, pc)
    text = f"{where_bank:02x}:{pc:04x} {label or '(before any label)'}"
    if rom_byte(sym, where_bank, pc) == 0xFF:
        text += ("\n       That byte is $FF: padding or data, not code. The bug is whatever jumped or "
                 "returned here;\n       the first STACK word is the last call still in progress.")
    return text


def describe_return(symbols, crash_bank: int, word: int) -> str:
    if word >= 0x8000:
        return "not ROM (data or a saved register, not a return address)"
    if word < 0x4000:
        label = nearest(symbols, 0, word)
        return f"called from {label} (HOME)" if label else "before any HOME label"
    label = nearest(symbols, crash_bank, word)
    return (f"called from {label}, if this call was made in bank ${crash_bank:02x}"
            if label else f"no label at or before it in bank ${crash_bank:02x}")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", help="build ID from the screen (or a .sym path)")
    parser.add_argument("pc", type=parse_pc, help="the PC line, bank:address")
    parser.add_argument("stack", nargs="*", help="the STACK words, in screen order")
    parser.add_argument("--built", help='date and time from the screen, e.g. "2026-10-01 13:10"')
    parser.add_argument("--builds-dir", type=Path, default=REPO / "builds")
    args = parser.parse_args(argv)

    sym = find_sym(args.build, args.built, args.builds_dir)
    symbols = load_symbols(sym)
    bank, pc = args.pc
    print(f"{sym.name}")
    print(f"PC     {describe_pc(symbols, sym, bank, pc)}")
    for index, text in enumerate(args.stack, 1):
        word = int(text, 16)
        print(f"stack{index} {word:04x}  {describe_return(symbols, bank, word)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
