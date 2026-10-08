#!/usr/bin/env python3
"""Preview the teams a PARTY_ROSTER.md character fields, without building or playing.

Samples many teams per round (or Elite Four tier) from the balance model
(tools/balance/model.py), which mirrors the ROM's party builder: pool draws
gated by the unlocked species groups, the ace drawn first and used as written,
NO_DUPES rerolls on the fielded species, and evolution by level. The model is
held to the ROM by tools/pyboy_smoke/test_balance_model_matches_rom.py.

    python3 tools/party_preview.py --list
    python3 tools/party_preview.py Brock
    python3 tools/party_preview.py Bugsy --groups johto
    python3 tools/party_preview.py GiovanniMiniBoss --at 5 --samples 5
    python3 tools/party_preview.py Gambler --runs 1000

Output is markdown: for each unlock state (Kanto only, + Johto, + Johto and
Time Warp), a chart of how often each species appears in a team, round by
round, with the ace slot counted separately. --at N adds sample teams for one
round. Species are shown as the model names them: a regional form shows as its
base species.

Party roster Phase 7b (2026-10-07).
"""

import argparse
import random
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "balance"))
import model  # noqa: E402
import parse  # noqa: E402

GROUP_STATES = {
    "kanto": ("Kanto only", ("KANTO",)),
    "johto": ("+ Johto", ("KANTO", "JOHTO")),
    "warp": ("+ Johto + Time Warp", ("KANTO", "JOHTO", "WARP")),
}
MINIBOSSES = {"RivalMiniBoss": "RIVAL", "GiovanniMiniBoss": "GIOVANNI", "KarateMiniBoss": "KARATE"}
CHAMPIONS = ("Rival3", "ChampionLance", "ProfOak")


def title(sp):
    return sp.replace("_", " ").title()


class Character:
    """kind, the rounds it can be asked for, and a battle builder per round."""

    def __init__(self, g, name, starter):
        self.g, self.name, self.starter = g, name, starter
        k = g.knobs
        leaders = {l.name: l for l in g.leaders}
        e4 = {m.name: m for m in g.e4}
        events = {pre for _, pre in model.STAGE_EVENTS}
        if name in leaders:
            self.kind, self.unit, self.rounds = "gym leader", "round", range(1, 9)
            self.build = lambda cfg, r, rng: model.leader_battle(g, cfg, leaders[name], r, rng)
        elif name in e4:
            self.kind, self.unit, self.rounds = "Elite Four", "tier", range(1, 5)
            self.build = lambda cfg, t, rng: model.e4_battle(
                g, cfg, e4[name], k["E4_FIRST_BATTLECOUNT"] - 1 + t, rng)
        elif name in MINIBOSSES:
            self.kind, self.unit, self.rounds = "mini-boss", "round", range(2, 10)
            self.build = lambda cfg, r, rng: model.miniboss_battle(
                g, cfg, MINIBOSSES[name], self.count(r), starter, rng)
        elif name in events:
            self.kind, self.unit, self.rounds = "wild-area trainer", "round", range(1, 10)
            self.build = lambda cfg, r, rng: model.stage_event_battle(
                g, cfg, self.count(r), rng, pick=name)
        elif name in CHAMPIONS:
            self.kind, self.unit, self.rounds = "Champion", "fight", range(1, 2)
            self.build = lambda cfg, _r, rng: self.champion(cfg, rng)
        elif name == "Gambler":
            self.kind, self.unit, self.rounds = "Gambler (roster levels)", "round", range(1, 10)
            self.build = lambda cfg, r, rng: self.gambler(cfg, r, rng)
        else:
            raise SystemExit("unknown character {!r}; --list shows them".format(name))

    def count(self, r):
        return (r - 1) * self.g.knobs["ROUND_BATTLES"] + 4

    def champion(self, cfg, rng):
        g, k = self.g, self.g.knobs
        base, step = k["CHAMPION_BASE_LEVEL"], k["CHAMPION_LEVEL_STEP"]
        fod = "POOL_BAND_{}_Fod1".format(self.name)
        if self.name == "Rival3":
            return model.spec_battle(g, cfg, "champion", 0, 6, base, step, fod,
                                     "RIVAL_STARTER_PLACEHOLDER", False, 0, rng, self.starter)
        uber = self.name == "ProfOak"
        ace_lv = model.apply_difficulty(min(base + 5 * step, model.MAX_LEVEL), cfg.difficulty)
        ace = model.draw_pool(g, cfg, "POOL_BAND_{}_Ace1".format(self.name), ace_lv, [], uber,
                              rng, keep=True)
        return model.spec_battle(g, cfg, "champion", 0, 6, base, step, fod, ace, uber, 0, rng)

    def gambler(self, cfg, r, rng):
        """GetRandRosterLoop for a Gambler: six draws (duplicates allowed) at the
        round's route-trainer levels, each evolved by level."""
        block = self.g.tables.route[r - 1]
        mons = []
        for _ in range(6):
            lv = block.min_level + (rng.randrange(block.level_range) if block.level_range else 0)
            lv = model.apply_difficulty(lv, cfg.difficulty)
            mons.append((model.draw_pool(self.g, cfg, "POOL_BAND_Gambler_Fod1", lv, [], True, rng), lv))
        return model.Battle("gambler", self.count(r), mons, True, 0)


