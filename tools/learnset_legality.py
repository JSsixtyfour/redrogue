#!/usr/bin/env python3
"""What can each species / form actually learn in this tree?

Used by tools/gen_movesets.py to drop curated sets that carry a move their
mon cannot learn (2026-10-21: 135 corpus sets did - Stadium-era Yellow moves,
removed TMs, Gen 2 snub cuts). Runnable on its own to print the illegal sets:

    python tools/learnset_legality.py

A move is LEGAL for a mon when the mon, or any pre-evolution of it, gets the
move from one of:
  - its level-1 learnset   (data/pokemon/base_stats/*.asm, forms/*.asm)
  - its level-up learnset  (data/pokemon/evos_moves.asm, form_evos_moves/*.asm)
  - its TM/HM list         (the tmhm block of the same base_stats/forms file)
  - its tutor list         (evos_moves.asm third block; SPECIES-keyed, so a
                            form uses its base species' list, exactly like
                            PrepareMoveTutorList)
Level is ignored: this answers "can it ever have this move", not "by level N".
"""
import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POKEMON = os.path.join(ROOT, "data", "pokemon")
TOKEN = re.compile(r"[A-Z_][A-Z0-9_]*")


def _read(path):
    return open(path, encoding="utf-8").read().replace("\r\n", "\n")


def _tmhm(text):
    lines = text.split("\n")
    i = next((k for k, l in enumerate(lines) if l.lstrip().startswith("tmhm")), None)
    if i is None:
        return set()
    out = []
    j = i
    while True:
        code = lines[j].split(";")[0]
        out += TOKEN.findall(code.replace("tmhm", "", 1) if j == i else code)
        j += 1
        if not code.rstrip().endswith("\\") or lines[j].strip().startswith(";"):
            break
    return set(out)


def _stats_file(path):
    text = _read(path)
    l1 = set()
    for line in text.split("\n"):
        if "level 1 learnset" in line:
            l1 = {t for t in TOKEN.findall(line.split(";")[0]) if t not in ("db", "NO_MOVE")}
    dex = re.search(r"db DEX_(\w+)", text)
    form = re.search(r"^\s*form_record\s+(\w+)\s*,\s*(\d+)", text, re.M)
    return {
        "dex": dex.group(1) if dex else None,
        "form": (form.group(1), int(form.group(2))) if form else None,
        "l1": l1,
        "tm": _tmhm(text),
    }


def _records(path, suffix):
    """label -> (evolution targets [(species, form or 0)], level-up moves, tutor moves,
    raw evolution lines)."""
    out = {}
    cur = None
    body = []
    for line in _read(path).split("\n"):
        m = re.match(r"^(\w+)" + suffix + r":", line)
        if m:
            if cur:
                out[cur] = body
            cur, body = m.group(1), []
        elif cur:
            body.append(line)
    if cur:
        out[cur] = body
    parsed = {}
    for label, lines in out.items():
        section, evos, levelup, tutor, raw = 0, [], {}, set(), []
        for line in lines:
            code = line.split(";")[0].strip()
            if not code:
                continue
            if re.fullmatch(r"db\s+0", code):
                section += 1
                if section == 3:
                    break
                continue
            if section == 0:
                raw.append(code)
                m = re.match(r"db\s+EVOLVE_\w+,(.*)", code)
                if m:
                    evos.append((m.group(1).split(",")[-1].strip(), 0))
                m = re.match(r"evo_\w+_form\s+(.*)", code)
                if m:
                    args = [a.strip() for a in m.group(1).split(",")]
                    evos.append((args[-1], int(args[0])))
            else:
                m = re.match(r"db\s+(\d+)\s*,\s*(\w+)", code)
                if m and section == 1:
                    lvl, mv = int(m.group(1)), m.group(2)
                    levelup[mv] = min(lvl, levelup.get(mv, lvl))
                elif m:
                    tutor.add(m.group(2))
        parsed[label.lower()] = (evos, levelup, tutor, raw)
    return parsed


