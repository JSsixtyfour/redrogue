"""Red Rogue balance report: runs model.py across the configs that matter for
tuning and writes BALANCE_REPORT.md plus one CSV per section.

Doesn't duplicate any ROM-mirroring logic: everything here calls parse.load_all,
model.simulate, model.summarize and model.format_round_table. If a number looks
wrong, the bug is in model.py, not here.

Usage:
  python tools/balance/report.py --runs 2000
  python tools/balance/report.py --out "K:/Other computers/My Laptop/Red Rogue Files/balance"
"""

from __future__ import annotations

import argparse
import csv
import json
import statistics
import subprocess
import sys
import time
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import curve  # noqa: E402
import model  # noqa: E402
import parse  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
# One row per report on the unmodified knobs (no --set), committed with the
# tree, so the economy can be compared across tuning passes. The dated report
# folders under --out are local and per machine; this file is the history.
HERE = Path(__file__).resolve().parent
HISTORY_CSV = HERE / "data" / "economy_history.csv"
HISTORY_ROWS_SHOWN = 12

# Battle terms: least-squares fit over the WON battles in
# tools/balance/data/battle_time.csv (calibrate_battle_time.py, 2026-09-25):
# sec = 17.8 + 15.3 x enemy mons, ~9.2 s per turn. That is a FLOOR: the harness
# taps A as fast as it can and the clock starts at the first battle menu, so the
# trainer intro and a human's reading time are not in it. The overworld term is
# still a placeholder; one real timed run replaces it.
CALIBRATION = {
    "source": "battle terms measured (fast-tap floor); overworld placeholder",
    "fixed_sec_per_trainer_battle": 18,
    "sec_per_enemy_mon": 15,
    "sec_per_wild_battle": 33,          # the fit at one mon
    "overworld_sec_per_stage": 180,
}

TARGET_DURATION_SEC = 2 * 3600
GROUP_SHORT = [c.removeprefix("GROWTH_").lower() for c in model.GROWTH_CURVES]


def config_row(cfg: model.Config) -> dict:
    return {
        "difficulty": cfg.difficulty,
        "exp_all": "off" if cfg.exp_all is None else cfg.exp_all,
        "policy": cfg.policy,
        "take_wild": cfg.take_wild,
    }


def write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        return
    fieldnames = list(rows[0].keys())
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)


def duration_estimate(g: parse.GameData, run: model.Run) -> float:
    """Sigma battles * sec-per-battle(mons) + Sigma stages * overworld_sec (see CALIBRATION)."""
    sec = 0.0
    for bt in run.battles:
        if bt.trainer:
            sec += CALIBRATION["fixed_sec_per_trainer_battle"] + CALIBRATION["sec_per_enemy_mon"] * len(bt.mons)
        else:
            sec += CALIBRATION["sec_per_wild_battle"]
    sec += len(run.stages) * CALIBRATION["overworld_sec_per_stage"]
    return sec


def sink_price_yen(g: parse.GameData, knob: str) -> int:
    """A lobby sink price in yen. The salesman and TM knobs are ONE BCD byte of
    THOUSANDS since 2026-09-28 ($20 = 20,000; the ROM splits it across the top
    two money bytes, see the *_WORD DEFs). The daycare's is still the old
    middle-byte form (2-byte $05,$00 = 500), so it is x 100. The Move Tutor
    fees are plain integers (TutorMovePrices encodes them with bcd3)."""
    if knob.startswith("MOVE_TUTOR_PRICE"):
        return g.knobs[knob]
    scale = 100 if knob.startswith("DAYCARE") else 1000
    return model.bcd(g.knobs[knob]) * scale


TM_TIERS = ("F", "D", "C", "B", "A", "S")