def characters(g):
    out = [("gym leader", l.name) for l in g.leaders]
    out += [("Elite Four", m.name) for m in g.e4]
    out += [("mini-boss", n) for n in MINIBOSSES]
    out += [("wild-area trainer", pre) for _, pre in model.STAGE_EVENTS]
    out += [("Champion", n) for n in CHAMPIONS]
    out += [("Gambler", "Gambler")]
    return out


def chart(char, cfg, runs, seed):
    """markdown table: species x round, % of teams fielding it (ace share in brackets)."""
    rows, ace_rows, sizes, levels = {}, {}, {}, {}
    for r in char.rounds:
        rng = random.Random(seed * 1000 + r)
        seen, aces, lv = Counter(), Counter(), []
        for _ in range(runs):
            b = char.build(cfg, r, rng)
            for sp in {m for m, _ in b.mons}:
                seen[sp] += 1
            aces[b.mons[-1][0]] += 1
            lv += [l for _, l in b.mons]
            sizes[r] = len(b.mons)
        rows[r], ace_rows[r] = seen, aces
        levels[r] = (min(lv), max(lv))
    species = sorted({s for c in rows.values() for s in c},
                     key=lambda s: (-sum(rows[r][s] for r in char.rounds), s))
    head = ["Species"] + ["{} {}".format(char.unit.title(), r) for r in char.rounds]
    out = ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
    out.append("| *team size, levels* | " + " | ".join(
        "{}, L{}-{}".format(sizes[r], *levels[r]) for r in char.rounds) + " |")
    for sp in species:
        cells = []
        for r in char.rounds:
            n = rows[r][sp]
            if not n:
                cells.append("")
                continue
            a = ace_rows[r][sp]
            cells.append("{:.0f}%".format(100 * n / runs) + (" ({:.0f}% ace)".format(100 * a / runs) if a else ""))
        out.append("| {} | {} |".format(title(sp), " | ".join(cells)))
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("character", nargs="?", help="a PARTY_ROSTER.md prefix (Brock, KogaE4, ...)")
    ap.add_argument("--list", action="store_true", help="list every character")
    ap.add_argument("--groups", choices=("kanto", "johto", "warp", "all"), default="all",
                    help="unlock state(s) to sample (default: all three)")
    ap.add_argument("--runs", type=int, default=500, help="teams sampled per round (default 500)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--at", type=int, help="also print sample teams for this round/tier")
    ap.add_argument("--samples", type=int, default=3, help="sample teams with --at (default 3)")
    ap.add_argument("--starter", default="CHARMANDER", help="the rival's starter (default CHARMANDER)")
    ap.add_argument("--difficulty", choices=model.DIFFICULTIES, default="normal")
    args = ap.parse_args(argv)

    g = parse.load_all()
    if args.list or not args.character:
        for kind, name in characters(g):
            print("{:<20} {}".format(kind, name))
        return 0
    char = Character(g, args.character, args.starter)
    states = list(GROUP_STATES) if args.groups == "all" else [args.groups]
    print("# {} ({})\n".format(char.name, char.kind))
    print("{} teams per {}, seed {}, difficulty {}. A cell is the share of teams that field "
          "the species; \"(n% ace)\" is how often it is the ace (last slot).\n".format(
              args.runs, char.unit, args.seed, args.difficulty))
    for state in states:
        label, groups = GROUP_STATES[state]
        cfg = model.Config(difficulty=args.difficulty, groups=groups)
        print("## {}\n".format(label))
        print(chart(char, cfg, args.runs, args.seed))
        print()
        if args.at is not None:
            if args.at not in char.rounds:
                raise SystemExit("--at {} is not one of {}'s {}s {}".format(
                    args.at, char.name, char.unit, list(char.rounds)))
            rng = random.Random(args.seed)
            print("Sample teams, {} {}:\n".format(char.unit, args.at))
            for _ in range(args.samples):
                b = char.build(cfg, args.at, rng)
                print("- " + ", ".join("{} L{}".format(title(s), l) for s, l in b.mons))
            print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
