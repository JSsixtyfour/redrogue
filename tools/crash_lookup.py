#!/usr/bin/env python3
r"""Turn a debug-build crash screen into labels.

The crash screen (engine/debug/crash_screen.asm) shows the build ID, the
crashing PC as bank:address, and the stack. Type them in:

    python3 tools/crash_lookup.py 9dba3ff3 1F:5A3C 5A12 0C4E 39A0 21F3 0000 0000

or run it with no arguments and it asks for each line. From PowerShell:
`py tools\crash_lookup.py`. README.md's "Crash screen" section has the walkthrough.

The first argument picks the archived build in builds/ or builds/releases/
(`9dba3ff3`, or with `-dirty`). If several archived builds share it, add the
screen's date and time (`--built "2026-10-01 13:10"`); otherwise the newest is
used, with a warning. With --exact (what the playtest bot uses) an ambiguous ID
is an error listing the candidates instead. Or pass a .sym path instead of an ID.

--json prints the result as JSON (for the bot): on success {"ok": true, ...},
otherwise {"ok": false, "error": ..., "candidates": [...]} and exit status 2.

Stack words are return addresses, so each names the routine that made a call
(the `call` itself sits just before). A stack word in $4000-$7FFF carries no
bank: it is resolved in the crash's bank, which is right for calls made within
that bank and wrong for a farcall's return, so treat those as a lead. Words
outside ROM are data or saved registers, not calls.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

REPO = Path(__file__).resolve().parents[1]
SYM_LINE = re.compile(r"^([0-9a-fA-F]{2}):([0-9a-fA-F]{4})\s+(\S+)$")
BUILD_ID = re.compile(r"^[0-9a-f]{4,40}(-dirty)?$")
BUILT = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:?\d{2}(:?\d{2})?$")
PC_TEXT = re.compile(r"^([0-9a-fA-F]{1,2}):([0-9a-fA-F]{4})$")
WORD_TEXT = re.compile(r"^[0-9a-fA-F]{4}$")
MAX_BANK = 0x7F  # MBC3


class LookupError_(Exception):
    """A lookup that can't give an exact answer; candidates lists the builds it could mean."""

    def __init__(self, message: str, candidates: Optional[List[str]] = None):
        super().__init__(message)
        self.candidates = candidates or []


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


def nearest_entry(symbols, bank: int, address: int) -> Optional[Tuple[str, int]]:
    """(label, offset) of the last label at or before bank:address."""
    found = None
    for symbol_address, label in symbols.get(bank, ()):
        if symbol_address > address:
            break
        found = (symbol_address, label)
    return None if found is None else (found[1], address - found[0])


def nearest(symbols: Dict[int, List[Tuple[int, str]]], bank: int, address: int) -> Optional[str]:
    entry = nearest_entry(symbols, bank, address)
    if entry is None:
        return None
    label, offset = entry
    return label if offset == 0 else f"{label}+${offset:x}"


def candidates(build: str, built: Optional[str], builds_dir: Path, exact: bool = False) -> List[Path]:
    """Archived debug .sym files matching a build ID (and the screen's date/time), oldest first.
    builds/releases/ copies win over builds/ ones of the same name, so a pruned archive doesn't matter."""
    build = build.lower()
    found = {}
    for folder in (builds_dir, builds_dir / "releases"):
        for m in folder.glob(f"pokeblue_debug_*_{build}*.sym"):
            found[m.name] = m
    matches = sorted(found.values(), key=lambda m: m.name)
    # A clean ID also finds that commit's -dirty builds, except in exact mode.
    matches = [m for m in matches if m.stem.endswith("_" + build)
               or (not exact and m.stem.endswith(f"_{build}-dirty"))]
    if built:
        date, _, clock = built.partition(" ")
        stamp = f"{date}_{clock.replace(':', '')}"
        matches = [m for m in matches if f"_{stamp}" in m.stem]
    return matches


