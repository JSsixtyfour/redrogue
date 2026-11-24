"""Guard: a move chosen (or skipped) before the menu must still be valid when it executes.

The enemy plans its turn before the player's menu and both sides skip move selection in
some states, so anything that ends such a state between selection and execution can
execute a move nobody chose: 0 at a battle's first turn, CANNOT_MOVE, or the previous
mon's. Found twice on 2026-11-24 (a frozen enemy thawed by a faster Fire move; a frozen
player thawed the same way), each a read before the Moves table and a crash.

Plays every combination of: who is held (player, enemy), how (frozen, asleep, about to
wake, held by Wrap, recharging after Hyper Beam, biding, thrashing, charging Dig, flinched
every turn), first turn or a later one, and what the other side does (a Fire move, Haze,
Growl, Thunder Wave, Transform, Mimic, Metronome, Mirror Move, Disable, Counter, switching out),
with the acting side faster and slower. Every detector is armed (autoplay_checks and
autoplay_battle_checks); a finding, a hang or a crash fails. The run also fails if a thaw
or a Haze cure never happened, since it would then prove nothing.

    python3 tools/pyboy_smoke/audit_stale_move_matrix.py [--jobs 6] [--only frozen]
"""
from __future__ import annotations

import argparse
import itertools
import multiprocessing
import os
import sys
import traceback
from collections import Counter
from pathlib import Path

import fight2_driver
import run_ai_benchmark as rab
from autoplay_checks import GameChecks
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants
from test_autoplay_battle_checks import Agent

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
FRZ, SLP_LONG, SLP_WAKING = 1 << 5, 4, 1
# name -> (the held side's move, status written at the chosen turn, move of the holder)
HELD = {
    "frozen": ("TACKLE", FRZ, None), "asleep": ("TACKLE", SLP_LONG, None), "waking": ("TACKLE", SLP_WAKING, None),
    "wrapped": ("TACKLE", 0, "WRAP"), "recharging": ("HYPER_BEAM", 0, None), "biding": ("BIDE", 0, None),
    "thrashing": ("THRASH", 0, None), "charging": ("DIG", 0, None), "raging": ("RAGE", 0, None),
    "empty": ("TACKLE", 0, None),  # no PP: Struggle
}
ACTIONS = ("FLAMETHROWER", "HAZE", "GROWL", "THUNDER_WAVE", "TRANSFORM", "MIMIC", "METRONOME", "MIRROR_MOVE", "DISABLE",
           "COUNTER", "switch")
CHECKS = ("party", "enemy_party")  # FIGHT 2's own fixture trips these; they are not the subject


def play(case) -> dict[str, object]:
    held_side, held, first_turn, action, faster = case
    held_move, status, holder_move = HELD[held]
    species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
    moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
    trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
    act = holder_move or "GROWL" if action == "switch" else action
    acting = {"species": species["JOLTEON" if faster else "SNORLAX"], "level": 50,
              "moves": [moves[m] for m in dict.fromkeys([holder_move or act, act])]}
    other = {"species": species["SNORLAX" if faster else "JOLTEON"], "level": 50, "moves": [moves[held_move]]}
    reserve = {"species": species["CHANSEY"], "level": 50, "moves": [moves["POUND"]]}
    player, enemy = ([other, reserve], [acting, reserve]) if held_side == "player" else ([acting, reserve], [other, reserve])
    prefix = "BattleMon" if held_side == "player" else "EnemyMon"
    h = RedRogueHarness(ROOT, ARTIFACTS)
    try:
        h.inject_fight2_spec(player, enemy, trainer_class=trainers["COOLTRAINER_M"], ai_tier=0)
        checks = GameChecks(Agent(h), ROOT)
        driver = fight2_driver.Fight2Driver(h, tier=0, player_policy="random",
                                            move_powers=rab.parse_move_powers(ROOT / "data/moves/moves.asm"))
        seen = {"turn": 0}
        when = 1 if first_turn else 3

        def turn(_context) -> None:
            seen["turn"] += 1
            driver.move_override = 0 if held_side == "player" or seen["turn"] < when else len(acting["moves"]) - 1
            driver.switch_override = 1 if action == "switch" and held_side == "enemy" and seen["turn"] == when else None
            if not h.read8("wBattleMonMoves", driver.move_override):
                driver.move_override = 0  # Transform left fewer moves
            if seen["turn"] == when:
                h.write8(f"w{prefix}Status", status)
                h.write8("wEnemyMonHP", h.read8("wEnemyMonMaxHP"))
                h.write8("wEnemyMonHP", h.read8("wEnemyMonMaxHP", 1), 1)
                if held == "empty":
                    for slot in range(4):
                        h.write8(f"w{prefix}PP", 0, slot)

        h.register_hook("MainInBattleLoop", turn)
        thaw = h.hook_flag("CheckDefrost")
        # A first turn must not be drawn out by the boot: the menu is reached inside boot().
        driver.boot(3)
        result = driver.play(500, stop=lambda: seen["turn"] >= when + 3)
        found = [f"{a['check']}: {a['detail']}" for a in checks.anomalies if a["check"] not in CHECKS]
        if checks.crash:
            found.append(f"crash: {checks.crash['detail']} from {checks.crash.get('from')}")
        if result == "timeout" and not found:
            found.append(f"no progress: {seen['turn']} turns")
        if h.hook_errors:
            found.append(f"hook: {h.hook_errors[0].strip().splitlines()[-1]}")
        return {"case": case, "found": found, "thaw": thaw["count"], "lookups": checks.battle.lookups}
    except Exception:
        return {"case": case, "found": [traceback.format_exc(limit=3)], "thaw": 0, "lookups": 0}
    finally:
        h.close()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    parser.add_argument("--only", default=None, help="one held state")
    args = parser.parse_args(argv)
    cases = [c for c in itertools.product(("enemy", "player"), HELD, (True, False), ACTIONS, (True, False))
             if args.only in (None, c[1])]
    findings, thaws = Counter(), 0
    with multiprocessing.Pool(args.jobs) as pool:
        for row in pool.imap_unordered(play, cases):
            thaws += row["thaw"]
            for item in row["found"]:
                findings[item] += 1
                if findings[item] <= 3:
                    print(f"{row['case']}: {item[-600:]}", flush=True)
    print(f"{len(cases)} battles, {thaws} defrost checks, {sum(findings.values())} findings")
    if args.only in (None, "frozen") and not thaws:
        print("CheckDefrost never ran: the matrix is not exercising thaws")
        return 2
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
