#!/usr/bin/env python3
"""Generate the AI's learnset-based move guess tables (AI_T4_REGRET_PLAN E1, 2026-11-18).

For an unrevealed player move slot the AI presumes a STAB attack of each visible type until
the mon reveals one (AIGetPlayerMoveN, engine/battle/ai/ai_accessors.asm). These tables say
WHICH move of that type: the strongest one this species/form could actually carry, from
  - its level-up learnset at or below its level (line-inherited, tools/learnset_legality.py),
  - its tutor list, and
  - the TMs/HMs it learns, each gated by a "ceiling" that rises with run progress: the TM's
    mart rarity class (engine/items/item_rarity.asm) Poke/Great = 1, Ultra = 2, Master = 3.
A species that can carry no damaging move of a type gets no guess for it.

Per (species, form, own type) the candidates are ranked by power x accuracy; an entry is kept
only if no stronger kept entry is available at no higher level and no higher ceiling, so the
runtime takes the FIRST entry that fits. Left out: OHKO, two-turn, self-KO, Super Fang and
Dream Eater (needs a sleeping target). Fixed damage stays, ranked by FIXED_DAMAGE_POWER.

Encoding (engine/battle/ai/ai_guess_learnset.asm reads it): two sections split by species id.
Each has an index (dw per species id from its first to its last) to that species' block:
  per form: db (form << 6) | (n1 << 3) | n2, then n1 entries for the species' first type and
            n2 for its second (0 when mono-typed); entry = db move, info where info < $80 is
            the minimum level and info = $80 | ceiling is a TM;
  db $FF ends the block. A species with no row points at a shared $FF.

    python3 tools/gen_ai_guess_learnset.py          # rewrite the files
    python3 tools/gen_ai_guess_learnset.py --check  # fail if stale (make audit)
"""
import glob
import os
import re
import sys
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tools", "pyboy_smoke"))
import learnset_legality  # noqa: E402
from source_constants import parse_rgbds_constants  # noqa: E402

OUT_DIR = os.path.join(ROOT, "data", "battle")
FILES = ("ai_guess_learnset_split.asm", "ai_guess_learnset_lo.asm", "ai_guess_learnset_hi.asm")
EXCLUDE = {"OHKO_EFFECT", "SUPER_FANG_EFFECT", "CHARGE_EFFECT",
           "FLY_EFFECT", "EXPLODE_EFFECT", "DREAM_EATER_EFFECT"}
# Fixed damage (SPECIAL_DAMAGE_EFFECT) is a real threat the estimator values exactly (Night
# Shade was the old table's Ghost guess, Dragon Rage its Dragon one), but its table power is
# 0/1, so it ranks by an equivalent power: level-based ones ~ a 75-power hit at mid levels.
FIXED_DAMAGE_POWER = {"NIGHT_SHADE": 75, "SEISMIC_TOSS": 75, "DRAGON_RAGE": 60, "SONICBOOM": 35}
MAX_ENTRIES = 7  # 3 bits per row count
CLASS_CEILING = (("pokeball", 1), ("greatball", 1), ("ultraball", 2), ("masterball", 3))


def read(path):
    return open(path, encoding="utf-8").read().replace("\r\n", "\n")


def move_data():
    out = {}
    for m in re.finditer(r"^\s*move\s+(\w+),\s*(\w+),\s*(\d+),\s*(\w+),\s*(\d+)",
                         read(os.path.join(ROOT, "data", "moves", "moves.asm")), re.M):
        name, effect, power, typ, acc = m.groups()
        out[name] = (effect, int(power), typ, int(acc))
    if len(out) < 150:
        raise SystemExit("data/moves/moves.asm: parsed only %d moves" % len(out))
    return out


def tm_ceilings():
    text = read(os.path.join(ROOT, "engine", "items", "item_rarity.asm"))
    out = {}
    for cls, ceiling in CLASS_CEILING:
        block = re.search(r"^tm_%s_class:(.*?)(?=^\w+:)" % cls, text, re.M | re.S)
        if not block:
            raise SystemExit("item_rarity.asm: tm_%s_class not found" % cls)
        for item in re.findall(r"db\s+(?:TM|HM)_(\w+)", block.group(1)):
            out[item] = ceiling
    return out


def own_types():
    out = {}
    for path in (glob.glob(os.path.join(ROOT, "data", "pokemon", "base_stats", "*.asm"))
                 + glob.glob(os.path.join(ROOT, "data", "pokemon", "forms", "*.asm"))):
        text = read(path)
        t = re.search(r"^\s*db\s+(\w+),\s*(\w+)\s*;\s*type", text, re.M)
        s = learnset_legality._stats_file(path)
        key = s["form"] if s["form"] else s["dex"]
        if t and key:
            out[key] = (t.group(1), t.group(2))
    return out


