"""Balance Phase 3: how long does a battle take, and who wins it?

Opt-in calibration, NOT part of make smoke. It never touches run_ai_scenarios.py
or make ai_scenarios; it borrows only run_ai_benchmark.py's player driver.

The model knows how many battles a run has and how many mons each enemy
fields; this measures what those cost in frames, and the win rate at a given
level gap (the "too hard / too easy" signal the model cannot see, since it
assumes the player always wins).

One FIGHT 2 boot per battle, with an injected fixture:
  player  the starter line evolved for its level (the carry ace) at L + gap,
          plus two bench mons at L + gap - BENCH_BEHIND, which is roughly
          where the model puts the team average behind the ace.
  enemy   n mons at level L, species drawn the way GetRandRoster draws a
          roster for the round whose trainers sit at L, AI tier from the ROM's
          AITierByRound (Normal row) for that round.
Both sides get their real level-up movesets: AddPartyMon writes them, and a
hook at DebugFight2Setup.gotSpecParty copies them into the fixture buffer so the
fixture's own move copy writes them back unchanged.

The player picks its highest-power move every turn (run_ai_benchmark's
best_power policy) and taps A as fast as the harness can, so frames here are
a floor on a human's time. The human reading overhead is the one term only
a real timed run can supply; see report.py's CALIBRATION.

Usage (WSL, needs PyBoy):
    python3 tools/balance/calibrate_battle_time.py                     # default sweep
    python3 tools/balance/calibrate_battle_time.py --rounds 2 5 8 --mons 1 3 6 --gaps 0 4 10 --trials 3
    python3 tools/balance/calibrate_battle_time.py --out tools/balance/data/battle_time.csv
"""

from __future__ import annotations

import argparse
import csv
import random
import statistics
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))
sys.path.insert(0, str(REPO_ROOT / "tools" / "balance"))

from harness import RedRogueHarness  # noqa: E402
from run_ai_benchmark import choose_player_move, choose_player_slot, parse_move_powers, prepare_party_driver  # noqa: E402
from source_constants import parse_trainer_constants  # noqa: E402
from test_party_spec_coverage import Image  # noqa: E402
import model  # noqa: E402
import parse  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"
OUT = Path(__file__).resolve().parent / "data" / "battle_time.csv"
BENCH_BEHIND = 8           # model: team average sits ~8 levels under a carried ace
MAX_STEPS = 4000           # ~10 frames per step: a 6-mon battle is well under this
PARTYMON_STRUCT_LENGTH = 44
ENEMY_CLASS = "COOLTRAINER_M"
FIELDS = ("round", "level", "mons", "gap", "ai_tier", "trial", "result", "turns", "frames",
          "player_species", "enemy_species", "ace_moves")


def round_level(g: parse.GameData, rnd: int) -> int:
    """A typical trainer level for round rnd: GetRewardMonLevel's mid-band."""
    return model.reward_level(g, 10 * (rnd - 1) + 1)


def player_team(g, cfg, level: int, gap: int, rng) -> list[tuple[str, int]]:
    ace_lv = max(2, min(100, level + gap))
    bench_lv = max(2, ace_lv - BENCH_BEHIND)
    ace = model.evolve_by_level(g, cfg, rng.choice(model.STARTERS), ace_lv, rng)
    bench = [model.select_from_tier_evolved(g, cfg, 1, bench_lv, rng) for _ in range(2)]
    return [(ace, ace_lv)] + [(b, bench_lv) for b in bench]


def enemy_team(g, cfg, rnd: int, level: int, n: int, rng) -> list[tuple[str, int]]:
    """Species as GetRandRoster rolls them for this round's route trainers,
    padded or cut to n, all at exactly `level` so the gap is controlled."""
    species: list[str] = []
    while len(species) < n:
        species += [sp for sp, _ in model.roster_battle(g, cfg, 10 * (rnd - 1) + 1, rng).mons]
    return [(model.scale_trainer_evolution(g, cfg, sp, level, rng), level) for sp in species[:n]]


