"""Moveset and enemy-rarity mirror for the balance model.

What an enemy trainer's four moves would be, slot by slot, for the battles
model.py simulates, and which rarity class each enemy mon belongs to. Mirrors,
by reading the same source the ROM is built from (nothing is a copied literal):

  mix rows        MovesetMixTable           data/trainers/party_specs.asm
  mix per battle  RogueRosterMixId / GymMixByBand / stage_event_mix /
                  e4_member_records / champion_spec      (same file + engine)
  slot sources    PartyGenAssignSources     engine/battle/rogue_build_party.asm
  curated sets    PartyGenApplySetMovesetMask (.recordPasses: exact window,
                  then lvl_max + SET_LEVEL_SLACK_BELOW)  data/trainers/movesets.asm
  generated roll  PartyGenRollMoveset / PartyGenPickOne / PartyGenDrawCandidate /
                  PartyGenApplyRequireFlags   (MoveRankByID, MoveFlagsByID,
                  MoveRankWeightTable, TMMovesForPartyGen in data/moves/move_ranks.asm)
  vanilla moves   WriteMonMoves (MSRC_LEARNSET, and every wild mon)
  candidates      GetLevelUpMovesFar: the mon's own (form-aware) level-1 moves,
                  then its own learnset at or below its level, deduplicated

Not modelled: Gambler's Paradise, Money Match / PokeManiac step overrides,
slot overrides that claim a source (no shipping spec has one), the Challenge
11 legendary boss ace, SpecialTrainerMoves, the Psychic's stolen mon.

Moves roll on the caller's RNG. model.py never calls this module, so the level
and money outputs are unaffected by it; use summarize() on finished runs.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import random
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import learnset_legality  # noqa: E402
import model  # noqa: E402
import parse  # noqa: E402

SOURCES = ("LEARNSET", "LEARNSET_FULL", "RANDOM", "RANDOM_TM", "RANDOM_TM_ONLY", "SET")
MSRC = {name: i for i, name in enumerate(SOURCES)}
RANKS = ("F", "D", "C", "B", "A", "S", "OFFLIST")
OFFLIST = RANKS.index("OFFLIST")
MAX_DRAWS = 40        # PARTY_GEN_MAX_DRAWS, checked against the source in load()
MAX_CANDIDATES = 16   # PARTY_GEN_MAX_CANDIDATES, likewise
# The summary's spread categories: what a slot's moves finally came from.
CATEGORY = {"SET": "Set", "RANDOM_TM": "Random+TM", "RANDOM_TM_ONLY": "Random+TM",
            "RANDOM": "Random", "LEARNSET": "Learnset", "LEARNSET_FULL": "Learnset"}
CATEGORIES = ("Set", "Random+TM", "Random", "Learnset")
KIND_GROUP = {"route": "Route", "route_final": "Trainer", "gym_trainer": "Trainer",
              "gym_final": "Trainer", "leader": "Leader", "miniboss": "Mini-boss",
              "victory_road": "Mini-boss", "stage_event": "Stage event",
              "e4": "E4/Champ", "champion": "E4/Champ"}
KINDS = ("Route", "Trainer", "Leader", "Mini-boss", "Stage event", "E4/Champ")
CLASS_NAMES = ("Poke", "Great", "Ultra", "Master", "Uber")
LEGENDARY_BIRDS = ("ZAPDOS", "ARTICUNO", "MOLTRES")


# =============================================================================
# Source parsing
# =============================================================================

def _code(line: str) -> str:
    return line.split(";", 1)[0].strip()


def _lines(rel: str) -> list[str]:
    return (ROOT / rel).read_text(encoding="utf-8").splitlines()


def _expr(text: str, names: dict[str, int]) -> int:
    """An rgbds integer expression with |, &, <<, ~ and names (the subset the
    mix rows and flag DEFs use)."""
    s = re.sub(r"\$([0-9A-Fa-f]+)", r"0x\1", text.strip())
    s = re.sub(r"%([01]+)", r"0b\1", s)

    def name(m):
        if m.group(0) not in names:
            raise ValueError(f"unknown name {m.group(0)!r} in {text!r}")
        return str(names[m.group(0)])
    s = re.sub(r"\b[A-Za-z_][A-Za-z0-9_]*\b", lambda m: m.group(0) if m.group(0).startswith(("0x", "0b")) else name(m), s)
    if not re.fullmatch(r"[0-9a-fA-FxXb()|&<>~+\-\s]+", s):
        raise ValueError(f"unsupported expression {text!r}")
    return int(eval(s, {"__builtins__": {}}, {}))


def _constants(rel: str, known: dict[str, int] | None = None) -> dict[str, int]:
    """const_def/const runs plus every DEF ... EQU / = the expression parser can
    evaluate, in file order (later DEFs may use earlier ones)."""
    out = dict(known or {})
    cur = 0
    for raw in _lines(rel):
        line = _code(raw)
        if line.startswith("const_def"):
            rest = line[len("const_def"):].strip()
            cur = _expr(rest, out) if rest else 0
            continue
        m = re.match(r"const\s+(\w+)$", line)
        if m:
            out[m.group(1)] = cur
            cur += 1
            out["const_value"] = cur
            continue
        m = re.match(r"DEF\s+(\w+)\s+(?:EQU|=)\s+(.+)$", line)
        if m:
            try:
                out[m.group(1)] = _expr(m.group(2), out)
            except (ValueError, SyntaxError):
                pass
    return out


@dataclass
class MixRow:
    name: str
    quotas: tuple[int, ...]   # per MSRC_LEARNSET .. MSRC_SET
    tier_mask: int
    rank_row: int
    tm_cap: int
    require: int
    forbid: int
    fallback: int


@dataclass
class Mon:
    l1: list[str]                       # base-stats level-1 moves, in order
    levelup: list[tuple[int, str]]      # own learnset, file order
    tms: list[str]                      # TM/HM moves, TMMovesForPartyGen bit order


@dataclass
class SetRecord:
    moves: tuple[str, str, str, str]
    tier: int
    lo: int
    hi: int
    origin: int = 0           # its LossOriginLabels index (wEnemyMoveOrigins)


@dataclass
class Data:
    consts: dict[str, int]
    mixes: list[MixRow]
    mix_id: dict[str, int]
    route_band: list[int]      # ROUTE_BAND<n>_MIX, n = 1..NUM_GYM_BANDS
    trainer_band: list[int]
    gym_band: list[int]
    stage_cuts: list[tuple[int, int]]   # (highest tier, mix id); last = ELSE
    e4_mix: int
    champion_mix: int
    weights: list[list[int]]   # MoveRankWeightTable[rank_row][rank]
    rank: dict[str, int]
    flags: dict[str, int]
    tm_order: list[str]
    mons: dict[tuple[str, int], Mon]
    sets: dict[tuple[str, int], list[SetRecord]]
    slack: int
    gym_band_rounds: int
    num_bands: int
    tm_gate: list[int]         # TMGateLevelByRank: TM_GATE_LEVEL_<grade>, F .. S
    # DifficultyMovesetMods per model.DIFFICULTIES name:
    # (set percent, rank_row delta, tm_cap delta, TM gate shift)
    diff_mods: dict[str, tuple[int, int, int, int]] = field(default_factory=dict)


def _mix_rows(consts: dict[str, int]) -> tuple[list[MixRow], dict[str, int]]:
    lines = _lines("data/trainers/party_specs.asm")
    start = next(i for i, l in enumerate(lines) if l.startswith("MovesetMixTable::"))
    rows = []
    for raw in lines[start + 1:]:
        if "assert_table_length" in raw:
            break
        code = _code(raw)
        if not code.startswith("mix "):
            continue
        args = [a.strip() for a in code[4:].split(",")]
        if len(args) != 12:
            raise ValueError(f"mix row with {len(args)} arguments: {raw!r}")
        v = [_expr(a, consts) for a in args]
        name = raw.split(";", 1)[1].strip() if ";" in raw else f"ROW{len(rows)}"
        rows.append(MixRow(name, tuple(v[:6]), v[6], v[7], v[8], v[9], v[10], v[11]))
    ids = {k[len("MIX_"):]: v for k, v in consts.items() if k.startswith("MIX_") and k != "MIX_ENTRY_SIZE"
           and k != "MIX_FALLBACK_OFFSET" and k != "MIX_ONLY_SPEC_SIZE"}
    if len(rows) != consts["NUM_MOVESET_MIXES"]:
        raise ValueError(f"parsed {len(rows)} mix rows, NUM_MOVESET_MIXES is {consts['NUM_MOVESET_MIXES']}")
    for name, i in ids.items():
        if i < len(rows) and rows[i].name != name:
            raise ValueError(f"mix row {i} is commented {rows[i].name}, constant says {name}")
    return rows, ids


def _macro_body(lines: list[str], name: str) -> list[str]:
    i = next(i for i, l in enumerate(lines) if re.match(rf"MACRO\s+{name}\b", l.strip()))
    body = []
    for raw in lines[i + 1:]:
        if raw.strip().startswith("ENDM"):
            return body
        body.append(_code(raw))
    raise ValueError(f"MACRO {name} has no ENDM")


def _stage_cuts(lines: list[str], ids: dict[str, int]) -> list[tuple[int, int]]:
    """stage_event_mix: IF (\\1) <= N / ELIF ... / ELSE, each with DEF _semix = MIX_X."""
    cuts, limit = [], None
    for code in _macro_body(lines, "stage_event_mix"):
        m = re.match(r"(?:IF|ELIF)\s+\(\\1\)\s*<=\s*(\d+)", code)
        if m:
            limit = int(m.group(1))
        elif code == "ELSE":
            limit = 99
        m = re.match(r"DEF\s+_semix\s*=\s*MIX_(\w+)", code)
        if m:
            cuts.append((limit, ids[m.group(1)]))
    if not cuts or cuts[-1][0] != 99:
        raise ValueError(f"stage_event_mix did not parse: {cuts}")
    return cuts


def _macro_mix(lines: list[str], name: str, ids: dict[str, int]) -> int:
    for code in _macro_body(lines, name):
        m = re.search(r"\bMIX_(\w+)", code)
        if m:
            return ids[m.group(1)]
    raise ValueError(f"MACRO {name} names no mix row")


def _move_tables() -> tuple[dict[str, int], dict[str, int], list[list[int]]]:
    rank, flags, weights, mode = {}, {}, [], None
    for raw in _lines("data/moves/move_ranks.asm"):
        code = _code(raw)
        if code.endswith("::"):
            mode = code[:-2]
            continue
        cmt = (raw.split(";", 1)[1].split() or [""])[0] if ";" in raw else ""
        if mode == "MoveRankByID":
            m = re.match(r"db MOVE_RANK_(\w+)$", code)
            if m:
                rank[cmt] = RANKS.index(m.group(1))
        elif mode == "MoveFlagsByID":
            m = re.match(r"dw\s+(\S+)$", code)
            if m:
                flags[cmt] = parse._int(m.group(1))
        elif mode == "MoveRankWeightTable":
            m = re.match(r"db\s+([\d,\s]+)$", code)
            if m:
                weights.append([int(x) for x in m.group(1).split(",")])
    if not rank or not flags or not weights:
        raise ValueError("move_ranks.asm: a table did not parse")
    return rank, flags, weights


def _tm_order() -> list[str]:
    """TMMovesForPartyGen: TM01..NUM_TMS, then HM01..NUM_HMS."""
    tms, hms = [], []
    for raw in _lines("constants/item_constants.asm"):
        m = re.match(r"\s*add_tm\s+(\w+)", raw)
        if m:
            tms.append(m.group(1))
        m = re.match(r"\s*add_hm\s+(\w+)", raw)
        if m:
            hms.append(m.group(1))
    return tms + hms


def _l1_ordered(text: str) -> list[str]:
    for line in text.splitlines():
        if "level 1 learnset" in line:
            return [t for t in re.findall(r"\b[A-Z][A-Z0-9_]+\b", _code(line)) if t != "NO_MOVE"]
    return []


def _levelup(lines: list[str]) -> list[tuple[int, str]]:
    out, section = [], 0
    for raw in lines:
        code = _code(raw)
        if not code:
            continue
        if re.fullmatch(r"db\s+0", code):
            section += 1
            if section == 2:
                break
            continue
        if section == 1:
            m = re.match(r"db\s+(\d+)\s*,\s*(\w+)", code)
            if m:
                out.append((int(m.group(1)), m.group(2)))
    return out


def _record_bodies(rel: str, suffix: str) -> dict[str, list[str]]:
    out, cur = {}, None
    for raw in _lines(rel):
        m = re.match(r"^(\w+)" + suffix + r":", raw)
        if m:
            cur = m.group(1).lower()
            out[cur] = []
        elif cur:
            out[cur].append(raw)
    return out


def _mons(tm_order: list[str]) -> dict[tuple[str, int], Mon]:
    """(species, form) -> the mon GetMonHeader + GetEvosMovesEntry describe."""
    order = {mv: i for i, mv in enumerate(tm_order)}
    evos = _record_bodies("data/pokemon/evos_moves.asm", "EvosMoves")
    form_evos: dict[str, list[str]] = {}
    for path in sorted((ROOT / "data/pokemon/form_evos_moves").glob("*.asm")):
        form_evos.update(_record_bodies(str(path.relative_to(ROOT)), "FormEvosMoves"))
    out: dict[tuple[str, int], Mon] = {}
    for path in sorted((ROOT / "data/pokemon/base_stats").glob("*.asm")):
        s = learnset_legality._stats_file(str(path))
        if not s["dex"]:
            continue
        text = path.read_text(encoding="utf-8")
        lv = _levelup(evos.get(s["dex"].replace("_", "").lower(), []))
        out[(s["dex"], 0)] = Mon(_l1_ordered(text), lv, sorted((m for m in s["tm"] if m in order), key=order.get))
    for path in sorted((ROOT / "data/pokemon/forms").glob("*.asm")):
        s = learnset_legality._stats_file(str(path))
        if not s["form"]:
            continue
        text = path.read_text(encoding="utf-8")
        base = out[(s["form"][0], 0)]
        # GetEvosMovesEntry: a form with no FormEvosMovesPointers entry keeps
        # its base species' learnset.
        lv = _levelup(form_evos[path.stem]) if path.stem in form_evos else base.levelup
        out[s["form"]] = Mon(_l1_ordered(text), lv, sorted((m for m in s["tm"] if m in order), key=order.get))
    return out


def _sets(consts: dict[str, int]) -> dict[tuple[str, int], list[SetRecord]]:
    lines = _lines("data/trainers/movesets.asm")
    form_of = {}
    for i, raw in enumerate(lines):
        m = re.match(r"\s*dw (MovesetForm_\w+)", raw)
        if m:
            sp, fi = re.match(r"\s*db (\w+), (\d+)", lines[i - 1]).groups()
            form_of[m.group(1)] = (sp, int(fi))
    out: dict[tuple[str, int], list[SetRecord]] = collections.defaultdict(list)
    key = None
    rec = re.compile(r"db (\w+), (\w+), (\w+), (\w+), ([A-Z_0-9| ]+), (\d+), (\d+), (\d+)$")
    for raw in lines:
        m = re.match(r"(?:Moveset_(\w+)|(MovesetForm_\w+))::", raw)
        if m:
            key = (m.group(1), 0) if m.group(1) else form_of[m.group(2)]
            continue
        m = rec.match(_code(raw))
        if m and key:
            out[key].append(SetRecord(m.group(1, 2, 3, 4), _expr(m.group(5), consts),
                                      int(m.group(7)), int(m.group(8)), int(m.group(6))))
    return dict(out)


def load() -> Data:
    consts = _constants("constants/party_spec_constants.asm")
    consts = _constants("constants/balance_constants.asm", {**parse.load_round_constants(), **consts})
    consts = _constants("data/trainers/party_specs.asm", consts)
    for name, want in (("PARTY_GEN_MAX_DRAWS", MAX_DRAWS), ("PARTY_GEN_MAX_CANDIDATES", MAX_CANDIDATES)):
        if consts[name] != want:
            raise ValueError(f"{name} is {consts[name]} in the source, movesets.py assumes {want}")
    mixes, ids = _mix_rows(consts)
    lines = _lines("data/trainers/party_specs.asm")
    nb = consts["NUM_GYM_BANDS"]
    rank, flags, weights = _move_tables()
    tm_order = _tm_order()
    if len(tm_order) != consts.get("NUM_TM_HM", len(tm_order)):
        raise ValueError("TM/HM list length disagrees with NUM_TM_HM")
    return Data(
        consts=consts, mixes=mixes, mix_id=ids,
        route_band=[consts[f"ROUTE_BAND{n}_MIX"] for n in range(1, nb + 1)],
        trainer_band=[consts[f"TRAINER_BAND{n}_MIX"] for n in range(1, nb + 1)],
        gym_band=[consts[f"GYM_BAND{n}_MIX"] for n in range(1, nb + 1)],
        stage_cuts=_stage_cuts(lines, ids),
        e4_mix=_macro_mix(lines, "e4_member_records", ids),
        champion_mix=_macro_mix(lines, "champion_spec", ids),
        weights=weights, rank=rank, flags=flags, tm_order=tm_order,
        mons=_mons(tm_order), sets=_sets(consts),
        slack=consts["SET_LEVEL_SLACK_BELOW"], gym_band_rounds=consts["GYM_BAND_ROUNDS"], num_bands=nb,
        tm_gate=[consts[f"TM_GATE_LEVEL_{g}"] for g in RANKS[:OFFLIST]],
        diff_mods={name: tuple(consts[f"DIFF_{knob}_{name.upper()}"]
                               for knob in ("SET_PCT", "RANK_DELTA", "TM_CAP_DELTA", "TM_GATE_SHIFT"))
                   for name in model.DIFFICULTIES},
    )


# =============================================================================
# Which mix row a battle uses
# =============================================================================

def mix_for(d: Data, g: parse.GameData, b: model.Battle) -> int | None:
    """None = no mix: vanilla moves (wild mons, the authored Oak's Lab rival)."""
    k = g.knobs
    if b.kind in ("route", "route_final", "gym_trainer", "gym_final"):
        # RogueRosterMixId: kind row by step, band by round index.
        idx, step = model.round_of(g, b.count), model.step_of(g, b.count)
        band = min(idx // d.gym_band_rounds, d.num_bands - 1)
        return (d.route_band if step < k["FINAL_ROUTE_STEP"] else d.trainer_band)[band]
    if b.kind in ("leader", "miniboss", "victory_road"):
        band = min((b.spec_round - 1) // d.gym_band_rounds, d.num_bands - 1)
        return d.gym_band[band]
    if b.kind == "stage_event":
        return next(mix for limit, mix in d.stage_cuts if b.spec_round <= limit)
    if b.kind == "e4":
        return d.e4_mix
    if b.kind == "champion":
        return d.champion_mix
    return None


def battle_round(g: parse.GameData, b: model.Battle) -> int:
    """1-9: the gym the battle is fought towards (9 = Victory Road and later)."""
    if b.kind in ("e4", "champion"):
        return 9
    return b.spec_round or model.round_of(g, b.count) + 1


# =============================================================================
# The ROM's routines
# =============================================================================

def assign_sources(mix: MixRow, n: int, ace_last: bool, rng: random.Random) -> list[int]:
    """PartyGenAssignSources: ace claim, then quotas strongest first onto random
    free slots, then the fallback for whatever is left."""
    q = list(mix.quotas)
    src: list[int | None] = [None] * n
    if ace_last and n:
        for s in range(len(q) - 1, -1, -1):
            if q[s]:
                src[n - 1] = s
                q[s] -= 1
                break
    for s in range(len(q) - 1, -1, -1):
        for _ in range(q[s]):
            free = [i for i in range(n) if src[i] is None]
            if not free:
                break
            src[free[rng.randrange(len(free))]] = s
    return [mix.fallback if s is None else s for s in src]


def vanilla_moves(mon: Mon, level: int) -> list[str]:
    """WriteMonMoves for an enemy mon: the level-1 moves, then each learnset move
    at or below the level not already known, into the first empty slot or, with
    four known, shifting the oldest out."""
    moves = list(mon.l1[:4])
    for lv, mv in mon.levelup:
        if lv > level:
            break
        if mv in moves:
            continue
        if len(moves) < 4:
            moves.append(mv)
        else:
            moves = moves[1:] + [mv]
    return moves


def level_candidates(mon: Mon, level: int) -> list[str]:
    """GetLevelUpMovesFar."""
    out: list[str] = []
    for mv in mon.l1[:4] + [m for lv, m in mon.levelup if lv <= level]:
        if mv not in out and len(out) < MAX_CANDIDATES:
            out.append(mv)
    return out


def set_records(d: Data, key: tuple[str, int], level: int, mask: int, slack: int) -> list[SetRecord]:
    """.recordPasses: tier & mask, lvl_min <= level <= lvl_max + slack."""
    return [r for r in d.sets.get(key, ()) if r.tier & mask and r.lo <= level <= r.hi + slack]


def for_difficulty(d: Data, mix: MixRow, difficulty: str) -> tuple[MixRow, int]:
    """The row PartyGenRankWeight / PartyGenTMCapReached actually read under a
    difficulty (DifficultyMovesetMods, clamped), and PartyGenTMGated's gate shift."""
    _, rank, cap, shift = d.diff_mods[difficulty]
    row = min(max(mix.rank_row + rank, 0), len(d.weights) - 1)
    return dataclasses.replace(mix, rank_row=row, tm_cap=min(max(mix.tm_cap + cap, 0), 4)), shift


def roll_generated(d: Data, mix: MixRow, mon: Mon, level: int, source: int,
                   rng: random.Random, gate_shift: int = 0) -> list[str]:
    """PartyGenRollMoveset for MSRC_LEARNSET_FULL / RANDOM / RANDOM_TM / RANDOM_TM_ONLY.
    mix is the difficulty-adjusted row (for_difficulty)."""
    lvl = level_candidates(mon, level)
    lvl_set = set(lvl)
    all_tms = mon.tms if source in (MSRC["RANDOM_TM"], MSRC["RANDOM_TM_ONLY"]) else []
    tms = list(all_tms)
    weights = d.weights[mix.rank_row if mix.rank_row < len(d.weights) else 0]
    chosen: list[str] = []
    used = 0

    def draw() -> tuple[str | None, int]:
        if source == MSRC["RANDOM_TM_ONLY"] and tms:
            mv = tms[rng.randrange(len(tms))]
            seg_tm = True
        else:
            total = len(lvl) + len(tms)
            if not total:
                return None, 0
            i = rng.randrange(total)
            seg_tm = i >= len(lvl)
            mv = tms[i - len(lvl)] if seg_tm else lvl[i]
        r = d.rank.get(mv, OFFLIST)
        if seg_tm and mv not in lvl_set:
            # PartyGenTMCapReached, then PartyGenTMGated
            if used >= mix.tm_cap or (r != OFFLIST and level < d.tm_gate[r] + gate_shift):
                return None, 0
        if mv in chosen or r == OFFLIST or d.flags.get(mv, 0) & mix.forbid:
            return None, 0
        w = weights[r]
        return (mv, w) if w else (None, 0)

    def pick_one() -> str | None:
        nonlocal used
        last = None
        for _ in range(MAX_DRAWS):
            mv, w = draw()
            if mv is None:
                continue
            last = mv
            if source == MSRC["LEARNSET_FULL"] or rng.randrange(64) < w:
                break
        else:
            if last is None:
                return None
        if last not in lvl_set:
            used += 1
        return last

    while len(chosen) < 4:
        mv = pick_one()
        if mv is None:
            if source == MSRC["RANDOM_TM_ONLY"] and tms:
                tms = []                          # .poolDry: the level-up fallback
                continue
            break
        chosen.append(mv)
    if not chosen:
        chosen = vanilla_moves(mon, level)        # .movesFinal: keep AddPartyMon's four
    return apply_require(d, mix, chosen, lvl, all_tms)


def apply_require(d: Data, mix: MixRow, moves: list[str], lvl: list[str], tms: list[str]) -> list[str]:
    """PartyGenApplyRequireFlags: one move carrying a required flag, if any
    candidate has one; it fills an empty slot, else the weakest move's."""
    if not mix.require or any(d.flags.get(m, 0) & mix.require for m in moves):
        return moves
    slots = moves + [None] * (4 - len(moves))
    if None in slots:
        target = slots.index(None)
    else:
        ranks = [d.rank.get(m, 0) for m in slots]
        target = ranks.index(min(ranks))
    for mv in lvl + tms:
        if (mv not in moves and d.rank.get(mv, OFFLIST) != OFFLIST
                and not d.flags.get(mv, 0) & mix.forbid and d.flags.get(mv, 0) & mix.require):
            slots[target] = mv
            break
    return [m for m in slots if m]


def could_generate(d: Data, mix: MixRow, mon: Mon, level: int, source: int, moves: list[str],
                   gate_shift: int = 0) -> bool:
    """Whether roll_generated(source) can produce exactly these moves (in any
    order of draws): every move a distinct, eligible candidate of the source's
    pool, at most tm_cap TM-only moves (one more if a require-flag move was
    added after the roll), or AddPartyMon's vanilla four when nothing was picked."""
    if moves == vanilla_moves(mon, level):
        return True
    lvl = level_candidates(mon, level)
    pool = set(lvl) | (set(mon.tms) if source in (MSRC["RANDOM_TM"], MSRC["RANDOM_TM_ONLY"]) else set())
    weights = d.weights[mix.rank_row if mix.rank_row < len(d.weights) else 0]
    if len(set(moves)) != len(moves) or not moves or not set(moves) <= pool:
        return False
    required = [m for m in moves if d.flags.get(m, 0) & mix.require] if mix.require else []
    for m in moves:
        r = d.rank.get(m, OFFLIST)
        if r == OFFLIST or d.flags.get(m, 0) & mix.forbid:
            return False
        if not weights[r] and m not in required:
            return False
    tm_only = [m for m in moves if m not in lvl]
    # The require pass (apply_require) checks neither tm_cap nor the TM gate.
    if any(level < d.tm_gate[d.rank[m]] + gate_shift for m in tm_only if m not in required):
        return False
    return len(tm_only) <= mix.tm_cap + (1 if any(m not in lvl for m in required) else 0)


@dataclass
class SlotMoves:
    species: str
    level: int
    claimed: str            # the source the slot was dealt
    source: str             # the source its moves finally came from
    set_result: str | None  # SET slots: exact / widened / fallback / skipped
    moves: list[str]
    tm_only: list[str] = field(default_factory=list)   # moves not learnable by level-up by now


def battle_movesets(d: Data, g: parse.GameData, cfg: model.Config, b: model.Battle,
                    rng: random.Random) -> list[SlotMoves] | None:
    """Every enemy mon's moves for one battle; None if the battle has no mix."""
    mix_id = mix_for(d, g, b)
    if mix_id is None or not b.trainer:
        return None
    mix = d.mixes[mix_id]
    rolled, gate_shift = for_difficulty(d, mix, cfg.difficulty)
    set_pct = d.diff_mods[cfg.difficulty][0]
    if mix.tier_mask & (d.consts["TIER_GAMBLER"] | d.consts["TIER_SIGNATURE_7"]):
        set_pct = 100                    # PartyGenDiffAllowsSet: a character's own sets
    out = []
    for (name, level), src in zip(b.mons, assign_sources(mix, len(b.mons), b.ace_last, rng)):
        sp = g.species[name]
        key = (sp.base_species, sp.form)
        mon = d.mons[key]
        claimed, result, moves = SOURCES[src], None, None
        if src == MSRC["SET"]:
            if rng.randrange(100) >= set_pct:
                result = "skipped"       # PartyGenDiffAllowsSet lost (VERY EASY: always)
            else:
                for slack, label in ((0, "exact"), (d.slack, "widened")):
                    recs = set_records(d, key, level, mix.tier_mask, slack)
                    if recs:
                        moves = [m for m in recs[rng.randrange(len(recs))].moves if m != "NO_MOVE"]
                        result = label
                        break
                else:
                    result = "fallback"
            if moves is None:
                src = mix.fallback
        if moves is None:
            moves = vanilla_moves(mon, level) if src == MSRC["LEARNSET"] else \
                roll_generated(d, rolled, mon, level, src, rng, gate_shift)
        lv = set(level_candidates(mon, level))
        out.append(SlotMoves(name, level, claimed, SOURCES[src], result, moves,
                             [m for m in moves if m not in lv]))
    return out


# =============================================================================
# Summary
# =============================================================================

def _pct(n: int, t: int) -> str:
    return f"{100 * n / t:.0f}%" if t else "-"


def summarize(d: Data, g: parse.GameData, cfg: model.Config, runs: list[model.Run],
              seed: int = 1) -> dict:
    """Per (round, kind group): source spread, set results, mean move grade,
    TM-only A/S share and rarity class share; per round: legendary-bird rate
    on roster trainers."""
    rng = random.Random(seed)
    spread = collections.defaultdict(collections.Counter)
    results = collections.defaultdict(collections.Counter)
    grade = collections.defaultdict(lambda: [0, 0])
    strong = collections.defaultdict(lambda: [0, 0, 0])    # mons, any A/S TM-only, any S TM-only
    rarity = collections.defaultdict(collections.Counter)
    birds = collections.defaultdict(lambda: [0, 0])
    for run in runs:
        for b in run.battles:
            group = KIND_GROUP.get(b.kind)
            if not group:
                continue
            rnd = battle_round(g, b)
            for name, _ in b.mons:
                cls = parse.classify(g.rarity, g.species[name].base_species, cfg.groups)
                rarity[(rnd, group)][cls[1] if cls else 0] += 1
            if group in ("Route", "Trainer"):
                birds[rnd][0] += 1
                birds[rnd][1] += any(g.species[s].base_species in LEGENDARY_BIRDS for s, _ in b.mons)
            slots = battle_movesets(d, g, cfg, b, rng)
            for s in slots or ():
                key = (rnd, group)
                spread[key][CATEGORY[s.source]] += 1
                if s.set_result:
                    results[key][s.set_result] += 1
                ranks = [d.rank.get(m, 0) for m in s.moves]
                grade[key][0] += sum(r for r in ranks if r != OFFLIST)
                grade[key][1] += 1
                tm_ranks = [d.rank.get(m, 0) for m in s.tm_only]
                st = strong[rnd]
                st[0] += 1
                st[1] += any(r in (4, 5) for r in tm_ranks)
                st[2] += any(r == 5 for r in tm_ranks)
    return {"spread": spread, "results": results, "grade": grade, "strong": strong,
            "rarity": rarity, "birds": birds}


def format_summary(s: dict) -> str:
    out = ["## Moveset sources per round (share of enemy mons)", "",
           "| Round | Kind | " + " | ".join(CATEGORIES) + " | Set slots that landed | Mean move grade |",
           "|---|---|" + "---|" * (len(CATEGORIES) + 2)]
    for rnd in range(1, 10):
        for kind in KINDS:
            c = s["spread"].get((rnd, kind))
            if not c:
                continue
            t = sum(c.values())
            r = s["results"].get((rnd, kind), collections.Counter())
            rt = sum(r.values())
            landed = _pct(r["exact"] + r["widened"], rt) if rt else "-"
            gs, gn = s["grade"][(rnd, kind)]
            out.append(f"| {rnd} | {kind} | " + " | ".join(_pct(c[k], t) for k in CATEGORIES)
                       + f" | {landed} | {gs / (4 * gn):.2f} |")
    out += ["", "Mean move grade: F=0 .. S=5, empty slot 0, averaged over four slots.", "",
            "## Strong TM-only moves per round", "",
            "| Round | Mons | TM-only A or S move | TM-only S move |", "|---|---|---|---|"]
    for rnd in sorted(s["strong"]):
        n, a, b = s["strong"][rnd]
        out.append(f"| {rnd} | {n} | {_pct(a, n)} | {_pct(b, n)} |")
    out += ["", "TM-only = not in the mon's level-1 moves or learnset at or below its level.", "",
            "## Enemy rarity class per round", "",
            "| Round | Kind | " + " | ".join(CLASS_NAMES[:4]) + " |", "|---|---|---|---|---|---|"]
    for rnd in range(1, 10):
        for kind in KINDS:
            c = s["rarity"].get((rnd, kind))
            if not c:
                continue
            t = sum(c.values())
            out.append(f"| {rnd} | {kind} | " + " | ".join(_pct(c[i], t) for i in range(4)) + " |")
    out += ["", "Uber is never fielded by these kinds. Evolved mons count as their line's class.", "",
            "## Route and gym trainers with a legendary bird", "",
            "| Round | Battles | With a bird |", "|---|---|---|"]
    for rnd in sorted(s["birds"]):
        n, k = s["birds"][rnd]
        out.append(f"| {rnd} | {n} | {_pct(k, n)} |")
    return "\n".join(out)


def selfcheck(d: Data, g: parse.GameData) -> list[str]:
    """Invariants a parse or mirror slip would break."""
    bad = []
    if len(d.weights) != d.consts["NUM_RANK_ROWS"]:
        bad.append(f"MoveRankWeightTable has {len(d.weights)} rows, NUM_RANK_ROWS is {d.consts['NUM_RANK_ROWS']}")
    if any(64 not in row[:OFFLIST] for row in d.weights):
        bad.append("a MoveRankWeightTable row has no 64")
    unranked = sorted({m for mon in d.mons.values() for m in mon.tms + mon.l1} - set(d.rank))
    if unranked:
        bad.append(f"moves with no MoveRankByID row: {unranked[:5]}")
    unlearnable = sorted({(k, m) for k, recs in d.sets.items() if k in d.mons for r in recs
                          for m in r.moves if m != "NO_MOVE" and m not in d.rank})
    if unlearnable:
        bad.append(f"set moves with no rank row: {unlearnable[:5]}")
    missing = [n for n, sp in g.species.items() if (sp.base_species, sp.form) not in d.mons]
    if missing:
        bad.append(f"no learnset for {len(missing)} model species, e.g. {missing[:3]}")
    if not d.sets.get(("KANGASKHAN", 0)):
        bad.append("no curated sets parsed for Kangaskhan")
    mix = d.mixes[d.e4_mix]
    srcs = assign_sources(mix, 6, True, random.Random(0))
    if srcs[-1] != MSRC["SET"]:
        bad.append("ACE_LAST did not give the E4 ace a set")
    return bad


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--runs", type=int, default=300)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--difficulty", default="hard", choices=model.DIFFICULTIES)
    ap.add_argument("--groups", default="KANTO", help="comma list, e.g. KANTO,JOHTO,WARP")
    ap.add_argument("--selfcheck", action="store_true")
    args = ap.parse_args(argv)
    g = parse.load_all()
    d = load()
    if args.selfcheck:
        bad = selfcheck(d, g)
        print("movesets selfcheck: " + ("OK" if not bad else "FAILED\n  " + "\n  ".join(bad)))
        return 1 if bad else 0
    cfg = model.Config(difficulty=args.difficulty, groups=tuple(args.groups.split(",")))
    runs = model.simulate(g, cfg, args.runs, seed=args.seed)
    print(f"# Movesets and enemy rarity: {args.difficulty}, {args.runs} runs, groups {cfg.groups}\n")
    print(format_summary(summarize(d, g, cfg, runs, args.seed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
