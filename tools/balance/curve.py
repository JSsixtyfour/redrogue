"""Level-curve measurement and solving, shared by report.py and curve_solver.py.

A *gap* is the enemy's top level minus the rolled starter's level when a battle
starts (the BALANCE_LEVEL_SPIKE convention), recorded per battle in Run.gaps.
Gaps are grouped by round (1-8, 9 = the finale) and battle column (Route, Gym,
Leader, ...). *Targets* are the gaps the curve should produce, stored in
tools/balance/data/gap_targets.csv with a tolerance each; curve_solver.py
--write-targets measures them from a reference configuration.

The solver moves every level source of a round together (shift_round), so a
round keeps its internal shape, then fine adjustments (adjust) move one kind
of source in one round. Both return a new GameData; nothing touches the .asm.
"""

from __future__ import annotations

import csv
import statistics
from dataclasses import replace
from pathlib import Path

import model
from model import Config

HERE = Path(__file__).resolve().parent
TARGETS_CSV = HERE / "data" / "gap_targets.csv"

GROUPS = {   # model Battle.kind -> report column
    "route": "Route", "route_final": "Route boss", "miniboss": "Mini-boss",
    "wild": "Wild", "facility_voltorb": "Wild", "stage_event": "Stage ev.", "wild_boss": "Wild boss",
    "gym_trainer": "Gym", "gym_final": "Gym final", "leader": "Leader",
    "victory_road": "VR rival", "e4": "E4", "champion": "Champion",
}
COLUMNS = ["Route", "Route boss", "Mini-boss", "Wild", "Stage ev.", "Wild boss", "Gym", "Gym final", "Leader"]
FINALE_COLUMNS = ["Route", "Route boss", "Gym", "Gym final", "VR rival", "E4", "Champion"]


def pct(values: list[float], q: float) -> float:
    s = sorted(values)
    return s[min(len(s) - 1, max(0, round(q * (len(s) - 1))))]


def gap_samples(runs) -> dict[int, dict[str, list[int]]]:
    acc: dict[int, dict[str, list[int]]] = {}
    for run in runs:
        for rnd, kind, gap in run.gaps:
            if rnd == 0:
                continue
            acc.setdefault(rnd, {}).setdefault(GROUPS.get(kind, kind), []).append(gap)
    return acc


def gap_table(runs) -> dict[int, dict[str, float]]:
    """Mean gap per round and column."""
    return {r: {c: statistics.mean(v) for c, v in cols.items()} for r, cols in gap_samples(runs).items()}


def gap_percentile(runs, q: float) -> dict[int, dict[str, float]]:
    """The q-quantile gap per round and column (q=0.9: the hardest 10% of fights)."""
    return {r: {c: pct(v, q) for c, v in cols.items()} for r, cols in gap_samples(runs).items()}


# --- targets -----------------------------------------------------------------

def load_targets(path: Path = TARGETS_CSV) -> dict[int, dict[str, tuple[float, float]]]:
    """{round: {column: (target, tolerance)}}; empty when the file is missing."""
    if not path.exists():
        return {}
    out: dict[int, dict[str, tuple[float, float]]] = {}
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(line for line in f if not line.startswith("#")):
            out.setdefault(int(row["round"]), {})[row["column"]] = (float(row["target"]), float(row["tolerance"]))
    return out


def write_targets(gaps: dict[int, dict[str, float]], note: str, tolerance: float = 0.5,
                  path: Path = TARGETS_CSV) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        f.write(f"# Level-gap targets (enemy top level - rolled starter). {note}\n")
        f.write("# Written by tools/balance/curve_solver.py --write-targets; edit by hand to retarget.\n")
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["round", "column", "target", "tolerance"])
        for r in sorted(gaps):
            for c in COLUMNS + [x for x in FINALE_COLUMNS if x not in COLUMNS]:
                if c in gaps[r]:
                    w.writerow([r, c, f"{gaps[r][c]:+.1f}", f"{tolerance:.1f}"])


def deviations(gaps, targets) -> list[tuple[int, str, float, float, float]]:
    """(round, column, measured, target, delta) for every targeted cell measured."""
    out = []
    for r, cols in sorted(targets.items()):
        for c, (t, _) in cols.items():
            if r in gaps and c in gaps[r]:
                out.append((r, c, gaps[r][c], t, gaps[r][c] - t))
    return out


def out_of_tolerance(gaps, targets) -> list[tuple[int, str, float, float, float]]:
    return [d for d in deviations(gaps, targets) if abs(d[4]) > targets[d[0]][d[1]][1]]


# --- moving level sources ----------------------------------------------------

def shift_round(g, r: int, d: int):
    """Every enemy level source of round r (1-8, 9 = finale) moved by d."""
    if d == 0:
        return g
    t = g.tables
    route, gym, wild, boss = list(t.route), list(t.gym), list(t.wild), list(t.wild_boss)
    route[r - 1] = replace(route[r - 1], min_level=route[r - 1].min_level + d)
    gym[r - 1] = replace(gym[r - 1], min_level=gym[r - 1].min_level + d)
    wild[r - 1] += d
    boss[r - 1] += d
    k = dict(g.knobs)
    names = [f"MINIBOSS_R{r}_BASE", f"STAGE_EVENT_R{r}_BASE"]
    names += [f"GYM_R{r}_BASE"] if r <= 8 else ["E4_BASE_LEVEL", "CHAMPION_BASE_LEVEL"]
    for n in names:
        k[n] += d
    return replace(g, knobs=k, tables=replace(t, route=route, gym=gym, wild=wild, wild_boss=boss))


