"""2026-10-09 player-feedback pass, Phase 0: level-curve variants for the route cut.

Compares, on the model (no ROM build):
  Baseline  the source as it is (L5 starter, 8 routes, today's NORMAL = proposed HARD)
  A0        L8 starter + skipped routes, tables untouched (what the cut does alone)
  A         primary: every round from round 1 shifted so each round's mean gap
            (enemy top level - starter, per battle type) matches Baseline (Curve F's gaps).
            Round 1 rises with the L8 start, so the whole run sits higher.
  B         A's solve against gentler targets: round 1's gaps --b-taper[0] smaller, later
            rounds --b-taper[1] smaller (a touch easier, less so after round 1).
  A75, B75  the same two solves with EXP Share at 75% instead of 62.5% (endgame lift).

A round's shift moves every level source of that round together (route block,
gym block -> also reward levels, leader base, mini-boss base, stage-event base,
wild and wild-boss tables; round 9 = Victory Road + E4 + Champion bases), so a
round keeps its internal shape (Curve F's gaps between battle types).

Money: the prize multiplier that returns each variant's final spendable money to
Baseline's, then x1.05 (proposed HARD); then per-tier multipliers solved so the
tiers really end with x1.1/1.2/1.3 of HARD's money despite their lower enemy levels.

Usage:
  python tools/balance/feedback_curves.py --runs 400 --skip 4,7 --out FILE.md
"""

from __future__ import annotations

import argparse
import statistics
import sys
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import parse  # noqa: E402
import model  # noqa: E402
from model import Config, PROPOSED_TIERS  # noqa: E402

GROUPS = {   # model Battle.kind -> report column
    "route": "Route", "route_final": "Route boss", "miniboss": "Mini-boss",
    "wild": "Wild", "facility_voltorb": "Wild", "stage_event": "Stage ev.", "wild_boss": "Wild boss",
    "gym_trainer": "Gym", "gym_final": "Gym final", "leader": "Leader",
    "victory_road": "VR rival", "e4": "E4", "champion": "Champion",
}
COLUMNS = ["Route", "Route boss", "Mini-boss", "Wild", "Stage ev.", "Wild boss", "Gym", "Gym final", "Leader"]
FINALE_COLUMNS = ["Route", "Route boss", "Gym", "Gym final", "VR rival", "E4", "Champion"]


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


def round1_trainers(g, d: int):
    t = g.tables
    route, gym = list(t.route), list(t.gym)
    route[0] = replace(route[0], min_level=max(1, route[0].min_level + d))
    gym[0] = replace(gym[0], min_level=max(1, gym[0].min_level + d))
    return replace(g, tables=replace(t, route=route, gym=gym))


def gap_table(runs) -> dict[int, dict[str, float]]:
    acc: dict[int, dict[str, list[int]]] = {}
    for run in runs:
        for rnd, kind, gap in run.gaps:
            if rnd == 0:
                continue
            acc.setdefault(rnd, {}).setdefault(GROUPS.get(kind, kind), []).append(gap)
    return {r: {c: statistics.mean(v) for c, v in cols.items()} for r, cols in acc.items()}


def run(g, cfg: Config, n: int):
    runs = model.simulate(g, cfg, n, 1)
    return runs, gap_table(runs), model.summarize(g, runs)


def round_error(var: dict[str, float], base: dict[str, float]) -> float:
    common = [c for c in var if c in base]
    return statistics.mean(var[c] - base[c] for c in common) if common else 0.0


def solve(g, cfg: Config, base_gaps, first_round: int, n: int, taper=(0.0, 0.0)):
    """Shift rounds first_round..9 in order; round r's target is Baseline's gaps
    minus taper[0] (round 1) or taper[1] (later rounds)."""
    shifts = {}
    for r in range(first_round, 10):
        d_total = 0
        ease = taper[0] if r == 1 else taper[1]
        for _ in range(4):
            _, gaps, _ = run(g, cfg, n)
            err = round_error(gaps[r], base_gaps[r]) + ease
            d = -round(err)
            if d == 0:
                break
            g = shift_round(g, r, d)
            d_total += d
        shifts[r] = d_total
    return g, shifts


def fmt_gaps(title: str, gaps, rows) -> list[str]:
    starter = {row["round"]: row["ace_rolled"] for row in rows}
    out = [f"### {title}", "",
           "| Round | " + " | ".join(COLUMNS) + " | Starter at leader |",
           "|---" * (len(COLUMNS) + 2) + "|"]
    for r in range(1, 9):
        cells = [f"{gaps[r][c]:+.1f}" if c in gaps[r] else "" for c in COLUMNS]
        cells[COLUMNS.index("Leader")] = f"**{cells[COLUMNS.index('Leader')]}**"
        out.append(f"| {r} | " + " | ".join(cells) + f" | {starter.get(r, 0):.1f} |")
    fin = gaps.get(9, {})
    out += ["", "Finale: " + ", ".join(f"{c} {fin[c]:+.1f}" for c in FINALE_COLUMNS if c in fin)
            + f"; team average at the Champion {rows[-1]['team_rolled']:.1f}.", ""]
    return out


