"""Import a composer's finished song into the game as a new song.

    make import_music MID=path/to/song.mid NAME=SongName
    make import_music ASM=path/to/song.asm NAME=SongName     (native Crystal format)

Uses the same convert.ps1 the kit runs (only the label differs), so the
imported song is what he heard. Then:
  1. measures the song's exact size by assembling it alone
  2. checks it against the largest free ROMX gap and the song-id room
     (audio_banks.py): the Crystal engine stores each song in a section of its
     own, which may land in any ROMX bank, so no bank is chosen here
  3. adds crysaudio/music/imported/<name>.asm, its own SECTION at the end of
     audio.asm, a `const MUSIC_<NAME>` and a `dba Music_<Name>` Music table row
  4. builds all three ROMs; on failure restores every file it touched
It doesn't make the song play anywhere: callers use HOME PlayMusic with
a = MUSIC_<NAME> (no bank argument; the Music table row carries the bank).

Runs under WSL (needs powershell.exe interop and the repo's rgbds).
"""

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import audio_banks  # noqa: E402
import make_music_kit  # noqa: E402

MAPS = ("pokered.map", "pokeblue.map", "pokeblue_debug.map")
CONSTANTS = "constants/music_constants.asm"
POINTERS = "crysaudio/music_pointers_red.asm"
IMPORT_DIR = "crysaudio/music/imported"


def die(msg):
    sys.exit("import_music: " + msg)


