"""Lossless size optimizer for Crystal-engine song files (prototype, 2026-11-26).

    python3 tools/music_kit/song_optimize.py IN.asm [-o OUT.asm] [--report]

Rewrites a song so it assembles smaller while every channel plays exactly the same
notes, rests, durations and channel state. What it relies on (crysaudio/engine.asm):

- ParseMusic runs every command byte in the same frame until a note or rest, so
  where a state command sits between two notes doesn't affect timing.
- `octave`, `note_type`, `drum_speed` and `volume_envelope` only store a channel
  value. The speed (CHANNEL_NOTE_LENGTH) is read only by SetNoteDuration, which
  uses the low byte of speed * length. So any (speed, length) with the same product
  gives the same frames, and the fractional carry stays identical.
- `sound_call` is one level deep (the return address is a single slot) and a
  finite `sound_loop N` runs its body N times. One loop counter per channel, so no
  nested finite loops.

Passes: flatten every channel to straight-line tokens (intro, plus the body of
the final infinite loop), choose speeds with a DP that minimizes the note_type,
volume_envelope and drum_speed bytes, re-emit octave only when it changes, then
share repeated token runs as subroutines (across channels too) and fold
back-to-back repeats into finite loops.

Equivalence is checked on the flattened event streams. Each note or rest becomes
(kind, pitch, octave, low byte of speed*length, envelope), and every other command
is an ordered opaque event. The real proof is identical PyBoy audio
(tools/music_kit/song_audio_compare.py).
"""

import argparse
import re
import sys
from collections import defaultdict

PITCHES = {n: i + 1 for i, n in enumerate(
    ["C_", "C#", "D_", "D#", "E_", "F_", "F#", "G_", "G#", "A_", "A#", "B_"])}

# bytes per command (ch1-3 note_type has the envelope byte, ch4's has not)
SIZE = {
    "note": 1, "rest": 1, "drum_note": 1, "octave": 1, "volume_envelope": 2,
    "drum_speed": 2, "sound_call": 3, "sound_jump": 3, "sound_loop": 4, "sound_ret": 1,
    "tempo": 3, "duty_cycle": 2, "vibrato": 3, "volume": 2, "pitch_offset": 3,
    "transpose": 2, "stereo_panning": 2, "force_stereo_panning": 2, "toggle_noise": 2,
    "pitch_sweep": 2, "duty_cycle_pattern": 2, "pitch_slide": 3, "tempo_relative": 2,
    "toggle_sfx": 1, "sfx_priority_on": 1, "sfx_priority_off": 1,
}
STATE_OPS = {"octave", "note_type", "drum_speed", "volume_envelope"}
FLOW_OPS = {"sound_call", "sound_jump", "sound_loop", "sound_ret"}


class Unsupported(Exception):
    pass


# ------------------------------------------------------------------ parsing

def parse(text):
    """-> (instrs, labels, header). instrs: [(op, args)], labels: {fullname: index}."""
    instrs, labels, header = [], {}, []
    glob = None
    for raw in text.split("\n"):
        line = raw.split(";", 1)[0].rstrip()
        if not line.strip():
            continue
        m = re.match(r"^(\.?[A-Za-z_][\w.]*?)(::?)\s*(.*)$", line.strip()) if not line[0].isspace() else None
        if m:
            name = m.group(1)
            if name.startswith("."):
                name = glob + name
            else:
                glob = name
            labels[name] = len(instrs)
            rest = m.group(3).strip()
            if not rest:
                continue
            line = "\t" + rest
        parts = line.strip().split(None, 1)
        op = parts[0]
        args = [a.strip() for a in parts[1].split(",")] if len(parts) > 1 else []
        if op in ("channel_count", "channel"):
            header.append((op, args))
            continue
        if op in ("sound_call", "sound_jump") or op == "sound_loop":
            tgt = args[-1]
            if tgt.startswith("."):
                args[-1] = glob + tgt
        instrs.append((op, tuple(args)))
    return instrs, labels, header


