"""Battle fuzzer: random FIGHT 2 battles full of unusual moves, played with random input.

The autoplay bots play sensible moves, so Bide, Transform, Mimic, Metronome, Mirror
Move, Disable, Haze, Rage, Wrap and Struggle hardly ever run, and they rarely open a
menu in battle without using it. Both bugs of 2026-11-24 lived exactly there. Each seed
here draws two parties (movesets weighted to those moves), an AI tier, a trainer class,
key items and sometimes a Witch challenge, then presses random buttons: moves, switches,
STATS, the ITEM list, move reordering, backing out of every menu. At the top of some turns
(before the enemy plans, where a real status could already be in place) it also writes a
status, low HP or nearly spent PP on one side.

    python3 tools/pyboy_smoke/battle_fuzz.py --seeds 1-500 --jobs 4
    python3 tools/pyboy_smoke/battle_fuzz.py --seeds 37 --jobs 1 --verbose   # one seed again
    ... --cgb                                                                # CGB mode

Every GameChecks detector is armed (autoplay_checks, autoplay_screen and
autoplay_battle_checks), plus autoplay_branch's freeze watch, and each seed runs in its
own process so an illegal opcode (a hang inside tick()) is killed at --timeout. A seed is
decided entirely by its number and the ROM. Writes artifacts/battle_fuzz[_cgb].json; exits
1 on any finding. The exposure block counts what really ran: a clean run that never used
Bide proves nothing about Bide.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import random
import sys
import time
import traceback
from collections import Counter
from pathlib import Path

import autoplay
import autoplay_branch
import run_autoplay
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = autoplay.ROOT
ARTIFACTS = autoplay.ARTIFACTS
WEIRD = ("BIDE WRAP BIND CLAMP FIRE_SPIN TRANSFORM MIMIC METRONOME MIRROR_MOVE DISABLE HAZE RAGE THRASH PETAL_DANCE "
         "HYPER_BEAM FLY DIG SOLARBEAM SKY_ATTACK REST RECOVER COUNTER SUBSTITUTE LEECH_SEED TOXIC CONFUSE_RAY SPORE "
         "HYPNOSIS ICE_BEAM BLIZZARD FLAMETHROWER FIRE_BLAST EMBER THUNDER_WAVE SELFDESTRUCT EXPLOSION DREAM_EATER "
         "SUPER_FANG DOUBLE_EDGE PAY_DAY CONVERSION MIST FOCUS_ENERGY REFLECT LIGHT_SCREEN MINIMIZE STOMP HEADBUTT "
         "DOUBLESLAP FURY_ATTACK TWINEEDLE JUMP_KICK ROAR WHIRLWIND TELEPORT PSYWAVE NIGHT_SHADE SEISMIC_TOSS "
         "QUICK_ATTACK SWIFT ROCK_SLIDE SWORDS_DANCE AMNESIA AGILITY GROWL SPLASH").split()
# Mostly A, so battles move on; B and the d-pad so menus are entered and left; SELECT
# reorders moves and party; START is ignored in battle.
BUTTONS = (("a", 46), ("b", 14), ("up", 11), ("down", 13), ("left", 5), ("right", 8), ("select", 4))
STATUS = {"sleep": 1, "sleep_long": 5, "poison": 1 << 3, "burn": 1 << 4, "freeze": 1 << 5, "paralysis": 1 << 6}
TESTED_CLASSES = ("COOLTRAINER_M", "COOLTRAINER_F", "JUGGLER", "AGATHA", "LANCE", "BROCK", "SABRINA", "GIOVANNI",
                  "LORELEI", "GENTLEMAN")


def real_species() -> set[int]:
    """Internal ids with a Pokedex number: pokemon_constants.asm also holds counts and a
    skipped id ($1F), and a mon of that id has garbage base stats."""
    rows = [line.split(";")[0].split() for line in
            (ROOT / "data/pokemon/dex_order.asm").read_text(encoding="utf-8").splitlines()]
    rows = [row for row in rows if row and row[0] == "db"]
    return {index + 1 for index, row in enumerate(rows) if row[1] != "0"}


def scenario(seed: int) -> dict[str, object]:
    rng = random.Random(f"battle_fuzz/{seed}")
    species = sorted(real_species())
    move_ids = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
    ordinary = list(range(1, move_ids["STRUGGLE"]))
    weird = [move_ids[name] for name in WEIRD if name in move_ids]
    trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
    base = rng.randint(15, 90)

    def mon() -> dict[str, object]:
        pool = weird if rng.random() < 0.7 else ordinary
        # A third of the mons know a single move: locks, Disable and 0 PP bite hardest there.
        count = 1 if rng.random() < 0.2 else rng.randint(1, 4)
        return {"species": rng.choice(species), "level": max(5, min(100, base + rng.randint(-6, 6))),
                "moves": rng.sample(pool, count)}

    items = sorted(n for n in autoplay.key_item_bits() if n not in autoplay.KIT_EXCLUDED)
    owned = rng.sample(items, rng.randint(0, 6))
    # The items that rewrite battle state mid-turn get most of the exposure.
    for name in ("TURN_REWIND", "KO_DEFIANCE"):
        if rng.random() < 0.5 and name in items:
            owned = [name] + [other for other in owned if other != name]
    last_stand = rng.random() < 0.25  # one mon, KO DEFIANCE carried and kept charged
    if last_stand:
        owned = ["KO_DEFIANCE"] + [other for other in owned if other != "KO_DEFIANCE"]
    return {
        "last_stand": last_stand,
        "player": [mon() for _ in range(1 if last_stand else rng.choice((1, 2, 4, 5, 6, 6, 6)))],
        "enemy": [mon() for _ in range(rng.choice((1, 2, 3, 6, 6)))],
        "trainer": trainers[rng.choice([n for n in TESTED_CLASSES if n in trainers])],
        "tier": rng.choice((0, 1, 2, 3, 3, 3)),
        "kit": [[n, rng.randint(0, 2), i < 3] for i, n in enumerate(owned)],
        "flute": rng.random() < 0.4,
        "challenge": rng.choice((0, 0, 0, 8, 9, 10, 12, 14, 16)),
        "meddle": 0.5 if last_stand else rng.choice((0.0, 0.1, 0.3, 0.6)),
    }


class FuzzDriver(autoplay_branch.BranchDriver):
    def __init__(self, harness, seed: int, plan: dict[str, object]):
        super().__init__(harness)
        self.plan = plan
        self.meddle_rng = random.Random(f"battle_fuzz/meddle/{seed}")
        self.exposure: Counter = Counter()
        h = harness
        h.register_hook("DisplayBattleMenu", self._on_menu)
        h.register_hook("MainInBattleLoop", self._on_turn)
        for label in ("StatusScreenCycle", "DisplayPartyMenu", "BuildBattleItemList", "MoveSelectionMenu",
                      "ItemUsePokeFlute_Real", "TurnRewindRestore", "SwitchEnemyMon", "TrainerBattleVictory",
                      "HandlePlayerBlackOut", "CheckPlayerStatusConditions.FrozenCheck", "KODefianceRevive"):
            if label in h.symbols._symbols:
                h.register_hook(label, lambda _c, name=label: self.exposure.update([name]))

    def _on_menu(self, _context) -> None:
        # FIGHT 2 is a test battle: without this bit clear the move info box and the
        # normal selected-move read never run.
        self.h.write8("wStatusFlags7", self.h.read8("wStatusFlags7") & ~1)
        self.exposure["turns"] += 1
        if self.plan["last_stand"]:
            self.h.write8("wKODefianceUsages", 3)

    def _on_turn(self, _context) -> None:
        rng, h = self.meddle_rng, self.h
        if rng.random() >= self.plan["meddle"]:
            return
        side = rng.choice(("BattleMon", "EnemyMon"))
        # Conditions stack: KO DEFIANCE reviving a SLEEPING last mon (2026-11-24) needed a
        # status and low HP on the same side in the same turn.
        kind = rng.choice(("status", "status", "hp", "pp", "status+hp", "status+hp"))
        if not (h.read8(f"w{side}HP") | h.read8(f"w{side}HP", 1)):
            return
        self.exposure[f"meddle_{kind}"] += 1
        if "status" in kind:
            name = rng.choice(sorted(STATUS))
            h.write8(f"w{side}Status", STATUS[name])
            self.exposure[f"meddle_{name}"] += 1
        if "hp" in kind:
            h.write8(f"w{side}HP", 0)
            h.write8(f"w{side}HP", rng.randint(1, min(30, h.read8(f"w{side}MaxHP", 1) or 30)), 1)
        if kind == "pp":
            for slot in range(4):
                if h.read8(f"w{side}Moves", slot):
                    h.write8(f"w{side}PP", rng.choice((0, 1)), slot)


def play(seed: int, *, cgb: bool, frames: int, rom: str = "pokeblue_debug") -> dict[str, object]:
    plan = scenario(seed)
    started = time.monotonic()
    h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=cgb)
    try:
        h.inject_fight2_spec(plan["player"], plan["enemy"], trainer_class=plan["trainer"], ai_tier=plan["tier"])
        driver = FuzzDriver(h, seed, plan)
        h.boot_fight2(seed=100 + seed % 60000)
        autoplay.grant_kit(h, plan["kit"])
        for label, value in (("wKODefianceUsages", 3), ("wTurnRewindUsages", 4), ("wDiceCharges", 0x3F)):
            h.write8(label, value)
        if plan["flute"]:
            h.write8("wRecoveryItemCounts", 1, 20)
        if plan["challenge"]:
            h.write8("wWitchChallenge", plan["challenge"])
            h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") | 1 << 3)  # BIT_WITCH_ACCEPTED
            h.write8("wBattleTurnLimit", 4)
        state = io.BytesIO()
        h.save_state(state)
        result = driver.run(state.getvalue(), f"battle_fuzz/{seed}", frames, buttons=BUTTONS)
        summary = driver.checks.summary()
        result["seed"] = seed
        result["exposure"] = dict(driver.exposure)
        result["battle_checks"] = summary["battle_checks"]
        result["first_anomaly_state"] = None
        if driver.checks.first_anomaly_state is not None or result["outcome"] != "ok":
            stem = ARTIFACTS / f"battle_fuzz_{'cgb_' if cgb else ''}{seed}"
            stem.with_suffix(".start.state").write_bytes(state.getvalue())
            if driver.checks.first_anomaly_state is not None:
                stem.with_suffix(".state").write_bytes(driver.checks.first_anomaly_state)
            else:
                final = io.BytesIO()
                h.save_state(final)
                stem.with_suffix(".state").write_bytes(final.getvalue())
            result["first_anomaly_state"] = str(stem.with_suffix(".state"))
        result["plan"] = plan
    except Exception:
        result = {"seed": seed, "outcome": "error", "detail": traceback.format_exc(limit=4), "anomalies": [],
                  "exposure": {}, "battle_checks": {}, "frames": 0, "plan": plan}
    finally:
        h.close()
    result["wall_seconds"] = round(time.monotonic() - started, 1)
    return result


def _worker(seed, options, results) -> None:
    results.put((seed, play(seed, cgb=options["cgb_mode"], frames=options["frames"])))


def _hung(seed, timeout, _options) -> dict[str, object]:
    return {"seed": seed, "outcome": "hung", "detail": f"no result within {timeout:.0f}s", "anomalies": [],
            "exposure": {}, "battle_checks": {}, "frames": 0, "plan": scenario(seed)}


def signature(row: dict[str, object]) -> list[str]:
    found = [f"{a['check']}: {a['detail']}" for a in row["anomalies"]]
    if row["outcome"] != "ok":
        found.append(f"{row['outcome']}: {row['detail'].strip().splitlines()[-1] if row['detail'] else ''}")
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Random battles with random input and every detector armed.")
    parser.add_argument("--seeds", default="1-60")
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    parser.add_argument("--frames", type=int, default=14000)
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--cgb", action="store_true")
    parser.add_argument("--minutes", type=float, default=None, help="stop starting seeds after this long")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)
    seeds = run_autoplay.parse_seeds(args.seeds)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    options = {"cgb_mode": args.cgb, "frames": args.frames}
    findings: dict[str, list[int]] = {}
    exposure, checks, outcomes = Counter(), Counter(), Counter()
    rows, frames, started = [], 0, time.monotonic()
    output = ARTIFACTS / f"battle_fuzz{'_cgb' if args.cgb else ''}.json"

    def write() -> None:
        output.write_text(json.dumps({
            "seeds": args.seeds, "played": sum(outcomes.values()), "outcomes": dict(outcomes), "frames": frames,
            "findings": findings, "exposure": dict(exposure), "battle_checks": dict(checks),
            "rows": rows}, indent=1) + "\n", encoding="utf-8")

    for start in range(0, len(seeds), 60):
        if args.minutes is not None and time.monotonic() - started > args.minutes * 60:
            break
        for row in run_autoplay.run_all(seeds[start:start + 60], options, args.jobs, args.timeout,
                                        worker=_worker, timeout_row=_hung):
            outcomes[row["outcome"]] += 1
            frames += row["frames"]
            exposure.update(row["exposure"])
            inner = row["battle_checks"]
            checks.update({k: v for k, v in inner.items() if isinstance(v, int)})
            checks.update(inner.get("exposure", {}))
            found = signature(row)
            for item in found:
                findings.setdefault(item, []).append(row["seed"])
            if found:
                rows.append(row)
                print(f"seed {row['seed']}: {'; '.join(found)[:300]}", flush=True)
            elif args.verbose:
                print(f"seed {row['seed']}: ok {row['frames']} frames {row['exposure']}", flush=True)
        write()
    write()
    print(f"{sum(outcomes.values())} seeds {dict(outcomes)}, {frames} frames, {time.monotonic() - started:.0f}s")
    print("exposure:", dict(sorted(exposure.items())))
    for item, hit in sorted(findings.items(), key=lambda kv: -len(kv[1])):
        print(f"  {len(hit)}x {item[:200]}  seeds {hit[:6]}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
