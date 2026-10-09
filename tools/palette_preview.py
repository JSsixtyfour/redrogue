#!/usr/bin/env python3
"""Render Enhanced Colors (CGB) overworld palettes as a browsable HTML page.

Reads straight from source, so the page always matches the tree:
  - constants/tileset_constants.asm        tileset IDs
  - data/tilesets/tileset_headers.asm      tileset ID -> gfx/block label stem
  - gfx/tilesets.asm                       label stem -> .2bpp / .bst files
  - data/gfx/overworld_tile_palettes.asm   PalSettings_* (tile -> register)
  - custom_functions/func_enhancedcolor.asm base sets (register -> 4 colours),
                                            EnhBasePalSetPointers, TownSpecialPal
  - data/gfx/cgb_palettes.asm              the overworld PAL_* rows the game uses
                                            when Enhanced Colors is OFF (one
                                            palette for the whole map)

Needs the built .2bpp files (run `make` first). No third-party modules.

    python tools/palette_preview.py [--out PATH]

Colours are the raw source values, which is what the game sends with the
ENH GAMMA option off (the default). With it on, GBCGamma
(custom_functions/func_gamma.asm) makes them lighter and much less saturated.
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
    "ENH_BASE_DEFAULT": "Every map without an override. Procedural Cave variant 0, Procedural Forest variant 2, Procedural Facility variant 0 (PowerPlant).",
    "ENH_BASE_COLD": "Seafoam Islands. Procedural Cave variant 1 (cold).",
    "ENH_BASE_DARK": "Only through wMapPalOffset == 6, which nothing in Red Rogue writes. Cut as a cave variant.",
    "ENH_BASE_FOREST_SPRING": "Procedural Forest variant 0 (spring).",
    "ENH_BASE_FOREST_FALL": "Procedural Forest variant 1 (fall).",
    "ENH_BASE_FACILITY_RED": "Procedural Facility variant 1 (Mansion), and Pokemon Mansion 1F-3F, B1F.",
}

# Regular-GBC overworld palettes (Enhanced Colors off): what GetOverworldPalette
# (engine/gfx/palettes.asm) can return for a map. Each is one 4-colour row of
# data/gfx/cgb_palettes.asm, applied to the whole screen. Listed in menu order;
# the name is matched against the row's leading comment, aliases included.
REGULAR_PAL_USES = {
    "PAL_FOREST_SPRING": "Procedural Forest variant 0 (spring), Enhanced Colors off. Paired with the PAL_25 row of data/sgb/sgb_palettes.asm.",
    "PAL_FOREST_FALL": "Procedural Forest variant 1 (fall), Enhanced Colors off. Paired with the PAL_27 row of data/sgb/sgb_palettes.asm.",
    "PAL_VIRIDIAN": "Viridian City and what is inside it. Also Procedural Forest variant 2 (default green) and the forest's fallback for a bad save byte.",
    "PAL_ROUTE": "Every route, and Procedural Facility variant 0 (PowerPlant).",
    "PAL_CAVE": "CAVERN-tileset caves without an override, Cerulean Cave, Bruno, Procedural Cave variant 0.",
    "PAL_CAVE_COLD": "Procedural Cave variant 1 (cold). Paired with the PAL_0F row of data/sgb/sgb_palettes.asm.",
    "PAL_GRAYMON": "CEMETERY tileset: Pokemon Tower, Agatha, the procedural cemeteries.",
    "PAL_PALLET": "Pallet Town and what is inside it, Lorelei.",
    "PAL_PEWTER": "Pewter City and what is inside it.",
    "PAL_CERULEAN": "Cerulean City and what is inside it.",
    "PAL_LAVENDER": "Lavender Town and what is inside it.",
    "PAL_VERMILION": "Vermilion City and what is inside it.",
    "PAL_CELADON": "Celadon City and what is inside it.",
    "PAL_FUCHSIA": "Fuchsia City and what is inside it.",
    "PAL_CINNABAR": "Cinnabar Island and what is inside it, and Procedural Facility variant 1 (Mansion).",
    "PAL_INDIGO": "Indigo Plateau and what is inside it.",
    "PAL_SAFFRON": "Saffron City and what is inside it, and the Silph Co hub maps.",
}

# What parse_regular treats as defined: a pokeblue build (see the Makefile;
# _YSPRITES, _GREEN and _JPLOGO are never defined).
BUILD_DEFINES = {"_BLUE"}
# cgb_palettes.asm keeps shinpokered's spelling in one comment.
SPELLING = {"PAL_GREYMON": "PAL_GRAYMON"}

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
    return base_sets, towns, macros


def parse_regular():
    """The REGULAR_PAL_USES rows of CGBPalettes, 4 colours each. A row's name
    comes from its leading `; PAL_X` or `; PAL_25 / PAL_FOREST_SPRING` comment;
    only rows named in REGULAR_PAL_USES are kept, so the _RED/_BLUE branches
    some non-overworld rows carry never matter."""
    rows = {}
    names, cols, started = None, [], False
    # IF/ELIF/ELSE/ENDC frames [live, taken]; only what a Blue build assembles
    # counts. Conditions here are DEF(...) terms joined by && (checked below).
    frames = []
    live = lambda: all(f[0] for f in frames)
    def cond(expr):
        if re.sub(r"DEF\(\w+\)|&&|[()\s]", "", expr):
            sys.exit(f"cgb_palettes.asm: cannot evaluate IF {expr!r}")
        return all(d in BUILD_DEFINES for d in re.findall(r"DEF\((\w+)\)", expr))
    for line in read("data/gfx/cgb_palettes.asm").splitlines():
        if line.startswith("CGBPalettes:"):
            started = True
            continue
        if not started:
            continue
        code = strip_comment(line).strip()
        im = re.match(r"(IF|ELIF)\s+(.*)", code)
        if im and im.group(1) == "IF":
            c = cond(im.group(2))
            frames.append([c, c])
            continue
        if im:
            f = frames[-1]
            f[0] = not f[1] and cond(im.group(2))
            f[1] = f[1] or f[0]
            continue
        if code == "ELSE":
            f = frames[-1]
            f[0], f[1] = not f[1], True
            continue
        if code == "ENDC":
            frames.pop()
            continue
        if not live():
            continue
        cm = re.match(r"\s*;\s*(PAL_\w+(?:\s*,?\s*/?\s*PAL_\w+)*)", line)
        if cm and not strip_comment(line).strip():
            names, cols = re.findall(r"PAL_\w+", cm.group(1)), []
            continue
        rm = re.match(r"\s*RGB\s+(.*)", strip_comment(line))
        if rm and names is not None and len(cols) < 4:
            nums = [parse_int(x) for x in rm.group(1).replace(" ", "").split(",") if x]
            cols += [nums[i:i + 3] for i in range(0, len(nums), 3)]
            if len(cols) == 4:
                for n in names:
                    rows[SPELLING.get(n, n)] = cols
    out = []
    for name, uses in REGULAR_PAL_USES.items():
        if name not in rows:
            sys.exit(f"cgb_palettes.asm: no 4-colour row named {name}")
        out.append({"id": name, "label": name, "kind": "cgb", "colors": [rows[name]],
                    "uses": uses, "notes": {}})
    return out


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
    base_sets, towns, macros = parse_enhanced()

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

    # macros lets the page's asm export write GBCEnh_White etc. back by name.
    data = {"registers": REGISTER_NAMES, "baseSets": base_sets, "regular": parse_regular(),
            "towns": towns, "tilesets": tilesets, "macros": macros}
    template = (Path(__file__).with_name("palette_preview_template.html")).read_text(encoding="utf-8")
    html = template.replace("/*__DATA__*/null", json.dumps(data, separators=(",", ":")))
    Path(args.out).write_text(html, encoding="utf-8", newline="\n")
    print(f"wrote {args.out}: {len(tilesets)} tilesets, {len(base_sets)} base sets, {len(data['regular'])} regular palettes")


if __name__ == "__main__":
    main()
