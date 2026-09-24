#!/usr/bin/env python3
"""List every species and form of a type, as ready-to-paste pool_mon lines.

For writing "all <type>" clauses into data/trainers/pools.asm without typing
species from memory. Reads the ROM's own data, not an outside dex:

  - types:  data/pokemon/base_stats/*.asm (the `; type` line) and every form
            record in data/pokemon/forms/*.asm (form_record SPECIES, n)
  - runs:   engine/pokemon/rarity.asm - a species is in the Kanto, Johto or
            Warp run of whichever Kanto*/Johto*/Warp* tier lists it (base or
            _Evos half, both count)

Forms are printed PINNED (`pool_mon SPECIES, n`) and always in the Warp run:
a pin bypasses species-group gating, so the Warp run is the only place that
keeps them out of a Kanto-only or Johto-off run (JoyPool's Sylveon precedent).

Usage:
  python tools/list_pool_candidates.py ICE
  python tools/list_pool_candidates.py GHOST POISON
  python tools/list_pool_candidates.py --species CROBAT NINETALES   # look up

This tree has no DARK or STEEL type, so those clauses cannot be expanded here;
they are written by hand from the real-world typing.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TYPE_LINE = re.compile(r"^\s*db\s+(\w+)\s*,\s*(\w+)\s*;\s*type", re.M)
DEX_LINE = re.compile(r"^\s*db\s+DEX_(\w+)", re.M)
FORM_LINE = re.compile(r"^\s*form_record\s+(\w+)\s*,\s*(\d+)", re.M)


def species_types():
    out = {}
    for path in sorted((ROOT / "data/pokemon/base_stats").glob("*.asm")):
        text = path.read_text(encoding="utf-8")
        dex, types = DEX_LINE.search(text), TYPE_LINE.search(text)
        if dex and types:
            out[dex.group(1)] = set(types.groups())
    return out


def form_types():
    out = {}
    for path in sorted((ROOT / "data/pokemon/forms").glob("*.asm")):
        text = path.read_text(encoding="utf-8")
        rec, types = FORM_LINE.search(text), TYPE_LINE.search(text)
        if rec and types:
            out[(rec.group(1), int(rec.group(2)))] = (set(types.groups()), path.stem)
    return out


def species_runs():
    run, out = None, {}
    for raw in (ROOT / "engine/pokemon/rarity.asm").read_text(encoding="utf-8").splitlines():
        line = raw.split(";")[0].strip()
        label = re.match(r"^(Kanto|Johto|Warp)\w*:", line)
        if label:
            run = label.group(1)
            continue
        if re.match(r"^[A-Za-z]\w*:", line):
            run = None
            continue
        mon = re.match(r"^db\s+(\w+)$", line)
        if run and mon:
            out.setdefault(mon.group(1), run)
    return out


def main(argv):
    base, forms, runs = species_types(), form_types(), species_runs()
    if argv[:1] == ["--species"]:
        for name in argv[1:]:
            print(f"{name}: types {sorted(base.get(name, []))}, run {runs.get(name, '?')}")
            for (sp, n), (types, stem) in forms.items():
                if sp == name:
                    print(f"  form {n} ({stem}): types {sorted(types)}")
        return 0
    wanted = {t.upper() for t in argv}
    if not wanted:
        print(__doc__)
        return 1
    by_run = {"Kanto": [], "Johto": [], "Warp": []}
    for name, types in base.items():
        if types & wanted:
            by_run.setdefault(runs.get(name, "?"), []).append(f"\tpool_mon {name}")
    for (name, n), (types, stem) in sorted(forms.items()):
        if types & wanted:
            by_run["Warp"].append(f"\tpool_mon {name}, {n} ; {stem}")
    for run, lines in by_run.items():
        print(f"; --- {run} run ({len(lines)}) ---")
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