def shop_prices(g: parse.GameData) -> dict[str, int]:
    """Every price the economy sections quote, in yen. Vitamins (HP Up,
    Protein, Iron, Carbos, Calcium) share one price; the report reads HP Up's
    and checks the rest match."""
    vit = {g.item_prices[i] for i in ("HP_UP", "PROTEIN", "IRON", "CARBOS", "CALCIUM")}
    if len(vit) != 1:
        raise ValueError(f"vitamin prices differ: {sorted(vit)}")
    out = {
        "full_restore": g.item_prices["FULL_RESTORE"],
        "revive": g.item_prices["REVIVE"],
        "vitamin": g.item_prices["HP_UP"],
        "pp_up": g.item_prices["PP_UP"],
        "rare_candy": g.item_prices["RARE_CANDY"],
        "salesman_pokeball": sink_price_yen(g, "SALESMAN_PRICE_POKEBALL_BCD"),
        "daycare_round": sink_price_yen(g, "DAYCARE_PRICE_PER_ROUND_BCD"),
    }
    for t in TM_TIERS:
        out[f"tm_{t}"] = sink_price_yen(g, f"TM_PRICE_{t}_BCD")
    for t in TM_TIERS:
        out[f"tutor_{t}"] = sink_price_yen(g, f"MOVE_TUTOR_PRICE_{t}")
    return out


# Battle.kind -> the money source it is reported under.
MONEY_SOURCES = {
    "route": "route trainers", "route_final": "route trainers",
    "gym_trainer": "gym trainers", "gym_final": "gym trainers",
    "leader": "gym leaders",
    "miniboss": "mini-bosses", "victory_road": "mini-bosses",
    "stage_event": "stage events",
    "oak_rival": "Oak's Lab rival",
    "e4": "Elite Four (unspendable)", "champion": "Champion (unspendable)",
}


def money_by_source(g: parse.GameData, cfg: model.Config, runs: list[model.Run]) -> dict[str, float]:
    """Mean yen per run from each MONEY_SOURCES bucket, plus the starting money."""
    totals: dict[str, float] = {"starting money": model.bcd(g.knobs["START_MONEY"]) * len(runs)}
    for run in runs:
        for bt in run.battles:
            won = model.money_for(g, bt, cfg.amulet_coin, cfg.difficulty)
            if won:
                src = MONEY_SOURCES.get(bt.kind, bt.kind)
                totals[src] = totals.get(src, 0) + won
    return {k: v / len(runs) for k, v in totals.items()}


def git_commit() -> str:
    try:
        sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True,
                             text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT,
                               capture_output=True, text=True, check=True).stdout.strip()
        return sha + ("+dirty" if dirty else "")
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


# =============================================================================
# Sections
# =============================================================================

# The headline configs. With EXP Share on, every party mon gets the same cut of
# every KO whoever lands it, so carry and rotate are the same run and only one
# is shown. With it off, the two are the extremes of how a player spreads KOs.
HEADLINE_CONFIGS = (
    ("EXP Share on", "equal", "rotate"),
    ("EXP Share off, carry (the starter takes every KO)", None, "carry"),
    ("EXP Share off, rotate (KOs spread across the party)", None, "rotate"),
)


def section_headline(g: parse.GameData, args, out: Path) -> list[str]:
    lines = ["## 1. Headline: HARD (the balance baseline), EXP Share on vs off\n",
             "Target: player's level ~ the enemy ace's level - 2 (the gym leader's ace at Gyms 1-8). "
             "Gaps are vs that target, Medium Slow curve; rows with `|gap| > 3` are bolded. "
             "`ace` is the starter, `team` the party average.\n"]
    all_rows = []
    args.headline = {}

    def gap_str(gap: float) -> str:
        return f"**{gap:+.1f}**" if abs(gap) > 3 else f"{gap:+.1f}"

    for title, exp_all, policy in HEADLINE_CONFIGS:
        cfg = model.Config(difficulty="hard", exp_all=exp_all, policy=policy)
        runs = model.simulate(g, cfg, args.runs, args.seed)
        rows = model.summarize(g, runs)
        args.headline[title] = rows
        lines.append(f"### {title}\n")
        lines.append("| checkpoint | battles | enemy ace | ace (p10-p90) | ace gap | team avg | team gap "
                     "| spendable money |")
        lines.append("|---|---|---|---|---|---|---|---|")
        for r in rows:
            target = r["enemy_ace"] - 2
            lines.append(f"| {r['label']} | {r['battles']:.0f} | {r['enemy_ace']:.1f} "
                         f"| {r['ace_medium_slow']:.1f} ({r['ace_medium_slow_p10']}-{r['ace_medium_slow_p90']}) "
                         f"| {gap_str(r['ace_medium_slow'] - target)} | {r['team_medium_slow']:.1f} "
                         f"| {gap_str(r['team_medium_slow'] - target)} | {r['spendable']:,.0f} |")
            all_rows.append({**config_row(cfg), **r, "team_gap_medium_slow": r["team_medium_slow"] - target})
        lines.append("")
    write_csv(out / "headline.csv", all_rows)
    return lines


