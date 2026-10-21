"""Baseline for the Explosion / Self-Destruct trade policy (2026-10-21).

Probe, not a smoke test (probe_ prefix keeps it out of `make smoke`).

For each (enemy, player) pair, one FIGHT 2 boot; then a grid of boards from one
savestate: tier x enemy HP x player HP. Each board runs AIEnemyTrainerChooseMoves
and reads the final four scores plus wAIReliableKOFound. The move pick is a
uniform draw among the lowest scores, so Explosion's pick rate on a board is
1/|best set| when its slot is in that set, else 0.

"threat" is AIPlayerWouldKO's carry, read by a raw hook on the instruction after
AILayerRisky's call (T3 only); boards at T1/T2 reuse the T3 value of the same
HP configuration, since the predicate depends only on the board.

Usage: python3 tools/pyboy_smoke/probe_explosion_policy.py [--repeat N]
"""
from __future__ import annotations

import argparse
import io
from collections import defaultdict
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]

ENEMIES = {
    "GRAVELER": ["TACKLE", "ROCK_THROW", "DEFENSE_CURL", "SELFDESTRUCT"],
    "ELECTRODE": ["THUNDERBOLT", "SCREECH", "SWIFT", "EXPLOSION"],
    "GOLEM": ["ROCK_SLIDE", "EARTHQUAKE", "DEFENSE_CURL", "EXPLOSION"],
}
PLAYERS = {  # name: (species, level, moves); SNORLAX60 out-levels the enemy so it threatens a KO
    "SNORLAX": ("SNORLAX", 40, ["BODY_SLAM", "EARTHQUAKE"]),
    "SNORLAX60": ("SNORLAX", 60, ["BODY_SLAM", "EARTHQUAKE"]),
    "PIKACHU": ("PIKACHU", 40, ["THUNDERBOLT", "QUICK_ATTACK"]),
    "GENGAR": ("GENGAR", 40, ["NIGHT_SHADE", "HYPNOSIS"]),
}
LEVEL = 40
TURNS = (("first", 0), ("later", 2))  # wAILayer2Encouragement: AI_SETUP only favours setup at 0
TIERS = (1, 2, 3)
ENEMY_HP = (("full", 1.0), ("mid", 0.6), ("low", 0.2))
PLAYER_HP = (("full", 1.0), ("low", 0.25))


