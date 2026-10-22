"""Import a composer's finished .mid into the game as a new song.

    make import_music MID=path/to/song.mid NAME=SongName

Uses the same convert.ps1 the kit runs (only the label differs), so the
imported song is what he heard. Then:
  1. measures the song's exact size by assembling it alone
  2. picks the audio bank with the most free space that also has song-id room
     (audio_banks.py: banks $02/$08/$1F are out of ids, measured 2026-10-21)
  3. adds the song file, its INCLUDE, its 4-channel header and its music_const
  4. builds all three ROMs; on failure restores every file it touched
It doesn't make the song play anywhere: callers use HOME PlayMusic with
c = BANK(Music_<Name>), a = MUSIC_<NAME>.

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


def die(msg):
    sys.exit("import_music: " + msg)


def snake(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", "_", name).upper()


def song_size(asm_path):
    """Exact bytes of the converted song, assembled on its own."""
    with tempfile.TemporaryDirectory() as tmp:
        wrapper = os.path.join(tmp, "probe.asm")
        with open(wrapper, "w") as f:
            f.write('SECTION "Import Probe", ROMX\nINCLUDE "%s"\n' % asm_path)
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


def insert_include(text, n, line):
    """Append an INCLUDE at the end of SECTION "Music N" in audio.asm."""
    lines = text.split("\n")
    start = lines.index('SECTION "Music %d", ROMX' % n)
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("SECTION ")), len(lines))
    last = max(i for i in range(start, end) if lines[i].strip())
    lines.insert(last + 1, line)
    return "\n".join(lines)


def insert_const(text, n, line):
    """Append a music_const at the end of the '; AUDIO_N' music group."""
    lines = text.split("\n")
    try:
        i = lines.index("\t; AUDIO_%d" % n)
    except ValueError:
        die("no '\\t; AUDIO_%d' group in constants/music_constants.asm" % n)
    while i + 1 < len(lines) and lines[i + 1].lstrip().startswith("music_const "):
        i += 1
    lines.insert(i + 1, line)
    return "\n".join(lines)


def main():
    if len(sys.argv) != 3:
        die("usage: make import_music MID=song.mid NAME=SongName")
    mid, name = os.path.abspath(sys.argv[1]), sys.argv[2]
    if not re.match(r"^[A-Z][A-Za-z0-9]+$", name):
        die("NAME must be CamelCase letters/digits, e.g. NAME=ForestTheme")
    label, const, lower = "Music_" + name, "MUSIC_" + snake(name), name.lower()
    song_rel = "audio/music/%s.asm" % lower
    os.chdir(REPO)
    if os.path.exists(song_rel):
        die("%s already exists" % song_rel)
    for path, needle in (("audio.asm", song_rel), ("constants/music_constants.asm", const + ","),
                         ("constants/music_constants.asm", label)):
        if needle in open(path).read():
            die("%s already mentions %s" % (path, needle))

    # 1. convert with the kit's converter
    pokemid = make_music_kit.find_file(make_music_kit.unpack("pokemid"), "pokemid.exe")
    tmp_asm = os.path.join(HERE, "output", "import_%s.asm" % lower)
    os.makedirs(os.path.dirname(tmp_asm), exist_ok=True)
    p = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                        make_music_kit.winpath(os.path.join(HERE, "convert.ps1")), make_music_kit.winpath(mid),
                        "-NoBuild", "-Label", label, "-OutAsm", make_music_kit.winpath(tmp_asm),
                        "-Pokemid", make_music_kit.winpath(pokemid)], text=True, capture_output=True)
    print(p.stdout, end="")
    if p.returncode:
        die("conversion failed:\n" + p.stderr)
    size = song_size(tmp_asm)

    # 2. pick a bank
    banks = audio_banks.merged([m for m in MAPS if os.path.exists(m)])
    fits = {k: v for k, v in banks.items() if v["id_room"] > 0 and v["free"] >= size + audio_banks.HEADER_BYTES}
    if not fits:
        die("no audio bank can take %d + %d bytes: %s. See ROM_BIBLE.md before making room."
            % (size, audio_banks.HEADER_BYTES, {"$%02X" % k: v for k, v in sorted(banks.items())}))
    bank = max(fits, key=lambda k: fits[k]["free"])
    n = banks[bank]["n"]
    print("import_music: %s is %d bytes (+%d header) -> AUDIO_%d, bank $%02X (%d free, room for %d more song ids)"
          % (label, size, audio_banks.HEADER_BYTES, n, bank, banks[bank]["free"], banks[bank]["id_room"]))

    # 3. edit, remembering originals
    headers = "audio/headers/musicheaders%d.asm" % n
    touched = {path: open(path).read() for path in ("audio.asm", headers, "constants/music_constants.asm")}
    header = "\n%s::\n\tchannel_count 4\n%s" % (label, "".join("\tchannel %d, %s_Ch%d\n" % (c, label, c) for c in range(1, 5)))
    try:
        with open(song_rel, "w", newline="\n") as f:
            f.write(open(tmp_asm).read())
        with open("audio.asm", "w", newline="\n") as f:
            f.write(insert_include(touched["audio.asm"], n, 'INCLUDE "%s"' % song_rel))
        with open(headers, "w", newline="\n") as f:
            f.write(touched[headers].rstrip("\n") + "\n" + header)
        with open("constants/music_constants.asm", "w", newline="\n") as f:
            f.write(insert_const(touched["constants/music_constants.asm"], n,
                                 "\tmusic_const %s, %s" % (const, label)))

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
        die("build failed, all edits reverted:\n%s" % e)

    after = audio_banks.merged([m for m in MAPS if os.path.exists(m)])[bank]
    print("import_music: done. Bank $%02X now %d free, room for %d more song ids." % (bank, after["free"], after["id_room"]))
    print("  files: %s, audio.asm, %s, constants/music_constants.asm" % (song_rel, headers))
    print("  to play it: ld c, BANK(%s) / ld a, %s / call PlayMusic   (HOME; c = bank, a = id)" % (label, const))
    print("  Always pass the bank at the call. Ids are only unique per audio bank: a plain PlaySound")
    print("  inherits whatever wAudioROMBank was left (the title screen inherits the intro's AUDIO_3),")
    print("  and leaving wAudioROMBank on AUDIO_4 breaks that screen's own SFX (title hung on a white")
    print("  screen in WaitForSoundToFinish when tried, 2026-10-21).")
    print("  ROM_BIBLE.md entry (K: isn't visible from WSL, paste it): %s, %d bytes song + %d header in bank $%02X (AUDIO_%d); free %d -> %d."
          % (label, size, audio_banks.HEADER_BYTES, bank, n, banks[bank]["free"], after["free"]))
    print("  next: make smoke")


if __name__ == "__main__":
    main()