def section_difficulty(g: parse.GameData, args, out: Path) -> list[str]:
    lines = ["## 3. Per difficulty (EXP Share on)\n"]
    all_rows = []
    for diff in model.DIFFICULTIES:
        cfg = model.Config(difficulty=diff, exp_all="equal", policy="rotate")
        runs = model.simulate(g, cfg, args.runs, args.seed)
        rows = model.summarize(g, runs)
        lines.append(f"### {diff}\n")
        lines.append(model.format_round_table(rows, cfg))
        lines.append("")
        for r in rows:
            all_rows.append({**config_row(cfg), **r})
    write_csv(out / "per_difficulty.csv", all_rows)
    return lines


def section_wild_vs_route(g: parse.GameData, args, out: Path) -> list[str]:
    lines = ["## 4. Route vs wild area (take_wild 0.0 vs 1.0; forced areas happen in both)\n",
             "Encounter-rolling steps come from ROM-generated layouts measured by "
             "`measure_wild_paths.py` (`tools/balance/data/wild_paths.json`), per wild-area "
             "type, on the `full` route (every ball, then the boss).\n"]
    all_rows = []
    cfgs = {"take_wild=0.0": model.Config(difficulty="hard", exp_all="equal", policy="rotate", take_wild=0.0),
            "take_wild=1.0": model.Config(difficulty="hard", exp_all="equal", policy="rotate", take_wild=1.0)}
    results = {}
    for name, cfg in cfgs.items():
        runs = model.simulate(g, cfg, args.runs, args.seed)
        rows = model.summarize(g, runs)
        results[name] = rows
        for r in rows:
            all_rows.append({**config_row(cfg), "label": name, **r})
    lines.append("| checkpoint | ace MedSlow (wild 0.0) | ace MedSlow (wild 1.0) | delta ace | "
                 "money (0.0) | money (1.0) | delta money |")
    lines.append("|---|---|---|---|---|---|---|")
    for r0, r1 in zip(results["take_wild=0.0"], results["take_wild=1.0"]):
        d_ace = r1["ace_medium_slow"] - r0["ace_medium_slow"]
        d_money = r1["spendable"] - r0["spendable"]
        lines.append(f"| {r0['label']} | {r0['ace_medium_slow']:.1f} | {r1['ace_medium_slow']:.1f} "
                     f"| {d_ace:+.1f} | {r0['spendable']:,.0f} | {r1['spendable']:,.0f} | {d_money:+,.0f} |")
    lines.append("")
    write_csv(out / "route_vs_wild.csv", all_rows)
    return lines