def rows():
    moves, ceilings, types = move_data(), tm_ceilings(), own_types()
    full, lvl = learnset_legality.load(), learnset_legality.load(levelup_only=True)
    out = {}
    for key, learnable in full.items():
        if key not in types:
            continue
        t1, t2 = types[key]
        per_type = []
        for typ in ((t1,) if t1 == t2 else (t1, t2)):
            cands = []
            for mv in learnable:
                info = moves.get(mv)
                if not info or info[2] != typ or info[0] in EXCLUDE:
                    continue
                power = FIXED_DAMAGE_POWER.get(mv, info[1]) if info[0] == "SPECIAL_DAMAGE_EFFECT" else info[1]
                if power < 2:
                    continue
                strength = power * info[3]
                if mv in lvl.get(key, {}):
                    cands.append((max(1, lvl[key][mv]), 0, strength, mv))
                elif mv in ceilings:
                    cands.append((1, ceilings[mv], strength, mv))
                else:
                    cands.append((1, 0, strength, mv))  # tutor
            cands.sort(key=lambda c: (-c[2], c[0], c[1], c[3]))
            kept = []
            for c in cands:
                if not any(k[0] <= c[0] and k[1] <= c[1] for k in kept):
                    kept.append(c)
            per_type.append(kept[:MAX_ENTRIES])
        out[key] = per_type
    return out


def render():
    species = parse_rgbds_constants(Path(ROOT) / "constants" / "pokemon_constants.asm")
    by_id = {}
    for key, per_type in rows().items():
        name, form = (key, 0) if isinstance(key, str) else key
        ident = species.get(name)
        if not ident:
            continue
        by_id.setdefault(ident, (name, []))[1].append((form, per_type))
    ids = sorted(by_id)
    size = {i: sum(1 + 2 * sum(len(r) for r in pt) for _, pt in by_id[i][1]) + 1 for i in ids}
    total, half, split = sum(size.values()), 0, ids[-1]
    for i in ids:  # first species id of the high section: balances the bytes
        half += size[i]
        if half * 2 >= total:
            split = i + 1
            break
    header = ["; Generated by tools/gen_ai_guess_learnset.py. Do not edit: rerun the script",
              "; (make audit fails while this file is stale)."]
    lo_ids = [i for i in ids if i < split]
    hi_ids = [i for i in ids if i >= split]
    split_file = header + ["; Species id ranges of the two sections (low: first..split-1, high: split..last).",
                           "DEF AI_GUESS_LO_FIRST EQU $%02x" % lo_ids[0],
                           "DEF AI_GUESS_SPLIT_SPECIES EQU $%02x" % split,
                           "DEF AI_GUESS_HI_LAST EQU $%02x" % hi_ids[-1]]

    def table(lo, hi, label):
        lines = header + ["; Index: dw per species id $%02x..$%02x." % (lo, hi), label + "Index:"]
        for i in range(lo, hi + 1):
            lines.append("\tdw %s" % ((label + "_%02x" % i) if i in by_id else label + "None"))
        lines.append(label + "None:")
        lines.append("\tdb $ff")
        for i in range(lo, hi + 1):
            if i not in by_id:
                continue
            name, forms = by_id[i]
            lines.append(label + "_%02x: ; %s" % (i, name))
            for form, per_type in sorted(forms):
                n1 = len(per_type[0])
                n2 = len(per_type[1]) if len(per_type) > 1 else 0
                lines.append("\tdb (%d << 6) | (%d << 3) | %d" % (form, n1, n2))
                for kept in per_type:
                    for level, ceiling, _, mv in kept:
                        info = "$80 | %d" % ceiling if ceiling else "%d" % level
                        lines.append("\tdb %s, %s" % (mv, info))
            lines.append("\tdb $ff")
        return "\n".join(lines) + "\n"

    return {
        FILES[0]: "\n".join(split_file) + "\n",
        FILES[1]: table(lo_ids[0], lo_ids[-1], "AIGuessLo"),
        FILES[2]: table(hi_ids[0], hi_ids[-1], "AIGuessHi"),
    }


def main():
    texts = render()
    if "--check" in sys.argv:
        stale = [f for f, t in texts.items()
                 if not os.path.exists(os.path.join(OUT_DIR, f))
                 or read(os.path.join(OUT_DIR, f)) != t]
        if stale:
            print("stale: %s (run python3 tools/gen_ai_guess_learnset.py)" % ", ".join(stale))
            return 1
        print("ai_guess_learnset tables are current")
        return 0
    for f, t in texts.items():
        with open(os.path.join(OUT_DIR, f), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(t)
        print("wrote", f, len(t.splitlines()), "lines")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
