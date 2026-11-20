"""The music kit's "Game Songs" folder: every song in the game as its .asm file,
plus a plain-English instrument sheet per file, so composers can see how the
existing songs (Red, Gold/Silver/Crystal, Stadium...) set up each channel.

    python3 tools/music_kit/song_sheets.py <out_dir> [battle labels...]

make_music_kit.py calls build(). Each channel is walked the way the engine
plays it (sound_call returns, loops and jumps followed once), so the sheet
lists what the channel really uses, in the order it first uses it.
"""

import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

NOTE_INDEX = {n: i for i, n in enumerate(("C_", "C#", "D_", "D#", "E_", "F_", "F#", "G_", "G#", "A_", "A#", "B_"))}
NOTE_NAME = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
SQUARE = ("Square 12.5", "Square 25", "Square 50", "Square 75")
# The kit's own 19 drums (MIDI notes 0-18), INSTRUMENTS AND DRUMS.txt.
KIT_DRUMS = ("snare 1", "snare 2", "snare 3", "snare 4", "snare 5", "triangle 1", "triangle 2", "snare 6",
             "snare 7", "snare 8", "snare 9", "cymbal 1", "cymbal 2", "cymbal 3", "muted snare 1",
             "triangle 3", "muted snare 2", "muted snare 3", "muted snare 4")
WAVE_VOLUME = {0: "muted", 1: "100%", 2: "50%", 3: "25%"}
FLOW = ("sound_call", "sound_loop", "sound_jump", "sound_ret", "sound_jump_if")


def midi_name(n):
    return "%s%d" % (NOTE_NAME[n % 12], n // 12 - 1)


def pretty(label):
    name = label[len("Music_"):] if label.startswith("Music_") else label
    name = re.sub(r"^RBY", "", name)
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])|(?<=[a-zA-Z])(?=\d)", " ", name)


def song_files(repo):
    """crysaudio/music files audio.asm includes, in include order."""
    files = []
    for line in open(os.path.join(repo, "audio.asm")):
        m = re.match(r'\s*INCLUDE "(crysaudio/music/[^"]+\.asm)"', line)
        if m:
            files.append(m.group(1))
    return files


def music_table(repo):
    """Song labels in Music table order (index = song id)."""
    rows = []
    for line in open(os.path.join(repo, "crysaudio/music_pointers_red.asm")):
        m = re.match(r"\s*dba (Music_\w+)", line)
        if m:
            rows.append(m.group(1))
    return rows


def drumkits(repo):
    kits, cur = {}, None
    for line in open(os.path.join(repo, "crysaudio/drumkits.asm")):
        m = re.match(r"^Drumkit(\d+):", line)
        if m:
            cur = kits.setdefault(int(m.group(1)), [])
            continue
        m = re.match(r"^\s*dw (\w+)", line)
        if m and cur is not None:
            cur.append(m.group(1))
        elif re.match(r"^\S", line):
            cur = None
    return kits