def section_money(g: parse.GameData, args, out: Path) -> list[str]:
    lines = ["## 5. Money: spendable earnings, converted to purchases\n",
             "Every money figure in this report is **spendable**: cumulative earned (starting money "
             "included) minus Elite Four and Champion winnings. Those five battles run back to back "
             "with no shop between them and the run ends after the Champion, so that money can't buy "
             "anything (`model.DEAD_MONEY_KINDS`). Spending isn't modelled. Purchases are what that "
             "amount alone could buy of one item, not a shopping plan.\n"]
    cfg = model.Config(difficulty="hard", exp_all="equal", policy="rotate")
    runs = model.simulate(g, cfg, args.runs, args.seed)
    rows = model.summarize(g, runs)
    prices = shop_prices(g)
    spend = statistics.mean(r.spendable_money for r in runs)
    total = statistics.mean(r.total_money for r in runs)
    lines.append(f"Per run: **Y{spend:,.0f} spendable** of Y{total:,.0f} earned; "
                 f"Y{total - spend:,.0f} ({(total - spend) / total:.0%}) is Elite Four + Champion "
                 "prize money and is excluded.\n")

    lines.append("### Where the money comes from (mean per run)\n")
    lines.append("| source | yen | share of earned |")
    lines.append("|---|---|---|")
    sources = money_by_source(g, cfg, runs)
    for src, yen in sorted(sources.items(), key=lambda kv: -kv[1]):
        lines.append(f"| {src} | {yen:,.0f} | {yen / total:.0%} |")
    lines.append("")

    lines.append("### Prices\n")
    lines.append("| item | price |")
    lines.append("|---|---|")
    names = {"full_restore": "Full Restore", "revive": "Revive", "vitamin": "Vitamin / HP Up",
             "pp_up": "PP Up", "rare_candy": "Rare Candy", "salesman_pokeball": "salesman Pokeball",
             "daycare_round": "daycare round"}
    names |= {f"tm_{t}": f"TM grade {t}" for t in TM_TIERS}
    names |= {f"tutor_{t}": f"tutor grade {t}" for t in TM_TIERS}
    for key, label in names.items():
        lines.append(f"| {label} | Y{prices[key]:,} |")
    lines.append("")

    lines.append("### Purchasing power at each checkpoint\n")
    lines.append("| checkpoint | spendable | Full Restores | Revives | Vitamins | PP Ups | "
                 "TMs (C) | TMs (B) | TMs (S) | tutor (B) | salesman Pokeballs | daycare rounds |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    buys = ("full_restore", "revive", "vitamin", "pp_up", "tm_C", "tm_B", "tm_S", "tutor_B",
            "salesman_pokeball", "daycare_round")
    all_rows = []
    for r in rows:
        m = r["spendable"]
        all_rows.append({**config_row(cfg), **r, **{f"buy_{k}": m / prices[k] for k in buys}})
        lines.append(f"| {r['label']} | {m:,.0f} | " + " | ".join(f"{m / prices[k]:.1f}" for k in buys) + " |")
    lines.append("")
    write_csv(out / "money.csv", all_rows)
    write_csv(out / "money_sources.csv", [{"source": k, "yen_per_run": v} for k, v in sources.items()])
    args.economy = {"rows": rows, "runs": runs, "spend": spend, "total": total,
                    "sources": sources, "prices": prices}
    return lines


def section_duration(g: parse.GameData, args, out: Path) -> list[str]:
    marker = CALIBRATION["source"]
    lines = [f"## 7. Duration (partly calibrated: {marker})\n",
             "Coefficients: " + ", ".join(f"{k}={v}" for k, v in CALIBRATION.items() if k != "source") + ".\n",
             "Battle seconds are fitted to `calibrate_battle_time.py` frame counts, a machine-speed "
             "floor (no trainer intro, no reading time). The overworld term is still a guess until "
             "one real timed run replaces it.\n"]
    cfg = model.Config(difficulty="hard", exp_all="equal", policy="rotate")
    durations = []
    for seed in range(args.runs):
        sim = model.Simulator(g, cfg, args.seed * 100003 + seed)
        run = sim.simulate()
        durations.append(duration_estimate(g, run))
    mean_sec = sum(durations) / len(durations)
    lines.append(f"Mean estimated duration: **{mean_sec / 3600:.2f} h** "
                 f"({mean_sec:.0f} s) across {len(durations)} runs. Target: {TARGET_DURATION_SEC / 3600:.1f} h.")
    lines.append(f"Delta vs target: {(mean_sec - TARGET_DURATION_SEC) / 60:+.0f} min.\n")
    write_csv(out / "duration.csv", [{"run": i, "seconds": d, **CALIBRATION} for i, d in enumerate(durations)])
    return lines


