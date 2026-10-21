"""Baseline for narrowing B9's scarce-PP substitution (2026-10-21).

Probe, not a smoke test (probe_ prefix keeps it out of `make smoke`).

AIDamageScarceAlternative moves AI_DAMAGE's one-point best-damage nudge off a
best move with AI_SCARCE_PP or less to another slot. The shipped rule (hits-to-KO,
2026-10-21) needs the same hit count and no two-turn move; the older same-tier rule
let charge moves and possible-KO downgrades through. Each
board runs AIEnemyTrainerChooseMoves twice from one savestate:
  full    every slot at 10 PP: finds the best-damage slot
  scarce  that slot at 1-2 PP
and records whether the nudge moved, where to, and whether the pick set moved.

A substitution is classed as
  charge     the stand-in is CHARGE_EFFECT / FLY_EFFECT (hits next turn)
  downgrade  the best slot reached AILayerDamage.kill (a possible KO) and the
             stand-in did not
  ok         neither

Usage: python3 tools/pyboy_smoke/probe_scarce_pp.py [--boards N] [--seed S]
"""
from __future__ import annotations

import argparse
import io
import random
import re
from collections import Counter
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
CURSLOT = 17  # AI_BUF_CURSLOT
APPLY_BEST_CALL_RETURN = 9  # applyBest: ld a,[nn] / cp n / ret nc / call -> +9

PAIRS = [  # (player, enemy)
    ("SNORLAX", "TAUROS"), ("ALAKAZAM", "GENGAR"), ("GYARADOS", "JOLTEON"),
    ("RHYDON", "STARMIE"), ("MACHAMP", "DRAGONITE"), ("CHANSEY", "VENUSAUR"),
]


def parse_moves() -> dict[str, tuple[str, int]]:
    """Move name -> (effect, power) from data/moves/moves.asm."""
    out = {}
    for line in (ROOT / "data/moves/moves.asm").read_text().splitlines():
        m = re.match(r"\s*move\s+(\w+),\s*(\w+),\s*(\d+),", line)
        if m:
            out[m.group(1)] = (m.group(2), int(m.group(3)))
    return out


