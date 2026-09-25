"""Reads the balance inputs straight from the assembly source.

Nothing here is a guess or a copy: every number the model uses comes from the
same file the ROM is built from, so a knob edited in the .asm is picked up on
the next model run with no second place to update. Anything that cannot be
parsed raises, rather than silently falling back to a default.

Stdlib only; runs under Windows python and WSL python3 alike.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "pyboy_smoke"))
from source_constants import parse_rgbds_constants  # noqa: E402

NUM_RARITY_TIERS = 5          # pokeball, greatball, ultraball, masterball, uber
TIER_UBER = 4
GROUPS = ("KANTO", "JOHTO", "WARP")

_NUM = r"(?:0x[0-9A-Fa-f]+|\$[0-9A-Fa-f]+|%[01]+|\d+)"


def _int(tok: str) -> int:
    tok = tok.strip()
    if tok.startswith("$"):
        return int(tok[1:], 16)
    if tok.startswith("%"):
        return int(tok[1:], 2)
    return int(tok, 0) if tok.lower().startswith("0x") else int(tok)


def _code(line: str) -> str:
    return line.split(";", 1)[0].strip()


def _lines(rel: str) -> list[str]:
    return (ROOT / rel).read_text(encoding="utf-8").splitlines()


# --- knobs -------------------------------------------------------------------

def load_knobs() -> dict[str, int]:
    """Every integer DEF in constants/balance_constants.asm."""
    return parse_rgbds_constants(ROOT / "constants" / "balance_constants.asm")


def _db_after_label(rel: str, label: str) -> list[int]:
    """Numeric `db` bytes from `label:` to the next label (comments ignored)."""
    out: list[int] = []
    inside = False
    for raw in _lines(rel):
        code = _code(raw)
        if not inside:
            if re.match(rf"^{re.escape(label)}::?$", code):
                inside = True
            continue
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*::?$", code):
            break
        if code.startswith("db "):
            for tok in code[3:].split(","):
                if not re.fullmatch(_NUM, tok.strip()):
                    raise ValueError(f"{rel}: non-numeric db byte {tok!r} under {label}")
                out.append(_int(tok))
    if not inside:
        raise ValueError(f"{rel}: label {label} not found")
    return out


# --- trainer level tables ----------------------------------------------------

@dataclass(frozen=True)
class LevelBlock:
    level_range: int
    min_level: int
    counts: tuple[int, int, int, int]        # pokeball, greatball, ultraball, masterball
    final_bonus: int
    final_counts: tuple[int, int, int, int]


def _blocks(label: str) -> list[LevelBlock]:
    raw = _db_after_label("data/balance/trainer_levels.asm", label)
    if len(raw) % 11:
        raise ValueError(f"{label}: {len(raw)} bytes is not a whole number of 11-byte blocks")
    return [LevelBlock(raw[i], raw[i + 1], tuple(raw[i + 2:i + 6]), raw[i + 6], tuple(raw[i + 7:i + 11]))
            for i in range(0, len(raw), 11)]


@dataclass(frozen=True)
class MiniBossRow:
    level_range: int
    min_level: int
    base_class: int      # GetRandMon convention: 4 = pokeball .. 1 = masterball
    rare_chance: int     # /256


@dataclass
class Tables:
    route: list[LevelBlock]
    gym: list[LevelBlock]
    miniboss: list[MiniBossRow]
    wild: list[int]
    wild_boss: list[int]


def load_tables() -> Tables:
    mb = _db_after_label("data/balance/miniboss_levels.asm", "trainer_difficulty_settings_miniboss")
    return Tables(
        route=_blocks("trainer_difficulty_settings"),
        gym=_blocks("trainer_difficulty_settings_gym"),
        miniboss=[MiniBossRow(*mb[i:i + 4]) for i in range(0, len(mb), 4)],
        wild=_db_after_label("data/balance/wild_levels.asm", "PCWildLevelTable"),
        wild_boss=_db_after_label("data/balance/wild_boss_levels.asm", "PCBossLevelTable"),
    )


# --- species -----------------------------------------------------------------

EVOLVE_LEVEL, EVOLVE_ITEM, EVOLVE_TRADE = 1, 2, 3


@dataclass
class Species:
    name: str
    internal_id: int
    base_exp: int
    growth: str
    # (method, min level, target species name); item evolutions keep their
    # min-level byte (1), exactly as EvolveMonByLevel reads it.
    evos: list[tuple[int, int, str]] = field(default_factory=list)


def _base_stats() -> dict[str, tuple[int, str]]:
    out: dict[str, tuple[int, str]] = {}
    for path in sorted((ROOT / "data" / "pokemon" / "base_stats").glob("*.asm")):
        text = path.read_text(encoding="utf-8")
        dex = re.search(r"db\s+DEX_([A-Z0-9_]+)", text)
        exp = re.search(r"db\s+(\d+)\s*;\s*base exp", text)
        growth = re.search(r"db\s+(GROWTH_[A-Z_]+)", text)
        if not (dex and exp and growth):
            raise ValueError(f"{path.name}: missing dex id, base exp or growth rate")
        out[dex.group(1)] = (int(exp.group(1)), growth.group(1))
    return out


def load_species() -> dict[str, Species]:
    ids = parse_rgbds_constants(ROOT / "constants" / "pokemon_constants.asm")
    # First name per id wins: later DEF aliases (RESTLESS_SOUL EQU MAROWAK,
    # STARTER1 EQU CHARMANDER) must not shadow the species' own const.
    by_id: dict[int, str] = {}
    for k, v in ids.items():
        if k != "NO_MON":
            by_id.setdefault(v, k)
    stats = _base_stats()

    # EvosMovesPointerTable is positional: entry k is internal id k + 1.
    lines = _lines("data/pokemon/evos_moves.asm")
    pointers: list[str] = []
    in_table = False
    for raw in lines:
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

    evos_by_label: dict[str, list[tuple[int, int, str]]] = {}
    current: str | None = None
    reading = False
    for raw in lines:
        code = _code(raw)
        m = re.match(r"^([A-Za-z0-9_]+EvosMoves):$", code)
        if m:
            current, reading = m.group(1), True
            evos_by_label[current] = []
            continue
        if not (current and reading and code.startswith("db ")):
            continue
        parts = [p.strip() for p in code[3:].split(",")]
        if parts == ["0"]:
            reading = False
        elif parts[0] == "EVOLVE_LEVEL":
            evos_by_label[current].append((EVOLVE_LEVEL, int(parts[1]), parts[2]))
        elif parts[0] == "EVOLVE_ITEM":
            evos_by_label[current].append((EVOLVE_ITEM, int(parts[2]), parts[3]))
        elif parts[0] == "EVOLVE_TRADE":
            evos_by_label[current].append((EVOLVE_TRADE, int(parts[1]), parts[2]))
        else:
            raise ValueError(f"evos_moves.asm: unparsed evolution line under {current}: {code!r}")

    out: dict[str, Species] = {}
    for k, label in enumerate(pointers):
        iid = k + 1
        name = by_id.get(iid)
        if name is None or name not in stats:
            continue                     # MissingNo slots
        exp, growth = stats[name]
        out[name] = Species(name, iid, exp, growth, list(evos_by_label.get(label, [])))
    return out


# --- rarity pools (GetRandMon / Random_Pokemon_Selection) --------------------

@dataclass
class Tier:
    base: list[str]      # rollable base forms
    all: list[str]       # base + _Evos, used only for classification


def load_rarity() -> dict[str, list[Tier]]:
    """{group: [tier 0..4]} from engine/pokemon/rarity.asm."""
    lists: dict[str, list[str]] = {}
    evos_at: dict[str, int] = {}
    current: str | None = None
    for raw in _lines("engine/pokemon/rarity.asm"):
        code = _code(raw)
        m = re.match(r"^((?:Kanto|Johto|Warp)[A-Za-z]+?)(_Evos|_End)?:$", code)
        if m:
            base, suffix = m.group(1), m.group(2)
            if suffix is None:
                current = base
                lists.setdefault(base, [])
            elif suffix == "_Evos":
                evos_at[base] = len(lists.get(base, []))
                current = base
            else:
                current = None
            continue
        if current and code.startswith("db "):
            lists[current].append(code[3:].strip())

    tier_names = ("Pokeball", "Greatball", "Ultraball", "Masterball", "Uber")
    out: dict[str, list[Tier]] = {}
    for group, prefix in zip(GROUPS, ("Kanto", "Johto", "Warp")):
        tiers = []
        for t in tier_names:
            species = lists.get(prefix + t, [])
            n_base = evos_at.get(prefix + t, len(species))
            tiers.append(Tier(species[:n_base], species))
        out[group] = tiers
    kanto_total = sum(len(t.all) for t in out["KANTO"])
    if kanto_total != 151:
        raise ValueError(f"rarity.asm Kanto pool parsed as {kanto_total} species, expected 151")
    return out


def classify(rarity: dict[str, list[Tier]], species: str) -> tuple[str, int] | None:
    """RogueClassifySpecies: first (group, tier) whose full list holds it."""
    for group in GROUPS:
        for t, tier in enumerate(rarity[group]):
            if species in tier.all:
                return group, t
    return None


# --- trainer pools and spec records -----------------------------------------

def load_pools() -> dict[str, dict[str, list[str]]]:
    """{POOL_X: {KANTO: [...], JOHTO: [...], WARP: [...]}} from data/trainers/pools.asm."""
    consts = parse_rgbds_constants(ROOT / "data" / "trainers" / "pools.asm")
    order = [line.split("trainer_pool", 1)[1].strip()
             for line in (_code(r) for r in _lines("data/trainers/pools.asm"))
             if line.startswith("trainer_pool ")]
    pool_ids = sorted((v, k) for k, v in consts.items() if k.startswith("POOL_") and k != "POOL_FORM_ROLL")
    if len(pool_ids) != len(order):
        raise ValueError(f"pools.asm: {len(pool_ids)} POOL_ ids but {len(order)} TrainerPoolTable rows")

    runs: dict[str, dict[str, list[str]]] = {label: {g: [] for g in GROUPS} for label in order}
    current: tuple[str, str] | None = None
    for raw in _lines("data/trainers/pools.asm"):
        code = _code(raw)
        m = re.match(r"^([A-Za-z0-9]+Pool)(_Johto|_Warp|_End)?:$", code)
        if m and m.group(1) in runs:
            suffix = m.group(2)
            current = None if suffix == "_End" else (m.group(1), {None: "KANTO", "_Johto": "JOHTO", "_Warp": "WARP"}[suffix])
            continue
        if current and code.startswith("pool_mon "):
            runs[current[0]][current[1]].append(code.split()[1].rstrip(","))
    return {name: runs[label] for (_, name), label in zip(pool_ids, order)}


@dataclass(frozen=True)
class LeaderRecord:
    name: str
    pool: str
    ace_a_early: str
    ace_a_late: str
    ace_c_early: str
    ace_c_late: str
    late_flags: str       # extra BIT_PSPEC_* expression applied from round 7


@dataclass(frozen=True)
class E4Record:
    name: str
    pool: str
    ace_a: str
    ace_c: str


def load_spec_records() -> tuple[list[LeaderRecord], list[E4Record]]:
    leaders, e4 = [], []
    for raw in _lines("data/trainers/party_specs.asm"):
        code = _code(raw)
        if code.startswith("gym_leader_records "):
            args = [a.strip() for a in code.split(None, 1)[1].split(",")]
            leaders.append(LeaderRecord(*args[:7]))
        elif code.startswith("e4_member_records "):
            args = [a.strip() for a in code.split(None, 1)[1].split(",")]
            e4.append(E4Record(args[0], args[1], args[2], args[4]))
    return leaders, e4


def load_miniboss_teams() -> dict[str, list[list[str]]]:
    """Curated mini-boss compositions; 'FILL:n' marks MINIBOSS_RANDOM_FILL, n."""
    out: dict[str, list[list[str]]] = {}
    current = None
    for raw in _lines("data/trainers/parties.asm"):
        code = _code(raw)
        m = re.match(r"^(RivalMiniBossData|GiovanniMiniBossData):$", code)
        if m:
            current = m.group(1)
            out[current] = []
            continue
        if current and re.match(r"^[A-Za-z_][A-Za-z0-9_]*:$", code):
            current = None
        if current and code.startswith("db "):
            toks = [t.strip() for t in code[3:].split(",")]
            team, i = [], 0
            while i < len(toks) and toks[i] != "0":
                if toks[i] == "MINIBOSS_RANDOM_FILL":
                    team.append(f"FILL:{int(toks[i + 1])}")
                    i += 2
                else:
                    team.append(toks[i])
                    i += 1
            out[current].append(team)
    return out


# --- money -------------------------------------------------------------------

def load_money_bases(knobs: dict[str, int]) -> dict[str, int]:
    """{TRAINER_CLASS: base money}. Row i of the pic table is class i + 1."""
    classes: list[str] = []
    for raw in _lines("constants/trainer_constants.asm"):
        m = re.match(r"^trainer_const\s+([A-Z0-9_]+)", _code(raw))
        if m:
            classes.append(m.group(1))
    rows: list[int] = []
    for raw in _lines("data/trainers/pic_pointers_money.asm"):
        m = re.match(r"^pic_money\s+[A-Za-z0-9_]+\s*,\s*([A-Za-z0-9_$]+)$", _code(raw))
        if m:
            tok = m.group(1)
            rows.append(knobs[tok] if tok in knobs else _int(tok))
    if len(rows) != len(classes) - 1:
        raise ValueError(f"pic_pointers_money.asm has {len(rows)} rows for {len(classes) - 1} classes")
    return {cls: rows[i] for i, cls in enumerate(classes[1:])}


# --- growth ------------------------------------------------------------------

def load_item_prices() -> dict[str, int]:
    """{ITEM_NAME: price} from data/items/prices.asm. `bcd3 NNNN  ; ITEM` rows
    are already decimal literals, so no BCD decode is needed here."""
    out: dict[str, int] = {}
    for raw in _lines("data/items/prices.asm"):
        m = re.match(r"^\s*bcd3\s+(\d+)\s*;\s*([A-Z0-9_]+)\s*$", raw)
        if m:
            out[m.group(2)] = int(m.group(1))
    if "FULL_RESTORE" not in out or "REVIVE" not in out:
        raise ValueError("data/items/prices.asm: FULL_RESTORE or REVIVE price not found")
    return out


def load_growth_rates() -> dict[str, tuple[int, int, int, int, int]]:
    names = [n for n, _ in sorted(((k, v) for k, v in parse_rgbds_constants(
        ROOT / "constants" / "pokemon_data_constants.asm").items() if k.startswith("GROWTH_")), key=lambda kv: kv[1])]
    rows = []
    for raw in _lines("data/growth_rates.asm"):
        m = re.match(r"^growth_rate\s+(.+)$", _code(raw))
        if m:
            rows.append(tuple(int(x) for x in m.group(1).split(",")))
    if len(rows) != len(names):
        raise ValueError(f"growth_rates.asm: {len(rows)} rows for {len(names)} GROWTH_ constants")
    return dict(zip(names, rows))


# --- bundle ------------------------------------------------------------------

@dataclass
class GameData:
    knobs: dict[str, int]
    tables: Tables
    species: dict[str, Species]
    rarity: dict[str, list[Tier]]
    pools: dict[str, dict[str, list[str]]]
    leaders: list[LeaderRecord]
    e4: list[E4Record]
    miniboss_teams: dict[str, list[list[str]]]
    money: dict[str, int]
    growth: dict[str, tuple[int, int, int, int, int]]
    constants: dict[str, int]
    item_prices: dict[str, int]


def load_all() -> GameData:
    knobs = load_knobs()
    leaders, e4 = load_spec_records()
    consts = {}
    for rel in ("constants/ram_constants.asm", "constants/party_spec_constants.asm"):
        consts.update(parse_rgbds_constants(ROOT / rel))
    data = GameData(
        knobs=knobs,
        tables=load_tables(),
        species=load_species(),
        rarity=load_rarity(),
        pools=load_pools(),
        leaders=leaders,
        e4=e4,
        miniboss_teams=load_miniboss_teams(),
        money=load_money_bases(knobs),
        growth=load_growth_rates(),
        constants=consts,
        item_prices=load_item_prices(),
    )
    _validate(data)
    return data


def _validate(d: GameData) -> None:
    """Every species name the model can reach must resolve to base stats."""
    names: set[str] = set()
    for tiers in d.rarity.values():
        for t in tiers:
            names.update(t.all)
    for runs in d.pools.values():
        for lst in runs.values():
            names.update(lst)
    for r in d.leaders:
        names.update((r.ace_a_early, r.ace_a_late, r.ace_c_early, r.ace_c_late))
    for r in d.e4:
        names.update((r.ace_a, r.ace_c))
    for teams in d.miniboss_teams.values():
        for team in teams:
            names.update(s for s in team if not s.startswith("FILL:") and s != "RIVAL_STARTER_PLACEHOLDER")
    for sp in list(d.species.values()):
        names.update(target for _, _, target in sp.evos)
    missing = sorted(n for n in names if n not in d.species)
    if missing:
        raise ValueError(f"species with no base stats / evos entry: {missing}")
    if len(d.tables.route) != len(d.tables.gym):
        raise ValueError("route and gym level tables have different round counts")


if __name__ == "__main__":
    g = load_all()
    print(f"knobs {len(g.knobs)}, species {len(g.species)}, pools {len(g.pools)}, "
          f"leaders {len(g.leaders)}, e4 {len(g.e4)}, rounds {len(g.tables.route)}")
    for grp, tiers in g.rarity.items():
        print(grp, [len(t.base) for t in tiers])