def history_row(g: parse.GameData, args) -> dict:
    eco = args.economy
    row = {
        "date": time.strftime("%Y-%m-%d %H:%M"),
        "commit": git_commit(),
        "runs": args.runs,
        "seed": args.seed,
        "spendable_per_run": round(eco["spend"]),
        "unspendable_per_run": round(eco["total"] - eco["spend"]),
    }
    for r in eco["rows"]:
        if r["round"] <= 9:
            key = "e4" if r["round"] == 9 else f"gym{r['round']}"
            row[f"spendable_{key}"] = round(r["spendable"])
    for src in ("route trainers", "gym trainers", "gym leaders", "mini-bosses", "stage events"):
        row["from_" + src.replace(" ", "_").replace("-", "_")] = round(eco["sources"].get(src, 0))
    for k in ("MONEY_BASE_TRAINER", "MONEY_BASE_LEADER", "MONEY_BASE_LEADER_GIOVANNI"):
        row[k.lower()] = g.knobs[k]
    for k, v in eco["prices"].items():
        row[f"price_{k}"] = v
    # Credit Exchange key items (credits, not yen); added 2026-10-09. Rows before
    # that date have these columns empty.
    for k, v in parse.load_credit_prices().items():
        row[f"credit_{k.lower()}"] = v
    # Level curve (added 2026-10-09): mean leader gap per round and at the Champion
    # (HARD, EXP Share on), and the team's level there. Older rows leave them empty.
    lv = getattr(args, "levels", None)
    if lv:
        for r in range(1, 9):
            row[f"gap_leader_r{r}"] = round(lv["gaps"][r]["Leader"], 2)
        row["gap_champion"] = round(lv["gaps"][9]["Champion"], 2)
        row["gap_leader_p90_max"] = max(lv["p90"][r]["Leader"] for r in range(1, 9))
        row["team_at_champion"] = round(lv["rows"][-1]["team_rolled"], 2)
        row["leader_aces"] = " ".join(map(str, curve.leader_aces(g)))
    row["wild_levels"] = " ".join(map(str, g.tables.wild))
    row["wild_boss_levels"] = " ".join(map(str, g.tables.wild_boss))
    return row


def section_levels(g: parse.GameData, args, out: Path) -> list[str]:
    """Level gaps by round against tools/balance/data/gap_targets.csv, the hardest
    10% of fights, and the leader gap by the starter's growth rate. HARD, EXP
    Share on, today's run shape (Config defaults)."""
    cfg = model.Config(difficulty="hard", exp_all="equal", policy="rotate")
    runs = model.simulate(g, cfg, args.runs, args.seed)
    rows = model.summarize(g, runs)
    gaps = curve.gap_table(runs)
    p90 = curve.gap_percentile(runs, 0.9)
    targets = curve.load_targets()
    misses = curve.out_of_tolerance(gaps, targets) if targets else []
    args.levels = {"gaps": gaps, "p90": p90, "rows": rows}
    lines = ["## 2. Level gaps vs targets (HARD, EXP Share on)\n",
             "Gap = enemy top level - the rolled starter's level when the battle starts. Targets: "
             f"`{curve.TARGETS_CSV.relative_to(ROOT).as_posix()}` (cells marked `!` are outside their "
             "tolerance). Re-solve or check a curve with `tools/balance/curve_solver.py`.\n"]
    if targets:
        lines.append(f"**{len(misses)} of {len(curve.deviations(gaps, targets))} cells outside tolerance.**\n")
    else:
        lines.append("_No targets file: run `curve_solver.py --write-targets`._\n")
    lines += curve.fmt_gap_table("Mean gap per round", gaps, rows, targets or None)
    lines += ["### The hardest 10% of fights (90th-percentile gap)\n",
              "| Round | " + " | ".join(("Route boss", "Wild boss", "Gym final", "Leader")) + " |",
              "|---|---|---|---|---|"]
    for r in range(1, 9):
        cells = [f"{p90[r][c]:+.0f}" if c in p90.get(r, {}) else "" for c in ("Route boss", "Wild boss", "Gym final", "Leader")]
        lines.append(f"| {r} | " + " | ".join(cells) + " |")
    fin = p90.get(9, {})
    lines += ["", "Finale: " + ", ".join(f"{c} {fin[c]:+.0f}" for c in ("E4", "Champion") if c in fin) + ".\n"]

    # Leader gap by the starter's growth rate (the rolled starter, not a pinned curve).
    by_growth: dict[str, dict[int, list[int]]] = {}
    for run in runs:
        growth = run.checkpoints[0].ace_growth.removeprefix("GROWTH_").lower()
        for rnd, kind, gap in run.gaps:
            if kind in ("leader", "champion"):
                by_growth.setdefault(growth, {}).setdefault(rnd, []).append(gap)
    lines += ["### Leader gap by the starter's growth rate\n",
              "| Growth (share of runs) | " + " | ".join(f"L{r}" for r in range(1, 9)) + " | Champion |",
              "|---" * 10 + "|"]
    total = len(runs)
    for growth, per in sorted(by_growth.items(), key=lambda kv: -len(kv[1].get(1, []))):
        share = len(per.get(1, [])) / total
        cells = [f"{statistics.mean(per[r]):+.1f}" if r in per else "" for r in range(1, 10)]
        lines.append(f"| {growth} ({share:.0%}) | " + " | ".join(cells) + " |")
    lines.append("")
    flat = [{"round": r, "column": c, "mean": gaps[r][c], "p90": p90[r].get(c),
             "target": targets.get(r, {}).get(c, (None,))[0] if targets else None}
            for r in sorted(gaps) for c in gaps[r]]
    write_csv(out / "level_gaps.csv", flat)
    return lines