def leader_aces(g) -> str:
    k = g.knobs
    return " ".join(str(k[f"GYM_R{r}_BASE"] + (k[f"GYM_R{r}_MONS"] - 1) * k[f"GYM_R{r}_STEP"]) for r in range(1, 9))


def table_dump(g) -> list[str]:
    t, k = g.tables, g.knobs
    return [
        f"- route min level R1-9: {' '.join(str(b.min_level) for b in t.route)}",
        f"- gym trainer min level R1-9: {' '.join(str(b.min_level) for b in t.gym)}",
        f"- `GYM_R1-8_BASE`: {' '.join(str(k[f'GYM_R{r}_BASE']) for r in range(1, 9))} (leader aces {leader_aces(g)})",
        f"- `MINIBOSS_R1-9_BASE`: {' '.join(str(k[f'MINIBOSS_R{r}_BASE']) for r in range(1, 10))}",
        f"- `STAGE_EVENT_R1-9_BASE`: {' '.join(str(k[f'STAGE_EVENT_R{r}_BASE']) for r in range(1, 10))}",
        f"- `wild_area_levels`: {' '.join(map(str, t.wild))}",
        f"- wild boss: {' '.join(map(str, t.wild_boss))}",
        f"- `E4_BASE_LEVEL` {k['E4_BASE_LEVEL']}, `CHAMPION_BASE_LEVEL` {k['CHAMPION_BASE_LEVEL']}",
    ]


TIER_TARGET = {"very_easy": 1.3, "easy": 1.2, "normal": 1.1, "hard": 1.0, "very_hard": 1.0}


