#!/usr/bin/env python3
"""Generate docs/EVOLUTIONS.md: the player-facing evolution guide.

Every evolution is read from the game data (data/pokemon/evos_moves.asm, the
form lists under data/pokemon/form_evos_moves/, and Eevee's EvoStoneForms in
engine/pokemon/evos_moves.asm), through the same parser the balance tools use
(tools/balance/parse.py). Each row is filed under the species group its target
needs, mirroring RogueClassifySpecies (species) and FormJohtoPairs (forms).

The highlights are hand-written below, keyed by from -> to. Each key is checked
against the data, so a renamed or removed evolution fails the run instead of
leaving a stale claim in the guide.

    python3 tools/gen_evolution_doc.py          # rewrite docs/EVOLUTIONS.md
    python3 tools/gen_evolution_doc.py --check  # fail if it is stale (make audit)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "balance"))
sys.path.insert(0, os.path.join(ROOT, "tools", "pyboy_smoke"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import parse  # noqa: E402

OUT = os.path.join(ROOT, "docs", "EVOLUTIONS.md")
GROUP_TITLES = {
    "KANTO": "Kanto",
    "JOHTO": "Johto",
    "WARP": "Time Warp",
}

# Form names that the in-game name table abbreviates without a dash.
NAME_FIXES = {
    "ASANDSHREW": "A-SANDSHREW", "ASANDSLASH": "A-SANDSLASH",
    "AEXEGGUTOR": "A-EXEGGUTOR", "ANINETALES": "A-NINETALES",
    "HGROWLITHE": "H-GROWLITHE", "HELECTRODE": "H-ELECTRODE",
    "GFARFETCHD": "G-FARFETCH'D", "G-MRMIME": "G-MR.MIME",
}
SPECIAL_TITLES = {"MR.MIME": "Mr. Mime", "MR.RIME": "Mr. Rime", "FARFETCH'D": "Farfetch'd",
                  "G-FARFETCH'D": "G-Farfetch'd", "G-MR.MIME": "G-Mr. Mime"}

# --- hand-written highlights (from, to, note) -------------------------------
# Species keys are the parser's: BASE or BASE#form. Eevee's stone branches use
# the form its stone makes (FLAREON#1 = Leafeon, JOLTEON#1 = Espeon, ...).
NEW_BRANCHES = [
    ("SCYTHER", "KLEAVOR", "A second branch, beside the Scizor line"),
    ("SLOWPOKE", "SLOWKING", "Water Stone instead of a trade"),
    ("SLOWPOKE#1", "SLOWKING#1", "Water Stone instead of a trade"),
    ("GLOOM", "BELLOSSOM", "Sun Stone, beside Vileplume's Leaf Stone"),
    ("EXEGGCUTE", "EXEGGUTOR#1", "Moon Stone makes the Alolan form"),
    ("CUBONE", "MAROWAK#1", "Dusk Stone makes the Alolan form"),
    ("KOFFING", "WEEZING#1", "Moon Stone makes the Galarian form"),
    ("PIKACHU", "RAICHU#1", "Moon Stone makes the Alolan form"),
    ("MURKROW", "MURKROW#1", "Dusk Stone makes Honchkrow"),
    ("URSARING", "URSARING#1", "Moon Stone makes Ursaluna"),
]
LEVEL_REPLACEMENTS = [
    ("TOGEPI", "TOGETIC", "Level-up instead of friendship"),
    ("GOLBAT", "CROBAT", "Level-up instead of friendship"),
    ("CHANSEY", "BLISSEY", "Level-up instead of friendship"),
    ("LICKITUNG", "LICKILICKY", "Level-up instead of knowing Rollout"),
    ("TANGELA", "TANGROWTH", "Level-up instead of knowing Ancient Power"),
    ("PRIMEAPE", "ANNIHILAPE", "Level-up instead of using Rage Fist"),
    ("PILOSWINE", "MAMOSWINE", "Level-up instead of knowing Ancient Power"),
]
STONE_VERSIONS = [
    ("MAGMAR", "MAGMORTAR"),
    ("MAGNETON", "MAGNEZONE"),
    ("SNEASEL", "WEAVILE"),
    ("MISDREAVUS", "MISMAGIUS"),
    ("SUNKERN", "SUNFLORA"),
]
EEVEE_BRANCHES = [
    ("EEVEE", "FLAREON"), ("EEVEE", "JOLTEON"), ("EEVEE", "VAPOREON"),
    ("EEVEE", "FLAREON#1"), ("EEVEE", "JOLTEON#1"), ("EEVEE", "JOLTEON#2"),
    ("EEVEE", "VAPOREON#1"), ("EEVEE", "VAPOREON#2"),
]
FORM_ONLY_LINES = [
    ("FARFETCHD#1", "SIRFETCHD", "Galarian Farfetch'd only"),
    ("MR_MIME#1", "MR_RIME", "Galarian Mr. Mime only"),
    ("QWILFISH#1", "QWILFISH#2", "Hisuian Qwilfish only"),
    ("TENTACOOL#1", "TENTACRUEL#1", "Toedscool becomes Toedscruel"),
    ("DIGLETT#2", "DUGTRIO#2", "Wiglett becomes Wugtrio"),
    ("MEOWTH#2", "PERSIAN#2", "Galarian Meowth becomes Perrserker"),
    ("WOOPER#1", "QUAGSIRE#1", "Paldean Wooper becomes Clodsire"),
]
# Everything listed under Highlights, for the star marker in the full tables.
# Not "differs from the main games": Bellossom, Mismagius and Sunflora are
# canon stone evolutions, highlighted for context.
CUSTOM = {(a, b) for table in (NEW_BRANCHES, LEVEL_REPLACEMENTS, STONE_VERSIONS, FORM_ONLY_LINES)
          for a, b, *_ in table} | set(EEVEE_BRANCHES)


# --- data -------------------------------------------------------------------

def monster_names():
    """internal id -> in-game name, from data/pokemon/names.asm (positional)."""
    names = re.findall(r'^\s*dname "([^"]+)"', open(os.path.join(ROOT, "data", "pokemon", "names.asm"),
                                                    encoding="utf-8").read(), re.M)
    return names


def title(name):
    name = NAME_FIXES.get(name, name)
    if name in SPECIAL_TITLES:
        return SPECIAL_TITLES[name]
    return "-".join(part.capitalize() for part in name.split("-"))


def item_title(const):
    return " ".join(word.capitalize() for word in const.split("_"))


def eevee_stone_forms():
    """EvoStoneForms rows: {(stone, target species): form}."""
    text = open(os.path.join(ROOT, "engine", "pokemon", "evos_moves.asm"), encoding="utf-8").read()
    block = re.search(r"^EvoStoneForms:(.*?)^\s*db 0\b", text, re.M | re.S)
    if not block:
        raise SystemExit("EvoStoneForms not found in engine/pokemon/evos_moves.asm")
    rows = re.findall(r"^\s*db ([A-Z_]+),\s*([A-Z_]+),\s*(\d+)", block.group(1), re.M)
    if len(rows) != 5:
        raise SystemExit(f"EvoStoneForms: expected 5 rows, got {len(rows)}")
    return {(stone, species): int(form) for stone, species, form in rows}


def build():
    species = parse.load_species()
    rarity = parse.load_rarity()
    names = monster_names()
    stone_forms = eevee_stone_forms()

    def display(key):
        sp = species.get(key)
        if sp is None:
            raise SystemExit(f"evolution names {key}, which has no species or form record")
        if sp.form:
            return title(sp.display_name)
        if sp.internal_id > len(names):
            raise SystemExit(f"{key}: no entry in data/pokemon/names.asm")
        return title(names[sp.internal_id - 1])

    def group_of(key):
        sp = species[key]
        if sp.form:
            return sp.form_group
        found = parse.classify(rarity, key)
        return found[0] if found else "KANTO"  # a species in no pool is always allowed

    rows = []
    for source_key, sp in species.items():
        for (method, level, target), stone in zip(sp.evos, sp.evo_items):
            if method == parse.EVOLVE_ITEM and "#" not in target:
                form = stone_forms.get((stone, target))
                if form:
                    target = f"{target}#{form}"
            rows.append({"from": source_key, "to": target, "method": method,
                         "level": level, "stone": stone,
                         "group": group_of(target)})
    return species, display, rows


def method_text(row):
    if row["method"] == parse.EVOLVE_ITEM:
        return item_title(row["stone"])
    if row["method"] == parse.EVOLVE_TRADE:
        return f"Level {row['level']} (or trade)"
    return f"Level {row['level']}"


def render():
    species, display, rows = build()
    by_pair = {}
    for row in rows:
        by_pair.setdefault((row["from"], row["to"]), []).append(row)

    def lookup(a, b):
        found = by_pair.get((a, b))
        if not found:
            raise SystemExit(f"highlight {a} -> {b} matches no evolution in the data; "
                             f"update tools/gen_evolution_doc.py")
        return found

    def line(a, b, note, rows_for=None):
        rows_for = rows_for or lookup(a, b)
        method = " / ".join(method_text(r) for r in rows_for)
        return f"| {display(a)} | {display(b)} | {method} | {note} |"

    trades = sorted((r for r in rows if r["method"] == parse.EVOLVE_TRADE),
                    key=lambda r: (display(r["from"]), display(r["to"])))

    out = []
    w = out.append
    w("<!-- Generated by tools/gen_evolution_doc.py from the evolution data. Do not edit by hand. -->")
    w("# Evolutions in Red Rogue")
    w("")
    w("Many evolutions here work differently from the main games. This guide lists every one.")
    w("")
    w("## How evolution works")
    w("")
    w("- **Trade evolutions also happen by level-up.** A Pokémon that evolves by trade in the main games "
      "evolves at the level listed, or instantly in a real trade at any level.")
    w("- **Evolution stones work at any level.**")
    w("- **The Mist Stone** evolves any Pokémon with an evolution into a branch you choose. "
      "On an Eevee it rolls one of the branches your run has unlocked, at random.")
    w("- **Species groups gate evolutions.** An evolution into a Johto or Time Warp species or form "
      "only happens while that group is unlocked and enabled for your run. Forms that already carry "
      "their own form forward (an Alolan Rattata growing into Alolan Raticate) are never blocked.")
    w("- **Fusions and some special forms never evolve.**")
    w("- **The Pokédex shows what is possible right now.** Open an owned Pokémon's entry and press A "
      "through to the last page: it lists only the evolutions your current run allows.")
    w("")
    w("Markers in the tables: ★ is listed under Highlights, ⇄ is a trade evolution "
      "that also works by level-up. Form prefixes: A- Alolan, G- Galarian, H- Hisuian, P- Paldean.")
    w("")
    w("## Highlights")
    w("")
    head = "| From | To | Method | Note |\n|---|---|---|---|"

    w("### New branches")
    w("")
    w("Second branches and regional forms that a stone makes, plus Honchkrow and Ursaluna, "
      "which Red Rogue stores as forms of Murkrow and Ursaring.")
    w("")
    w(head)
    for a, b, note in NEW_BRANCHES:
        w(line(a, b, note))
    w("")
    w("### Level-up replaces a special condition")
    w("")
    w("Evolutions that need friendship, a held item, a known move or a special action in the "
      "main games happen at a level here.")
    w("")
    w(head)
    for a, b, note in LEVEL_REPLACEMENTS:
        w(line(a, b, note))
    w("")
    w("### Stone versions of newer evolutions")
    w("")
    w("Newer evolutions that a stone triggers here.")
    w("")
    w("| From | To | Method |")
    w("|---|---|---|")
    for a, b in STONE_VERSIONS:
        r = lookup(a, b)
        w(f"| {display(a)} | {display(b)} | {' / '.join(method_text(x) for x in r)} |")
    w("")
    w("### Eevee's eight stones")
    w("")
    w("Each stone gives a different Eevee evolution. The Mist Stone rolls one of the branches "
      "your run has unlocked.")
    w("")
    w("| Stone | Evolves into | Needs |")
    w("|---|---|---|")
    for a, b in EEVEE_BRANCHES:
        r = lookup(a, b)[0]
        w(f"| {item_title(r['stone'])} | {display(b)} | {GROUP_TITLES[r['group']]} |")
    w("")
    w("### Trade evolutions that work by level")
    w("")
    w("| From | To | Method |")
    w("|---|---|---|")
    for r in trades:
        w(f"| {display(r['from'])} | {display(r['to'])} | {method_text(r)} |")
    w("")
    w("### Lines only a regional form has")
    w("")
    w(head)
    for a, b, note in FORM_ONLY_LINES:
        w(line(a, b, note))
    w("")
    w("## Every evolution")
    w("")
    w("Grouped by the species group the evolved Pokémon belongs to.")
    w("")
    for group in ("KANTO", "JOHTO", "WARP"):
        group_rows = sorted((r for r in rows if r["group"] == group),
                            key=lambda r: (display(r["from"]), display(r["to"]), r["stone"]))
        w(f"### {GROUP_TITLES[group]}")
        w("")
        if group != "KANTO":
            w(f"Evolutions into {GROUP_TITLES[group]} species and forms. They need that group "
              "unlocked and enabled, except a form growing into its own later form.")
            w("")
        w("| From | To | Method | |")
        w("|---|---|---|---|")
        for r in group_rows:
            marks = ""
            if (r["from"], r["to"]) in CUSTOM:
                marks += "★"
            if r["method"] == parse.EVOLVE_TRADE:
                marks += "⇄"
            w(f"| {display(r['from'])} | {display(r['to'])} | {method_text(r)} | {marks} |")
        w("")
    return "\n".join(out).rstrip("\n") + "\n"


def main():
    text = render()
    if "--check" in sys.argv:
        current = open(OUT, encoding="utf-8", newline="").read() if os.path.exists(OUT) else ""
        if current.replace("\r\n", "\n") != text:
            print("docs/EVOLUTIONS.md is stale: run python3 tools/gen_evolution_doc.py")
            sys.exit(1)
        print("docs/EVOLUTIONS.md is up to date")
        return
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"wrote {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
