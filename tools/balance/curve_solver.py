"""Solve, check and record level curves against gap targets (model only).

  # Record the targets: measure the curve the source holds today.
  python tools/balance/curve_solver.py --write-targets

  # How far is the source from the targets? (no solve)
  python tools/balance/curve_solver.py --from-round 0

  # Re-solve every round for a new run shape, then show the edits to make.
  python tools/balance/curve_solver.py --starter-level 8 --skip 4,7 --exp-all equal6875

  # A named curve (shifts + hand adjustments), optionally re-solved from a round.
  python tools/balance/curve_solver.py --curve G --from-round 0
  python tools/balance/curve_solver.py --curve G --from-round 1

  # Hand adjustments on top: KIND@ROUND:DELTA, KIND in route/gym/leader/wild/boss/stage/miniboss
  python tools/balance/curve_solver.py --curve G --from-round 0 --adjust leader@6:+1

Gap = enemy top level - the rolled starter's level when the battle starts.
Difficulty is HARD (the balance baseline). Nothing is written to the .asm: the
"Edits" section lists the values to change by hand (BALANCE_CHANGELOG rule).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import curve  # noqa: E402
import model  # noqa: E402
import parse  # noqa: E402
from model import Config  # noqa: E402

# Named curves: the run shape they assume, the per-round shifts from the
# source's tables as of 2026-10-09 (Curve F), and hand adjustments after.
CURVES = {
    "F": dict(config={}, shifts={}, adjust=[]),
    # Curve G (2026-10-09 player-feedback pass, "A+" in the Phase 0 docs): Curve
    # F's gaps re-solved from round 1 for an L8 start, routes 4 and 7 skipped and
    # EXP Share 68.75%; then Gym 4 -1 and round 8's non-gym fights -1.
    "G": dict(config=dict(starter_level=8, rival_level=8, skip_rounds=(4, 7), exp_all="equal6875"),
              shifts={1: 2, 2: 2, 3: 2, 7: -3, 8: -2, 9: -1},
              adjust=[("gym", 4, -1), ("route", 8, -1), ("wild", 8, -1), ("boss", 8, -1), ("stage", 8, -1)]),
}


def parse_adjust(spec: str) -> tuple[str, int, int]:
    kind, rest = spec.split("@")
    rnd, delta = rest.split(":")
    if kind not in curve.ADJUST_KINDS:
        raise argparse.ArgumentTypeError(f"kind must be one of {curve.ADJUST_KINDS}")
    return kind, int(rnd), int(delta)


def git_commit() -> str:
    try:
        sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True,
                             cwd=curve.HERE).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True,
                               cwd=curve.HERE).stdout.strip()
        return sha + ("+dirty" if dirty else "")
    except OSError:
        return "?"


def edits(before, after) -> list[str]:
    out = []
    a, b = curve.table_values(before), curve.table_values(after)
    for name in a:
        if a[name] != b[name]:
            changed = [(f"R{i + 1} " if len(a[name]) > 1 else "") + f"{x}->{y}" for i, (x, y) in enumerate(zip(a[name], b[name])) if x != y]
            out.append(f"- `{name}`: {' '.join(map(str, b[name]))}  ({', '.join(changed)})")
    return out or ["- none"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runs", type=int, default=1000, help="runs for the final measurement")
    ap.add_argument("--solve-runs", type=int, default=300)
    ap.add_argument("--curve", choices=tuple(CURVES), help="start from a named curve (shape, shifts, adjustments)")
    ap.add_argument("--starter-level", type=int)
    ap.add_argument("--skip", help="rounds whose route is skipped, e.g. 4,7")
    ap.add_argument("--exp-all", choices=model.EXP_SHARE_CANDIDATES)
    ap.add_argument("--from-round", type=int, default=1, help="solve rounds from here on (0 = no solve)")
    ap.add_argument("--ease", default="0,0", help="target minus this: round 1, later rounds")
    ap.add_argument("--adjust", action="append", type=parse_adjust, default=[], metavar="KIND@ROUND:DELTA")
    ap.add_argument("--write-targets", action="store_true", help="measure the current source and save targets")
    ap.add_argument("--tolerance", type=float, default=0.5)
    ap.add_argument("--out", type=Path)
    args = ap.parse_args()

    g0 = parse.load_all()
    named = CURVES[args.curve] if args.curve else dict(config={}, shifts={}, adjust=[])
    cfg = Config(**named["config"])
    if args.starter_level is not None:
        cfg = replace(cfg, starter_level=args.starter_level, rival_level=args.starter_level)
    if args.skip is not None:
        cfg = replace(cfg, skip_rounds=tuple(int(x) for x in args.skip.split(",") if x))
    if args.exp_all is not None:
        cfg = replace(cfg, exp_all=args.exp_all)

    if args.write_targets:
        _, gaps, rows = curve.run(g0, Config(), args.runs)
        note = (f"Measured {time.strftime('%Y-%m-%d')} at {git_commit()} from the source as it stands "
                f"(today's run shape, HARD), {args.runs} runs.")
        curve.write_targets(gaps, note, args.tolerance)
        print(f"wrote {curve.TARGETS_CSV}")
        return 0

    targets = curve.load_targets()
    if not targets:
        print("no targets: run with --write-targets first")
        return 1
    target_means = {r: {c: t for c, (t, _) in cols.items()} for r, cols in targets.items()}

    g = g0
    for r, d in named["shifts"].items():
        g = curve.shift_round(g, r, d)
    for kind, r, d in named["adjust"]:
        g = curve.adjust(g, kind, r, d)
    shifts = {}
    if args.from_round:
        ease = tuple(float(x) for x in args.ease.split(","))
        g, shifts = curve.solve(g, cfg, target_means, args.from_round, args.solve_runs, ease)
    for kind, r, d in args.adjust:
        g = curve.adjust(g, kind, r, d)

    _, gaps, rows = curve.run(g, cfg, args.runs)
    misses = curve.out_of_tolerance(gaps, targets)
    shape = (f"starter L{cfg.starter_level}, skipped routes {list(cfg.skip_rounds) or 'none'}, "
             f"EXP Share {cfg.exp_all}")
    out = [f"# Curve solve ({time.strftime('%Y-%m-%d %H:%M')}, {git_commit()})", "",
           f"Run shape: {shape}. Difficulty HARD. {args.runs} runs. Curve: {args.curve or 'source'}; "
           f"solved from round {args.from_round or 'none'}; adjustments {args.adjust or 'none'}.", "",
           f"- Leader aces: {' '.join(map(str, curve.leader_aces(g)))} "
           f"(source {' '.join(map(str, curve.leader_aces(g0)))})",
           f"- Team average at the Champion: {rows[-1]['team_rolled']:.1f}; starter {rows[-1]['ace_rolled']:.1f}",
           f"- Spendable money (HARD, its prize bonus included): {rows[-1]['spendable']:,.0f}",
           f"- Cells outside tolerance: {len(misses)} of {len(curve.deviations(gaps, targets))}", ""]
    if shifts:
        out += ["Per-round shift from the solve: "
                + ", ".join(f"R{r if r < 9 else 'finale'} {d:+d}" for r, d in shifts.items()), ""]
    out += curve.fmt_gap_table("Gaps: target / this curve (`!` = outside tolerance)", gaps, rows, targets,
                               compare=target_means)
    out += ["## Edits to make in the source (vs today's values)", ""] + edits(g0, g) + [""]
    text = "\n".join(out) + "\n"
    if args.out:
        args.out.write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote {args.out}")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
