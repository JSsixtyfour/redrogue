"""Build RedRogueMusicTester_<date>_<hash>.zip for the composer.

    make music_kit          (builds pokered.gbc first, then runs this under WSL)

See MUSIC_TEST_KIT_PLAN.md in Red Rogue Files. Steps:
  1. read the exact rgbasm/rgblink/rgbfix flags for pokered.gbc from `make -n`
  2. stage _engine/: prebuilt *_red.o + buildid, layout.link, audio.asm's
     include closure, Windows rgbds/pokemid, portable mGBA, convert.ps1
  3. kit.json: flags, IMPORT_BUDGET (largest free audio bank), build hash
  4. end-to-end check through the staged kit with powershell.exe: an untouched
     rebuild must equal pokered.gbc byte for byte; Template.mid must build
  5. record the 19 drums from the game (PyBoy) and build the DAW sample pack
  6. zip

Runs under WSL: needs powershell.exe interop, PyBoy, and 7-Zip on Windows for
the first mGBA download.
"""

import datetime
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import audio_banks  # noqa: E402
import make_sample_pack  # noqa: E402
import record_title  # noqa: E402
import test_midis  # noqa: E402

CACHE = os.path.join(HERE, "cache")
OUT = os.path.join(HERE, "out")
KIT_NAME = "RedRogueMusicTester"
KIT = os.path.join(OUT, KIT_NAME)
ENGINE = os.path.join(KIT, "_engine")
WORK = os.path.join(OUT, "work")

RGBDS_VERSION = open(os.path.join(REPO, ".rgbds-version")).read().strip()
MGBA_VERSION = "0.10.5"
DOWNLOADS = {
    "rgbds": ("https://github.com/gbdev/rgbds/releases/download/v%s/rgbds-win64.zip" % RGBDS_VERSION, "rgbds-%s.zip" % RGBDS_VERSION),
    "pokemid": ("https://github.com/mtolly/pokemid/releases/download/v0.9/pokemid-v0.9-windows-x64.zip", "pokemid-v0.9.zip"),
    "mgba": ("https://github.com/mgba-emu/mgba/releases/download/%s/mGBA-%s-win64.7z" % (MGBA_VERSION, MGBA_VERSION), "mgba-%s.7z" % MGBA_VERSION),
}
SEVENZIP = "/mnt/c/Program Files/7-Zip/7z.exe"
# mGBA files the composer doesn't need (keep LICENSE.txt + licenses/: MPL-2.0)
MGBA_SKIP = {"mgba-sdl.exe", "nointro.dat", "README_DE.html", "README_ES.html", "README_ZH_CN.html", "shaders", "scripts"}


def log(msg):
    print("[music_kit] " + msg, flush=True)


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw).stdout


def winpath(p):
    return run(["wslpath", "-w", p]).strip()


def fetch(key):
    url, name = DOWNLOADS[key]
    path = os.path.join(CACHE, name)
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        log("downloading " + url)
        urllib.request.urlretrieve(url, path + ".part")
        os.replace(path + ".part", path)
    return path


def unpack(key):
    """Extract a cached download once; return the extraction dir."""
    archive = fetch(key)
    dest = archive + ".d"
    if not os.path.isdir(dest):
        tmp = dest + ".part"
        shutil.rmtree(tmp, ignore_errors=True)
        os.makedirs(tmp)
        if archive.endswith(".zip"):
            with zipfile.ZipFile(archive) as z:
                z.extractall(tmp)
        else:
            if not os.path.exists(SEVENZIP):
                sys.exit("need 7-Zip at %s to unpack %s" % (SEVENZIP, archive))
            run([SEVENZIP, "x", "-y", "-o" + winpath(tmp), winpath(archive)])
        os.replace(tmp, dest)
    return dest


def find_file(root, name):
    for d, _, files in os.walk(root):
        if name in files:
            return os.path.join(d, name)
    sys.exit("%s not found under %s" % (name, root))


# ------------------------------------------------------------------ flags

