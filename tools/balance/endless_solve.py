#!/usr/bin/env python3
"""Solve data/balance/endless_levels.asm: the Endless level bonus per round.

ENDLESS_MODE_CHECKPOINT_D.md section 3.3. Past the original circuit every
round-indexed table sits on its last authored row, so encounter SHAPE stays at
its maximum; levels grow by one bonus per global round (EndlessLevelRows),
added before the difficulty % (the level funnel, func_enc_gen.asm).

The rows are not chosen, they are solved: the user's rule (2026-10-28) is to
hold the gap the original run ends on, until level 100. So:

  targets  for each encounter kind, the median enemy-ace-minus-starter gap at
           the last round that kind is fought in the ORIGINAL circuit
           (model.py at depth 0, same policy, same seed set);
  update   simulate the run into Endless with the current rows; in every
           Endless round, move that round's row by the mean error over the
           kinds fought there (a kind pinned at level 100 still votes down
           when it is over target, but not up);
           rows never decrease and stop at the value that puts every
           category at 100;
  repeat   until no row moves.

Usage:  python3 tools/balance/endless_solve.py [--runs N] [--depth D] [--write]
        --write  emit data/balance/endless_levels.asm (else print only)
"""

import argparse
import statistics
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import model  # noqa: E402
import parse  # noqa: E402

OUT = parse.ROOT / parse.ENDLESS_LEVELS


class Recorder(model.Simulator):
    """Records (depth, global round, kind, gap, enemy ace) for every fight."""

    def __init__(self, g, cfg, seed, sink):
        super().__init__(g, cfg, seed)
        self.sink = sink
        self._round = 0

    def p(self, count=None):
        prog = super().p(count)
        self._round = prog // self.g.knobs["ROUND_BATTLES"]
        return prog

    def fight(self, battle):
        if battle.mons:
            ace = max(lv for _, lv in battle.mons)
            gap = ace - self.members[0].level(self.g)
            self.sink.append((self.depth, self._round, battle.kind, gap, ace))
        super().fight(battle)


def run(g, rows, depth, runs, seed=1):
    cfg = model.Config(difficulty="hard", endless_depth=depth, endless_rows=tuple(rows))
    sink = []
    for i in range(runs):
        Recorder(g, cfg, seed * 100003 + i, sink).simulate()
    return sink


def targets(g, runs):
    """Median gap per kind at the last round it appears in the original circuit."""
    last = {}
    by = defaultdict(list)
    for depth, rnd, kind, gap, _ in run(g, [0] * 23, 0, runs):
        by[(kind, rnd)].append(gap)
        last[kind] = max(last.get(kind, -1), rnd)
    return {kind: statistics.median(by[(kind, rnd)]) for kind, rnd in last.items()
            if kind != "oak_rival"}


def row_max(g):
    """The bonus that puts every category's final-row base at 100."""
    t, k = g.tables, g.knobs
    last = k["LAST_ROUND_BATTLECOUNT"] // k["ROUND_BATTLES"]
    bases = [t.route[last].min_level, t.gym[last].min_level, t.wild[last], t.wild_boss[last]]
    return model.MAX_LEVEL - min(bases)


def solve(g, runs, depth, iterations=12):
    first = g.knobs["LAST_ROUND_BATTLECOUNT"] // g.knobs["ROUND_BATTLES"] + 1
    n = 255 // g.knobs["ROUND_BATTLES"] + 1 - first
    target = targets(g, runs)
    cap = row_max(g)
    rows = [min(cap, 7 * (i + 1)) for i in range(n)]   # a first guess; the loop owns it
    for it in range(iterations):
        per = defaultdict(lambda: defaultdict(list))
        for d, rnd, kind, gap, ace in run(g, rows, depth, runs):
            if d and kind in target:
                per[rnd - first][kind].append((gap, ace))
        moved = 0
        new = list(rows)
        for i in range(n):
            errs = []
            for kind, samples in per.get(i, {}).items():
                err = target[kind] - statistics.median(gp for gp, _ in samples)
                if err > 0 and statistics.median(a for _, a in samples) >= model.MAX_LEVEL:
                    continue                      # pinned at 100: raising the bonus cannot move it
                # A pinned kind above target still votes down: the 100 clamp only
                # hides overshoot, so its error underestimates the drop (never past it).
                errs.append(err)
            if errs:
                new[i] = rows[i] + round(statistics.mean(errs))
            if i:
                new[i] = max(new[i], new[i - 1])  # never lower difficulty
            new[i] = max(0, min(cap, new[i]))
            if new[i] != rows[i]:
                moved += 1
        rows = new
        print(f"iteration {it + 1}: {moved} row(s) moved: {rows}", file=sys.stderr)
        if not moved:
            break
    return rows, target


def emit(rows, first):
    out = [
        "; Endless level growth per global round (EndlessLevelBonus, custom_functions/endless.asm).",
        ";",
        "; GENERATED by tools/balance/endless_solve.py --write (ENDLESS_MODE_CHECKPOINT_D.md 3.3).",
        "; Cumulative bonus over each table's last authored row, solved to hold the",
        "; original run's final enemy-minus-starter gaps until level 100. Never hand-edit.",
        "EndlessLevelRows:",
    ]
    for at in range(0, len(rows), 8):
        chunk = rows[at:at + 8]
        lo, hi = first + at, first + at + len(chunk) - 1
        out.append("\tdb %s ; rounds %2d-%d" % (", ".join("%3d" % v for v in chunk), lo, hi))
    out.append("ASSERT @ - EndlessLevelRows == NUM_ENDLESS_LEVEL_ROWS")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=200)
    ap.add_argument("--depth", type=int, default=3)
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    g = parse.load_all()
    rows, target = solve(g, args.runs, args.depth)
    first = g.knobs["LAST_ROUND_BATTLECOUNT"] // g.knobs["ROUND_BATTLES"] + 1
    print("targets:", {k: round(v, 1) for k, v in sorted(target.items())})
    print("rows:", rows)
    if args.write:
        OUT.write_text(emit(rows, first), newline="\n")
        print("wrote", OUT.relative_to(parse.ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
