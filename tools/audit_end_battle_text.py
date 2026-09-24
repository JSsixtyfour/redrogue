#!/usr/bin/env python3
"""Audit every trainer end-battle text for the "NAME: " prefix overflow.

PrintEndBattleText (home/trainers.asm) prints TrainerEndBattleText, which is
`text_far _TrainerNameText` ("<NAME>: ") followed by the trainer's own end
text ON THE SAME LINE. So the first line of that text has only
18 - (len(name) + 2) columns, not 18. `KAREN: Well, aren't you` is 23 and
wraps mid-word on screen, and nothing in the build notices.

It also checks two things that break the same texts:
  - every rendered line fits 18 columns
  - the text ends in `prompt`, not `done`. The end text is printed mid-battle
    and nothing waits afterwards, so with `done` the prize-money box draws
    straight over it (the ProceduralForest.asm note documents this).

Sources, both resolved through `text_far` to the body in text/ or data/text/:
  1. `trainer EVENT, n, Before, END, After` headers in scripts/*.asm. The
     class is the map object the header serves: header k of a
     `def_trainers S` block is object S + k in data/maps/objects/<Map>.asm.
  2. `ld hl, END / ld de, LOSE / call SaveEndBattleTextPointers` sites. The
     class is the nearest `OPP_X` loaded in the same routine.

Name widths follow SaveTrainerName: TrainerNamePointers' short names where the
row has one, else TrainerNames. The rival classes print wRivalName, counted
as 7 (the player-name cap).

A `text_asm` end text (the leaders' ReceivedBadge handlers, which print their
own box) is listed as INFO, not a violation. So is any text whose class could
not be resolved (a wild legendary's `trainer` header has no prefix at all).

Maps nothing can reach (gen_event_constants.py's reachable_maps, the graph the
event layout is built from) are listed under DEAD and do not fail the audit.

Exit status is 1 if anything is flagged, so it can gate a handoff.
  python tools/audit_end_battle_text.py            # the to-do table
  python tools/audit_end_battle_text.py --all      # every text, passing too
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WIDTH = 18
RIVAL_CLASSES = {"RIVAL1", "RIVAL2", "RIVAL3", "RIVAL_MINIBOSS"}
NAME_LEN = 7  # <PLAYER>, <RIVAL>, wRivalName, wPlayerName
# text_ram buffers whose width is known well enough to count.
RAM_WIDTH = {"wPlayerName": NAME_LEN, "wRivalName": NAME_LEN,
             "wNameBuffer": 10, "wStringBuffer": 10}
TOKEN_WIDTH = {"<PLAYER>": NAME_LEN, "<RIVAL>": NAME_LEN, "<USER>": 10,
               "<TARGET>": 10, "#": 4}
# charmap multi-character glyphs that print as ONE tile.
ONE_TILE = ["'d", "'l", "'m", "'r", "'s", "'t", "'v", "<PK>", "<MN>", "<……>"]


def strip(line):
    out, quoted = [], False
    for ch in line:
        if ch == '"':
            quoted = not quoted
        if ch == ";" and not quoted:
            break
        out.append(ch)
    return "".join(out).strip()


def width(s):
    n = 0
    i = 0
    while i < len(s):
        for tok, w in TOKEN_WIDTH.items():
            if s.startswith(tok, i):
                n += w
                i += len(tok)
                break
        else:
            for tok in ONE_TILE:
                if s.startswith(tok, i):
                    n += 1
                    i += len(tok)
                    break
            else:
                if s[i] == "@":
                    return n  # string terminator
                n += 1
                i += 1
    return n


def asm_files(*dirs):
    for d in dirs:
        yield from sorted((ROOT / d).rglob("*.asm"))


def class_names():
    classes = []
    for raw in (ROOT / "constants/trainer_constants.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*trainer_const\s+(\w+)", strip(raw))
        if m:
            classes.append(m.group(1))
    # TrainerNamePointers rows, in class order after NOBODY.
    ptr_text = (ROOT / "data/trainers/name_pointers.asm").read_text(encoding="utf-8")
    shorts = dict(re.findall(r"^(\.\w+):\s*db\s+\"([^\"]*)\"", ptr_text, re.M))
    rows = re.findall(r"^\s*dw\s+(\S+)", ptr_text, re.M)
    longs = re.findall(r'^\s*li\s+"([^"]*)"',
                       (ROOT / "data/trainers/names.asm").read_text(encoding="utf-8"), re.M)
    names = {}
    for i, cls in enumerate(classes[1:]):  # classes[0] is NOBODY
        if cls in RIVAL_CLASSES:
            names[cls] = ("<RIVAL>", NAME_LEN)
            continue
        row = rows[i] if i < len(rows) else "wTrainerName"
        text = shorts[row].rstrip("@") if row in shorts else (longs[i] if i < len(longs) else "?")
        names[cls] = (text, width(text))
    return names


def label_index():
    """label -> (path, line number) for every label in the text-bearing trees."""
    idx = {}
    for path in asm_files("scripts", "text", "data/text", "engine", "custom_functions", "home"):
        for n, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines()):
            m = re.match(r"^([A-Za-z_][\w.]*)::?", raw)
            if m:
                idx.setdefault(m.group(1), (path, n))
    return idx


def body_at(idx, label, depth=0):
    """Resolve a label to ("text", [commands]) / ("asm", None) / (None, why)."""
    if label not in idx or depth > 3:
        return None, f"label {label} not found"
    path, n = idx[label]
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[n + 1:]
    first = None
    for raw in lines:
        code = strip(raw)
        if code:
            first = code
            break
    if first is None:
        return None, "empty"
    if first.startswith("text_far"):
        return body_at(idx, first.split()[1], depth + 1)
    if first.startswith("text_asm"):
        return "asm", None
    cmds = []
    for raw in lines:
        code = strip(raw)
        if not code:
            continue
        if re.match(r"^[A-Za-z_][\w.]*::?$", code):
            break
        m = re.match(r'^(text|line|cont|para|next)\s+"(.*)"$', code)
        if m:
            cmds.append((m.group(1), m.group(2)))
            continue
        m = re.match(r"^text_ram\s+(\w+)", code)
        if m:
            cmds.append(("ram", m.group(1)))
            continue
        if code in ("prompt", "done", "text_end"):
            cmds.append((code, None))
            if code != "text_end":
                break
            continue
        m = re.match(r"^(text_decimal|text_bcd)", code)
        if m:
            cmds.append(("ram", "?num"))
            continue
    return "text", cmds


def measure(cmds, prefix):
    """Return (list of problems, terminator)."""
    problems, lines = [], []
    cur, first_line, vague = 0, True, False
    for op, arg in cmds:
        if op in ("line", "cont", "para", "next"):
            lines.append((cur, first_line, vague))
            first_line = op == "para" and False
            cur, vague = 0, False
            cur += width(arg)
        elif op == "text":
            cur += width(arg)
        elif op == "ram":
            if arg in RAM_WIDTH:
                cur += RAM_WIDTH[arg]
            else:
                vague = True
    lines.append((cur, first_line, vague))
    # only the very first rendered line carries the prefix
    for i, (w, _first, vague) in enumerate(lines):
        limit = WIDTH - prefix if i == 0 else WIDTH
        if w > limit:
            where = "line 1 (after the name prefix)" if i == 0 else f"line {i + 1}"
            problems.append(f"{where} is {w} wide, max {limit}" + (" (+var)" if vague else ""))
    term = next((op for op, _ in reversed(cmds) if op in ("prompt", "done")), None)
    if term != "prompt":
        problems.append(f"ends in {term or 'text_end'}, needs prompt")
    return problems


def trainer_header_sources():
    out = []
    for path in asm_files("scripts"):
        mapname = path.stem
        obj = ROOT / "data/maps/objects" / f"{mapname}.asm"
        objects = []
        if obj.exists():
            for raw in obj.read_text(encoding="utf-8").splitlines():
                code = strip(raw)
                if code.startswith("object_event"):
                    m = re.search(r"OPP_(\w+)", code)
                    objects.append(m.group(1) if m else None)
        start, k = None, 0
        for n, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines()):
            code = strip(raw)
            m = re.match(r"def_trainers(?:\s+(\d+))?$", code)
            if m:
                start, k = int(m.group(1) or 1), 0
                continue
            m = re.match(r"trainer\s+\w+\s*,\s*\w+\s*,\s*\w+\s*,\s*(\w+)", code)
            if m:
                cls = None
                if start is not None and 0 <= start - 1 + k < len(objects):
                    cls = objects[start - 1 + k]
                out.append((f"{path.relative_to(ROOT)}:{n + 1}", m.group(1), cls))
                k += 1
    return out


def save_pointer_sources():
    out = []
    for path in asm_files("scripts", "custom_functions", "engine"):
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for n, raw in enumerate(lines):
            if "call SaveEndBattleTextPointers" not in strip(raw):
                continue
            label = None
            for back in range(n - 1, max(n - 4, -1), -1):
                m = re.match(r"ld hl, (\w+)", strip(lines[back]))
                if m:
                    label = m.group(1)
                    break
            cls = None
            for near in list(range(n + 1, min(n + 25, len(lines)))) + list(range(n - 1, max(n - 25, -1), -1)):
                code = strip(lines[near])
                m = re.search(r"\bOPP_(\w+)", code)
                if m:
                    cls = m.group(1)
                    break
                if re.match(r"^[A-Za-z_]\w*::?$", code):  # left the routine
                    if near > n:
                        continue
                    break
            if label:
                out.append((f"{path.relative_to(ROOT)}:{n + 1}", label, cls))
    return out


def dead_script_stems():
    """Script stems whose map no warp, connection or stage table reaches."""
    sys.path.insert(0, str(ROOT / "tools"))
    import gen_event_constants  # the one reachability oracle the repo has
    seen, obj_map = gen_event_constants.reachable_maps()
    return {stem for stem, const in obj_map.items() if const not in seen}


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    show_all = "--all" in argv
    names, idx = class_names(), label_index()
    dead = dead_script_stems()
    flagged, info, ok, dead_hits = [], [], 0, []
    seen = set()
    for where, label, cls in trainer_header_sources() + save_pointer_sources():
        if (label, cls) in seen:
            continue
        seen.add((label, cls))
        kind, cmds = body_at(idx, label)
        name, nlen = names.get(cls, ("?", 13)) if cls else ("?", 0)
        prefix = nlen + 2
        if kind == "asm":
            info.append((where, label, name, "text_asm handler - prints its own box, not measured"))
            continue
        if kind is None:
            info.append((where, label, name, cmds))
            continue
        problems = measure(cmds, prefix)
        # A speaker tag of its own doubles the engine's: "LANCE: LANCE: What?!"
        first = next((arg for op, arg in cmds if op == "text"), "")
        if re.match(r"^[A-Z][A-Z.]*: ", first):
            problems.append(f"starts with its own speaker tag {first.split(':')[0]!r}; "
                            "the engine already prints the name")
        if cls is None:
            # No OPP_ class resolved: a wild legendary's `trainer` header (no
            # name prefix at all) or a script whose class is loaded far from
            # the pointer save. Not measurable, so a hand check, not a flag.
            info.append((where, label, "?", "class unresolved - check by hand"
                         + (": " + "; ".join(problems) if problems else "")))
            continue
        if problems and Path(where.split(":")[0]).stem in dead:
            dead_hits.append((where, label, name, problems))
        elif problems:
            flagged.append((where, label, name, problems))
        else:
            ok += 1
            if show_all:
                print(f"ok    {label} ({name})")
    for where, label, name, problems in flagged:
        print(f"FIX   {label}  [{name}: prefix {len(name) + 2 if name != '<RIVAL>' else 9}]  {where}")
        for p in problems:
            print(f"        - {p}")
    for where, label, name, why in info:
        print(f"INFO  {label}  [{name}]  {where}: {why}")
    for where, label, name, problems in dead_hits:
        print(f"DEAD  {label}  [{name}]  {where}: unreachable map - " + "; ".join(problems))
    print(f"\n{len(flagged)} to fix, {ok} ok, {len(info)} info, {len(dead_hits)} on dead maps")
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
