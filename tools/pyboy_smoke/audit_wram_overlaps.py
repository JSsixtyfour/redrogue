"""Guard: which WRAM/HRAM/SRAM labels share bytes, and which of those pairs are new since pret.

A UNION is safe only while its branches are never live together. Nothing in the
assembler checks that, and an edit inside one branch can slide later labels under
another branch's buffer without any line about that buffer changing. Found
2026-11-24: a NEXTU added on 2026-05-11 cut the battle branch in two, which slid
wEnemyBideAccumulatedDamage down under wMonPartySpritesSavedOAM's fifth entry, and
opening the party menu overwrote the Bide tally.

This lists every pair of labels whose bytes overlap, drops the pairs vanilla (the
pret merge-base) already had, and compares the rest with wram_overlap_baseline.json.
A pair that is not in the baseline fails: decide whether both labels can be live at
once, then re-record with --update. Extents are exact: a marker label is added after
every directive in a throwaway copy of ram/*.asm and the RAM sections alone are
assembled and linked, so no size expression is re-evaluated here.

Pairs are between whole labels (`wBattleMon:: battle_struct` is one label).

    python3 tools/pyboy_smoke/audit_wram_overlaps.py            # fail on new pairs
    python3 tools/pyboy_smoke/audit_wram_overlaps.py --update   # re-record the baseline
    python3 tools/pyboy_smoke/audit_wram_overlaps.py --show wMiscBattleData wBattleStatusData
                                                                # new pairs touching that span
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = Path(__file__).with_name("wram_overlap_baseline.json")
VANILLA = "fbcf7d0e19a3a2db505440d3ccd3d40ca996c15c"  # the pret/pokered merge-base
RAM_FILES = ("wram", "sram", "hram")
LABEL = re.compile(r"^([A-Za-z_][\w{}:]*?)::?(?:\s+(.*))?$")
DIRECTIVE = re.compile(r"^(db|dw|dl|ds|flag_array|\w*_struct|\w*statedata\d)\b")
BREAK = re.compile(r"^(UNION|NEXTU|ENDU|SECTION)\b", re.I)
MARK = "zzEnd"


def instrument(text: str, prefix: str) -> str:
    """Add an end marker after every `label:: directive` line. Inside a FOR the
    marker takes the loop variable, so each pass defines its own."""
    out: list[str] = []
    loops: list[str | None] = []
    pending: list[str] = []
    before: list[str] = []
    for number, raw in enumerate(text.splitlines()):
        code = raw.split(";", 1)[0].strip()
        out.append(raw)
        head = re.match(r"^for\s+(\w+)", code, re.I)
        if (head or re.match(r"^rept", code, re.I)) and not loops:
            before, pending = pending, []  # `wBoxMons::` above a FOR spans the whole loop
        if head:
            loops.append(head.group(1))
            continue
        if re.match(r"^rept\b", code, re.I):
            loops.append(None)
            continue
        if re.match(r"^endr\b", code, re.I):
            loops.pop()
            if not loops:
                out += before
                pending = []
            continue
        if None in loops or not code:
            continue
        match = LABEL.match(code)
        if not match:
            # Labels on their own line take the first directive under them.
            if DIRECTIVE.match(code):
                out += pending
                pending = []
            elif BREAK.match(code):
                pending = []
            continue
        label, rest = match.group(1), match.group(2)
        suffix = "".join("_{d:%s}" % name for name in loops)
        pending.append(f"{MARK}_{prefix}{number}{suffix}_{label}::")
        if rest:
            out += pending
            pending = []
    return "\n".join(out) + "\n"


def extents(tree: Path, flags: list[str]) -> dict[str, tuple[int, int, int]]:
    """label -> (bank, start, end) from a RAM-only link of `tree`."""
    with tempfile.TemporaryDirectory(prefix="wram_overlap_") as name:
        scratch = Path(name)
        for folder in ("macros", "constants", "ram", "vc"):
            if (tree / folder).exists():
                shutil.copytree(tree / folder, scratch / folder)
        shutil.copy(tree / "includes.asm", scratch / "includes.asm")
        shutil.copy(tree / "ram.asm", scratch / "ram.asm")
        for ram in RAM_FILES:
            path = scratch / "ram" / f"{ram}.asm"
            path.write_text(instrument(path.read_text(encoding="utf-8"), ram[0]), encoding="utf-8")
        # The linker script's RAM half: some ASSERTs check pinned addresses.
        sources = "".join((scratch / "ram" / f"{ram}.asm").read_text(encoding="utf-8") for ram in RAM_FILES)
        layout = (tree / "layout.link").read_text(encoding="utf-8")
        layout = layout[layout.index("\nWRAM0") + 1:].splitlines()
        kept = [line for line in layout
                if not line.strip().startswith('"') or f"SECTION {line.strip()}" in sources]
        (scratch / "ram.link").write_text("\n".join(kept) + "\n", encoding="utf-8")
        for command in (["rgbasm", "-Q8", "-P", "includes.asm", *flags, "-o", "ram.o", "ram.asm"],
                        ["rgblink", "-d", "-l", "ram.link", "-n", "ram.sym", "-o", "ram.gb", "ram.o"]):
            done = subprocess.run(command, cwd=scratch, capture_output=True, text=True)
            if done.returncode:
                raise RuntimeError(f"{' '.join(command)}\n{done.stderr[-3000:]}")
        symbols = {}
        for line in (scratch / "ram.sym").read_text(encoding="utf-8").splitlines():
            match = re.match(r"^([0-9a-f]+):([0-9a-f]{4}) (\S+)$", line)
            if match:
                symbols[match.group(3)] = (int(match.group(1), 16), int(match.group(2), 16))
    result = {}
    for marker, (bank, end) in symbols.items():
        if marker.startswith(MARK + "_"):
            label = re.sub(rf"^{MARK}_[a-z]\d+(_\d+)*_", "", marker)
            if label in symbols:
                result[label] = (bank, symbols[label][1], end)
    return result


def overlapping(table: dict[str, tuple[int, int, int]]) -> set[tuple[str, str]]:
    rows = sorted((bank, start, end, name) for name, (bank, start, end) in table.items() if end > start)
    pairs = set()
    for index, (bank, start, end, name) in enumerate(rows):
        for other_bank, other_start, _other_end, other in rows[index + 1:]:
            if other_bank != bank or other_start >= end:
                break
            pairs.add(tuple(sorted((name, other))))
    return pairs


def vanilla_table() -> dict[str, tuple[int, int, int]]:
    with tempfile.TemporaryDirectory(prefix="wram_vanilla_") as scratch:
        archive = subprocess.run(
            ["git", "archive", VANILLA, "ram.asm", "ram", "macros", "constants", "includes.asm", "vc", "layout.link"],
            cwd=ROOT, check=True, capture_output=True).stdout
        subprocess.run(["tar", "-x", "-C", scratch], input=archive, check=True)
        return extents(Path(scratch), ["-D", "_BLUE"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--tree", type=Path, default=ROOT, help="another checkout to measure")
    parser.add_argument("--show", nargs=2, metavar=("FIRST", "LAST"),
                        help="print every new pair touching the span from one label to another")
    args = parser.parse_args(argv)
    table = extents(args.tree, ["-D", "_BLUE", "-D", "_DEBUG"])
    vanilla = vanilla_table()
    if len(table) < 1000 or len(vanilla) < 700:
        print(f"only {len(table)} / {len(vanilla)} labels measured: the parser is broken")
        return 2
    pairs = overlapping(table)
    new = pairs - overlapping(vanilla)
    if args.show:
        low, high = table[args.show[0]][1], table[args.show[1]][2]
        for a, b in sorted(new, key=lambda pair: table[pair[0]][1]):
            if any(table[x][1] < high and table[x][2] > low for x in (a, b)):
                print(f"  {table[a][1]:04x}-{table[a][2] - 1:04x} {a:34} {table[b][1]:04x}-{table[b][2] - 1:04x} {b}")
        return 0
    print(f"{len(table)} labels, {len(pairs)} overlapping pairs, {len(new)} not in vanilla ({len(vanilla)} labels)")
    if args.update:
        BASELINE.write_text(json.dumps(sorted(map(list, new)), indent=0) + "\n", encoding="utf-8")
        return 0
    known = {tuple(pair) for pair in json.loads(BASELINE.read_text(encoding="utf-8"))}
    fresh = sorted(new - known)
    for a, b in fresh:
        print(f"NEW OVERLAP {a} {table[a][1]:04x}-{table[a][2] - 1:04x} / "
              f"{b} {table[b][1]:04x}-{table[b][2] - 1:04x}")
    if known - new:
        print(f"{len(known - new)} baseline pairs are gone; re-record with --update")
    return 1 if fresh else 0


if __name__ == "__main__":
    raise SystemExit(main())