def make_flags():
    """Exact pokered.gbc commands, as make would run them after audio.asm changed."""
    text = run(["make", "-n", "-W", "audio.asm", "pokered.gbc"], cwd=REPO)
    asm = link = fix = None
    for line in text.splitlines():
        words = shlex.split(line) if re.match(r"^(rgbasm|rgblink|rgbfix) ", line) else []
        if not words:
            continue
        if words[0] == "rgbasm" and "audio_red.o" in words:
            asm = words[1:words.index("-o")]
        elif words[0] == "rgblink":
            link = words
        elif words[0] == "rgbfix" and words[-1] == "pokered.gbc":
            fix = words[1:-1]
    if not (asm and link and fix):
        sys.exit("couldn't read rgbasm/rgblink/rgbfix lines from `make -n`:\n" + text)
    link_flags, objs, i = [], [], 1
    while i < len(link):
        w = link[i]
        if w in ("-l", "-m", "-n", "-o"):
            i += 2
            continue
        if w.endswith(".o"):
            objs.append(w)
        else:
            link_flags.append(w)
        i += 1
    if "audio_red.o" not in objs:
        sys.exit("audio_red.o not in the link line: %s" % objs)
    prebuilt = [o for o in objs if o != "audio_red.o"]
    return {"asm": asm, "link": link_flags, "fix": fix}, prebuilt


# ------------------------------------------------------------------ staging

def stage(flags, prebuilt):
    shutil.rmtree(KIT, ignore_errors=True)
    for d in ("src", "prebuilt", "output", "emulator"):
        os.makedirs(os.path.join(ENGINE, d))

    closure = set(run(["tools/scan_includes", "audio.asm"], cwd=REPO).split())
    closure |= set(run(["tools/scan_includes", "includes.asm"], cwd=REPO).split())
    closure |= {"audio.asm", "includes.asm"}
    for rel in sorted(closure):
        dst = os.path.join(ENGINE, "src", rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(REPO, rel), dst)
    # convert.ps1 never edits these; a preview assembles generated kit_*.asm copies.
    log("src: %d files from the include closure" % len(closure))

    names = set()
    for o in prebuilt:
        base = os.path.basename(o)
        if base in names:
            sys.exit("two prebuilt objects named %s" % base)
        names.add(base)
        shutil.copy2(os.path.join(REPO, o), os.path.join(ENGINE, "prebuilt", base))
    shutil.copy2(os.path.join(REPO, "layout.link"), ENGINE)

    rgbds = unpack("rgbds")
    for exe in ("rgbasm.exe", "rgblink.exe", "rgbfix.exe"):
        shutil.copy2(find_file(rgbds, exe), ENGINE)
    for dll in ("libpng16.dll", "zlib1.dll"):  # rgbasm doesn't need them, but they ship together
        p = os.path.join(os.path.dirname(find_file(rgbds, "rgbasm.exe")), dll)
        if os.path.exists(p):
            shutil.copy2(p, ENGINE)
    shutil.copy2(find_file(unpack("pokemid"), "pokemid.exe"), ENGINE)
    for script in ("convert.ps1", "midi_normalize.ps1", "gm_drums.json"):
        shutil.copy2(os.path.join(HERE, script), ENGINE)

    mgba = os.path.dirname(find_file(unpack("mgba"), "mGBA.exe"))
    for entry in os.listdir(mgba):
        if entry in MGBA_SKIP:
            continue
        src = os.path.join(mgba, entry)
        dst = os.path.join(ENGINE, "emulator", entry)
        (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, dst)

    for entry in os.listdir(os.path.join(HERE, "kit_files")):
        shutil.copy2(os.path.join(HERE, "kit_files", entry), KIT)


def convert(mid=None, *extra):
    """Run the staged kit's convert.ps1 the way the .bat does; return its output."""
    cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
           winpath(os.path.join(ENGINE, "convert.ps1"))]
    if mid:
        cmd.append(winpath(mid))
    cmd += ["-NoLaunch", *extra]
    p = subprocess.run(cmd, text=True, capture_output=True)
    if p.returncode != 0:
        sys.exit("convert.ps1 failed on %s:\n%s%s" % (mid or " ".join(extra), p.stdout, p.stderr))
    return p.stdout


