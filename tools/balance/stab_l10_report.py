"""Which species and forms have no damaging move of their FIRST type by a level?

Player-feedback item 3 (2026-10-09): every mon should have a primary-type
(type 1) damaging move by level 10. This lists the ones that fail, read from the
same source the ROM is built from:

  data/pokemon/base_stats/*.asm     type 1, level-1 moves
  data/pokemon/evos_moves.asm       level-up learnset (EvosMovesPointerTable,
                                    positional: entry k = internal id k + 1)
  data/pokemon/forms/*.asm          a form's own type 1 and level-1 moves
  data/pokemon/form_evos_moves.asm  a form's own learnset, when it has one
                                    (FormEvosMovesPointers); otherwise the
                                    base species' learnset applies
  data/moves/moves.asm              power and type

"Damaging" = power > 0. Fixed-damage moves (power 1: Seismic Toss, Night Shade,
Sonicboom, Dragon Rage, Counter, ...) are reported separately, since whether
they count is a design call. The "Tutoring Learnset" block is not level-up and
is ignored.

Usage:
  python tools/balance/stab_l10_report.py [--level 10] [--out FILE.md]
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass, field
from pathlib import Path

from parse import ROOT, _code, _lines, load_species, parse_rgbds_constants

FIXED_DAMAGE_POWER = 1


@dataclass
class Mon:
    name: str                 # GEODUDE, or GEODUDE form 1 (AGEODUDE)
    type1: str
    type2: str
    level1: list[str]
    learnset: list[tuple[int, str]]
    is_form: bool = False
    evolves_from: list[tuple[str, int]] = field(default_factory=list)  # (pre-evo, level or 0 = item/trade)


def load_moves() -> dict[str, tuple[int, str]]:
    out: dict[str, tuple[int, str]] = {}
    for raw in _lines("data/moves/moves.asm"):
        m = re.match(r"^move\s+([A-Z0-9_]+)\s*,\s*[A-Z0-9_]+\s*,\s*(\d+)\s*,\s*([A-Z_]+)\s*,", _code(raw))
        if m:
            out[m.group(1)] = (int(m.group(2)), m.group(3))
    if len(out) < 160:
        raise ValueError(f"moves.asm: parsed only {len(out)} moves")
    return out


def _header(text: str, path: Path) -> tuple[str, str, list[str]]:
    t = re.search(r"^\s*db\s+([A-Z_]+)\s*,\s*([A-Z_]+)\s*;\s*type", text, re.M)
    l1 = re.search(r"^\s*db\s+([A-Z0-9_]+)\s*,\s*([A-Z0-9_]+)\s*,\s*([A-Z0-9_]+)\s*,\s*([A-Z0-9_]+)\s*;\s*level 1 learnset", text, re.M)
    if not (t and l1):
        raise ValueError(f"{path.name}: missing type or level-1 learnset line")
    return t.group(1), t.group(2), [mv for mv in l1.groups() if mv != "NO_MOVE"]


def _learnsets(rel: str, label_re: str) -> dict[str, list[tuple[int, str]]]:
    """label -> level-up learnset. Each record is: evolutions up to `db 0`,
    then the learnset up to the next `db 0`."""
    out: dict[str, list[tuple[int, str]]] = {}
    current = None
    zeros = 0
    for raw in _lines(rel):
        code = _code(raw)
        m = re.match(label_re, code)
        if m:
            current, zeros = m.group(1), 0
            out[current] = []
            continue
        if current is None or not code.startswith("db "):
            continue
        parts = [p.strip() for p in code[3:].split(",")]
        if parts == ["0"]:
            zeros += 1
            if zeros >= 2:
                current = None
            continue
        if zeros == 1 and len(parts) == 2 and parts[0].isdigit():
            out[current].append((int(parts[0]), parts[1]))
    return out


def load_mons() -> list[Mon]:
    species = load_species()
    # base stats keyed by species name (DEX_<NAME> == species constant name)
    headers: dict[str, tuple[str, str, list[str]]] = {}
    for path in sorted((ROOT / "data" / "pokemon" / "base_stats").glob("*.asm")):
        text = path.read_text(encoding="utf-8")
        dex = re.search(r"db\s+DEX_([A-Z0-9_]+)", text)
        if dex:
            headers[dex.group(1)] = _header(text, path)

    # learnsets by label, then label -> species through the positional table
    learn_by_label = _learnsets("data/pokemon/evos_moves.asm", r"^([A-Za-z0-9_]+EvosMoves):$")
    pointers: list[str] = []
    in_table = False
    for raw in _lines("data/pokemon/evos_moves.asm"):
        code = _code(raw)
        if code.startswith("EvosMovesPointerTable"):
            in_table = True
            continue
        if in_table:
            m = re.match(r"^dw\s+([A-Za-z0-9_]+)$", code)
            if m:
                pointers.append(m.group(1))
            elif code and not code.startswith(("table_width", "assert_table_length")):
                break
    ids = parse_rgbds_constants(ROOT / "constants" / "pokemon_constants.asm")
    by_id: dict[int, str] = {}
    for k, v in ids.items():
        if k != "NO_MON":
            by_id.setdefault(v, k)
    learn_by_species = {by_id[k + 1]: learn_by_label.get(lbl, []) for k, lbl in enumerate(pointers) if (k + 1) in by_id}

    pre: dict[str, list[tuple[str, int]]] = {}
    for sp in species.values():
        for method, lvl, target in sp.evos:
            pre.setdefault(target, []).append((sp.name, lvl if method == 1 else 0))

    mons: list[Mon] = []
    for name in species:
        if name not in headers:
            continue
        t1, t2, l1 = headers[name]
        mons.append(Mon(name, t1, t2, l1, learn_by_species.get(name, []), evolves_from=pre.get(name, [])))

    # forms
    form_learn_label: dict[tuple[str, int], str] = {}
    lines = _lines("data/pokemon/form_evos_moves.asm")
    for i, raw in enumerate(lines):
        m = re.match(r"^db\s+([A-Z0-9_]+)\s*,\s*(\d+)$", _code(raw))
        if m and i + 1 < len(lines):
            m2 = re.match(r"^dw\s+([A-Za-z0-9_]+)$", _code(lines[i + 1]))
            if m2:
                form_learn_label[(m.group(1), int(m.group(2)))] = m2.group(1)
    form_learn: dict[str, list[tuple[int, str]]] = {}
    for path in sorted((ROOT / "data" / "pokemon" / "form_evos_moves").glob("*.asm")):
        form_learn.update(_learnsets(str(path.relative_to(ROOT)), r"^([A-Za-z0-9_]+FormEvosMoves):$"))
    for path in sorted((ROOT / "data" / "pokemon" / "forms").glob("*.asm")):
        text = path.read_text(encoding="utf-8")
        fr = re.search(r"form_record\s+([A-Z0-9_]+)\s*,\s*(\d+)", text)
        if not fr:
            continue
        base, idx = fr.group(1), int(fr.group(2))
        t1, t2, l1 = _header(text, path)
        label = form_learn_label.get((base, idx))
        learn = form_learn[label] if label else learn_by_species.get(base, [])
        mons.append(Mon(f"{base} form {idx} ({path.stem.upper()})", t1, t2, l1, learn, is_form=True))
    return mons


def first_stab(mon: Mon, moves: dict[str, tuple[int, str]], fixed_ok: bool) -> tuple[int, str] | None:
    cands = [(1, mv) for mv in mon.level1] + sorted(mon.learnset)
    for lvl, mv in cands:
        power, mtype = moves.get(mv, (0, ""))
        if mtype == mon.type1 and (power > FIXED_DAMAGE_POWER or (fixed_ok and power == FIXED_DAMAGE_POWER)):
            return lvl, mv
    return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--level", type=int, default=10)
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()
    moves = load_moves()
    mons = load_mons()

    fail, fixed_only = [], []
    for mon in mons:
        hit = first_stab(mon, moves, fixed_ok=False)
        if hit and hit[0] <= args.level:
            continue
        fx = first_stab(mon, moves, fixed_ok=True)
        if fx and fx[0] <= args.level:
            fixed_only.append((mon, fx))
        else:
            fail.append((mon, hit))

    def evo_note(mon: Mon) -> str:
        if mon.is_form:
            return "form"
        if not mon.evolves_from:
            return "base"
        return ", ".join(f"from {p} {'L' + str(l) if l else '(item/trade)'}" for p, l in mon.evolves_from)

    def l10_moves(mon: Mon) -> str:
        ms = [f"{mv} (1)" for mv in mon.level1] + [f"{mv} ({l})" for l, mv in sorted(mon.learnset) if l <= args.level]
        return ", ".join(ms) or "-"

    out = [f"# Species without a damaging type-1 move by L{args.level}", "",
           f"Generated by `tools/balance/stab_l10_report.py --level {args.level}` from source. "
           f"{len(mons)} species + forms checked; **{len(fail)} fail**, plus {len(fixed_only)} whose only "
           "type-1 damage by then is a fixed-damage move (power 1).", "",
           "Columns: type 1 / type 2; what it knows by the level (move (level)); the first damaging type-1 move "
           "it does learn and at what level (`never` = no level-up one at all); evolution note (an evolved stage "
           "inherits its pre-evolution's moves in play, so its own row matters only when it is met at low level).", "",
           f"Split: **{sum(1 for m, _ in fail if not m.is_form and not m.evolves_from)} base species**, "
           f"{sum(1 for m, _ in fail if not m.is_form and m.evolves_from)} evolved stages, "
           f"{sum(1 for m, _ in fail if m.is_form)} forms; "
           f"{sum(1 for _, h in fail if h is None)} never learn a damaging type-1 move by level-up at all.", "",
           "Gen 1 move typing applies: KARATE_CHOP, BITE, GUST and SAND_ATTACK are NORMAL here, so they don't "
           "count for Fighting, Dark-ish, Flying or Ground mons.", "",
           "## Fails", "",
           "| Mon | Types | Knows by L%d | First type-1 damaging | Note |" % args.level,
           "|---|---|---|---|---|"]
    for mon, hit in sorted(fail, key=lambda x: (x[0].is_form, x[0].name)):
        first = f"{hit[1]} L{hit[0]}" if hit else "never"
        types = mon.type1 if mon.type1 == mon.type2 else f"{mon.type1}/{mon.type2}"
        out.append(f"| {mon.name} | {types} | {l10_moves(mon)} | {first} | {evo_note(mon)} |")
    out += ["", "## Only fixed-damage type-1 by the level", "", "| Mon | Types | Move |", "|---|---|---|"]
    for mon, fx in sorted(fixed_only, key=lambda x: x[0].name):
        out.append(f"| {mon.name} | {mon.type1}/{mon.type2} | {fx[1]} L{fx[0]} |")
    text = "\n".join(out) + "\n"
    if args.out:
        args.out.write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote {args.out}: {len(fail)} fail, {len(fixed_only)} fixed-only, {len(mons)} checked")
    else:
        print(text)


if __name__ == "__main__":
    main()
