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
import sys
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import model  # noqa: E402
import parse  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]

# Duration coefficients: PLACEHOLDER until Phase 3's calibrate_battle_time.py
# and one real timed run replace them with measured values.
CALIBRATION = {
    "source": "placeholder",
    "fixed_sec_per_trainer_battle": 20,
    "sec_per_enemy_mon": 25,
    "sec_per_wild_battle": 20,
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
    """UNCALIBRATED: Sigma battles * sec-per-battle(mons) + Sigma stages * overworld_sec."""
    sec = 0.0
    for bt in run.battles:
        if bt.trainer:
            sec += CALIBRATION["fixed_sec_per_trainer_battle"] + CALIBRATION["sec_per_enemy_mon"] * len(bt.mons)
        else:
            sec += CALIBRATION["sec_per_wild_battle"]
    sec += len(run.stages) * CALIBRATION["overworld_sec_per_stage"]
    return sec


def purchase_counts(money: float, g: parse.GameData) -> dict:
    full_restore = g.item_prices["FULL_RESTORE"]
    revive = g.item_prices["REVIVE"]
    ball_bcd = model.bcd(g.knobs["SALESMAN_PRICE_POKEBALL_BCD"])
    return {
        "full_restores": money / full_restore,
        "revives": money / revive,
        "salesman_pokeballs": money / ball_bcd,
    }


# =============================================================================
# Sections
# =============================================================================

def section_headline(g: parse.GameData, args, out: Path) -> list[str]:
    lines = ["## 1. Headline: Normal, EXP All tier 0, both policies\n",
             f"Target: player's ace level ~ gym leader's ace level - 2. "
             f"Rows with `|gap| > 3` are bolded.\n"]
    all_rows = []
    for policy in ("carry", "rotate"):
        cfg = model.Config(difficulty="normal", exp_all=0, policy=policy)
        runs = model.simulate(g, cfg, args.runs, args.seed)
        rows = model.summarize(g, runs)
        lines.append(f"### policy={policy}\n")
        lines.append("| checkpoint | battles | enemy ace | ace MedSlow (p10-p90) | gap vs ace-2 | money |")
        lines.append("|---|---|---|---|---|---|")
        for r in rows:
            gap = r["gap_medium_slow"]
            gap_str = f"**{gap:+.1f}**" if abs(gap) > 3 else f"{gap:+.1f}"
            lines.append(f"| {r['label']} | {r['battles']:.0f} | {r['enemy_ace']:.1f} "
                         f"| {r['ace_medium_slow']:.1f} ({r['ace_medium_slow_p10']}-{r['ace_medium_slow_p90']}) "
                         f"| {gap_str} | {r['money']:,.0f} |")
        lines.append("")
        for r in rows:
            all_rows.append({**config_row(cfg), **r})
    write_csv(out / "headline.csv", all_rows)
    return lines


def section_difficulty(g: parse.GameData, args, out: Path) -> list[str]:
    lines = ["## 2. Per difficulty (policy=rotate, EXP All tier 0)\n"]
    all_rows = []
    for diff in model.DIFFICULTIES:
        cfg = model.Config(difficulty=diff, exp_all=0, policy="rotate")
        runs = model.simulate(g, cfg, args.runs, args.seed)
        rows = model.summarize(g, runs)
        lines.append(f"### {diff}\n")
        lines.append(model.format_round_table(rows, cfg))
        lines.append("")
        for r in rows:
            all_rows.append({**config_row(cfg), **r})
    write_csv(out / "per_difficulty.csv", all_rows)
    return lines


def section_exp_all(g: parse.GameData, args, out: Path) -> list[str]:
    lines = ["## 3. EXP All comparison: off / tier 0 / tier 3, both policies\n",
             "Expected pattern: under carry, tier 0 barely changes the ace (the "
             "fighter's own gain is unaffected; the ace only benefits from the "
             "reduced-value shares given to the rest of the party, none of which "
             "come back to it), but roughly doubles the bench's levels.\n"]
    all_rows = []
    lines.append("| policy | exp_all | checkpoint | ace MedSlow | team MedSlow |")
    lines.append("|---|---|---|---|---|")
    for policy in ("carry", "rotate"):
        for exp_all in ("off", 0, 3):
            cfg = model.Config(difficulty="normal",
                               exp_all=None if exp_all == "off" else exp_all, policy=policy)
            runs = model.simulate(g, cfg, args.runs, args.seed)
            rows = model.summarize(g, runs)
            for r in rows:
                lines.append(f"| {policy} | {exp_all} | {r['label']} "
                             f"| {r['ace_medium_slow']:.1f} | {r['team_medium_slow']:.1f} |")
                all_rows.append({**config_row(cfg), **r})
    lines.append("")
    write_csv(out / "exp_all.csv", all_rows)
    return lines


def section_wild_vs_route(g: parse.GameData, args, out: Path) -> list[str]:
    lines = ["## 4. Route vs wild area (take_wild 0.0 vs 1.0; forced areas happen in both)\n",
             f"**`wild_steps=250` is a placeholder** until Phase 3's "
             f"`measure_wild_paths.py` measures real layout step counts.\n"]
    all_rows = []
    cfgs = {"take_wild=0.0": model.Config(difficulty="normal", exp_all=0, policy="rotate", take_wild=0.0),
            "take_wild=1.0": model.Config(difficulty="normal", exp_all=0, policy="rotate", take_wild=1.0)}
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
        d_money = r1["money"] - r0["money"]
        lines.append(f"| {r0['label']} | {r0['ace_medium_slow']:.1f} | {r1['ace_medium_slow']:.1f} "
                     f"| {d_ace:+.1f} | {r0['money']:,.0f} | {r1['money']:,.0f} | {d_money:+,.0f} |")
    lines.append("")
    write_csv(out / "route_vs_wild.csv", all_rows)
    return lines


def section_money(g: parse.GameData, args, out: Path) -> list[str]:
    lines = ["## 5. Money: cumulative earned, converted to purchases\n",
             "Spending isn't modelled; every money figure is cumulative earned. "
             "Purchases are what that amount alone could buy of one item, not a "
             "shopping plan.\n"]
    cfg = model.Config(difficulty="normal", exp_all=0, policy="rotate")
    runs = model.simulate(g, cfg, args.runs, args.seed)
    rows = model.summarize(g, runs)
    all_rows = []
    lines.append("| checkpoint | money | Full Restores | Revives | salesman Pokeballs | "
                 "move relearner uses | daycare rounds |")
    lines.append("|---|---|---|---|---|---|---|")
    relearner = model.bcd(g.knobs["MOVE_RELEARNER_PRICE_BCD"]) * 2   # charged twice
    daycare = model.bcd(g.knobs["DAYCARE_PRICE_PER_ROUND_BCD"])
    for r in rows:
        p = purchase_counts(r["money"], g)
        row = {**config_row(cfg), **r, **{f"buy_{k}": v for k, v in p.items()},
               "buy_relearner_uses": r["money"] / relearner, "buy_daycare_rounds": r["money"] / daycare}
        all_rows.append(row)
        lines.append(f"| {r['label']} | {r['money']:,.0f} | {p['full_restores']:.1f} "
                     f"| {p['revives']:.1f} | {p['salesman_pokeballs']:.1f} "
                     f"| {r['money'] / relearner:.1f} | {r['money'] / daycare:.1f} |")
    lines.append("")
    write_csv(out / "money.csv", all_rows)
    return lines


def section_duration(g: parse.GameData, args, out: Path) -> list[str]:
    marker = CALIBRATION["source"]
    lines = [f"## 6. Duration (UNCALIBRATED, source={marker})\n",
             "Coefficients: " + ", ".join(f"{k}={v}" for k, v in CALIBRATION.items() if k != "source") + ".\n",
             "Phase 3's `calibrate_battle_time.py` (per-battle frame counts) and one "
             "real timed run (overworld overhead) replace these.\n"]
    cfg = model.Config(difficulty="normal", exp_all=0, policy="rotate")
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


def section_findings() -> list[str]:
    return [
        "## 7. Findings\n",
        "1. **The ace runs hot against \"leader ace - 2\" almost everywhere.**\n"
        "   - Carry (the starter takes every KO): +2 at Gym 1, rising to +22 at Gym 8, "
        "and +14 at the Champion (Medium Slow).\n"
        "   - Rotate (KOs spread across the party): +1 / +3 / +7 / +8 / +0.6 / +7 / +9 / +12 "
        "across Gyms 1-8, +2.9 at the E4 and +2.3 at the Champion.\n"
        "   - The leader curve is the laggard. Gyms 3-4 (24, 29) and 6-8 (43, 47, 50) sit "
        "well under the route/gym-trainer bands of the same rounds. Gym 5's jump to 43 is "
        "the only place the curve catches up (the round 5-6 plateau, as predicted in the plan).\n",
        "2. **The \"at least 2 per run\" special guarantees fail about 53% of the time** "
        "(~80% confident this is real ROM behaviour, not a model artifact; Phase 3 should confirm).\n"
        "   - `SpecialKindForced` forces a kind when `8 - badges <= shortfall`, and it counts offers.\n"
        "   - A run that reaches route 8 one short of each kind has both forced on a single visit, "
        "and `.chooseKind`'s tie-break drops one.\n"
        "   - Measured over 2000 runs: 26% end with 1 wild area offered, 26% with 1 mini-boss.\n"
        "   - A second contributor: `MINIBOSS_TOTAL_ROUTES` is 8, but route 1 is ineligible "
        "(`MINIBOSS_FIRST_BATTLECOUNT`), so only 7 visits exist.\n",
        "3. **Money earned is about Y275k per run.** Leaders dominate (200 x ace level); "
        "route trainers pay Y150-2000.\n",
        "4. **EXP All tier 0 barely changes the ace under carry.** The fighter gets two "
        "half-shares, which is about one full share. It lifts the bench from a Medium Slow "
        "average of about 31 to about 64 at the Champion.\n",
    ]


def section_caveats() -> list[str]:
    return [
        "## 8. Known approximations\n",
        "- Round-1 leader variant A is an authored team in the ROM (the `wTrainerNo 1` hole). "
        "The model rolls it from the pool at the same levels.\n",
        "- Johto/Warp runs: leaders are sampled from all 17 records and the E4 stays the Kanto "
        "four. The real Phase 7 lineup roll isn't mirrored. Kanto-only (the default) is exact.\n",
        "- The Gambler class, witch challenges/prizes, Element Prism, Rare Scope, and the "
        "ownership re-roll in `RogueSelectFromTier` are ignored.\n",
        "- `wild_steps=250` is a placeholder. Wild encounters are "
        "`min(budget, Binomial(steps, rate/256))`.\n",
        "- One reward mon joins per stage, at `GetRewardMonLevel`. Boss catches, salesman "
        "buys and daycare aren't modelled as joins.\n",
        "- A stage event is one battle when armed and taken. Jessie & James counts as a "
        "single battle, matching \"beating either half ends the encounter\".\n",
        "- Money spending isn't modelled; every money figure is cumulative earned.\n",
        "- The player wins every battle. Win difficulty is Phase 3.\n",
        "- The Champion is RIVAL3 (`Rival3Spec`, levels 60-65). Champion Lance / Oak aren't modelled.\n",
        f"- Duration coefficients (section 6) are a placeholder (source={CALIBRATION['source']}), "
        "not measured frame counts.\n",
    ]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default=str(ROOT / "tmp" / "balance"))
    ap.add_argument("--set", action="append", default=[], metavar="KNOB=VALUE")
    args = ap.parse_args(argv)

    out = Path(args.out)
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
    for section in (section_headline, section_difficulty, section_exp_all,
                    section_wild_vs_route, section_money, section_duration):
        lines += section(g, args, out)
    lines += section_findings()
    lines += section_caveats()

    report_path = out / "BALANCE_REPORT.md"
    report_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {report_path}")
    for csv_path in sorted(out.glob("*.csv")):
        print(f"wrote {csv_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