def run_battle(g, player, enemy, ai_tier: int, powers, trainer_class: int) -> dict:
    h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        # Keep AddPartyMon's level-up moves: copy them over the fixture's move
        # bytes before .copySpecMoves writes those back into the mon.
        def keep_learnset_moves() -> None:
            enemy_side = h.read8("wMonDataLocation") & 0x0F
            count = h.read8("wEnemyPartyCount" if enemy_side else "wPartyCount")
            label = "wEnemyMon1Moves" if enemy_side else "wPartyMon1Moves"
            moves = h.read_bytes(label, 4, offset=(count - 1) * PARTYMON_STRUCT_LENGTH)
            for i, mv in enumerate(moves):
                h.write8("wBuffer", mv, 2 + i)

        h.hook_flag("DebugFight2Setup.gotSpecParty", action=keep_learnset_moves)
        h.register_hook("MainInBattleLoop.noLinkBattle",
                        lambda _c: h.write8("wTestBattlePlayerSelectedMove",
                                            choose_player_move(h, "best_power", powers)))
        h.hook_flag("DisplayBattleMenu", action=lambda: h.write8("wBattleAndStartSavedMenuItem", 0))
        h.hook_flag("MoveSelectionMenu",
                    action=lambda: h.write8("wPlayerMoveListIndex",
                                            choose_player_slot(h, "best_power", powers)[0]))
        turns = h.hook_turn_telemetry()
        party_inputs, party_modes, _ = prepare_party_driver(h)
        victories, defeats = h.hook_flag("TrainerBattleVictory"), h.hook_flag("HandlePlayerBlackOut")

        mon = lambda sp, lv: {"species": g.species[sp].internal_id, "level": lv, "moves": []}
        h.inject_fight2_spec([mon(*p) for p in player], [mon(*e) for e in enemy],
                             trainer_class=trainer_class, ai_tier=ai_tier)
        h.boot_fight2(seed=1)

        # The ace's moves as the battle starts: proves the learnset hook ran
        # (an empty or all-zero set means the fixture's zero moves stood).
        ace_moves = " ".join(str(mv) for mv in h.read_bytes("wBattleMonMoves", 4))
        start = h.pyboy.frame_count
        handled, mode_index = party_inputs["count"], 0
        for _ in range(MAX_STEPS):
            if party_inputs["count"] > handled:
                h.tick(2)
                h.tap("a" if party_modes[mode_index] else "b")
                handled, mode_index = party_inputs["count"], mode_index + 1
            else:
                h.tap("a", 1)
                h.tick(8)
            if victories["count"] or defeats["count"]:
                break
        else:
            image, state = h.write_failure_artifacts("calibrate_battle_time_timeout")
            print(f"  timeout: artifacts {image} {state}; player moves "
                  f"{h.read_bytes('wBattleMonMoves', 4)} pp {h.read_bytes('wBattleMonPP', 4)} "
                  f"enemy moves {h.read_bytes('wEnemyMonMoves', 4)}", flush=True)
            return {"result": "timeout", "turns": len(turns), "frames": h.pyboy.frame_count - start,
                    "ace_moves": ace_moves}
        return {"result": "win" if victories["count"] else "loss", "turns": len(turns),
                "frames": h.pyboy.frame_count - start, "ace_moves": ace_moves}
    finally:
        try:
            h.close()
        except Exception:
            pass


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rounds", type=int, nargs="+", default=[2, 5, 8])
    ap.add_argument("--mons", type=int, nargs="+", default=[1, 3, 6])
    ap.add_argument("--gaps", type=int, nargs="+", default=[-2, 2, 6, 12])
    ap.add_argument("--trials", type=int, default=3)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args(argv)

    g, cfg = parse.load_all(), model.Config()
    image = Image("pokeblue_debug")
    tier_row = image.rom[image.offset("AITierByRound"):][:9]          # DIFFICULTY_NORMAL row
    powers = parse_move_powers(REPO_ROOT / "data" / "moves" / "moves.asm")
    # An OPP_* opponent id, not a class index: see inject_fight2_spec.
    trainer_class = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")[ENEMY_CLASS]
    rng = random.Random(args.seed)

    rows = []
    t0 = time.time()
    for rnd in args.rounds:
        level = round_level(g, rnd)
        for n in args.mons:
            for gap in args.gaps:
                for trial in range(args.trials):
                    player = player_team(g, cfg, level, gap, rng)
                    enemy = enemy_team(g, cfg, rnd, level, n, rng)
                    res = run_battle(g, player, enemy, tier_row[rnd - 1], powers, trainer_class)
                    rows.append({"round": rnd, "level": level, "mons": n, "gap": gap,
                                 "ai_tier": tier_row[rnd - 1], "trial": trial, **res,
                                 "player_species": " ".join(f"{s}:{lv}" for s, lv in player),
                                 "enemy_species": " ".join(s for s, _ in enemy)})
                cell = rows[-args.trials:]
                wins = sum(r["result"] == "win" for r in cell)
                print(f"round {rnd} L{level} mons {n} gap {gap:+d}: "
                      f"{statistics.mean(r['frames'] for r in cell) / 60:6.1f}s "
                      f"{statistics.mean(r['turns'] for r in cell):4.1f} turns  wins {wins}/{len(cell)}"
                      f"  ({time.time() - t0:.0f}s)", flush=True)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