def find_sym(build: str, built: Optional[str], builds_dir: Path, exact: bool = False) -> Path:
    as_path = Path(build)
    if as_path.suffix == ".sym":
        if exact:
            raise LookupError_("--exact takes a build ID, not a .sym path")
        if as_path.is_file():
            return as_path
    if not BUILD_ID.match(build.lower()):
        raise LookupError_(f"{build!r} isn't a build ID (like 9dba3ff3 or 9dba3ff3-dirty)")
    if built and not BUILT.match(built):
        raise LookupError_(f"--built must look like 2026-10-01 13:24, not {built!r}")
    matches = candidates(build, built, builds_dir, exact)
    if not matches:
        raise LookupError_(f"no archived debug build matching {build!r}" + (f" built {built}" if built else "")
                           + " in builds/ or builds/releases/")
    if len(matches) > 1:
        names = [m.stem for m in matches]
        if exact:
            raise LookupError_(f"{len(matches)} archived builds match {build!r}; give the screen's date and "
                               "time to pick one", names)
        print(f"note: {len(matches)} archived builds match; using the newest, {matches[-1].name}. "
              "Pass --built with the screen's date and time to pick one.", file=sys.stderr)
    return matches[-1]


def parse_pc(text: str) -> Tuple[int, int]:
    match = PC_TEXT.match(text.strip())
    if not match:
        raise argparse.ArgumentTypeError(f"PC must be bank:address, like 1F:5A3C (got {text!r})")
    bank, address = int(match.group(1), 16), int(match.group(2), 16)
    if bank > MAX_BANK:
        raise argparse.ArgumentTypeError(f"bank ${bank:02x} is past the last ROM bank (${MAX_BANK:02x})")
    return bank, address


def parse_word(text: str) -> int:
    if not WORD_TEXT.match(text.strip()):
        raise argparse.ArgumentTypeError(f"stack words are 4 hex digits, like 0C4E (got {text!r})")
    return int(text, 16)


def rom_byte(sym: Path, bank: int, address: int) -> Optional[int]:
    """The byte at bank:address in the .gbc archived beside the .sym, if present."""
    rom = sym.with_suffix(".gbc")
    if not rom.is_file():
        return None
    offset = address if address < 0x4000 else bank * 0x4000 + (address - 0x4000)
    data = rom.read_bytes()
    return data[offset] if offset < len(data) else None


def pc_info(symbols, sym: Path, bank: int, pc: int) -> dict:
    if pc == 0:
        return {"kind": "null", "address": "0000",
                "text": "jumped to $0000 (NULL): a call or jump through a zeroed pointer"}
    if pc >= 0x8000:
        return {"kind": "ram", "address": f"{pc:04x}",
                "text": f"${pc:04x} is RAM: executing a $FF byte there, so a jump through a garbage pointer"}
    where_bank = 0 if pc < 0x4000 else bank
    entry = nearest_entry(symbols, where_bank, pc)
    padding = rom_byte(sym, where_bank, pc) == 0xFF
    label = nearest(symbols, where_bank, pc)
    text = f"{where_bank:02x}:{pc:04x} {label or '(before any label)'}"
    if padding:
        text += ("\n       That byte is $FF: padding or data, not code. The bug is whatever jumped or "
                 "returned here;\n       the first STACK word is the last call still in progress.")
    return {"kind": "rom", "bank": f"{where_bank:02x}", "address": f"{pc:04x}",
            "label": entry[0] if entry else None, "offset": entry[1] if entry else None,
            "ff_padding": padding, "text": text}


def describe_pc(symbols, sym: Path, bank: int, pc: int) -> str:
    return pc_info(symbols, sym, bank, pc)["text"]