class Song:
    """One file's lines, labels and the songs it defines."""

    def __init__(self, path):
        self.lines = []  # (scope, command, args) per source line; command None for labels/blank
        self.labels = {}  # "Global" / "Global.local" -> line index
        self.entries = []  # (label, [(channel, target label)])
        scope = ""
        for raw in open(path, encoding="utf-8"):
            code = raw.split(";")[0].rstrip()
            m = re.match(r"^([A-Za-z_]\w*)::?$", code)
            if m:
                scope = m.group(1)
                self.labels[scope] = len(self.lines)
                self.lines.append((scope, None, ""))
                continue
            m = re.match(r"^\.(\w+):?:?$", code)
            if m:
                self.labels["%s.%s" % (scope, m.group(1))] = len(self.lines)
                self.lines.append((scope, None, ""))
                continue
            m = re.match(r"^\s+(\w+)\s*(.*)$", code)
            self.lines.append((scope, m.group(1), m.group(2).strip()) if m else (scope, None, ""))
        for i, (scope, cmd, args) in enumerate(self.lines):
            if cmd == "channel_count":
                chans = []
                for scope2, cmd2, args2 in self.lines[i + 1:]:
                    if cmd2 == "channel":
                        n, target = [a.strip() for a in args2.split(",")]
                        chans.append((int(n), target))
                    elif cmd2 is not None:
                        break
                self.entries.append((scope, chans))

    def resolve(self, scope, target):
        key = scope + target if target.startswith(".") else target
        return self.labels.get(key)

    def walk(self, start):
        """Commands of one channel in first-play order: [(command, args, octave, transpose)].
        Calls return, loops and jumps are followed once (visited lines are not replayed)."""
        out, seen = [], set()
        state = {"octave": 4, "transpose": 0}

        def run(i, depth):
            while 0 <= i < len(self.lines):
                if i in seen:
                    return
                seen.add(i)
                scope, cmd, args = self.lines[i]
                if cmd is None:
                    i += 1
                    continue
                ops = [a.strip() for a in args.split(",")] if args else []
                if cmd == "octave":
                    state["octave"] = int(ops[0])
                elif cmd == "inc_octave":
                    state["octave"] += 1
                elif cmd == "dec_octave":
                    state["octave"] -= 1
                elif cmd == "transpose":
                    state["transpose"] = int(ops[0]) * 12 + int(ops[1])
                out.append((cmd, ops, state["octave"], state["transpose"]))
                if cmd == "sound_ret":
                    return
                if cmd in ("sound_call", "sound_jump", "sound_loop", "sound_jump_if"):
                    t = self.resolve(scope, ops[-1])
                    if t is not None and depth < 32:
                        run(t, depth + 1)  # a call returns here; a loop body is usually seen already
                    if cmd == "sound_jump" or (cmd == "sound_loop" and ops[0] == "0"):
                        return
                i += 1

        if start is not None:
            run(start, 0)
        return out


def envelope(volume, fade):
    """'12 fading 2' style; the sheet's legend explains it."""
    if fade == 0:
        return "%d steady" % volume
    return "%d %s %d" % (volume, "fading" if fade > 0 else "swelling", abs(fade))