def load_shopping_plan() -> dict:
    return json.loads((HERE / "data" / "shopping_plan.json").read_text(encoding="utf-8"))


def simulate_shopping(spend_by_gym: list[float], prices: dict[str, int], plan: list[dict]) -> dict:
    """Greedy buyer over mean spendable money at each leader (Gyms 1-8, then the
    E4 checkpoint): at each stop buy plan lines in priority order, as many units
    as the purse allows. Returns per-line completion stop and the money left."""
    bought = [0] * len(plan)
    done_at: list[str | None] = [None] * len(plan)
    spent = 0.0
    stops = [f"Gym {i + 1}" for i in range(8)] + ["E4"]
    for stop_i, (stop, earned) in enumerate(zip(stops, spend_by_gym)):
        gyms_beaten = stop_i + 1 if stop_i < 8 else 8
        for i, line in enumerate(plan):
            if line["from_gym"] > gyms_beaten or bought[i] >= line["count"]:
                continue
            price = prices[line["item"]]
            while bought[i] < line["count"] and earned - spent >= price:
                spent += price
                bought[i] += 1
            if bought[i] >= line["count"] and done_at[i] is None:
                done_at[i] = stop
    return {"done_at": done_at, "bought": bought, "spent": spent, "left": spend_by_gym[-1] - spent}


def section_shopping(g: parse.GameData, args, out: Path) -> list[str]:
    plan_doc = load_shopping_plan()
    plan = plan_doc["plan"]
    prices = shop_prices(g)
    cost = sum(prices[l["item"]] * l["count"] for l in plan)
    lines = ["## 6. Shopping plan per difficulty (assumed plan)\n",
             f"_{plan_doc['note']}_ Plan cost Y{cost:,}. Each cell is the stop where that line is fully "
             "bought (`-` = never). Money is the mean spendable at each leader; Amulet Coin off.\n"]
    header = "| Line | Cost |"
    sep = "|---|---|"
    results = {}
    for diff in ("very_easy", "easy", "normal", "hard", "very_hard"):
        cfg = model.Config(difficulty=diff, exp_all="equal", policy="rotate")
        runs = model.simulate(g, cfg, args.runs, args.seed)
        rows = model.summarize(g, runs)
        spend = [r["spendable"] for r in rows[:9]]
        results[diff] = simulate_shopping(spend, prices, plan)
        header += f" {diff.replace('_', ' ').title()} |"
        sep += "---|"
    lines += [header, sep]
    out_rows = []
    for i, line in enumerate(plan):
        label = f"{line['count']}x {line['item']} (from Gym {line['from_gym']})"
        cells = [results[d]["done_at"][i] or "-" for d in results]
        lines.append(f"| {label} | Y{prices[line['item']] * line['count']:,} | " + " | ".join(cells) + " |")
        out_rows.append({"line": label, **{d: results[d]["done_at"][i] for d in results}})
    lines.append("| **Left at the E4** | | " + " | ".join(f"Y{results[d]['left']:,.0f}" for d in results) + " |")
    lines.append("")
    write_csv(out / "shopping.csv", out_rows)
    return lines


