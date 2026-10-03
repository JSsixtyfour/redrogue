#!/usr/bin/env python3
"""Describe a build's battery-save layout, and compare two of them.

    python3 tools/save_schema.py extract pokeblue_debug.sym --map pokeblue_debug.map --out s.json
    python3 tools/save_schema.py diff old.json new.json
    python3 tools/save_schema.py check        (after `make`: the build against the committed schema)

`extract` reads every SRAM label and every saved WRAM field from a build's .sym
and .map: bank, address, size (up to the next label), and for saved WRAM where
it lands inside the save (block + offset). It also records the save-schema ID
the ROM declares (constants/save_constants.asm, if present), how each checksum
is computed, and the value of every constant a save can store (species, item,
move, map, event and toggle IDs and so on), as rgbasm resolves them.

`diff` classifies the change between two schemas:
  identical      same layout, and every stored constant keeps its value
  semantic       same layout, but a constant a save can store was renumbered or removed
  layout         stored fields moved, resized, appeared or vanished: migration needed
Exit status 0 / 1 / 2 for identical / semantic / layout. Added constants are
not a change: no existing save holds their numbers. Comments, formatting and
unsaved RAM never are.

`check` extracts the current build and compares it with
tools/save_schemas/schema_<id>.json for the schema ID the ROM declares, and
with the constants of the newest `make release` package of that schema (so a
constant added after the schema was written is protected once it has shipped).
Any layout change or renumbering without a new schema ID fails, and so does any
persisted label with no policy in tools/save_schemas/policy.json. `make
save_schema` runs it, and so does `make release`, right after the build.

Names: symbol names alone never prove two fields mean the same thing; the
policy file and the migration code carry the meaning.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCHEMAS = REPO / "tools" / "save_schemas"
FORMAT = 1
SYM_LINE = re.compile(r"^([0-9a-fA-F]{2}):([0-9a-fA-F]{4}) (\S+)$")
SECTION_LINE = re.compile(r'^\s*SECTION: \$([0-9a-f]{4})-\$([0-9a-f]{4}) \(\$[0-9a-f]+ bytes\) \["(.+)"\]')
SRAM_BANK_LINE = re.compile(r"^SRAM bank #(\d+):")

RELEASES = REPO / "builds" / "releases"
RELEASE_VALUES = "save_values.json"  # what `make release` keeps in each package

# Files whose values a save stores: IDs, flag numbers, enum values. Renumbering
# one of these changes what saved bytes mean without moving any of them. The
# check compares the constants named in these files by value, so comments,
# formatting and additions never trip it. (Saved RAM is the layout check's job.)
SEMANTIC_SOURCES = [
    "constants/event_constants.asm", "constants/item_constants.asm", "constants/map_constants.asm",
    "constants/move_constants.asm", "constants/pokemon_constants.asm", "constants/pokemon_data_constants.asm",
    "constants/ram_constants.asm", "constants/rogue_species_groups.asm", "constants/round_constants.asm",
    "constants/sprite_constants.asm", "constants/toggle_constants.asm", "constants/trainer_constants.asm",
    "constants/type_constants.asm", "constants/player_constants.asm", "constants/map_object_constants.asm",
    "constants/tileset_constants.asm", "constants/pokedex_constants.asm", "constants/save_constants.asm",
]
# Everything includes.asm pulls in, for assembling an older commit's constants.
CONSTANT_TREES = ["includes.asm", "macros", "constants", "vc"]
STATE_DEF = re.compile(r"^def (\S+) equ \$([0-9a-fA-F]+)$")
IDENT = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")

# Saved WRAM spans and the SRAM block each is copied to (engine/menus/save.asm).
SAVED_SPANS = [
    ("wPlayerName", 11, "sPlayerName"),
    ("wMainDataStart", "wMainDataEnd", "sMainData"),
    ("wSpriteDataStart", "wSpriteDataEnd", "sSpriteData"),
    ("wPartyDataStart", "wPartyDataEnd", "sPartyData"),
    ("wBoxDataStart", "wBoxDataEnd", "sCurBoxData"),
]

# Every checksum is an 8-bit sum of the bytes, complemented (CalcCheckSum,
# FinalTeamArchiveChecksum). resolve_checksums() turns these into bank/start/
# length/at addresses for this build.
def resolve_checksums(labels) -> list[dict]:
    def at(name, plus=0):
        bank, addr = labels[name]
        return bank, addr + plus

    box = labels["wBoxDataEnd"][1] - labels["wBoxDataStart"][1]
    out = []

    def add(name, bank, start, length, at_bank, at_addr, optional=False):
        out.append({"name": name, "bank": bank, "start": f"{start:04x}", "length": length,
                    "at_bank": at_bank, "at": f"{at_addr:04x}", "optional": optional})

    b, s = at("sGameData")
    add("main", b, s, labels["sGameDataEnd"][1] - s, *at("sMainDataCheckSum"))
    for first, all_label, each_label in ((1, "sBank2AllBoxesChecksum", "sBank2IndividualBoxChecksums"),
                                         (7, "sBank3AllBoxesChecksum", "sBank3IndividualBoxChecksums")):
        b, s = at(f"sBox{first}")
        add(f"boxes_{first}_to_{first + 5}", b, s, labels[all_label][1] - s, *at(all_label))
        for i in range(6):
            b, s = at(f"sBox{first + i}")
            add(f"box{first + i}", b, s, box, *at(each_label, i))
    if "sFinalTeamArchive" in labels:
        b, s = at("sFinalTeamArchiveMagic")
        add("final_team_header", b, s, labels["sFinalTeamArchiveHeaderChecksum"][1] - s,
            *at("sFinalTeamArchiveHeaderChecksum"), optional=True)
        records = labels["sFinalTeamArchiveRecords"][1]
        record = (labels["sFinalTeamArchiveEnd"][1] - records) // 4
        for i in range(4):
            add(f"final_team_record{i}", b, records + i * record, record,
                *at("sFinalTeamArchiveRecordChecksums", i), optional=True)
    return out


def parse_sym(path: Path) -> dict[str, tuple[int, int]]:
    labels = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = SYM_LINE.match(line.strip())
        if m:
            labels[m.group(3)] = (int(m.group(1), 16), int(m.group(2), 16))
    return labels


def parse_sram_sections(path: Path) -> list[dict]:
    """SRAM sections from the .map: bank, start, end (exclusive), name."""
    sections, bank = [], None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = SRAM_BANK_LINE.match(line)
        if m:
            bank = int(m.group(1))
            continue
        if line and not line[0].isspace():
            bank = None
        if bank is None:
            continue
        s = SECTION_LINE.match(line)
        if s:
            sections.append({"bank": bank, "start": int(s.group(1), 16), "end": int(s.group(2), 16) + 1,
                             "name": s.group(3)})
    return sections


def _sized(entries: list[tuple[int, str]], end: int) -> list[dict]:
    """[(address, label)] sorted -> labels with size = distance to the next different address (or end)."""
    out = []
    addresses = sorted({a for a, _ in entries})
    for address, label in entries:
        later = [a for a in addresses if a > address]
        out.append({"label": label, "address": address, "size": (later[0] if later else end) - address})
    return out


def sram_fields(labels, sections) -> list[dict]:
    fields = []
    for sec in sections:
        inside = sorted((addr, name) for name, (bank, addr) in labels.items()
                        if bank == sec["bank"] and sec["start"] <= addr < sec["end"] and name.startswith("s")
                        and "." not in name)
        for f in _sized(inside, sec["end"]):
            fields.append({"label": f["label"], "bank": sec["bank"], "address": f"{f['address']:04x}",
                           "size": f["size"], "section": sec["name"]})
    return fields


def saved_wram(labels) -> list[dict]:
    out = []
    for start, end, block in SAVED_SPANS:
        s = labels[start][1]
        e = s + end if isinstance(end, int) else labels[end][1]
        base = labels[block]
        inside = sorted((addr, name) for name, (bank, addr) in labels.items()
                        if 0xC000 <= addr < 0xE000 and s <= addr < e and "." not in name and name.startswith("w"))
        for f in _sized(inside, e):
            out.append({"label": f["label"], "wram": f"{f['address']:04x}", "size": f["size"], "block": block,
                        "bank": base[0], "sram": f"{base[1] + f['address'] - s:04x}",
                        "offset": f["address"] - s})
    return out


def declared_schema_id(source_root: Path | None, commit: str | None) -> int | None:
    text = _read_source("constants/save_constants.asm", source_root, commit)
    if text is None:
        return None
    m = re.search(r"DEF\s+SAVE_SCHEMA_ID\s+EQU\s+(\d+)", text)
    return int(m.group(1)) if m else None


def _read_source(rel: str, source_root: Path | None, commit: str | None) -> str | None:
    if commit:
        out = subprocess.run(["git", "show", f"{commit}:{rel}"], cwd=REPO, capture_output=True, text=True,
                             encoding="utf-8", errors="replace")
        return out.stdout if out.returncode == 0 else None
    path = (source_root or REPO) / rel
    return path.read_text(encoding="utf-8", errors="replace") if path.is_file() else None


def constant_values(commit: str | None) -> dict[str, int]:
    """{name: value} for every numeric constant named in SEMANTIC_SOURCES, as
    rgbasm resolves it for the debug ROM (-s writes the assembler's final state).
    commit=None reads the work tree; otherwise that commit's files via git archive."""
    with tempfile.TemporaryDirectory() as tmp:
        root = REPO
        if commit:
            root = Path(tmp) / "src"
            root.mkdir()
            archive = subprocess.run(["git", "archive", commit, *CONSTANT_TREES], cwd=REPO, capture_output=True)
            if archive.returncode:
                raise SystemExit(f"git archive {commit} failed: {archive.stderr.decode(errors='replace')}")
            subprocess.run(["tar", "-x", "-C", str(root)], input=archive.stdout, check=True)
        empty, state = Path(tmp) / "empty.asm", Path(tmp) / "state.asm"
        empty.write_text("")
        result = subprocess.run(["rgbasm", "-Q8", "-P", "includes.asm", "-D", "_BLUE", "-D", "_DEBUG",
                                 "-s", f"equ:{state}", "-o", str(Path(tmp) / "empty.o"), str(empty)],
                                cwd=root, capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(f"rgbasm couldn't resolve the constants:\n{result.stderr}")
        names = set()
        for rel in SEMANTIC_SOURCES:
            path = root / rel
            if path.is_file():
                names |= set(IDENT.findall(re.sub(r";.*", "", path.read_text(encoding="utf-8", errors="replace"))))
        values = {}
        for line in state.read_text(encoding="utf-8").splitlines():
            m = STATE_DEF.match(line)
            if m and m.group(1) in names:
                values[m.group(1)] = int(m.group(2), 16)
        return dict(sorted(values.items()))


def extract(sym: Path, map_path: Path, commit: str | None = None) -> dict:
    labels = parse_sym(sym)
    sections = parse_sram_sections(map_path)
    header = labels.get("sSaveHeader")
    return {
        "format": FORMAT,
        "schema_id": declared_schema_id(None, commit),
        "source": {"sym": sym.name, "commit": commit},
        "sram_size": 0x8000,
        "header": {"bank": header[0], "address": f"{header[1]:04x}"} if header else None,
        "sections": [{**s, "start": f"{s['start']:04x}", "end": f"{s['end']:04x}"} for s in sections],
        "sram": sram_fields(labels, sections),
        "saved_wram": saved_wram(labels),
        "checksums": resolve_checksums(labels),
        "constants": constant_values(commit),
    }


# --- comparing ------------------------------------------------------------------------

def _layout(schema: dict, ignore_header: bool) -> tuple[dict, dict]:
    sram = {f["label"]: (f["bank"], f["address"], f["size"]) for f in schema["sram"]}
    if ignore_header:
        sram = {k: v for k, v in sram.items() if not k.startswith("sSaveHeader")}
    wram = {f["label"]: (f["block"], f["offset"], f["size"]) for f in schema["saved_wram"]}
    return sram, wram


def diff(old: dict, new: dict, ignore_header: bool = False) -> dict:
    """What changed between two schemas, by label. ignore_header compares an
    untagged baseline with its first tagged successor."""
    report = {"sram": {}, "saved_wram": {}, "semantic": {}, "kind": "identical"}
    for part, (a, b) in zip(("sram", "saved_wram"), zip(_layout(old, ignore_header), _layout(new, ignore_header))):
        changed = {}
        for label in sorted(set(a) | set(b)):
            if a.get(label) != b.get(label):
                changed[label] = {"old": a.get(label), "new": b.get(label)}
        report[part] = changed
    if ignore_header:
        # The header's 8 bytes come out of padding: the block around it moves, nothing stored does.
        report["sram"] = {k: v for k, v in report["sram"].items() if not _is_padding_split(k, v)}
    report["semantic"] = renumbered(old.get("constants"), new.get("constants"))
    if report["sram"] or report["saved_wram"]:
        report["kind"] = "layout"
    elif report["semantic"]:
        report["kind"] = "semantic"
    return report


def renumbered(old: dict | None, new: dict | None) -> dict:
    """{name: {"old", "new"}} for constants whose value changed or that vanished
    (new None). Additions are left out: no save made before them holds their
    numbers. A schema without constants (the untagged baseline) compares as none."""
    if old is None or new is None:
        return {}
    return {name: {"old": value, "new": new.get(name)} for name, value in old.items() if new.get(name) != value}


def _is_padding_split(label: str, change: dict) -> bool:
    """sStolenRecordEnd is the label the bank-1 padding hangs off; carving the header
    from that padding changes only its 'size'."""
    old, new = change["old"], change["new"]
    return label == "sStolenRecordEnd" and old and new and old[:2] == new[:2]


def print_diff(report: dict) -> None:
    print(f"kind: {report['kind']}")
    for part in ("sram", "saved_wram"):
        for label, change in list(report[part].items())[:60]:
            print(f"  {part} {label}: {change['old']} -> {change['new']}")
        if len(report[part]) > 60:
            print(f"  ... {len(report[part]) - 60} more {part} changes")
    for name, change in list(report["semantic"].items())[:60]:
        new = "removed" if change["new"] is None else f"${change['new']:x}"
        print(f"  constant {name}: ${change['old']:x} -> {new}")
    if len(report["semantic"]) > 60:
        print(f"  ... {len(report['semantic']) - 60} more constants")


# --- policy ----------------------------------------------------------------------------

def unclassified(schema: dict, policy: dict) -> list[str]:
    """Persisted SRAM labels and saved-WRAM blocks that no policy rule covers."""
    rules = policy["sram"]
    missing = []
    for f in schema["sram"]:
        if not any(re.fullmatch(pattern, f["label"]) for pattern in rules):
            missing.append(f["label"])
    return missing


def newest_release_values(sid: int, releases: Path = RELEASES) -> tuple[str, dict] | None:
    """(package name, constants) of the newest `make release` package for schema sid, if any.
    Package names start with the build stamp, so name order is release order."""
    for pkg in sorted((p for p in releases.glob("*/") if (p / RELEASE_VALUES).is_file()), reverse=True):
        data = json.loads((pkg / RELEASE_VALUES).read_text(encoding="utf-8"))
        if data.get("schema_id") == sid:
            return pkg.name, data["constants"]
    return None


def expected_constants(stored: dict, release: tuple[str, dict] | None) -> tuple[dict, str]:
    """The constants saves of this schema may hold: the committed schema's, plus
    whatever the newest release shipped on top (it can only add names the schema
    predates), unless --accept was run after that release."""
    expected, against = dict(stored.get("constants") or {}), "the committed schema"
    if release and release[0] > (stored.get("accepted_after_release") or ""):
        expected.update(release[1])
        against = f"the committed schema and release {release[0]}"
    return expected, against


def check(schema_dir: Path, sym: Path, map_path: Path, accept: bool = False, save_values: Path | None = None,
          releases: Path = RELEASES) -> int:
    current = extract(sym, map_path)
    sid = current["schema_id"]
    if sid is None:
        print("check: constants/save_constants.asm declares no SAVE_SCHEMA_ID")
        return 2
    policy = json.loads((schema_dir / "policy.json").read_text(encoding="utf-8"))
    missing = unclassified(current, policy)
    if missing:
        print("check: persisted SRAM labels with no policy in tools/save_schemas/policy.json:")
        for label in missing:
            print(f"  {label}")
        return 2
    committed = schema_dir / f"schema_{sid}.json"
    if not committed.is_file():
        print(f"check: no {committed.relative_to(REPO)} yet. Create it with:\n"
              f"  python3 tools/save_schema.py extract {sym.name} --map {map_path.name} --out {committed.relative_to(REPO)}")
        return 2
    stored = json.loads(committed.read_text(encoding="utf-8"))
    release = newest_release_values(sid, releases)
    expected, against = expected_constants(stored, release)
    report = diff({**stored, "constants": expected}, current)
    if report["kind"] == "layout":
        print_diff(report)
        print(f"check: the save layout changed but SAVE_SCHEMA_ID is still {sid}. Bump it, write the "
              "migration, and commit the new schema (see SAVE_COMPATIBILITY_RUNBOOK.md).")
        return 2
    if report["kind"] == "semantic":
        print_diff(report)
        if not accept:
            print(f"check: same layout as schema {sid}, but {len(report['semantic'])} constant(s) a save can store "
                  f"were renumbered or removed since {against}, so old saves would read them wrong. Bump "
                  "SAVE_SCHEMA_ID and add a migration (SAVE_COMPATIBILITY_RUNBOOK.md). Only if no save can hold "
                  "these numbers, record that with: python3 tools/save_schema.py check --accept")
            return 1
        stored["constants"] = current["constants"]
        if release:
            stored["accepted_after_release"] = release[0]
        committed.write_text(json.dumps(stored, indent=1) + "\n", encoding="utf-8", newline="\n")
        print(f"check: accepted; stored the current constants in {committed.relative_to(REPO)} (commit it)")
    else:
        print(f"check: save layout and stored constants match schema {sid}")
    if save_values:
        save_values.parent.mkdir(parents=True, exist_ok=True)
        save_values.write_text(json.dumps({"schema_id": sid, "constants": current["constants"]}, indent=1) + "\n",
                               encoding="utf-8", newline="\n")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    ex = sub.add_parser("extract")
    ex.add_argument("sym", type=Path)
    ex.add_argument("--map", type=Path, required=True)
    ex.add_argument("--commit", help="read the semantic sources and schema ID from this commit (default: work tree)")
    ex.add_argument("--out", type=Path)
    df = sub.add_parser("diff")
    df.add_argument("old", type=Path)
    df.add_argument("new", type=Path)
    df.add_argument("--ignore-header", action="store_true", help="compare an untagged baseline with its tagged successor")
    ck = sub.add_parser("check")
    ck.add_argument("--sym", type=Path, default=REPO / "pokeblue_debug.sym")
    ck.add_argument("--map", type=Path, default=REPO / "pokeblue_debug.map")
    ck.add_argument("--accept", action="store_true",
                    help="renumbered constants reviewed and no save can hold them: store the current values")
    ck.add_argument("--save-values", type=Path, help=f"write this build's constants here ({RELEASE_VALUES} for make release)")
    args = parser.parse_args(argv)

    if args.cmd == "extract":
        schema = extract(args.sym, args.map, args.commit)
        text = json.dumps(schema, indent=1) + "\n"
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(text, encoding="utf-8", newline="\n")
            print(f"wrote {args.out} (schema id {schema['schema_id']}, {len(schema['sram'])} SRAM labels, "
                  f"{len(schema['saved_wram'])} saved WRAM fields)")
        else:
            sys.stdout.write(text)
        return 0
    if args.cmd == "diff":
        report = diff(json.loads(args.old.read_text(encoding="utf-8")), json.loads(args.new.read_text(encoding="utf-8")),
                      args.ignore_header)
        print_diff(report)
        return {"identical": 0, "semantic": 1, "layout": 2}[report["kind"]]
    return check(SCHEMAS, args.sym, args.map, args.accept, args.save_values)


if __name__ == "__main__":
    sys.exit(main())