def snake(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", "_", name).upper()


def song_size(asm_path):
    """Exact bytes of the converted song, assembled on its own in a section of its own."""
    with tempfile.TemporaryDirectory() as tmp:
        wrapper = os.path.join(tmp, "probe.asm")
        with open(wrapper, "w") as f:
            # macros and audio constants come from audio.asm, not includes.asm
            f.write('INCLUDE "crysaudio/macros.asm"\nINCLUDE "crysaudio/audio_constants.asm"\n'
                    'SECTION "Import Probe", ROMX\nINCLUDE "%s"\n' % asm_path)
        obj, mapf = os.path.join(tmp, "probe.o"), os.path.join(tmp, "probe.map")
        flags, _ = make_music_kit.make_flags()
        p = subprocess.run(["rgbasm", *flags["asm"], "-o", obj, wrapper], cwd=REPO, text=True, capture_output=True)
        if p.returncode:
            die("the converted song doesn't assemble:\n" + p.stdout + p.stderr)
        p = subprocess.run(["rgblink", "-m", mapf, "-o", os.devnull, obj], cwd=REPO, text=True, capture_output=True)
        if p.returncode:
            die("the converted song doesn't link on its own:\n" + p.stdout + p.stderr)
        m = re.search(r'\(\$([0-9a-f]+) bytes\) \["Import Probe"\]', open(mapf).read())
        if not m:
            die("couldn't read the probe section size")
        return int(m.group(1), 16)


def section_placement(mapfile, name):
    """(bank, size) of a ROMX section by name, read from an rgblink map."""
    bank = None
    for line in open(mapfile):
        m = re.match(r"^(\w+) bank #(\d+):", line)
        if m:
            bank = int(m.group(2)) if m.group(1) == "ROMX" else None
            continue
        m = re.match(r'^\s+SECTION: \$[0-9a-f]{4}-\$[0-9a-f]{4} \(\$([0-9a-f]+) bytes\) \["%s"\]' % re.escape(name), line)
        if m and bank is not None:
            return bank, int(m.group(1), 16)
    return None


def insert_before(text, anchor, line, what):
    """Insert `line` on its own line right before the (single) line `anchor`."""
    lines = text.split("\n")
    hits = [i for i, l in enumerate(lines) if l.strip() == anchor]
    if len(hits) != 1:
        die("expected exactly one %r in %s, found %d" % (anchor, what, len(hits)))
    lines.insert(hits[0], line)
    return "\n".join(lines)


def main():
    if len(sys.argv) != 3 or not sys.argv[1]:
        die("usage: make import_music MID=song.mid NAME=SongName   or   ASM=song.asm NAME=SongName")
    src, name = os.path.abspath(sys.argv[1]), sys.argv[2]
    if not os.path.isfile(src):
        die("no such file: %s" % src)
    ext = os.path.splitext(src)[1].lower()
    if ext not in (".mid", ".midi", ".asm"):
        die("expected a .mid or .asm file, got %s" % src)
    if not re.match(r"^[A-Z][A-Za-z0-9]+$", name):
        die("NAME must be CamelCase letters/digits, e.g. NAME=ForestTheme")
    label, const, lower = "Music_" + name, "MUSIC_" + snake(name), name.lower()
    song_rel = "%s/%s.asm" % (IMPORT_DIR, lower)
    os.chdir(REPO)
    if os.path.exists(song_rel):
        die("%s already exists" % song_rel)
    consts_text, table_text, audio_text = (open(p).read() for p in (CONSTANTS, POINTERS, "audio.asm"))
    for text, path, needle in ((consts_text, CONSTANTS, "const " + const), (consts_text, CONSTANTS, label),
                               (table_text, POINTERS, label), (audio_text, "audio.asm", song_rel)):
        if re.search(re.escape(needle) + r"\b", text):
            die("%s already mentions %s" % (path, needle))

    # A converted file made for another engine would assemble and sound wrong.
    if ext == ".asm":
        m = re.search(r"^;\s*kit-engine:\s*(.+?)\s*$", open(src).read(), re.MULTILINE)
        if m and m.group(1) != make_music_kit.ENGINE_ID:
            die("%s was converted for the engine %r, but this tree is %r. Convert the original again."
                % (src, m.group(1), make_music_kit.ENGINE_ID))

    # 1. convert with the kit's converter
    pokemid = make_music_kit.find_file(make_music_kit.unpack("pokemid"), "pokemid.exe") if ext != ".asm" else None
    tmp_asm = os.path.join(HERE, "output", "import_%s.asm" % lower)
    os.makedirs(os.path.dirname(tmp_asm), exist_ok=True)
    cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
           make_music_kit.winpath(os.path.join(HERE, "convert.ps1")), make_music_kit.winpath(src),
           "-NoBuild", "-Label", label, "-OutAsm", make_music_kit.winpath(tmp_asm),
           "-EngineId", make_music_kit.ENGINE_ID]
    if pokemid:
        cmd += ["-Pokemid", make_music_kit.winpath(pokemid)]
    p = subprocess.run(cmd, text=True, capture_output=True)
    print(p.stdout, end="")
    if p.returncode:
        die("conversion failed:\n" + p.stderr)
    size = song_size(tmp_asm)

    # 2. does it fit
    maps = [m for m in MAPS if os.path.exists(m)]
    if len(maps) != len(MAPS):
        die("need all three maps (make red blue blue_debug): missing %s" % [m for m in MAPS if m not in maps])
    space = audio_banks.merged(maps)
    budget = audio_banks.song_budget(space)
    first_id = audio_banks.song_count(CONSTANTS)
    room = audio_banks.MAX_SONG_ID + 1 - first_id
    print("import_music: %s is %d bytes; largest free ROMX gap %d bytes (bank $%02X), %d free in all; %d song ids left"
          % (label, size, space["largest"], space["bank"], space["free"], room))
    if room <= 0:
        die("no song ids left (highest is $%02X)" % audio_banks.MAX_SONG_ID)
    if size > budget:
        die("%d bytes is more than the largest free ROMX gap (%d). Shorten the song, or see ROM_BIBLE.md before making room."
            % (size, budget))

    # 3. edit, remembering originals
    section = "Song " + name
    touched = {"audio.asm": audio_text, CONSTANTS: consts_text, POINTERS: table_text}
    made_dir = not os.path.isdir(IMPORT_DIR)
    try:
        os.makedirs(IMPORT_DIR, exist_ok=True)
        with open(song_rel, "w", newline="\n") as f:
            f.write(open(tmp_asm).read())
        new_audio = audio_text.rstrip("\n") + '\n\nSECTION "%s", ROMX\n\nINCLUDE "%s"\n' % (section, song_rel)
        new_consts = insert_before(consts_text, "DEF NUM_MUSIC_SONGS EQU const_value",
                                   "\tconst %s ; imported: %s" % (const, os.path.basename(src)), CONSTANTS)
        new_table = insert_before(table_text, "assert_table_length NUM_MUSIC_SONGS", "\tdba %s" % label, POINTERS)
        for path, text in (("audio.asm", new_audio), (CONSTANTS, new_consts), (POINTERS, new_table)):
            with open(path, "w", newline="\n") as f:
                f.write(text)

        # 4. build everything
        print("import_music: building all ROMs")
        p = subprocess.run(["make", "pokered.gbc", "pokeblue.gbc", "pokeblue_debug.gbc"], text=True, capture_output=True)
        if p.returncode:
            raise RuntimeError(p.stdout[-3000:] + p.stderr[-3000:])
    except BaseException as e:
        for path, text in touched.items():
            with open(path, "w", newline="\n") as f:
                f.write(text)
        if os.path.exists(song_rel):
            os.remove(song_rel)
        if made_dir and os.path.isdir(IMPORT_DIR) and not os.listdir(IMPORT_DIR):
            os.rmdir(IMPORT_DIR)
        die("build failed, all edits reverted:\n%s" % e)

    after = audio_banks.merged(maps)
    print("import_music: done. %s is song id %d ($%02X)." % (const, first_id, first_id))
    for rom_map in maps:
        placed = section_placement(rom_map, section)
        print("  %-22s %s" % (rom_map, "bank $%02X, %d bytes" % placed if placed else "section not found in the map"))
    print("  largest free ROMX gap now %d bytes, %d song ids left." % (after["largest"], room - 1))
    print("  files: %s, audio.asm, %s, %s" % (song_rel, CONSTANTS, POINTERS))
    print("  to play it: ld a, %s / call PlayMusic   (HOME; no bank argument, the Music table row carries it)" % const)
    placements = {m: section_placement(m, section) for m in maps}
    banks = ", ".join("%s $%02X" % (m.replace(".map", ""), p[0]) for m, p in placements.items() if p)
    print("  ROM_BIBLE.md entry (K: isn't visible from WSL, paste it): %s imported, %d bytes in its own section "
          "\"%s\" (%s); largest ROMX gap %d -> %d." % (label, size, section, banks, space["largest"], after["largest"]))
    print("  next: make smoke TEST=crysaudio")


if __name__ == "__main__":
    main()