def return_info(symbols, crash_bank: int, word: int) -> dict:
    """A stack word as a return address. ROMX words are only candidates: they carry no bank."""
    base = {"word": f"{word:04x}"}
    if word >= 0x8000:
        return {**base, "kind": "not_rom", "text": "not ROM (data or a saved register, not a return address)"}
    bank = 0 if word < 0x4000 else crash_bank
    entry = nearest_entry(symbols, bank, word)
    label = nearest(symbols, bank, word)
    if word < 0x4000:
        text = f"called from {label} (HOME)" if label else "before any HOME label"
        kind = "home"
    else:
        text = (f"called from {label}, if this call was made in bank ${crash_bank:02x}"
                if label else f"no label at or before it in bank ${crash_bank:02x}")
        kind = "romx_candidate"
    return {**base, "kind": kind, "bank": f"{bank:02x}", "label": entry[0] if entry else None,
            "offset": entry[1] if entry else None, "exact_label": bool(entry and entry[1] == 0), "text": text}


def describe_return(symbols, crash_bank: int, word: int) -> str:
    return return_info(symbols, crash_bank, word)["text"]


def _sha256(path: Path) -> Optional[str]:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def lookup(sym: Path, bank: int, pc: int, stack: List[int]) -> dict:
    """The whole answer as data: which files were used, the PC, and each stack word."""
    symbols = load_symbols(sym)
    rom = sym.with_suffix(".gbc")
    return {
        "ok": True,
        "build": sym.stem,
        "sym": sym.name,
        "sym_sha256": _sha256(sym),
        "rom": rom.name if rom.is_file() else None,
        "rom_sha256": _sha256(rom),
        "crash_bank": f"{bank:02x}",
        "pc": pc_info(symbols, sym, bank, pc),
        "stack": [return_info(symbols, bank, w) for w in stack],
        "note": "ROMX stack words ($4000-$7FFF) are looked up in the crash's bank and are candidates, "
                "not a proven call chain; a farcall's return lives in another bank.",
    }


def ask() -> List[str]:
    """No arguments: ask for each line of the crash screen in turn."""
    print("Copy these from the crash screen (or its screenshot).")
    build = input("ID line, e.g. 9dba3ff3-dirty: ").strip()
    built = input("Date and time line, e.g. 2026-10-01 13:24 (Enter to skip): ").strip()
    pc = input("PC line, e.g. 00:3E7C: ").strip()
    stack = input("The six STACK words, in order, spaces between: ").split()
    print()
    return [build, pc, *stack] + (["--built", built] if built else [])


class _Parser(argparse.ArgumentParser):
    """In --json mode, argument errors come back as JSON too."""
    json_mode = False

    def error(self, message):
        if self.json_mode:
            print(json.dumps({"ok": False, "error": message, "candidates": []}))
            sys.exit(2)
        super().error(message)


def main(argv: Optional[List[str]] = None) -> int:
    if argv is None and len(sys.argv) == 1:
        argv = ask()
    argv = list(sys.argv[1:] if argv is None else argv)
    parser = _Parser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.json_mode = "--json" in argv
    parser.add_argument("build", help="build ID from the screen (or a .sym path)")
    parser.add_argument("pc", type=parse_pc, help="the PC line, bank:address")
    parser.add_argument("stack", nargs="*", type=parse_word, help="the STACK words, in screen order")
    parser.add_argument("--built", help='date and time from the screen, e.g. "2026-10-01 13:10"')
    parser.add_argument("--builds-dir", type=Path, default=REPO / "builds")
    parser.add_argument("--exact", action="store_true", help="refuse an ambiguous build instead of using the newest")
    parser.add_argument("--json", action="store_true", help="print the result as JSON")
    args = parser.parse_args(argv)
    if len(args.stack) > 16:
        parser.error("at most 16 stack words")

    try:
        sym = find_sym(args.build, args.built, args.builds_dir, exact=args.exact)
    except LookupError_ as e:
        if args.json:
            print(json.dumps({"ok": False, "error": str(e), "candidates": e.candidates}))
            return 2
        sys.exit(f"{e}" + ("".join(f"\n  {c}" for c in e.candidates)))
    bank, pc = args.pc
    result = lookup(sym, bank, pc, args.stack)
    if args.json:
        print(json.dumps(result))
        return 0
    print(sym.name)
    print(f"PC     {result['pc']['text']}")
    for index, item in enumerate(result["stack"], 1):
        print(f"stack{index} {item['word']}  {item['text']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
