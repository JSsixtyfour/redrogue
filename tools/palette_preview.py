#!/usr/bin/env python3
"""Render Enhanced Colors (CGB) overworld palettes as a browsable HTML page.

Reads straight from source, so the page always matches the tree:
  - constants/tileset_constants.asm        tileset IDs
  - data/tilesets/tileset_headers.asm      tileset ID -> gfx/block label stem
  - gfx/tilesets.asm                       label stem -> .2bpp / .bst files
  - data/gfx/overworld_tile_palettes.asm   PalSettings_* (tile -> register)
  - custom_functions/func_enhancedcolor.asm base sets (register -> 4 colours),
                                            EnhBasePalSetPointers, TownSpecialPal

Needs the built .2bpp files (run `make` first). No third-party modules.

    python tools/palette_preview.py [--out PATH]

Colours are the raw source values. The game also runs them through
GBCGamma (custom_functions/func_gamma.asm) before they reach the screen, so
on hardware they look somewhat darker and less saturated.
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

REGISTER_NAMES = ["RED", "PINK", "PURPLE", "GRAY", "GREEN", "YELLOW", "BROWN", "BLUE"]

# Which maps each base set reaches. Mirrors ResolveEnhancedBasePalSet; update
# this when a base set gains or loses a consumer.
BASE_SET_USES = {
    "ENH_BASE_DEFAULT": "Every map without an override. Procedural Cave variant 0, Procedural Facility variant 0 (PowerPlant).",
    "ENH_BASE_COLD": "Seafoam Islands. Procedural Cave variant 1 (cold).",
    "ENH_BASE_DARK": "Only through wMapPalOffset == 6, which nothing in Red Rogue writes. Cut as a cave variant.",
    "ENH_BASE_FOREST_SPRING": "Procedural Forest variant 0 (spring).",
    "ENH_BASE_FOREST_FALL": "Procedural Forest variant 1 (fall).",
    "ENH_BASE_FACILITY_RED": "Procedural Facility variant 1 (Mansion), and Pokemon Mansion 1F-3F, B1F.",
}

# Tilesets that are worth opening first for the variant work.
SUGGESTED = {"FOREST": "ENH_BASE_FOREST_SPRING", "FACILITY": "ENH_BASE_FACILITY_RED"}


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def strip_comment(line):
    return line.split(";", 1)[0]


def parse_int(tok):
    tok = tok.strip()
    if tok.startswith("$"):
        return int(tok[1:], 16)
    if tok.startswith("%"):
        return int(tok[1:], 2)
    return int(tok)


def parse_tileset_ids():
    ids = []
    for line in read("constants/tileset_constants.asm").splitlines():
        m = re.match(r"\s*const\s+(\w+)", strip_comment(line))
        if m:
            ids.append(m.group(1))
    return ids


def parse_tileset_stems():
    stems = []
    in_table = False
    for line in read("data/tilesets/tileset_headers.asm").splitlines():
        code = strip_comment(line)
        if code.startswith("Tilesets:"):
            in_table = True
            continue
        if in_table:
            m = re.match(r"\s*tileset\s+(\w+)", code)
            if m:
                stems.append(m.group(1))
            elif "assert_table_length" in code:
                break
    return stems


def parse_gfx_files():
    """label stem -> {'gfx': path, 'block': path}. Stacked labels share the
    next INCBIN; only the first INCBIN after a label run counts."""
    files = {}
    pending = []
    for line in read("gfx/tilesets.asm").splitlines():
        code = strip_comment(line)
        for label in re.findall(r"(\w+)_(GFX|Block)::", code):
            pending.append(label)
        m = re.search(r'INCBIN\s+"([^"]+)"', code)
        if m and pending:
            for stem, kind in pending:
                files.setdefault(stem, {})["gfx" if kind == "GFX" else "block"] = m.group(1)
            pending = []
    return files


def parse_labeled_db(text, start_label=None):
    """label -> list of bytes, for every label whose body is db rows. Stacked
    labels (two labels, one body) both get the body."""
    tables = {}
    pending = []
    current = []
    def flush():
        for lab in pending:
            tables[lab] = list(current)
    for line in text.splitlines():
        code = strip_comment(line).rstrip()
        m = re.match(r"^(\w+)::?", code)
        if m:
            if current:
                flush()
                pending, current = [], []
            pending.append(m.group(1))
            rest = code[m.end():]
            code = rest
        dm = re.match(r"\s*db\s+(.*)", code)
        if dm and pending:
            for tok in dm.group(1).split(","):
                if tok.strip():
                    current.append(tok.strip())
    if current:
        flush()
    return tables


def parse_pal_settings():
    text = read("data/gfx/overworld_tile_palettes.asm")
    pointers = []
    in_ptr = False
    for line in text.splitlines():
        code = strip_comment(line)
        if code.startswith("OverworldTilePalPointers"):
            in_ptr = True
            continue
        if in_ptr:
            m = re.match(r"\s*dw\s+(\w+)", code)
            if m:
                pointers.append(m.group(1))
            elif code.strip():
                break
    tables = {k: [parse_int(v) for v in vals]
              for k, vals in parse_labeled_db(text).items() if k.startswith("PalSettings_")}
    return pointers, tables


def gbc_word_from_macro(name, macros):
    return macros[name]


def parse_enhanced():
    text = read("custom_functions/func_enhancedcolor.asm")

    # GBCEnh_* colour macros: dw (b << 10 | g << 5 | r)
    macros = {}
    for m in re.finditer(r"MACRO\s+(GBCEnh_\w+)\s*\n\s*dw\s*\((\d+)\s*<<\s*10\s*\|\s*(\d+)\s*<<\s*5\s*\|\s*(\d+)\)", text):
        b, g, r = int(m.group(2)), int(m.group(3)), int(m.group(4))
        macros[m.group(1)] = [r, g, b]

    # Base set tables: label then 32 colours from RGB lines and GBCEnh_* macros.
    base_tables = {}
    current = None
    for line in text.splitlines():
        code = strip_comment(line).strip()
        m = re.match(r"^(GBCEnhancedOverworldPalettes\w*):", code)
        if m:
            current = m.group(1)
            base_tables[current] = []
            continue
        if current is None:
            continue
        if re.match(r"^\w+:", code) or code.startswith("MACRO"):
            current = None
            continue
        if code in macros:
            base_tables[current].append(macros[code])
            continue
        rm = re.match(r"RGB\s+(.*)", code)
        if rm:
            nums = [parse_int(x) for x in rm.group(1).replace(" ", "").split(",") if x]
            for i in range(0, len(nums), 3):
                base_tables[current].append(nums[i:i + 3])
        if len(base_tables.get(current, [])) >= 32:
            current = None

    # Per-register comment notes inside each base set (e.g. "spring trees ...").
    notes = {}
    current = None
    for line in text.splitlines():
        m = re.match(r"^(GBCEnhancedOverworldPalettes\w*):\s*;?(.*)", line)
        if m:
            current = m.group(1)
            notes[current] = {"_": m.group(2).strip()}
            continue
        if current:
            nm = re.match(r"\s*;\s*PAL_ENH_OVW_(\w+)\s*;\s*\$(\w+)\s*(?:-\s*(.*))?", line)
            if nm and nm.group(3):
                notes[current][int(nm.group(2), 16)] = nm.group(3).strip()
            if re.match(r"^\w+:", line) and not line.startswith(current):
                current = None

    # EnhBasePalSetPointers order + ENH_BASE_* names.
    ptr_block = re.search(r"EnhBasePalSetPointers:\n(.*?)EnhBasePalSetPointers_End:", text, re.S).group(1)
    base_sets = []
    for m in re.finditer(r"dw\s+(\w+)\s*;\s*(ENH_BASE_\w+)", ptr_block):
        label, name = m.group(1), m.group(2)
        cols = base_tables.get(label)
        if not cols or len(cols) != 32:
            sys.exit(f"base set {label}: expected 32 colours, parsed {len(cols or [])}")
        base_sets.append({
            "id": name, "label": label,
            "colors": [cols[i * 4:(i + 1) * 4] for i in range(8)],
            "uses": BASE_SET_USES.get(name, ""),
            "notes": {str(k): v for k, v in notes.get(label, {}).items() if k != "_"},
        })

    # TownSpecialPal: register per town, in map-ID order.
    towns = []
    tm = re.search(r"PalSettings_TownSpecialPal:\n(.*?)\n\s*\n", text, re.S)
    for m in re.finditer(r"db\s+PAL_ENH_OVW_(\w+)\s*;\s*(\w+)", tm.group(1)):
        towns.append({"name": m.group(2).replace("_", " ").title(), "reg": REGISTER_NAMES.index(m.group(1))})
    return base_sets, towns


def decode_2bpp(data):
    tiles = []
    for t in range(len(data) // 16):
        px = []
        for row in range(8):
            lo, hi = data[t * 16 + row * 2], data[t * 16 + row * 2 + 1]
            for bit in range(7, -1, -1):
                px.append(((lo >> bit) & 1) | (((hi >> bit) & 1) << 1))
        tiles.append("".join(str(p) for p in px))
    return tiles


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(ROOT / "tools" / "palette_preview.html"))
    args = ap.parse_args()

    ids = parse_tileset_ids()
    stems = parse_tileset_stems()
    gfx = parse_gfx_files()
    pointers, pal_tables = parse_pal_settings()
    base_sets, towns = parse_enhanced()

    if len(ids) != len(stems) or len(ids) != len(pointers):
        sys.exit(f"table length mismatch: {len(ids)} ids, {len(stems)} headers, {len(pointers)} PalSettings pointers")

    tilesets = []
    for idx, (tid, stem, ptr) in enumerate(zip(ids, stems, pointers)):
        files = gfx.get(stem, {})
        gpath, bpath = ROOT / files.get("gfx", ""), ROOT / files.get("block", "")
        if not files.get("gfx") or not gpath.is_file():
            sys.exit(f"{tid}: missing {files.get('gfx')} - run make first")
        blocks = list(bpath.read_bytes()) if files.get("block") and bpath.is_file() else []
        tilesets.append({
            "index": idx, "id": tid, "stem": stem, "table": ptr,
            "shared": [t for t, p in zip(ids, pointers) if p == ptr and t != tid],
            "pal": pal_tables[ptr],
            "tiles": decode_2bpp(gpath.read_bytes()),
            "blocks": [blocks[i:i + 16] for i in range(0, len(blocks) - 15, 16)],
            "suggested": SUGGESTED.get(tid),
        })

    data = {"registers": REGISTER_NAMES, "baseSets": base_sets, "towns": towns, "tilesets": tilesets}
    template = (Path(__file__).with_name("palette_preview_template.html")).read_text(encoding="utf-8")
    html = template.replace("/*__DATA__*/null", json.dumps(data, separators=(",", ":")))
    Path(args.out).write_text(html, encoding="utf-8", newline="\n")
    print(f"wrote {args.out}: {len(tilesets)} tilesets, {len(base_sets)} base sets")


if __name__ == "__main__":
    main()
