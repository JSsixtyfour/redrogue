#!/usr/bin/env python3
"""Build the Textbox Writer page: prose in, width-checked `text`/`line`/`cont`/
`para` macros out, with a preview drawn in the game's own font.

Reads from source, so it tracks the tree:
  - constants/charmap.asm         which characters exist (rgbasm matches the
                                  LONGEST charmap entry, so "'s" is one tile)
  - gfx/font/font.1bpp            glyphs $80-$FF
  - gfx/font/font_extra.2bpp      glyphs $60-$7F (box borders, quotes, ellipsis)

    python tools/textbox_writer.py [--out PATH]
"""

import argparse
import base64
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Control characters that print something. Width is the WORST case the
# assembler cannot see: names are capped by the naming screen.
EXPANSIONS = {
    "<PLAYER>":  {"width": 7, "sample": "RED", "note": "player name, up to 7"},
    "<RIVAL>":   {"width": 7, "sample": "BLUE", "note": "rival name, up to 7"},
    "#":         {"width": 4, "sample": "POKé", "note": "prints POKé"},
    "<PKMN>":    {"width": 2, "sample": "<PK><MN>", "note": "PK MN glyphs"},
    "<PC>":      {"width": 2, "sample": "PC"},
    "<TM>":      {"width": 2, "sample": "TM"},
    "<TRAINER>": {"width": 7, "sample": "TRAINER"},
    "<ROCKET>":  {"width": 6, "sample": "ROCKET"},
    "<……>": {"width": 2, "sample": "……"},
    "<TARGET>":  {"width": 16, "sample": "Enemy PIKACHU", "note": "battle only: \"Enemy \" + a 10-char name"},
    "<USER>":    {"width": 16, "sample": "Enemy PIKACHU", "note": "battle only: \"Enemy \" + a 10-char name"},
}

# Characters that are never body text even though charmap names them.
NOT_TEXT = {"@", "<NULL>", "<PAGE>", "<_CONT>", "<SCROLL>", "<NEXT>", "<LINE>", "<PARA>",
            "<CONT>", "<DONE>", "<PROMPT>", "<DEXEND>"}


def parse_charmap():
    out = {}
    for line in (ROOT / "constants/charmap.asm").read_text(encoding="utf-8").splitlines():
        if "Japanese kana" in line:
            break  # the kana block reuses English tile IDs
        m = re.match(r'\s*charmap\s+"(.+?)",\s*\$([0-9a-fA-F]+)', line)
        if m and m.group(1) not in NOT_TEXT:
            out.setdefault(m.group(1), int(m.group(2), 16))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(ROOT / "tools" / "textbox_writer.html"))
    args = ap.parse_args()

    font = (ROOT / "gfx/font/font.1bpp").read_bytes()
    extra = (ROOT / "gfx/font/font_extra.2bpp").read_bytes()
    data = {
        "charmap": parse_charmap(),
        "expansions": EXPANSIONS,
        "font1bpp": base64.b64encode(font).decode(),      # tiles $80-$FF
        "extra2bpp": base64.b64encode(extra).decode(),    # tiles $60-$7F
    }
    template = Path(__file__).with_name("textbox_writer_template.html").read_text(encoding="utf-8")
    html = template.replace("/*__DATA__*/null", json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    Path(args.out).write_text(html, encoding="utf-8", newline="\n")
    print(f"wrote {args.out}: {len(data['charmap'])} charmap entries")


if __name__ == "__main__":
    main()
