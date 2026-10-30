#!/usr/bin/env python3
"""Solve data/balance/endless_levels.asm: the Endless level bonus per round.

ENDLESS_MODE_CHECKPOINT_D.md section 3.3. Past the original circuit every
round-indexed table sits on its last authored row, so encounter SHAPE stays at
its maximum; levels grow by one bonus per global round (EndlessLevelRows),
added before the difficulty % (the level funnel, func_enc_gen.asm).

The rows are not chosen, they are solved: the user's rule (2026-10-28) is to
hold the gap the original run ends on. Checkpoint G (2026-10-29) lifted the
caps: the player stops at MAX_LEVEL (235), enemies at ENEMY_MAX_LEVEL (255).
So:

  targets  for each encounter kind, the median enemy-ace-minus-starter gap at
           the last round that kind is fought in the ORIGINAL circuit
           (model.py at depth 0, same policy, same seed set);
  update   simulate the run into Endless with the current rows; in every
           Endless round, move that round's row by the mean error over the
           kinds fought there (a kind pinned at its cap still votes down
           when it is over target, but not up);
           rows never decrease and stop at the value that puts every
           category at the enemy cap;
  repeat   until no row moves.
  ramp     holding the gap stops the rows once the player's team caps at 235
           (measured: around global round 84). From that plateau the rows
           climb --post-cap-step a round until every category reaches 255
           (user, 2026-10-29: a deliberate climb past the player's cap).

Usage:  python3 tools/balance/endless_solve.py [--runs N] [--depth D]
            [--last-round R] [--post-cap-step S] [--write]
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
        # The round EndlessLevelBonus indexes by: unsaturated, unlike progress,
        # which stops at 255 (round 31) and would leave later rows unsolved.
        k = self.g.knobs
        count = self.count if count is None else count
        self._round = (count + (k["LAST_ROUND_BATTLECOUNT"] + 1) * self.depth) // k["ROUND_BATTLES"]
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
    for depth, rnd, kind, gap, _ in run(g, [0], 0, runs):
        by[(kind, rnd)].append(gap)
        last[kind] = max(last.get(kind, -1), rnd)
    return {kind: statistics.median(by[(kind, rnd)]) for kind, rnd in last.items()
            if kind != "oak_rival"}


def row_max(g):
    """The bonus that puts every category's final-row base at the enemy cap."""
    t, k = g.tables, g.knobs
    last = k["LAST_ROUND_BATTLECOUNT"] // k["ROUND_BATTLES"]
    bases = [t.route[last].min_level, t.gym[last].min_level, t.wild[last], t.wild_boss[last]]
    return model.ENEMY_MAX_LEVEL - min(bases)


def kind_cap(kind):
    """Where a kind's levels stop: wild-area bosses at the player's cap (they
    become the player's mon), every other enemy at the enemy cap."""
    return model.MAX_LEVEL if kind == "wild_boss" else model.ENEMY_MAX_LEVEL


def solve(g, runs, depth, last_round, iterations=12):
    first = g.knobs["LAST_ROUND_BATTLECOUNT"] // g.knobs["ROUND_BATTLES"] + 1
    n = last_round + 1 - first
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
                if err > 0 and statistics.median(a for _, a in samples) >= kind_cap(kind):
                    continue                      # pinned at its cap: raising the bonus cannot move it
                # A pinned kind above target still votes down: the clamp only
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
    # EndlessLevelBonus holds the last row past the table, so rows after the
    # first one at the cap (or a flat tail) add nothing: keep the table short.
    while len(rows) > 1 and rows[-1] == rows[-2]:
        rows.pop()
    return rows, target


def ramp(rows, cap, step):
    """The post-cap climb: from the solved plateau, +step a round to the cap."""
    rows = list(rows)
    while step > 0 and rows[-1] < cap:
        rows.append(min(cap, rows[-1] + step))
    return rows


def emit(rows, first):
    out = [
        "; Endless level growth per global round (EndlessLevelBonus, custom_functions/endless.asm).",
        ";",
        "; GENERATED by tools/balance/endless_solve.py --write (ENDLESS_MODE_CHECKPOINT_D.md 3.3,",
        "; extended past level 100 by ENDLESS_MODE_CHECKPOINT_G.md). Cumulative bonus over",
        "; each table's last authored row, solved to hold the original run's final",
        "; enemy-minus-starter gaps up to the level caps. One row per global round from",
        "; ENDLESS_FIRST_ROUND; EndlessLevelBonus holds the last row past the end, so the",
        "; table stops at its first capped row. Never hand-edit.",
        "DEF NUM_ENDLESS_LEVEL_ROWS EQU %d" % len(rows),
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
    ap.add_argument("--depth", type=int, default=12,
                    help="Endless circuits to simulate; each is 9 rounds, so this must reach --last-round")
    ap.add_argument("--last-round", type=int, default=110,
                    help="the last global round solved (trailing capped rows are trimmed)")
    ap.add_argument("--post-cap-step", type=int, default=1,
                    help="levels a round the rows climb after the solved plateau (0 = none)")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    g = parse.load_all()
    rows, target = solve(g, args.runs, args.depth, args.last_round)
    solved = len(rows)
    rows = ramp(rows, row_max(g), args.post_cap_step)
    print(f"solved rows: {solved}, post-cap ramp rows: {len(rows) - solved}")
    first = g.knobs["LAST_ROUND_BATTLECOUNT"] // g.knobs["ROUND_BATTLES"] + 1
    print("targets:", {k: round(v, 1) for k, v in sorted(target.items())})
    print("rows:", rows)
    if args.write:
        OUT.write_text(emit(rows, first), newline="\n")
        print("wrote", OUT.relative_to(parse.ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