def money_section(name: str, g, cfg: Config, base_final: float, n: int) -> list[str]:
    """Prize multipliers for variant g: HARD restores Baseline's final spendable x1.05;
    each easier tier is solved so its real spendable is TIER_TARGET x HARD's.
    Spendable money is linear in the multiplier (every source is a battle prize)."""
    spend = {}
    for tier, (pct, _) in PROPOSED_TIERS.items():
        _, _, rows = run(g, replace(cfg, difficulty=f"pct:{pct}"), n)
        spend[tier] = rows[-1]["spendable"]
    hard_final = spend["hard"]
    m_hard = 1.05 * base_final / hard_final
    out = [f"### {name}", "",
           f"At x1.00, HARD ends with {hard_final:,.0f} spendable vs Baseline {base_final:,.0f}; "
           f"HARD's multiplier = 1.05 x {base_final:,.0f} / {hard_final:,.0f} = **x{m_hard:.3f}**.", "",
           "| Tier | Levels | Earlier proposal x | Solved x | Spendable Gym 4 / Gym 8 / final | vs HARD | Leader gap R1 / R4 / R8, Champion |",
           "|---|---|---|---|---|---|---|"]
    for tier, (pct, old) in PROPOSED_TIERS.items():
        mult = TIER_TARGET[tier] * m_hard * hard_final / spend[tier]
        if tier == "very_hard":
            mult = m_hard          # user rule: Very Hard pays HARD's multiplier
        _, gaps, rows = run(g, replace(cfg, difficulty=f"pct:{pct}", money_mult=mult), n)
        fin = rows[-1]["spendable"]
        out.append(f"| {tier.replace('_', ' ').title()} | {pct:+d}% | x{old:.3f} | **x{mult:.3f}** | "
                   f"{rows[3]['spendable']:,.0f} / {rows[7]['spendable']:,.0f} / {fin:,.0f} | "
                   f"{fin / (m_hard * hard_final):.2f} | {gaps[1]['Leader']:+.1f} / {gaps[4]['Leader']:+.1f} / "
                   f"{gaps[8]['Leader']:+.1f}, {gaps[9]['Champion']:+.1f} |")
    vh = spend["very_hard"] / hard_final
    out += ["", f"Very Hard at HARD's multiplier ends x{vh:.2f} of HARD (higher enemy levels pay more); "
            f"x{m_hard / vh:.3f} would make it equal.", ""]
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=400)
    ap.add_argument("--solve-runs", type=int, default=200)
    ap.add_argument("--skip", default="4,7")
    ap.add_argument("--starter-level", type=int, default=8)
    ap.add_argument("--b-taper", default="1.0,0.5", help="B's gap reduction: round 1, later rounds")
    ap.add_argument("--lift-mode", default="equal75", help="EXP Share what-if for the lifted variants")
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()
    skip = tuple(int(x) for x in args.skip.split(","))
    taper = tuple(float(x) for x in args.b_taper.split(","))
    n, ns = args.runs, args.solve_runs

    g0 = parse.load_all()
    base_cfg = Config(difficulty="pct:0")   # 0% levels, no ROM prize bonus (the Phase 0 baseline)
    new_cfg = Config(difficulty="pct:0", starter_level=args.starter_level, rival_level=args.starter_level, skip_rounds=skip)
    cfg75 = replace(new_cfg, exp_all=args.lift_mode)
    lift = {"equal75": "75%", "equal6875": "68.75%"}.get(args.lift_mode, args.lift_mode)

    _, base_gaps, base_rows = run(g0, base_cfg, n)
    _, a0_gaps, a0_rows = run(g0, new_cfg, n)
    variants = {}
    for name, cfg, tp in (("A", new_cfg, (0.0, 0.0)), ("B", new_cfg, taper),
                          ("A75", cfg75, (0.0, 0.0)), ("B75", cfg75, taper)):
        gv, shifts = solve(g0, cfg, base_gaps, 1, ns, tp)
        _, gaps, rows = run(gv, cfg, n)
        variants[name] = (gv, cfg, shifts, gaps, rows)
        print(f"{name}: champion team {rows[-1]['team_rolled']:.1f}, aces {leader_aces(gv)}", file=sys.stderr)

    desc = {
        "A": "A (primary): Curve F's gaps every round, solved from round 1",
        "B": f"B: round 1 gaps {-taper[0]:+.1f}, later rounds {-taper[1]:+.1f}",
        "A75": f"A75: A's targets with EXP Share {lift}",
        "B75": f"B75: B's targets with EXP Share {lift}",
    }
    out = ["# Level-curve variants for the route cut, rev 2 (2026-10-09)", "",
           f"Generated by `tools/balance/feedback_curves.py --runs {n} --skip {args.skip} "
           f"--starter-level {args.starter_level} --b-taper {args.b_taper} --lift-mode {args.lift_mode}`. Model only, no ROM build. "
           "Gap = enemy top level - the rolled starter's level when the battle starts (the BALANCE_LEVEL_SPIKE "
           "convention). Difficulty = today's NORMAL, which is the proposed HARD baseline.", "",
           f"Skipped routes: rounds {', '.join(map(str, skip))} (gyms {', '.join(f'{r - 1}->{r}' for r in skip)} back to "
           "back, Reward Room join between them, `wBattleCount` credited `ROUTE_BATTLES`). Starter and Oak's Lab "
           f"rival at L{args.starter_level}. Special-encounter quotas re-based to the routes that remain.", "",
           "## Summary", "",
           "| Variant | EXP Share | Leader aces | E4 / Champion base | Team avg at Champion | Starter at Champion |",
           "|---|---|---|---|---|---|",
           f"| Baseline | 62.5% | {leader_aces(g0)} | {g0.knobs['E4_BASE_LEVEL']} / {g0.knobs['CHAMPION_BASE_LEVEL']} | "
           f"{base_rows[-1]['team_rolled']:.1f} | {base_rows[-1]['ace_rolled']:.1f} |",
           f"| A0 | 62.5% | {leader_aces(g0)} | {g0.knobs['E4_BASE_LEVEL']} / {g0.knobs['CHAMPION_BASE_LEVEL']} | "
           f"{a0_rows[-1]['team_rolled']:.1f} | {a0_rows[-1]['ace_rolled']:.1f} |"]
    for name, (gv, cfg, _, _, rows) in variants.items():
        out.append(f"| {name} | {lift if cfg.exp_all == args.lift_mode else '62.5%'} | {leader_aces(gv)} | "
                   f"{gv.knobs['E4_BASE_LEVEL']} / {gv.knobs['CHAMPION_BASE_LEVEL']} | "
                   f"{rows[-1]['team_rolled']:.1f} | {rows[-1]['ace_rolled']:.1f} |")
    out += ["", "## Gap tables", ""]
    out += fmt_gaps("Baseline: today (L5 start, 8 routes)", base_gaps, base_rows)
    out += fmt_gaps(f"A0: L{args.starter_level} start + skipped routes, tables untouched", a0_gaps, a0_rows)
    for name, (gv, _, shifts, gaps, rows) in variants.items():
        out += fmt_gaps(desc[name], gaps, rows)
        out += ["Per-round shift vs today: " + ", ".join(f"R{r if r < 9 else 'finale'} {d:+d}" for r, d in shifts.items()), ""]
        out += table_dump(gv) + [""]

    out += ["## Money (spendable, cumulative, at each leader, prize x1.00)", "",
            "| Gym | Baseline | A0 | " + " | ".join(variants) + " |", "|---" * (len(variants) + 3) + "|"]
    for i in range(8):
        out.append(f"| {i + 1} | {base_rows[i]['spendable']:,.0f} | {a0_rows[i]['spendable']:,.0f} | "
                   + " | ".join(f"{v[4][i]['spendable']:,.0f}" for v in variants.values()) + " |")
    out.append(f"| final | {base_rows[-1]['spendable']:,.0f} | {a0_rows[-1]['spendable']:,.0f} | "
               + " | ".join(f"{v[4][-1]['spendable']:,.0f}" for v in variants.values()) + " |")
    out += ["", "## Prize multipliers per tier (Baseline's money restored, +5%, easier tiers solved)", ""]
    for name, (gv, cfg, _, _, _) in variants.items():
        out += money_section(name, gv, cfg, base_rows[-1]["spendable"], n)
    text = "\n".join(out) + "\n"
    if args.out:
        args.out.write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote {args.out}")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