def env_of(op, args, ch):
    if op == "note_type":
        if ch == 4 or len(args) < 3:
            return None
        return (int(args[1]), int(args[2]))
    if op == "volume_envelope":
        return (int(args[0]), int(args[1]))
    return None


# ------------------------------------------------------------------ flatten

def flatten(instrs, labels, start, limit=200000):
    """Run one channel like the engine. -> (intro, body); body None if the channel ends.

    Tokens are (op, args) with every flow command removed."""
    pc, out = labels[start], []
    in_sub, ret_pc = False, None
    looping, loop_count = False, 0
    seen_top = {}  # top-level pc -> first output index (to find the infinite loop target)
    steps = 0
    while True:
        steps += 1
        if steps > limit:
            raise Unsupported("runaway channel %s" % start)
        if not in_sub and pc not in seen_top:
            seen_top[pc] = len(out)
        op, args = instrs[pc]
        if op == "sound_ret":
            if in_sub:
                in_sub, pc = False, ret_pc
                continue
            return out, None
        if op == "sound_call":
            if in_sub:
                raise Unsupported("nested sound_call")
            in_sub, ret_pc, pc = True, pc + 1, labels[args[0]]
            continue
        if op == "sound_jump":
            tgt = labels[args[0]]
            if not in_sub and tgt in seen_top and tgt <= pc:
                return out[:seen_top[tgt]], out[seen_top[tgt]:]
            pc = tgt
            continue
        if op == "sound_loop":
            n, tgt = int(args[0]), labels[args[1]]
            if n == 0:
                if in_sub:
                    raise Unsupported("infinite loop inside a subroutine")
                if tgt not in seen_top:
                    raise Unsupported("loop target never ran at top level")
                return out[:seen_top[tgt]], out[seen_top[tgt]:]
            if not looping:
                looping, loop_count = True, n - 1
            if loop_count == 0:
                looping = False
                pc += 1
            else:
                loop_count -= 1
                pc = tgt
            continue
        if op in ("sound_jump_if", "new_song", "restart_channel", "set_condition"):
            raise Unsupported(op)
        out.append((op, args))
        pc += 1


# ------------------------------------------------------------------ semantics

def events(tokens, ch, state=None):
    """Tokens -> semantic events, plus the end state. state = [speed, env, octave]."""
    st = list(state) if state else [1, None, None]
    ev = []
    for op, args in tokens:
        if op == "note_type":
            st[0] = int(args[0])
            e = env_of(op, args, ch)
            if e is not None:
                st[1] = e
        elif op == "drum_speed":
            st[0] = int(args[0])
        elif op == "volume_envelope":
            st[1] = env_of(op, args, ch)
        elif op == "octave":
            st[2] = int(args[0])
        elif op == "note":
            ev.append(("note", PITCHES[args[0]], st[2], (st[0] * int(args[1])) & 0xFF, st[1]))
        elif op == "drum_note":
            ev.append(("drum", int(args[0]), (st[0] * int(args[1])) & 0xFF))
        elif op == "rest":
            ev.append(("rest", (st[0] * int(args[0])) & 0xFF, st[1]))
        else:
            ev.append((op, args))
    return ev, st


def channel_events(intro, body, ch, loops=3):
    ev, st = events(intro, ch)
    out = [ev]
    if body is not None:
        for _ in range(loops):
            e, st = events(body, ch, st)
            out.append(e)
    return out


# ------------------------------------------------------------------ re-emit

