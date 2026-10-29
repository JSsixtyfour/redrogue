"""Where a new song can go: the largest contiguous free ROMX gap.

Crystal audio engine (crysaudio/, 2026-10-28): the Music table
(crysaudio/music_pointers_red.asm) stores every song as a 3-byte `dba`
(bank, address) row indexed by its MUSIC_* id, so a song can live in any ROMX
bank. A song still has to sit in ONE bank: its channels' sound_call /
sound_loop / sound_jump targets are same-bank addresses (GetMusicByte only
switches to the channel's own bank). The kit preview and each imported song
therefore get a floating ROMX section of their own, and what fits is the
largest single EMPTY span, not the sum of free bytes.

Song ids are one byte (HOME PlayMusic takes the id in a; 0 stops the music)
and the table must match NUM_MUSIC_SONGS. $FF is kept free (older code used it
as a "no song" sentinel), so the highest id is $FE and the id room is
MAX_SONG_ID + 1 - NUM_MUSIC_SONGS.
"""

import re

MAX_SONG_ID = 0xFE


def rom_gaps(mapfile):
    """[(size, bank, start)] of every EMPTY span in ROMX, largest first."""
    gaps, bank = [], None
    with open(mapfile) as f:
        for line in f:
            m = re.match(r"^(\w+) bank #(\d+):", line)
            if m:
                bank = int(m.group(2)) if m.group(1) == "ROMX" else None
                continue
            if bank is None:
                continue
            m = re.match(r"^\s+EMPTY: \$([0-9a-f]{4})-\$([0-9a-f]{4})", line)
            if m:
                start, end = int(m.group(1), 16), int(m.group(2), 16)
                gaps.append((end - start + 1, bank, start))
    if not gaps:
        raise SystemExit("no ROMX EMPTY spans in %s (not an rgblink map?)" % mapfile)
    return sorted(gaps, reverse=True)


def song_count(constants_path):
    """NUM_MUSIC_SONGS: the MUSIC_* consts after `const_def 1` (row 0 is Music_Nothing)."""
    text = open(constants_path).read()
    block = text[:text.index("DEF NUM_MUSIC_SONGS")]
    block = block[block.index("const_def 1"):]
    return len(re.findall(r"^\s*const\s+MUSIC_\w+", block, re.MULTILINE)) + 1


def merged(mapfiles):
    """Worst case across several ROMs' maps: {"largest": bytes, "bank": n, "free": total}.

    The three variants place floating sections independently, so a song must fit
    the smallest of their largest gaps."""
    out = None
    for path in mapfiles:
        gaps = rom_gaps(path)
        size, bank, _ = gaps[0]
        this = {"largest": size, "bank": bank, "free": sum(g[0] for g in gaps)}
        if out is None or this["largest"] < out["largest"]:
            out = dict(this, free=min(this["free"], out["free"]) if out else this["free"])
        else:
            out["free"] = min(out["free"], this["free"])
    return out


def song_budget(info):
    """Largest song (bytes, header included) that can still be imported."""
    return info["largest"]