def main():
    os.chdir(REPO)
    git = run(["git", "rev-parse", "--short", "HEAD"]).strip()
    if subprocess.run(["git", "diff", "--quiet", "HEAD", "--"]).returncode:
        git += "-dirty"
    date = datetime.date.today().isoformat()

    flags, prebuilt = make_flags()
    log("flags from make: asm=%s" % " ".join(flags["asm"]))
    maps = [os.path.join(REPO, m) for m in ("pokered.map", "pokeblue.map", "pokeblue_debug.map")]
    if not all(os.path.exists(m) for m in maps):
        sys.exit("need all three maps for the budget (make red blue blue_debug): %s" % maps)
    space = audio_banks.merged(maps)
    budget = audio_banks.song_budget(space)
    id_room = audio_banks.MAX_SONG_ID + 1 - audio_banks.song_count(os.path.join(REPO, "constants/music_constants.asm"))
    log("largest free ROMX gap %d B (bank $%02X), %d B free in all; %d song ids left -> IMPORT_BUDGET %d"
        % (space["largest"], space["bank"], space["free"], id_room, budget))
    if budget <= 0 or id_room <= 0:
        sys.exit("no room for a new song (ROMX gap or song ids exhausted); see audio_banks.py")

    stage(flags, prebuilt)
    kit = {
        "kitDate": date, "buildHash": git, "rgbds": RGBDS_VERSION, "pokemid": "0.9", "mgba": MGBA_VERSION,
        "kitSchema": 2, "engine": "crysaudio pokered-crysaudio 9753183a",
        "importBudget": budget, "songIdRoom": id_room, "romSpace": space,
        "flags": flags,
    }
    with open(os.path.join(ENGINE, "kit.json"), "w") as f:
        json.dump(kit, f, indent=2)

    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    test_midis.write_all(WORK)
    out = os.path.join(ENGINE, "output")

    # 1. The pipeline itself: the game's own title music through the kit's
    #    tools, objects and flags must give pokered.gbc exactly.
    log("check: kit self-test == pokered.gbc")
    print(convert(None, "-SelfTest"), end="")
    with open(os.path.join(out, "test.gbc"), "rb") as a, open(os.path.join(REPO, "pokered.gbc"), "rb") as b:
        if a.read() != b.read():
            sys.exit("untouched kit rebuild differs from pokered.gbc: stale objects or flag drift")

    # 2. Drums: record from the game for the sample pack.
    log("recording drums")
    print(convert(os.path.join(WORK, "drumtest.mid")), end="")
    drums = os.path.join(WORK, "drums")
    record_title.cmd_drums(os.path.join(out, "test.gbc"), os.path.join(out, "test.map"), drums)
    make_sample_pack.build(REPO, drums, os.path.join(KIT, "DAW Samples"))

    # 3. Template: the first thing he'll try must build.
    log("check: Template.mid builds")
    shutil.copy2(os.path.join(WORK, "Template.mid"), KIT)
    print(convert(os.path.join(KIT, "Template.mid")), end="")

    # 3b. What MuseScore and FL Studio write must convert too: tracks found by
    #     order or by name, whole-song loop, timbre from the name, GM drums.
    for mid, wants in (("musescore_like.mid", ["Ch1::", "Ch2::", "Ch4::", "sound_loop 0, .loop"]),
                       ("fl_like.mid", ["duty_cycle 2", "duty_cycle 1", "note_type 12, 1, 2", "sound_loop 0, .loop"])):
        log("check: %s converts" % mid)
        asm = os.path.join(out, mid + ".asm")
        convert(os.path.join(WORK, mid), "-NoBuild", "-OutAsm", winpath(asm))
        text = open(asm).read()
        for want in wants:
            if want not in text.replace("Music_KitPreview_", ""):
                sys.exit("%s: expected %r in the converted song, got:\n%s" % (mid, want, text))

    # Leave the kit clean: no generated preview sources, empty output.
    for name in ("kit_audio.asm", "kit_music_pointers.asm", "kit_song.asm"):
        path = os.path.join(ENGINE, "src", name)
        if os.path.exists(path):
            os.remove(path)
    shutil.rmtree(out)
    os.makedirs(out)
    if not os.path.exists(os.path.join(KIT, "READ ME FIRST.txt")):
        log("WARNING: kit_files/READ ME FIRST.txt doesn't exist yet; the kit has no README")

    zpath = os.path.join(OUT, "%s_%s_%s.zip" % (KIT_NAME, date, git))
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for d, _, files in os.walk(KIT):
            for name in files:
                full = os.path.join(d, name)
                z.write(full, os.path.relpath(full, OUT))
    log("wrote %s (%.1f MB)" % (zpath, os.path.getsize(zpath) / 1e6))
    log("prebuilt objects are from %s. Re-run after changes to the audio engine or title screen;" % git)
    log("other code changes don't affect what he hears.")


if __name__ == "__main__":
    main()