def divisors_for(product):
    return [(s, product // s) for s in range(1, 256) if product % s == 0 and 1 <= product // s <= 16]


def reemit(tokens, ch, uses_slide, state_in=None):
    """Straight-line tokens -> equivalent tokens with fewer state bytes.

    Each timed event keeps its full speed*length product; the DP chooses the speed
    (and where envelopes are set) to minimize command bytes. Octave is re-emitted
    only when it changes. The state at the start is unknown, so the first of each is
    always emitted."""
    # gather the timed events and the opaque commands between them
    items = []  # ("timed", op, payload, product, env_needed, octave_needed) | ("opaque", op, args)
    st = list(state_in) if state_in else [1, None, None]
    speed_known = False
    for op, args in tokens:
        if op == "note_type":
            st[0] = int(args[0]); speed_known = True
            e = env_of(op, args, ch)
            if e is not None:
                st[1] = e
        elif op == "drum_speed":
            st[0] = int(args[0]); speed_known = True
        elif op == "volume_envelope":
            st[1] = env_of(op, args, ch)
        elif op == "octave":
            st[2] = int(args[0])
        elif op in ("note", "rest", "drum_note"):
            ln = int(args[-1])
            prod = st[0] * ln
            pitch = args[0] if op != "rest" else None
            items.append(("timed", op, pitch, prod, st[1], st[2] if op == "note" else None, st[0], ln))
        else:
            items.append(("opaque", op, args))
    timed = [it for it in items if it[0] == "timed"]
    if not timed:
        return list(tokens)

    # DP over timed events: state = (speed, env)
    ch4 = ch == 4
    INF = float("inf")
    layers = []
    prev = {(None, None): (0, None, None)}  # (speed, env) -> (cost, back_state, choice)
    for it in timed:
        _, op, pitch, prod, env, octv, s0, l0 = it
        if uses_slide or prod > 255:
            opts = [(s0, l0)]
        else:
            opts = divisors_for(prod)
        cur = {}
        for (ps, pe), (cost, _, _) in prev.items():
            for s, l in opts:
                if ch4:
                    c = cost + (2 if s != ps else 0)
                    key = (s, None)
                else:
                    target = env if env is not None else pe
                    if s != ps:
                        if target is None:
                            continue  # a note_type has to carry some envelope
                        c, key = cost + 3, (s, target)
                    elif target != pe:
                        c, key = cost + 2, (s, target)
                    else:
                        c, key = cost, (s, pe)
                if key not in cur or c < cur[key][0]:
                    cur[key] = (c, (ps, pe), (s, l))
        if not cur:
            raise Unsupported("no timing choice")
        layers.append(cur)
        prev = cur
    # backtrack
    key = min(prev, key=lambda k: prev[k][0])
    choices = []
    for layer in reversed(layers):
        c, back, choice = layer[key]
        choices.append((key, choice))
        key = back
    choices.reverse()

    out = []
    cur_speed, cur_env, cur_oct = None, None, None
    ti = 0
    for it in items:
        if it[0] == "opaque":
            out.append((it[1], it[2]))
            continue
        _, op, pitch, prod, env, octv, s0, l0 = it
        (s, e), (s_, l) = choices[ti]
        ti += 1
        if s != cur_speed:
            if ch4:
                out.append(("drum_speed", (str(s),)))
            else:
                out.append(("note_type", (str(s), str(e[0]), str(e[1]))))
                cur_env = e
            cur_speed = s
        if not ch4 and env is not None and env != cur_env:
            out.append(("volume_envelope", (str(env[0]), str(env[1]))))
            cur_env = env
        if op == "note" and octv != cur_oct:
            out.append(("octave", (str(octv),)))
            cur_oct = octv
        if op == "rest":
            out.append(("rest", (str(l),)))
        elif op == "note":
            out.append(("note", (pitch, str(l))))
        else:
            out.append(("drum_note", (pitch, str(l))))
    return out


# ------------------------------------------------------------------ compress

def tok_size(t):
    op = t[0]
    if op == "note_type":
        return 3 if len(t[1]) >= 2 else 2
    if op == "CALL":
        return 3
    return SIZE.get(op, 3)


def compress(segments, max_len=96, min_gain=1):
    """Share repeated token runs as subroutines. segments: list of token lists.

    A run may not contain a CALL (calls are one level deep). Returns (segments, subs)."""
    subs = []
    segs = [list(s) for s in segments]
    while True:
        best = None
        counts = defaultdict(list)
        for si, seg in enumerate(segs):
            n = len(seg)
            for i in range(n):
                if seg[i][0] == "CALL":
                    continue
                size = 0
                for L in range(1, min(max_len, n - i) + 1):
                    t = seg[i + L - 1]
                    if t[0] == "CALL":
                        break
                    size += tok_size(t)
                    if L >= 2 and size >= 5:
                        counts[tuple(seg[i:i + L])].append((si, i))
        for run, locs in counts.items():
            if len(locs) < 2:
                continue
            # non-overlapping occurrences per segment
            L = len(run)
            last = {}
            k = 0
            for si, i in locs:
                if si in last and i < last[si] + L:
                    continue
                last[si] = i
                k += 1
            if k < 2:
                continue
            B = sum(tok_size(t) for t in run)
            gain = k * B - (3 * k + B + 1)
            if gain >= min_gain and (best is None or gain > best[0]):
                best = (gain, run)
        if best is None:
            break
        run = best[1]
        sid = len(subs)
        subs.append(list(run))
        L = len(run)
        for si, seg in enumerate(segs):
            out, i = [], 0
            while i < len(seg):
                if tuple(seg[i:i + L]) == run:
                    out.append(("CALL", (sid,)))
                    i += L
                else:
                    out.append(seg[i])
                    i += 1
            segs[si] = out
    return segs, subs


def fold_loops(seg, max_len=48):
    """Back-to-back repeats of a run (calls allowed inside) -> one finite loop. -> tokens with ("LOOP", (n, tokens))."""
    out, i, n = [], 0, len(seg)
    while i < n:
        best = None
        for L in range(1, min(max_len, (n - i) // 2) + 1):
            run = seg[i:i + L]
            k = 1
            while seg[i + k * L:i + (k + 1) * L] == run:
                k += 1
            if k >= 2:
                B = sum(tok_size(t) for t in run)
                gain = k * B - (B + 4)
                if gain > 0 and (best is None or gain > best[0]):
                    best = (gain, L, k)
        if best:
            _, L, k = best
            out.append(("LOOP", (k, seg[i:i + L])))
            i += L * k
        else:
            out.append(seg[i])
            i += 1
    return out


# ------------------------------------------------------------------ emit

def fmt(t, subname):
    op, args = t
    if op == "CALL":
        return "\tsound_call %s" % subname(args[0])
    return "\t%s %s" % (op, ", ".join(args)) if args else "\t" + op


def emit(name, header, chans, subs):
    """chans: [(ch, label, intro, body)] with folded tokens."""
    lines = []
    subname = lambda i: "%s_Sub%d" % (name, i)
    lines.append("%s::" % name)
    for op, args in header:
        if op == "channel":
            continue
        lines.append("\t%s %s" % (op, ", ".join(args)))
    for ch, label, _, _ in chans:
        lines.append("\tchannel %d, %s" % (ch, label))
    lc = [0]

    def put(tokens):
        for t in tokens:
            if t[0] == "LOOP":
                n, run = t[1]
                lab = ".loop%d" % lc[0]
                lc[0] += 1
                lines.append(lab + ":")
                for r in run:
                    lines.append(fmt(r, subname))
                lines.append("\tsound_loop %d, %s" % (n, lab))
            else:
                lines.append(fmt(t, subname))

    for ch, label, intro, body in chans:
        lines.append("")
        lines.append("%s::" % label if label.count("_Ch") else "%s:" % label)
        put(intro)
        if body is None:
            lines.append("\tsound_ret")
        else:
            lines.append(".mainloop:")
            put(body)
            lines.append("\tsound_loop 0, .mainloop")
    for i, run in enumerate(subs):
        lines.append("")
        lines.append("%s:" % subname(i))
        for r in run:
            lines.append(fmt(r, subname))
        lines.append("\tsound_ret")
    return "\n".join(lines) + "\n"


def expand(tokens, subs):
    out = []
    for t in tokens:
        if t[0] == "CALL":
            out.extend(subs[t[1][0]])
        elif t[0] == "LOOP":
            n, run = t[1]
            for _ in range(n):
                out.extend(expand(run, subs))
        else:
            out.append(t)
    return out


def est_size(header, chans, subs):
    n = 1 + 3 * len(chans)  # channel_count nibble byte + 3 per channel
    for _, _, intro, body in chans:
        for seg in (intro, body or []):
            for t in seg:
                if t[0] == "LOOP":
                    n += sum(tok_size(r) for r in t[1][1]) + 4
                else:
                    n += tok_size(t)
        n += 4 if body is not None else 1
    for s in subs:
        n += sum(tok_size(t) for t in s) + 1
    return n


# ------------------------------------------------------------------ driver

def optimize(text, loops_pass=True):
    instrs, labels, header = parse(text)
    chan_rows = [(int(a[0]), a[1]) for op, a in header if op == "channel"]
    name = [k for k, v in labels.items() if "." not in k and k.endswith("") and v == labels[chan_rows[0][1]]]
    song = re.search(r"^(\w+)::", text, re.M).group(1)
    uses_slide = any(op == "pitch_slide" for op, _ in instrs)
    flat, orig_ev = [], []
    for ch, lab in chan_rows:
        intro, body = flatten(instrs, labels, lab)
        flat.append((ch, lab, intro, body))
        orig_ev.append(channel_events(intro, body, ch))
    # re-emit timing/octave state
    new = []
    for ch, lab, intro, body in flat:
        ni = reemit(intro, ch, uses_slide)
        nb = None
        if body is not None:
            _, st1 = events(intro, ch)
            _, st2 = events(body, ch, st1)
            nb = reemit(body, ch, uses_slide, st1)
            if reemit(body, ch, uses_slide, st2) != nb:
                # the loop body reads state it doesn't set, and the two entries differ
                nb = list(body)
        new.append((ch, lab, ni, nb))
    segs = []
    for _, _, ni, nb in new:
        segs.append(ni)
        segs.append(nb if nb is not None else [])
    csegs, subs = compress(segs)
    chans = []
    for k, (ch, lab, _, nb) in enumerate(new):
        intro, body = csegs[2 * k], csegs[2 * k + 1]
        if loops_pass:
            intro = fold_loops(intro)
            body = fold_loops(body)
        chans.append((ch, lab, intro, body if nb is not None else None))
    # verify on the semantic stream
    for k, (ch, lab, intro, body) in enumerate(chans):
        ei = expand(intro, subs)
        eb = expand(body, subs) if body is not None else None
        got = channel_events(ei, eb, ch)
        if got != orig_ev[k]:
            raise AssertionError("channel %d (%s) differs after optimizing" % (ch, lab))
    out = emit(song, header, chans, subs)
    # and once more by re-parsing what we wrote, like the engine would run it
    i2, l2, h2 = parse(out)
    for k, (ch, lab) in enumerate(chan_rows):
        a, b = flatten(i2, l2, lab)
        if channel_events(a, b, ch) != orig_ev[k]:
            raise AssertionError("emitted channel %d (%s) differs" % (ch, lab))
    return out, est_size(header, chans, subs)


def original_size(text):
    instrs, labels, header = parse(text)
    n = 1 + 3 * sum(1 for op, _ in header if op == "channel")
    for op, args in instrs:
        n += tok_size((op, args)) if op != "note_type" else (3 if len(args) >= 3 else 2)
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("song")
    ap.add_argument("-o", "--out")
    ap.add_argument("--no-loops", action="store_true")
    a = ap.parse_args()
    text = open(a.song).read()
    out, est = optimize(text, loops_pass=not a.no_loops)
    print("%s: %d -> %d bytes (estimate)" % (a.song, original_size(text), est))
    if a.out:
        open(a.out, "w").write(out)


if __name__ == "__main__":
    main()