def describe_channel(song, ch, start, kits):
    """Lines of text for one channel: sound, vibrato, volumes, extras, drums.
    Each list keeps first-use order; note_type's first number (note length) is
    rhythm, not sound, so it is left out."""
    events = song.walk(start)
    groups = {"sound": [], "vibrato": [], "volumes": [], "also": []}
    notes, drums, kit, tempo = [], {}, 0, None

    def add(group, text):
        if text not in groups[group]:
            groups[group].append(text)

    for cmd, ops, octave, transpose in events:
        try:
            if cmd == "tempo" and tempo is None:
                tempo = int(ops[0])
            elif cmd == "duty_cycle":
                add("sound", "%s (duty_cycle %d)" % (SQUARE[int(ops[0]) & 3], int(ops[0])))
            elif cmd == "duty_cycle_pattern":
                add("sound", "pulse width cycles %s every frame (duty_cycle_pattern)" % ", ".join(ops))
            elif cmd in ("note_type", "volume_envelope") and ch != 4:
                vals = [int(v) for v in ops]
                if cmd == "note_type" and len(vals) < 3:
                    continue
                vol, fade = (vals[1], vals[2]) if cmd == "note_type" else (vals[0], vals[1])
                if ch == 3:
                    if vol:
                        add("sound", "Wave %d at %s" % (fade, WAVE_VOLUME.get(vol & 3, "?")))
                elif vol or fade:  # pokemid opens with volume 0 under a leading rest
                    add("volumes", envelope(vol, fade))
            elif cmd == "vibrato":
                vals = [int(v) for v in ops]
                if len(vals) == 3 and vals[1]:
                    add("vibrato", "after %d, depth %d, speed %d" % tuple(vals))
                elif len(vals) != 3:
                    add("vibrato", "vibrato %s" % ", ".join(ops))
            elif cmd == "toggle_perfect_pitch" or (cmd == "pitch_offset" and ops == ["1"]):
                add("also", "tuned a hair sharp (toggle_perfect_pitch): Game Freak's trick to thicken two squares playing together")
            elif cmd == "pitch_offset":
                add("also", "tuned up by %s (pitch_offset)" % ops[0])
            elif cmd == "pitch_slide":
                add("also", "pitch slides (pitch_slide)")
            elif cmd == "stereo_panning":
                left, right = ops[0] not in ("FALSE", "0"), ops[1] not in ("FALSE", "0")
                add("also", "plays %s (stereo_panning)" % ("in both ears" if left and right else "on the left only" if left else "on the right only" if right else "muted"))
            elif cmd == "transpose":
                add("also", "transposed by %s octave(s) and %s semitone(s) (transpose)" % (ops[0], ops[1]))
            elif cmd in ("load_wave", "fade_wave", "channel_volume", "red_duty_cycle_pattern"):
                add("also", "%s (a special command the tester does not accept)" % cmd)
            elif cmd == "toggle_noise":
                kit = int(ops[0]) if ops else kit
            elif cmd == "note" and ch != 4:
                base = 12 if ch == 3 else 24
                notes.append(base + 12 * octave + NOTE_INDEX[ops[0]] + transpose)
            elif cmd == "drum_note" or (cmd == "note" and ch == 4):
                idx = int(ops[0]) if cmd == "drum_note" else NOTE_INDEX.get(ops[0], 0) + 1
                drums[(kit, idx)] = drums.get((kit, idx), 0) + 1
        except (ValueError, IndexError, KeyError):
            add("also", "%s %s" % (cmd, ", ".join(ops)))

    kind = {1: "square", 2: "square", 3: "wave", 4: "noise (drums)"}[ch]
    head = "Ch%d  %s" % (ch, kind)
    if notes:
        lo, hi = min(notes), max(notes)
        head += "   notes %s to %s (MIDI %d-%d)" % (midi_name(lo), midi_name(hi), lo, hi)
    text = [head]
    for group, title in (("sound", "sound"), ("vibrato", "vibrato"), ("volumes", "volumes"), ("also", "also")):
        items = groups[group]
        if not items:
            continue
        if group == "volumes":
            line = "starts at %s" % items[0] + ("; later %s" % ", ".join(items[1:]) if len(items) > 1 else "")
            text.append("    %-9s%s" % (title + ":", line))
        else:
            first = True
            for item in items:
                text.append("    %-9s%s%s" % (title + ":" if first else "", "" if first else "then ", item))
                first = False
    if drums:
        text.append("    drums used:")
        for (k, idx), count in sorted(drums.items()):
            # Kits 0 and 1 hold the tester's 19 drums (kit 0 index d = MIDI d-1,
            # kit 1 index d = MIDI d+6; convert.ps1's drum mapping, reversed).
            midi = idx - 1 if k == 0 else idx + 6 if k == 1 else None
            if midi is not None and 0 <= midi <= 18:
                what = "MIDI note %2d  %s" % (midi, KIT_DRUMS[midi])
            else:
                name = kits.get(k, [])[idx] if idx < len(kits.get(k, [])) else "?"
                what = "%s from drum kit %d (only in .asm songs: toggle_noise %d, drum_note %d)" % (name, k, k, idx)
            text.append("      %4d x  %s" % (count, what))
    return text, tempo


