"""Import a composer's finished song into the game as a new song.

    make import_music MID=path/to/song.mid NAME=SongName
    make import_music ASM=path/to/song.asm NAME=SongName     (native Crystal format)
    make import_music ASM=a.asm,b.asm NAME=NameA,NameB        (two songs sharing phrases)

Uses the same convert.ps1 the kit runs (only the label differs), so the
imported song is what he heard. Then:
  1. measures the song's exact size by assembling it alone
  2. picks a bank with song_placement.py: the end of a bank holding only pinned
     sections, best fit with a 512 B reserve, and pins the section there in
     layout.link. A floating song section made rgblink re-pack other code (the
     first four imports moved 187 labels to other banks); a pinned one cannot
  3. adds crysaudio/music/imported/<name>.asm, its own SECTION at the end of
     audio.asm, a `const MUSIC_<NAME>` and a `dba Music_<Name>` Music table row
     per song (a pair shares one section, so its cross-song calls stay in-bank)
  4. builds all three ROMs and checks no other section changed bank or address
     (only the table's own bank may shift by the new rows); on any failure it
     restores every file it touched
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
import song_placement  # noqa: E402

MAPS = ("pokered.map", "pokeblue.map", "pokeblue_debug.map")
CONSTANTS = "constants/music_constants.asm"
POINTERS = "crysaudio/music_pointers_red.asm"
IMPORT_DIR = "crysaudio/music/imported"
LAYOUT = "layout.link"


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


def convert_one(src, label, partner=None, partner_label=None):
    """Run convert.ps1 -NoBuild on one song; return the converted text."""
    ext = os.path.splitext(src)[1].lower()
    lower = label[len("Music_"):].lower()
    tmp_asm = os.path.join(HERE, "output", "import_%s.asm" % lower)
    os.makedirs(os.path.dirname(tmp_asm), exist_ok=True)
    cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
           make_music_kit.winpath(os.path.join(HERE, "convert.ps1")), make_music_kit.winpath(src),
           "-NoBuild", "-NoBundle", "-Label", label, "-OutAsm", make_music_kit.winpath(tmp_asm),
           "-EngineId", make_music_kit.ENGINE_ID]
    if ext != ".asm":
        cmd += ["-Pokemid", make_music_kit.winpath(make_music_kit.find_file(make_music_kit.unpack("pokemid"), "pokemid.exe"))]
    if partner:
        cmd += ["-Partner", make_music_kit.winpath(partner), "-PartnerLabel", partner_label]
    p = subprocess.run(cmd, text=True, errors="replace", capture_output=True)
    print(p.stdout, end="")
    if p.returncode:
        die("conversion of %s failed:\n%s" % (src, p.stderr))
    return open(tmp_asm).read()


def main():
    if len(sys.argv) != 3 or not sys.argv[1]:
        die("usage: make import_music MID=song.mid NAME=SongName   or   ASM=song.asm NAME=SongName\n"
            "       two songs that share phrases: ASM=a.asm,b.asm NAME=NameA,NameB (one section)")
    srcs = [os.path.abspath(s) for s in sys.argv[1].split(",")]
    names = sys.argv[2].split(",")
    if len(srcs) != len(names) or not 1 <= len(srcs) <= 2:
        die("give one song, or two that share phrases, with one NAME each (comma-separated)")
    os.chdir(REPO)
    consts_text, table_text, audio_text, layout_text = (open(p).read() for p in (CONSTANTS, POINTERS, "audio.asm", LAYOUT))
    songs = []
    for src, name in zip(srcs, names):
        if not os.path.isfile(src):
            die("no such file: %s" % src)
        ext = os.path.splitext(src)[1].lower()
        if ext not in (".mid", ".midi", ".asm"):
            die("expected a .mid or .asm file, got %s" % src)
        if len(srcs) > 1 and ext != ".asm":
            die("only native .asm songs can share phrases; import MIDI songs one at a time")
        if not re.match(r"^[A-Z][A-Za-z0-9]+$", name):
            die("NAME must be CamelCase letters/digits, e.g. NAME=ForestTheme")
        label, const = "Music_" + name, "MUSIC_" + snake(name)
        for text, path, needle in ((consts_text, CONSTANTS, "const " + const), (consts_text, CONSTANTS, label),
                                   (table_text, POINTERS, label)):
            if re.search(re.escape(needle) + r"\b", text):
                die("%s already mentions %s" % (path, needle))
        # A converted file made for another engine would assemble and sound wrong.
        if ext == ".asm":
            m = re.search(r"^;\s*kit-engine:\s*(.+?)\s*$", open(src).read(), re.MULTILINE)
            if m and m.group(1) != make_music_kit.ENGINE_ID:
                die("%s was converted for the engine %r, but this tree is %r. Convert the original again."
                    % (src, m.group(1), make_music_kit.ENGINE_ID))
        songs.append({"src": src, "name": name, "label": label, "const": const})
    first = songs[0]["name"]
    song_rel = "%s/%s.asm" % (IMPORT_DIR, first.lower())
    section = "Song " + first
    if os.path.exists(song_rel) or ('"%s"' % section) in audio_text:
        die("%s or section %r already exists" % (song_rel, section))

    # 1. convert with the kit's converter; a pair converts each against the other
    parts = []
    for i, s in enumerate(songs):
        other = songs[1 - i] if len(songs) == 2 else None
        parts.append(convert_one(s["src"], s["label"], other and other["src"], other and other["label"]))
    text = "\n".join(p.rstrip("\n") + "\n" for p in parts)
    tmp_all = os.path.join(HERE, "output", "import_%s_all.asm" % first.lower())
    with open(tmp_all, "w", newline="\n") as f:
        f.write(text)
    size = song_size(tmp_all)

    # 2. where it goes: pinned at the end of a bank that holds only pinned sections
    maps = [m for m in MAPS if os.path.exists(m)]
    if len(maps) != len(MAPS):
        die("need all three maps (make red blue blue_debug): missing %s" % [m for m in MAPS if m not in maps])
    first_id = audio_banks.song_count(CONSTANTS)
    room = audio_banks.MAX_SONG_ID + 1 - first_id
    if room < len(songs):
        die("no song ids left (highest is $%02X)" % audio_banks.MAX_SONG_ID)
    candidates = song_placement.pin_candidates(layout_text, maps)
    bank = song_placement.choose_bank(candidates, size)
    if bank is None:
        die("%d bytes: no bank has that much free space after its pinned sections (largest %d). Shorten the song, "
            "or see ROM_BIBLE.md before making room." % (size, max(candidates.values() or [0])))
    print("import_music: %s is %d bytes -> pinned in bank $%02X (%d free there, %d left after); %d song ids left"
          % (" + ".join(s["label"] for s in songs), size, bank, candidates[bank], candidates[bank] - size, room))
    before = {m: song_placement.placements(m) for m in maps}

    # 3. edit, remembering originals
    touched = {"audio.asm": audio_text, CONSTANTS: consts_text, POINTERS: table_text, LAYOUT: layout_text}
    made_dir = not os.path.isdir(IMPORT_DIR)
    try:
        os.makedirs(IMPORT_DIR, exist_ok=True)
        with open(song_rel, "w", newline="\n") as f:
            f.write(text)
        new_audio = audio_text.rstrip("\n") + '\n\nSECTION "%s", ROMX\n\nINCLUDE "%s"\n' % (section, song_rel)
        new_consts, new_table = consts_text, table_text
        for s in songs:
            new_consts = insert_before(new_consts, "DEF NUM_MUSIC_SONGS EQU const_value",
                                       "\tconst %s ; imported: %s" % (s["const"], os.path.basename(s["src"])), CONSTANTS)
            new_table = insert_before(new_table, "assert_table_length NUM_MUSIC_SONGS", "\tdba %s" % s["label"], POINTERS)
        new_layout = song_placement.pin(layout_text, bank, section)
        for path, new in (("audio.asm", new_audio), (CONSTANTS, new_consts), (POINTERS, new_table), (LAYOUT, new_layout)):
            with open(path, "w", newline="\n") as f:
                f.write(new)

        # 4. build everything, then prove nothing else moved
        print("import_music: building all ROMs")
        p = subprocess.run(["make", "pokered.gbc", "pokeblue.gbc", "pokeblue_debug.gbc"], text=True, capture_output=True)
        if p.returncode:
            raise RuntimeError(p.stdout[-3000:] + p.stderr[-3000:])
        for m in maps:
            after = song_placement.placements(m)
            if after.get(section, (None,))[0] != bank:
                raise RuntimeError("%s: %r landed in %s, not bank $%02X" % (m, section, after.get(section), bank))
            # Each new Music table row (3 B, in "Audio Engine") shifts the sections after it
            # in that same bank; that is expected and harmless. Any bank change, or a shift
            # anywhere else, is not.
            table_bank = before[m]["Audio Engine"][0]
            moved = [mv for mv in song_placement.unchanged_except(before[m], after, {section})
                     if not (mv[1][0] == table_bank and mv[2] is not None and mv[2][0] == table_bank)]
            if moved:
                raise RuntimeError("%s: pinning moved other sections (first few: %s)" % (m, moved[:5]))
    except BaseException as e:
        for path, original in touched.items():
            with open(path, "w", newline="\n") as f:
                f.write(original)
        if os.path.exists(song_rel):
            os.remove(song_rel)
        if made_dir and os.path.isdir(IMPORT_DIR) and not os.listdir(IMPORT_DIR):
            os.rmdir(IMPORT_DIR)
        die("import failed, all edits reverted (rebuild with make red blue blue_debug):\n%s" % e)

    after_space = audio_banks.merged(maps)
    print("import_music: done. Nothing else in the three ROMs moved.")
    for i, s in enumerate(songs):
        print("  %s is song id %d ($%02X): ld a, %s / call PlayMusic   (HOME; no bank argument)"
              % (s["const"], first_id + i, first_id + i, s["const"]))
    print("  files: %s, audio.asm, %s, %s, %s" % (song_rel, CONSTANTS, POINTERS, LAYOUT))
    print("  ROM_BIBLE.md entry (K: isn't visible from WSL, paste it): %s imported, %d bytes, section \"%s\" pinned "
          "in bank $%02X (all three ROMs); bank $%02X free after %d -> %d; largest ROMX gap now %d; nothing else moved."
          % (" + ".join(s["label"] for s in songs), size, section, bank, bank, candidates[bank],
             candidates[bank] - size, after_space["largest"]))
    print("  next: make smoke TEST='*crysaudio*'")


if __name__ == "__main__":
    main()