def load(_parents=False, levelup_only=False):
    """Return {key: {move: earliest level}}, key = species name or (base, form index).

    The level is the lowest level-up level anywhere in the line (the mon or a
    pre-evolution); 0 means no level gate (level-1 list, TM/HM or tutor).
    `move in load()[key]` is the legality test.

    levelup_only: only what the line learns by LEVELLING, level-1 moves at 1;
    a move it can get only from a TM/HM or a tutor is absent (the TM level
    gate in gen_movesets.py needs the two told apart)."""
    mons = {}
    for path in glob.glob(os.path.join(POKEMON, "base_stats", "*.asm")):
        s = _stats_file(path)
        if s["dex"]:
            mons[s["dex"]] = s
    species_recs = _records(os.path.join(POKEMON, "evos_moves.asm"), "EvosMoves")
    for name, s in mons.items():
        evos, levelup, tutor, raw = species_recs.get(name.replace("_", "").lower(), ([], {}, set(), []))
        s.update(evos=evos, levelup=levelup, tutor=tutor, evo_lines=raw)
    form_recs = {}
    for path in glob.glob(os.path.join(POKEMON, "form_evos_moves", "*.asm")):
        form_recs.update(_records(path, "FormEvosMoves"))
    for path in glob.glob(os.path.join(POKEMON, "forms", "*.asm")):
        s = _stats_file(path)
        stem = os.path.basename(path)[:-4]
        evos, levelup, _, _ = form_recs.get(stem, ([], {}, set(), []))
        base = mons[s["form"][0]]
        s.update(evos=evos, levelup=levelup, tutor=base["tutor"])
        mons[s["form"]] = s

    def target(key, species, form):
        # A plain EVOLVE_* entry keeps the evolving mon's form (form-preserving
        # evolution, GetEvolvedForm); evo_*_form names the target form outright.
        if form:
            return (species, form)
        if isinstance(key, tuple) and (species, key[1]) in mons:
            return (species, key[1])
        return species

    parents = {k: set() for k in mons}
    for key, s in mons.items():
        for species, form in s["evos"]:
            t = target(key, species, form)
            if t in parents:
                parents[t].add(key)
    # Eevee's stone forms (Espeon = JOLTEON form 1, ...) are not in any
    # evolution list: EvoStoneForms (engine/pokemon/evos_moves.asm) rewrites
    # the target after a plain EVOLVE_ITEM, keyed on the stone AND the target.
    # Without this, Espeon & co. never inherit Eevee's moves.
    engine = _read(os.path.join(ROOT, "engine", "pokemon", "evos_moves.asm"))
    table = re.search(r"^EvoStoneForms:.*?^\s*db 0\b", engine, re.M | re.S)
    for stone, species, form in re.findall(r"^\s*db\s+(\w+),\s*(\w+),\s*(\d+)", table.group(0) if table else "", re.M):
        for key, s in mons.items():
            if isinstance(key, str) and any(
                    re.search(r"db\s+EVOLVE_ITEM,\s*%s\s*,.*\b%s\b" % (stone, species), line)
                    for line in s.get("evo_lines", [])):
                parents[(species, int(form))].add(key)

    if _parents:
        return parents
    learnable = {}
    for key in mons:
        seen, stack, moves = set(), [key], {}
        while stack:
            k = stack.pop()
            if k in seen:
                continue
            seen.add(k)
            s = mons[k]
            for mv, lvl in s["levelup"].items():
                moves[mv] = min(lvl, moves.get(mv, lvl))
            if levelup_only:
                for mv in s["l1"]:
                    moves[mv] = min(1, moves.get(mv, 1))
            else:
                for mv in s["l1"] | s["tm"] | s["tutor"]:
                    moves[mv] = 0
            stack += parents[k]
        learnable[key] = moves
    return learnable


def parents():
    """{key: set of direct pre-evolution keys} - load()'s graph, for audits."""
    return load(_parents=True)


if __name__ == "__main__":
    L = load()
    print(f"{len(L)} species/forms loaded")