class Probe:
    def __init__(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        h = self.h
        h.register_hook("AIDamageScarceAlternative", self._entry)
        bank, address = h.symbols.get("AILayerDamage.applyBest")
        h._register_at((bank, address + APPLY_BEST_CALL_RETURN), self._returned)
        h.register_hook("AILayerDamage.kill", self._kill)
        h.register_hook("AILayerDamage.trackBest", self._track)
        self.reset()

    def _track(self, _ctx) -> None:  # wAIDamageEstimate is this slot's expected damage here
        e = self.h.read8("wAIDamageEstimate") << 8 | self.h.read8("wAIDamageEstimate", offset=1)
        self.expected[self.h.read8("wBuffer", offset=CURSLOT)] = e

    def reset(self) -> None:
        self.best = self.chosen = None
        self.kills: set[int] = set()
        self.expected: dict[int, int] = {}

    def _entry(self, _ctx) -> None:
        self.best = self.h.pyboy.register_file.A

    def _returned(self, _ctx) -> None:
        self.chosen = self.h.pyboy.register_file.A

    def _kill(self, _ctx) -> None:
        self.kills.add(self.h.read8("wBuffer", offset=CURSLOT))

    def boot(self, player: str, enemy: str) -> bytes:
        h, mv = self.h, self.moves
        h.inject_fight2_spec(
            [{"species": self.species[player], "level": 50, "moves": [mv["TACKLE"], mv["THUNDERBOLT"]]}],
            [{"species": self.species[enemy], "level": 50,
              "moves": [mv["TACKLE"], mv["GROWL"], mv["BITE"], mv["SURF"]]}],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
        h.boot_fight2(seed=1)
        h.reveal_player_moves(0, [0, 1], clear=True)
        h.park_before_hijack()
        state = io.BytesIO()
        h.save_state(state)
        return state.getvalue()

    def run(self, state: bytes, moves: list[int], pp: list[int], tier: int,
            player_hp: float) -> dict:
        h = self.h
        h.load_state(io.BytesIO(state))
        h.write8("wAIDebugTierOverride", tier + 1)
        h.write8("wAITier", 0)
        h.write8("wAILayer2Encouragement", 2)
        for slot, move in enumerate(moves):
            h.write8("wEnemyMonMoves", move, offset=slot)
            h.write8("wEnemyMonPP", pp[slot], offset=slot)
        hi, lo = h.read8("wBattleMonMaxHP"), h.read8("wBattleMonMaxHP", offset=1)
        hp = max(1, int(((hi << 8) | lo) * player_hp))
        h.write8("wBattleMonHP", hp >> 8)
        h.write8("wBattleMonHP", hp & 0xFF, offset=1)
        self.reset()
        h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
        picks = h.read_bytes("wBuffer", 4)
        player_hp = h.read8("wBattleMonHP") << 8 | h.read8("wBattleMonHP", offset=1)
        return {"best": self.best, "chosen": self.chosen,
                "kills": set(self.kills), "expected": dict(self.expected), "picks": {i for i in range(4) if picks[i]},
                "ko": h.read8("wAIReliableKOFound"), "php": player_hp}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--boards", type=int, default=60, help="boards per species pair")
    parser.add_argument("--seed", type=int, default=20261021)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    data = parse_moves()
    consts = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
    excluded = {"OHKO_EFFECT", "EXPLODE_EFFECT", "SPECIAL_DAMAGE_EFFECT", "SUPER_FANG_EFFECT"}
    pool = [consts[name] for name, (effect, power) in data.items()
            if power > 1 and effect not in excluded and name in consts and name != "STRUGGLE"]
    charge = {consts[name] for name, (effect, _p) in data.items()
              if effect in ("CHARGE_EFFECT", "FLY_EFFECT") and name in consts}
    charge_pool = sorted(charge & set(pool))

    totals = Counter()
    ratios: list[float] = []
    hit_pairs: list[tuple[int, int, float]] = []
    examples: dict[str, list[str]] = {"charge": [], "downgrade": [], "ok": []}
    for player, enemy in PAIRS:
        probe = Probe()  # boot_fight2 is one boot per harness
        try:
            state = probe.boot(player, enemy)
            for _ in range(args.boards):
                moves = rng.sample(pool, 4)
                if rng.random() < 0.3 and not set(moves) & charge:
                    moves[rng.randrange(4)] = rng.choice(charge_pool)  # make charge stand-ins common enough to see
                if len(set(moves)) < 4:
                    continue
                tier = rng.choice((2, 3))
                php = rng.choice((1.0, 0.6, 0.3))
                full = probe.run(state, moves, [10] * 4, tier, php)
                if full["best"] is None or full["best"] >= 4:
                    totals["no_best"] += 1
                    continue
                best = full["best"]
                pp = [10] * 4
                pp[best] = rng.choice((1, 2))
                scarce = probe.run(state, moves, pp, tier, php)
                totals["boards"] += 1
                if scarce["chosen"] == best:
                    totals["kept"] += 1
                    continue
                stand_in = scarce["chosen"]
                if moves[stand_in] in charge:
                    kind = "charge"
                elif best in scarce["kills"] and stand_in not in scarce["kills"]:
                    kind = "downgrade"
                else:
                    kind = "ok"
                totals[kind] += 1
                exp = full["expected"]
                hits_of = lambda d: -(-full["php"] // d) if d else 99
                if exp.get(best) and hits_of(exp.get(stand_in, 0)) > hits_of(exp[best]):
                    totals[f"{kind}_more_hits"] += 1  # the hits-to-KO rule must make this 0
                if kind == "ok" and exp.get(best):
                    ratios.append(exp.get(stand_in, 0) / exp[best])
                    hits = lambda d: -(-full["php"] // d) if d else 99
                    hb, hs = hits(exp[best]), hits(exp.get(stand_in, 0))
                    hit_pairs.append((hb, hs, exp.get(stand_in, 0) / exp[best]))
                changed = full["picks"] != scarce["picks"]
                if changed:
                    totals[f"{kind}_pick_changed"] += 1
                names = {v: k for k, v in consts.items()}
                examples[kind].append(
                    f"{enemy} vs {player} T{tier} pHP={php} moves={[names.get(m, m) for m in moves]} "
                    f"best={best} -> {stand_in} kills={sorted(scarce['kills'])} "
                    f"picks {sorted(full['picks'])} -> {sorted(scarce['picks'])}")
        finally:
            probe.h.close()

    subs = totals["charge"] + totals["downgrade"] + totals["ok"]
    print(f"boards={totals['boards']} (no damaging best: {totals['no_best']})")
    print(f"best slot kept: {totals['kept']}  substituted: {subs}")
    for kind in ("charge", "downgrade", "ok"):
        print(f"  {kind:9} {totals[kind]:4}  final pick set changed on {totals[kind + '_pick_changed']}, "
              f"needing more hits than the best: {totals[kind + '_more_hits']}")
        for line in examples[kind][:8]:
            print("    " + line)
    if ratios:
        ratios.sort()
        print(f"ok substitutions, stand-in expected damage / best's (n={len(ratios)}):")
        for q in (0.1, 0.25, 0.5, 0.75, 0.9):
            print(f"  p{int(q * 100):02d} {ratios[int(q * (len(ratios) - 1))]:.2f}")
        for cut in (0.5, 0.67, 0.75, 0.875, 0.9, 0.9375):
            print(f"  below {cut:.4f}: {sum(r < cut for r in ratios)}")
        same = [p for p in hit_pairs if p[0] == p[1]]
        print(f"ok substitutions keeping the same hits-to-KO (expected damage vs current HP): "
              f"{len(same)} of {len(hit_pairs)}")
        print(f"  of those, ratio below 0.75: {sum(p[2] < 0.75 for p in same)}, "
              f"below 0.875: {sum(p[2] < 0.875 for p in same)}")
        worse = [p for p in hit_pairs if p[1] > p[0]]
        print(f"ok substitutions needing MORE hits: {len(worse)}; of those ratio >= 0.75: "
              f"{sum(p[2] >= 0.75 for p in worse)}, >= 0.875: {sum(p[2] >= 0.875 for p in worse)}, "
              f">= 0.9375: {sum(p[2] >= 0.9375 for p in worse)}")
        print("  hits best->stand-in histogram:", sorted(Counter((a, b) for a, b, _ in hit_pairs).items()))


if __name__ == "__main__":
    main()
