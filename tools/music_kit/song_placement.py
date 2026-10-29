"""Pin an imported song where it cannot move anything else (ROM_BIBLE 2026-10-29).

A floating song section makes rgblink re-pack every other floating section: the first
four Crystal imports moved 187 code/text labels to other banks. A section pinned in
layout.link at the END of a bank whose contents are all pinned already, into the empty
space after them, changes no other placement: nothing floating lives in that bank, and
floating sections that went elsewhere did so with that space available, so shrinking it
changes none of their decisions. `unchanged_except` proves it after the build.

A bank qualifies when, in every one of the three maps:
  - every non-empty section in it is listed under that bank in layout.link (no floating
    neighbours), and
  - the bank ends in one EMPTY span that starts right where the last listed section ends
    (so appending to the list lands exactly there).
"""

import re

ROM_END = 0x8000


def parse_layout(text):
    """{bank: (header_line_index, [section names in order], last_listed_line_index)}."""
    lines = text.split("\n")
    out, bank = {}, None
    for i, line in enumerate(lines):
        m = re.match(r"^(ROM0|ROMX|WRAM0|WRAMX|VRAM|SRAM|HRAM)\b\s*(\$[0-9A-Fa-f]+)?", line)
        if m:
            bank = int(m.group(2)[1:], 16) if m.group(1) == "ROMX" and m.group(2) else None
            if bank is not None:
                out[bank] = (i, [], i)
            continue
        if bank is None:
            continue
        m = re.match(r'^\s*"([^"]+)"', line)
        if m:
            head, names, _ = out[bank]
            names.append(m.group(1))
            out[bank] = (head, names, i)
    return out


def map_sections(mapfile):
    """{bank: {"sections": [(start, end_excl, name)], "empty": [(start, end_excl)]}} for ROMX."""
    out, bank = {}, None
    for line in open(mapfile):
        m = re.match(r"^(\w+) bank #(\d+):", line)
        if m:
            bank = int(m.group(2)) if m.group(1) == "ROMX" else None
            if bank is not None:
                out[bank] = {"sections": [], "empty": []}
            continue
        if bank is None:
            continue
        m = re.match(r'^\s+SECTION: \$([0-9a-f]{4})(?:-\$([0-9a-f]{4}))? \(\$([0-9a-f]+) bytes\) \["([^"]+)"\]', line)
        if m:
            start, size = int(m.group(1), 16), int(m.group(3), 16)
            out[bank]["sections"].append((start, start + size, m.group(4)))
            continue
        m = re.match(r"^\s+EMPTY: \$([0-9a-f]{4})-\$([0-9a-f]{4})", line)
        if m:
            out[bank]["empty"].append((int(m.group(1), 16), int(m.group(2), 16) + 1))
    return out


def pin_candidates(layout_text, mapfiles):
    """{bank: trailing free bytes (worst of the maps)} for every bank a song can be pinned in."""
    layout = parse_layout(layout_text)
    maps = [map_sections(m) for m in mapfiles]
    out = {}
    for bank, (_, listed, _) in layout.items():
        if not listed:
            continue
        free = None
        for mp in maps:
            info = mp.get(bank)
            if not info:
                free = None
                break
            secs = [s for s in info["sections"] if s[1] > s[0]]
            if any(name not in listed for _, _, name in secs):
                free = None  # a floating neighbour: pinning here could push it out
                break
            ends = {name: end for _, end, name in info["sections"]}
            last_end = ends.get(listed[-1])
            tail = [e for e in info["empty"] if e[1] == ROM_END]
            if last_end is None or not tail or tail[0][0] != last_end or max(e for _, e, _ in secs) != last_end:
                free = None
                break
            gap = ROM_END - last_end
            free = gap if free is None else min(free, gap)
        if free:
            out[bank] = free
    return out


RESERVE = 512  # bytes left free after the song, so the bank's own sections can still grow


def choose_bank(candidates, size, reserve=RESERVE):
    """Best fit with headroom: the smallest qualifying gap that holds `size` and still
    leaves `reserve` bytes, so big gaps stay available for big songs. Falls back to the
    largest gap that holds the song at all. None if nothing fits."""
    roomy = [(free, bank) for bank, free in candidates.items() if free - size >= reserve]
    if roomy:
        return min(roomy)[1]
    fits = [(free, bank) for bank, free in candidates.items() if free >= size]
    return max(fits)[1] if fits else None


def pin(layout_text, bank, section):
    """layout.link text with `section` appended to `bank`'s list."""
    layout = parse_layout(layout_text)
    if bank not in layout:
        raise ValueError("no ROMX $%X in layout.link" % bank)
    lines = layout_text.split("\n")
    _, _, last = layout[bank]
    lines.insert(last + 1, '\t"%s" ; imported song, pinned by tools/music_kit/song_placement.py' % section)
    return "\n".join(lines)


def placements(mapfile):
    """{section name: (bank, start)} for every non-empty ROMX section."""
    return {name: (bank, start) for bank, info in map_sections(mapfile).items()
            for start, end, name in info["sections"] if end > start}


def unchanged_except(before, after, new_sections):
    """[(section, before, after)] for every section that moved, ignoring `new_sections`."""
    moved = []
    for name, where in before.items():
        if name in new_sections:
            continue
        if after.get(name) != where:
            moved.append((name, where, after.get(name)))
    return moved
