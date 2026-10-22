"""Where a new song can go: audio banks, their free bytes, and song-id room.

A song's id is computed from its header's address: (header - SFX_Headers_1) / 3
(constants/music_constants.asm), and every audio bank's headers start at the
same $4000. PlaySound treats $FF as SFX_STOP_ALL_MUSIC, so a new header must
START at or below $4000 + $FE * 3 = $42FA. Banks $02/$08/$1F already end their
"Music Headers N" at $42FC (measured 2026-10-21): free bytes there are
unusable for new songs. Only banks with id room count.
"""

import re

HEADER_BYTES = 12            # 4 channels x (dn + dw)
LAST_HEADER_START = 0x4000 + 0xFE * 3


def audio_banks(mapfile):
    """{bank: {"n": N, "free": bytes, "next_header": addr, "id_room": songs}}"""
    banks, bank, cur = {}, None, None
    with open(mapfile) as f:
        for line in f:
            m = re.match(r"^ROMX bank #(\d+):", line)
            if m:
                bank, cur = int(m.group(1)), None
                continue
            if bank is None:
                continue
            m = re.search(r'SECTION: \$([0-9a-f]{4})-\$([0-9a-f]{4}) \(\$[0-9a-f]+ bytes\) \["Music Headers (\d+)"\]', line)
            if m:
                nxt = int(m.group(2), 16) + 1
                cur = {"n": int(m.group(3)), "next_header": nxt,
                       "id_room": max(0, (LAST_HEADER_START - nxt) // HEADER_BYTES + 1)}
                banks[bank] = cur
            m = re.match(r"^\s+TOTAL EMPTY: \$([0-9a-f]+) bytes", line)
            if m:
                if cur is not None:
                    cur["free"] = int(m.group(1), 16)
                bank, cur = None, None
    if len(banks) < 4 or any("free" not in b for b in banks.values()):
        raise SystemExit("expected 4 audio banks with free space in %s, found %s" % (mapfile, banks))
    return banks


def merged(mapfiles):
    """Worst case across several ROMs' maps (free and id room can differ)."""
    out = None
    for path in mapfiles:
        b = audio_banks(path)
        if out is None:
            out = b
            continue
        for k, v in b.items():
            out[k]["free"] = min(out[k]["free"], v["free"])
            out[k]["id_room"] = min(out[k]["id_room"], v["id_room"])
    return out


def song_budget(banks):
    """Largest song (bytes of song data) that some bank can still take."""
    usable = [b["free"] - HEADER_BYTES for b in banks.values() if b["id_room"] > 0]
    return max(usable) if usable else 0