def sheet(path, rel, ids, battle, kits):
    song = Song(path)
    out = ["Instruments in %s" % os.path.basename(rel), "(from the game's %s)" % rel, "",
           "How to read this: \"volumes: starts at 11 fading 2\" means volume 11 (MIDI velocity 88-95;",
           "volume N is velocity N*8 to N*8+7) and each note fades out at speed 2 (1 = fastest fade,",
           "7 = slowest). \"steady\" notes hold their volume; \"swelling\" notes get louder. The volume",
           "list is in the order the song first uses each one. Wave volumes are 100%, 50% or 25%",
           "(tester velocity 85-127, 43-84, 1-42). \"vibrato: after 6, depth 3, speed 4\" means the",
           "wobble starts 6 ticks into each note. Sounds named like \"Square 75\" are the tester's",
           "track names.", ""]
    for label, chans in song.entries:
        sid = ids.get(label)
        title = "%s   (%s%s)" % (pretty(label).upper(), label, ", song id %d" % sid if sid is not None else ", not in the song table")
        out.append(title)
        if label in battle:
            out.append("Plays in battles.")
        body, tempo = [], None
        for ch, target in chans:
            lines, t = describe_channel(song, ch, song.labels.get(target), kits)
            tempo = tempo or t
            body += lines + [""]
        if tempo:
            out.append("Tempo %d (lower number = faster; about %d BPM if note_type 12 is a sixteenth note)" % (tempo, round(19114.4 / tempo)))
        out.append("")
        out += body
    return "\r\n".join(out).rstrip() + "\r\n"


INDEX_HEAD = """GAME SONGS
==========
Every song in the game, in the game's own format (.asm), with an instrument
sheet next to each one (the .txt with the same name).

  - The .txt says, channel by channel, which sound each voice uses (Square 50,
    Wave 2, drum kit...), its volume and fade, vibrato, and the notes' range.
    The names match the tester's track names, so you can copy a setup into
    your MIDI: "Square 75" goes in the Ch1 track name, volume 11 is MIDI
    velocity 88-95, and so on. Fades (a note getting quieter as it rings) and
    vibrato come from text markers in MIDI, or from the .asm commands.
  - The .asm opens in Crystal Tracker (in this kit). Open it from THIS folder
    so the tracker finds the waves and drums. You can see and hear every note
    and every instrument change there.
  - Dragging one of these .asm files onto DROP YOUR SONG HERE plays it in the
    tester. Files marked [tracker only] below use a command the tester does
    not accept, so they only open in the tracker.
  - "Plays in battles" songs are the ones the tester replaces in FIGHT 2.

Songs (id, name, file):
"""


def build(out_dir, battle=(), repo=REPO):
    os.makedirs(out_dir, exist_ok=True)
    ids = {label: i for i, label in enumerate(music_table(repo))}
    kits = drumkits(repo)
    rows = []
    for rel in song_files(repo):
        if rel.endswith("/nothing.asm"):
            continue
        path = os.path.join(repo, rel)
        base = os.path.splitext(os.path.basename(rel))[0]
        shutil.copy2(path, os.path.join(out_dir, base + ".asm"))
        with open(os.path.join(out_dir, base + ".txt"), "w", newline="") as f:
            f.write(sheet(path, rel, ids, set(battle), kits))
        text = open(path, encoding="utf-8").read()
        special = bool(re.search(r"^\s+(load_wave|fade_wave|channel_volume|red_duty_cycle_pattern)\b", text, re.M))
        for label, _ in Song(path).entries:
            rows.append((ids.get(label, 999), label, base, special, label in battle))
    rows.sort()
    with open(os.path.join(out_dir, "INDEX.txt"), "w", newline="") as f:
        f.write(INDEX_HEAD.replace("\n", "\r\n"))
        for sid, label, base, special, is_battle in rows:
            f.write("  %3s  %-28s %s.asm%s%s\r\n" % (sid if sid != 999 else "-", pretty(label), base,
                                                     "   [plays in battles]" if is_battle else "",
                                                     "   [tracker only]" if special else ""))
    return len(rows)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    print("%d songs" % build(sys.argv[1], sys.argv[2:]))