ADJUST_KINDS = ("route", "gym", "leader", "wild", "boss", "stage", "miniboss")


def adjust(g, kind: str, r: int, d: int):
    """One kind of level source in round r moved by d. "gym" moves the gym
    trainers AND the leader (the whole gym); "leader" only the leader."""
    t, k = g.tables, dict(g.knobs)
    route, gym, wild, boss = list(t.route), list(t.gym), list(t.wild), list(t.wild_boss)
    if kind == "route":
        route[r - 1] = replace(route[r - 1], min_level=route[r - 1].min_level + d)
    elif kind in ("gym", "leader"):
        if kind == "gym":
            gym[r - 1] = replace(gym[r - 1], min_level=gym[r - 1].min_level + d)
        k[f"GYM_R{r}_BASE" if r <= 8 else "E4_BASE_LEVEL"] += d
    elif kind == "wild":
        wild[r - 1] += d
    elif kind == "boss":
        boss[r - 1] += d
    elif kind == "stage":
        k[f"STAGE_EVENT_R{r}_BASE"] += d
    elif kind == "miniboss":
        k[f"MINIBOSS_R{r}_BASE"] += d
    else:
        raise ValueError(f"adjust kind must be one of {ADJUST_KINDS}")
    return replace(g, knobs=k, tables=replace(t, route=route, gym=gym, wild=wild, wild_boss=boss))


def run(g, cfg: Config, n: int, seed: int = 1):
    runs = model.simulate(g, cfg, n, seed)
    return runs, gap_table(runs), model.summarize(g, runs)


def round_error(var: dict[str, float], target: dict[str, float]) -> float:
    common = [c for c in var if c in target]
    return statistics.mean(var[c] - target[c] for c in common) if common else 0.0


def solve(g, cfg: Config, targets: dict[int, dict[str, float]], first_round: int, n: int,
          ease=(0.0, 0.0), last_round: int = 9):
    """Shift rounds first_round..last_round in order so each round's mean gap
    matches targets[r] minus ease[0] (round 1) or ease[1] (later rounds).
    Returns (new GameData, {round: total shift})."""
    shifts = {}
    for r in range(first_round, last_round + 1):
        d_total = 0
        e = ease[0] if r == 1 else ease[1]
        for _ in range(4):
            _, gaps, _ = run(g, cfg, n)
            if r not in gaps:
                break
            d = -round(round_error(gaps[r], targets[r]) + e)
            if d == 0:
                break
            g = shift_round(g, r, d)
            d_total += d
        shifts[r] = d_total
    return g, shifts


# --- presenting tables -------------------------------------------------------

def leader_aces(g) -> list[int]:
    k = g.knobs
    return [k[f"GYM_R{r}_BASE"] + (k[f"GYM_R{r}_MONS"] - 1) * k[f"GYM_R{r}_STEP"] for r in range(1, 9)]


def table_values(g) -> dict[str, list[int]]:
    """Every level source the solver can move, as the lists the .asm holds."""
    t, k = g.tables, g.knobs
    return {
        "route min level (trainer_levels.asm, trainer_difficulty_settings)": [b.min_level for b in t.route],
        "gym trainer min level (trainer_levels.asm, _gym)": [b.min_level for b in t.gym],
        "GYM_R1-8_BASE": [k[f"GYM_R{r}_BASE"] for r in range(1, 9)],
        "MINIBOSS_R1-9_BASE": [k[f"MINIBOSS_R{r}_BASE"] for r in range(1, 10)],
        "STAGE_EVENT_R1-9_BASE": [k[f"STAGE_EVENT_R{r}_BASE"] for r in range(1, 10)],
        "wild_area_levels": list(t.wild),
        "wild boss (wild_boss_levels.asm)": list(t.wild_boss),
        "E4_BASE_LEVEL": [k["E4_BASE_LEVEL"]],
        "CHAMPION_BASE_LEVEL": [k["CHAMPION_BASE_LEVEL"]],
    }


def fmt_gap_table(title: str, gaps, rows=None, targets=None, compare=None) -> list[str]:
    """Markdown gap table. targets: mark cells outside tolerance as `+0.7!`.
    compare: a second gap table shown as `base / this`."""
    def cell(r, c):
        if c not in gaps.get(r, {}):
            return f"{compare[r][c]:+.1f} / -" if compare and c in compare.get(r, {}) else ""
        v = gaps[r][c]
        s = f"{v:+.1f}"
        if compare is not None:
            b = compare.get(r, {}).get(c)
            s = (f"{b:+.1f}" if b is not None else "-") + " / " + s
        if targets and c in targets.get(r, {}):
            t, tol = targets[r][c]
            if abs(v - t) > tol:
                s += f" ({v - t:+.1f}!)"
        return s

    out = [f"### {title}", "", "| Round | " + " | ".join(COLUMNS) + (" | Starter at leader |" if rows else " |"),
           "|---" * (len(COLUMNS) + (2 if rows else 1)) + "|"]
    starter = {row["round"]: row["ace_rolled"] for row in rows} if rows else {}
    for r in range(1, 9):
        cells = [cell(r, c) for c in COLUMNS]
        tail = f" | {starter.get(r, 0):.1f} |" if rows else " |"
        out.append(f"| {r} | " + " | ".join(cells) + tail)
    fin = [f"{c} {cell(9, c)}" for c in FINALE_COLUMNS if c in gaps.get(9, {})]
    out += ["", "Finale: " + ", ".join(fin) + (f"; team average at the Champion {rows[-1]['team_rolled']:.1f}."
                                                if rows else "."), ""]
    return out