def section_history(g: parse.GameData, args, out: Path) -> list[str]:
    lines = ["## 8. Economy history\n",
             f"`{HISTORY_CSV.relative_to(ROOT).as_posix()}` gets one row per report run on the "
             "unmodified knobs (what-if runs with `--set` are not recorded). Commit it with the "
             "tuning change it measures.\n"]
    row = history_row(g, args)
    history: list[dict] = []
    if HISTORY_CSV.exists():
        with HISTORY_CSV.open(newline="", encoding="utf-8") as f:
            history = list(csv.DictReader(f))
    if args.set or args.no_history:
        lines.append("_This run was not recorded (" + ("--set overrides" if args.set else "--no-history")
                     + "); it is shown last for comparison._\n")
    else:
        history.append(row)
        fields = list(dict.fromkeys([*(history[0].keys() if history else []), *row.keys()]))
        with HISTORY_CSV.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=fields, restval="", lineterminator="\n")
            w.writeheader()
            w.writerows(history)
    shown = history[-HISTORY_ROWS_SHOWN:] + ([row] if (args.set or args.no_history) else [])
    lines.append("| date | commit | spendable/run | by Gym 4 | by E4 | leaders | route | "
                 "trainer/leader base | TM B | Vitamin | PP Up | wild L (r1-r8) | boss L (r1-r8) |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    prev = None
    for h in shown:
        spend = int(h["spendable_per_run"])
        delta = f" ({(spend - prev) / prev:+.0%})" if prev else ""
        prev = spend
        wild = " ".join(str(h["wild_levels"]).split()[1:])
        boss = " ".join(str(h["wild_boss_levels"]).split()[1:])
        lines.append(f"| {h['date']} | {h['commit']} | {spend:,}{delta} | {int(h['spendable_gym4']):,} "
                     f"| {int(h['spendable_e4']):,} | {int(h['from_gym_leaders']):,} "
                     f"| {int(h['from_route_trainers']):,} "
                     f"| {h['money_base_trainer']}/{h['money_base_leader']} | {int(h['price_tm_B']):,} "
                     f"| {int(h['price_vitamin']):,} | {int(h['price_pp_up']):,} | {wild} | {boss} |")
    lines.append("")
    return lines


def level_findings(args) -> list[str]:
    """Finding 1: each headline config's gap at a few checkpoints, read off the
    section 1 tables so the text can't go stale."""
    picks = ("Gym 1", "Gym 4", "Gym 8", "Champion")
    out = ["1. **Levels vs \"enemy ace - 2\"** (Medium Slow; ace gap / team gap at "
           + ", ".join(picks) + "):\n"]
    for title, rows in args.headline.items():
        by = {r["label"]: r for r in rows}
        cells = ", ".join(f"{by[p]['ace_medium_slow'] - by[p]['enemy_ace'] + 2:+.0f} / "
                          f"{by[p]['team_medium_slow'] - by[p]['enemy_ace'] + 2:+.0f}" for p in picks)
        out.append(f"   - {title}: {cells}.\n")
    return ["".join(out)]


def section_findings(args) -> list[str]:
    return [
        "## 9. Findings\n",
        *level_findings(args),
        "2. **Special encounters: two wild areas and two mini-bosses every run.** "
        "`SpecialEncounterPolicy`'s joint quota (completed encounters, by half-run) is mirrored by "
        "`model.special_encounter_policy`; the selfcheck asserts 2 + 2 even for a player who declines "
        "every optional door, with and without skipped routes. (The 2026-09 \"fails 53%\" finding was "
        "the retired per-kind logic.)\n",
        f"3. **Spendable money is about Y{args.economy['spend']:,.0f} per run** "
        f"(Y{args.economy['total']:,.0f} earned, minus the Elite Four and Champion prizes). "
        f"Gym leaders give {args.economy['sources'].get('gym leaders', 0) / args.economy['spend']:.0%} "
        "of it; see section 5 for the full breakdown.\n",
    ]


def section_caveats() -> list[str]:
    return [
        "## 10. Known approximations\n",
        "- Round-1 leader variant A is an authored team in the ROM (the `wTrainerNo 1` hole). "
        "The model rolls it from the pool at the same levels.\n",
        "- Johto/Warp runs: leaders are sampled from all 17 records and the E4 stays the Kanto "
        "four. The real Phase 7 lineup roll isn't mirrored. Kanto-only (the default) is exact.\n",
        "- The Gambler class, witch challenges/prizes, Element Prism, Rare Scope, and the "
        "ownership re-roll in `RogueSelectFromTier` are ignored.\n",
        "- Wild encounters are `min(budget, Binomial(rolling steps, rate/256))`, with rolling "
        "steps sampled from measured layouts of the offered type. The route is the shortest "
        "tour past every ball to the boss; a player who wanders gets more rolls.\n",
        "- One reward mon joins per stage, at `GetRewardMonLevel`. Boss catches, salesman "
        "buys and daycare aren't modelled as joins.\n",
        "- A stage event is one battle when armed and taken. Jessie & James counts as a "
        "single battle, matching \"beating either half ends the encounter\".\n",
        "- Money spending isn't modelled; every money figure is cumulative earned, minus the "
        "Elite Four and Champion prizes (unspendable).\n",
        "- The player wins every battle. Win difficulty is Phase 3.\n",
        "- The Champion is RIVAL3 (`Rival3Spec`, levels 60-65). Champion Lance / Oak aren't modelled.\n",
        "- Duration (section 7): battle seconds are a measured machine-speed floor; the overworld "
        "term waits on a real timed run.\n",
    ]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default=str(ROOT / "tmp" / "balance"))
    ap.add_argument("--set", action="append", default=[], metavar="KNOB=VALUE")
    ap.add_argument("--no-history", action="store_true",
                    help=f"don't append this run to {HISTORY_CSV.name}")
    ap.add_argument("--no-stamp", action="store_true",
                    help="write straight into --out instead of a new dated subfolder")
    args = ap.parse_args(argv)

    # Each report gets its own dated folder under --out: an older report that
    # is open in Excel can't block the new one, and the folders are the tuning
    # history. LATEST.md beside them names the newest.
    base = Path(args.out)
    stamp = time.strftime("%Y-%m-%d_%H%M%S")
    out = base if args.no_stamp else base / stamp
    out.mkdir(parents=True, exist_ok=True)

    g = model.apply_overrides(parse.load_all(), args.set)

    fails = model.selfcheck(g, 200)
    if fails:
        for f in fails:
            print("FAIL", f)
        print("report: aborted, selfcheck failed")
        return 1

    lines = ["# Red Rogue Balance Report\n",
             f"Generated from `tools/balance/report.py`, {args.runs} runs per config, seed {args.seed}.\n"]
    for section in (section_headline, section_levels, section_difficulty,
                    section_wild_vs_route, section_money, section_shopping, section_duration, section_history):
        lines += section(g, args, out)
    lines += section_findings(args)
    lines += section_caveats()

    report_path = out / "BALANCE_REPORT.md"
    report_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {report_path}")
    for csv_path in sorted(out.glob("*.csv")):
        print(f"wrote {csv_path}")
    if not args.no_stamp:
        overrides = ", ".join(args.set) or "none"
        latest = base / "LATEST.md"
        try:
            latest.write_text(
                f"# Latest balance report\n\n[{stamp}/BALANCE_REPORT.md]({stamp}/BALANCE_REPORT.md)\n\n"
                f"{args.runs} runs per config, seed {args.seed}, overrides: {overrides}.\n",
                encoding="utf-8")
            print(f"wrote {latest}")
        except PermissionError:
            print(f"note: {latest} is open elsewhere; the report itself is in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