class Probe:
    def __init__(self, veto: bool = True) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.threat = None
        self.pre = self.post = None
        bank, address = self.h.symbols.get("AILayerRisky")
        self.h._register_at((bank, address + 3), self._after_would_ko)
        self.h.register_hook("AIEnemyTrainerChooseMoves.loopFindMinimumEntries", self._pre_ko_pass)
        self.h.register_hook("AIEnemyTrainerChooseMoves.findMinimum", self._post_ko_pass)
        if not veto:  # A/B on one ROM: make AIExplosionTradeVeto return at once
            self.h.register_hook("AIExplosionTradeVeto", self._skip_veto)

    def _skip_veto(self, _ctx) -> None:
        rf, mem = self.h.pyboy.register_file, self.h.pyboy.memory
        rf.PC = mem[rf.SP] | mem[(rf.SP + 1) & 0xFFFF] << 8
        rf.SP = (rf.SP + 2) & 0xFFFF

    def _pre_ko_pass(self, _ctx) -> None:
        self.pre = self.h.read_bytes("wBuffer", 4)

    def _post_ko_pass(self, _ctx) -> None:
        if self.post is None:  # the loop revisits this label once per slot
            self.post = self.h.read_bytes("wBuffer", 4)

    def _after_would_ko(self, _ctx) -> None:
        self.threat = bool(self.h.pyboy.register_file.F & 0x10)

    def boot(self, enemy: str, player: str, reserve: bool) -> bytes:
        h, mv = self.h, self.moves
        party = [{"species": self.species[PLAYERS[player][0]], "level": PLAYERS[player][1],
                  "moves": [mv[m] for m in PLAYERS[player][2]]}]
        if reserve:  # a second live mon: a KO no longer ends the battle
            party.append({"species": self.species["RATTATA"], "level": 40, "moves": [mv["TACKLE"]]})
        h.inject_fight2_spec(
            party,
            [{"species": self.species[enemy], "level": LEVEL,
              "moves": [mv[m] for m in ENEMIES[enemy]]}],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
        h.boot_fight2(seed=1)
        h.reveal_player_moves(0, [0, 1], clear=True)
        h.park_before_hijack()
        state = io.BytesIO()
        h.save_state(state)
        return state.getvalue()

    def _set_hp(self, cur: str, cap: str, frac: float) -> None:
        h = self.h
        hi, lo = h.read8(cap), h.read8(cap, offset=1)
        value = max(1, int(((hi << 8) | lo) * frac))
        h.write8(cur, value >> 8)
        h.write8(cur, value & 0xFF, offset=1)

    def run(self, state: bytes, tier: int, enemy_frac: float, player_frac: float, turn: int) -> dict:
        h = self.h
        h.load_state(io.BytesIO(state))
        h.write8("wAILayer2Encouragement", turn)
        h.write8("wAIDebugTierOverride", tier + 1)
        h.write8("wAITier", 0)
        self._set_hp("wEnemyMonHP", "wEnemyMonMaxHP", enemy_frac)
        self._set_hp("wBattleMonHP", "wBattleMonMaxHP", player_frac)
        self.threat = None
        self.pre = self.post = None
        h.call_routine("AIEnemyTrainerChooseMoves", limit=12000)
        return {"picks": h.read_bytes("wBuffer", 4), "pre": self.pre, "scores": self.post,
                "ko": h.read8("wAIReliableKOFound"),
                "threat": self.threat}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repeat", type=int, default=2, help="runs per board (noise check)")
    parser.add_argument("--no-veto", action="store_true", help="skip AIExplosionTradeVeto (baseline)")
    args = parser.parse_args()
    rows = []
    for enemy, moveset in ENEMIES.items():
        boom = 3  # Explosion/Self-Destruct is slot 4 in every set
        assert moveset[boom] in ("SELFDESTRUCT", "EXPLOSION")
        for player, reserve in ((p, r) for p in PLAYERS for r in (True, False)):
            probe = Probe(veto=not args.no_veto)  # boot_fight2 is one boot per harness
            try:
                state = probe.boot(enemy, player, reserve)
                threat_of = {}
                for (turn_name, turn), tier, (ehp_name, ehp), (php_name, php) in (
                        (t, ti, e, p) for t in TURNS for ti in sorted(TIERS, reverse=True)
                        for e in ENEMY_HP for p in PLAYER_HP):  # T3 first, for threat
                            runs = [probe.run(state, tier, ehp, php, turn) for _ in range(args.repeat)]
                            r = runs[0]
                            noise = any(x["scores"] != r["scores"] for x in runs[1:])
                            if tier == 3:
                                threat_of[(ehp_name, php_name)] = r["threat"]
                            p = r["picks"]  # move ids of the tied best slots, 0 elsewhere
                            best = [i for i in range(4) if p[i]]
                            rate = 1 / len(best) if boom in best else 0.0
                            rows.append(dict(turn=turn_name, enemy=enemy, reserve=reserve,
                                             player=player + ("+R" if reserve else ""), tier=tier, ehp=ehp_name,
                                             php=php_name, scores=list(r["scores"]), pre=list(r["pre"]), ko=r["ko"],
                                             boom_ko=bool(r["ko"] & (1 << boom)),
                                             threat=threat_of.get((ehp_name, php_name)),
                                             rate=rate, noise=noise))
            finally:
                probe.h.close()

    print(f"{'turn':5} {'enemy':9} {'player':9} T {'eHP':4} {'pHP':4} thr  koMask boomKO  pre-KO-pass       final             P(boom)")
    for r in rows:
        print(f"{r['turn']:5} {r['enemy']:9} {r['player']:9} {r['tier']} {r['ehp']:4} {r['php']:4} "
              f"{str(r['threat'])[0]:4} {r['ko']:#06b} {str(r['boom_ko'])[0]:6} "
              f"{str(r['pre']):17} {str(r['scores']):17} {r['rate']:.2f}{'  NOISE' if r['noise'] else ''}")

    # Summary: mean pick rate by tier x enemy HP, and the cases the new policy
    # forbids (above 1/4 HP, no threat) that still pick Explosion.
    agg = defaultdict(list)
    for r in rows:
        agg[(r["turn"], r["tier"], r["ehp"])].append(r["rate"])
    print("\nmean P(boom) by turn x tier x enemy HP (Gengar boards included; it is immune):")
    for key in sorted(agg):
        print(f"  {key[0]:5} T{key[1]} {key[2]:4} {sum(agg[key]) / len(agg[key]):.2f}  (n={len(agg[key])})")
    bad = [r for r in rows if r["tier"] >= 2 and r["ehp"] != "low" and not r["threat"] and r["rate"] > 0
           and (r["reserve"] or not r["boom_ko"])]
    print(f"\nT2/T3, enemy above 1/4 HP, no threat, not a battle-winning KO, Explosion still picked: "
          f"{len(bad)} boards")
    win = [r for r in rows if r["tier"] >= 2 and r["ehp"] != "low" and not r["threat"]
           and not r["reserve"] and r["boom_ko"]]
    print(f"T2/T3 battle-winning KO boards (player's last mon): {len(win)}, Explosion picked on "
          f"{sum(r['rate'] > 0 for r in win)}")
    for r in bad:
        print(f"  {r['turn']} {r['enemy']} vs {r['player']} T{r['tier']} eHP={r['ehp']} pHP={r['php']} "
              f"boomKO={r['boom_ko']} scores={r['scores']} P={r['rate']:.2f}")
    t1 = [r for r in rows if r["tier"] == 1 and r["ehp"] != "low" and r["rate"] > 0]
    print(f"T1, enemy at 0.6 HP or more, Explosion picked: {len(t1)} boards")
    for r in t1:
        print(f"  {r['turn']} {r['enemy']} vs {r['player']} eHP={r['ehp']} pHP={r['php']} "
              f"scores={r['scores']} P={r['rate']:.2f}")
    thr = [r for r in rows if r["tier"] >= 2 and r["ehp"] != "low" and r["threat"]]
    print(f"T2/T3, enemy above 1/4 HP, threatened: {len(thr)} boards, "
          f"Explosion picked on {sum(r['rate'] > 0 for r in thr)}")
    print(f"noisy boards: {sum(r['noise'] for r in rows)}")


if __name__ == "__main__":
    main()
