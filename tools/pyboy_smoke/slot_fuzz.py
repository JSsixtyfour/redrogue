"""Slot machine fuzzer: the Credit Exchange machine, reached on foot, then random input.

Credits 0-9999 and 0-3 pulls already used this run. Checks: credits stay valid BCD, pulls used
stay 0-3 and never go down, and the autoplay_checks detectors and the freeze watch. The machine
is the only one left in the game and no bot plays it.

    python3 tools/pyboy_smoke/slot_fuzz.py --seeds 1-200 --jobs 6 [--cgb]
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

import autoplay
import autoplay_branch
import autoplay_world as world
import run_autoplay
from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT, ARTIFACTS = autoplay.ROOT, autoplay.ARTIFACTS
MACHINE = (8, 4)  # data/events/hidden_events.asm, CREDIT_EXCHANGE
BUTTONS = (("a", 62), ("b", 9), ("up", 10), ("down", 11), ("start", 1))
LABELS = ("StartSlotMachine", "PromptUserToPlaySlots", "MainSlotMachineLoop", "SlotMachine_CheckForMatches",
          "SlotMachine_PayCoinsToPlayer")


def arrive(cgb: bool) -> bytes:
    """Walk into the Credit Exchange and stand at the machine (only the arrival warp is set up)."""
    exchange = parse_map_constants(ROOT / "constants/map_constants.asm")["CREDIT_EXCHANGE"]
    h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=cgb)
    try:
        h.boot_to_lobby()
        h.tick(180)
        h.write8("wWarpEntries", 0, offset=2)
        h.write8("wWarpEntries", exchange, offset=3)
        h.move_tile("up")
        h.pyboy.button_press("down")
        h.wait_until(lambda: h.read8("hCurMap") == exchange, "the Credit Exchange", 600)
        h.pyboy.button_release("down")
        h.tick(180)
        agent = autoplay.AutoplayAgent(h, seed=7)
        grid = agent.read_grid()
        sides = {(MACHINE[0], MACHINE[1] + 1): "up", (MACHINE[0] - 1, MACHINE[1]): "right",
                 (MACHINE[0] + 1, MACHINE[1]): "left", (MACHINE[0], MACHINE[1] - 1): "down"}
        for _ in range(80):
            if agent.position() in sides:
                break
            path = world.find_path(agent.read_grid(), agent.position(), set(sides), agent.obstacles())
            if not path:
                raise RuntimeError(f"the machine is unreachable from {agent.position()} ({len(grid.__dict__)} fields)")
            agent.walk(path[0])
        agent.press(sides[agent.position()], 2, 20)
        state = io.BytesIO()
        h.save_state(state)
        return state.getvalue()
    finally:
        h.close()


def play(seed: int, *, cgb: bool, frames: int) -> dict[str, object]:
    rng = random.Random(f"slots/{seed}")
    h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=cgb)
    try:
        driver = autoplay_branch.BranchDriver(h)
        exposure: Counter = Counter()
        for label in LABELS:
            h.register_hook(label, lambda _c, name=label: exposure.update([name]))
        h.load_state(io.BytesIO((ARTIFACTS / f"slot_base{'_cgb' if cgb else ''}.state").read_bytes()))
        credits = rng.choice((0, 1, 2, 3, 10, 98, 500, 9990, 9999))
        h.write8("wPlayerCoins", int(str(credits // 100), 16))
        h.write8("wPlayerCoins", int(str(credits % 100), 16), 1)
        pulls = rng.choice((0, 0, 0, 1, 2, 3))
        h.write8("wRogueFlagsBitfield2", h.read8("wRogueFlagsBitfield2") & ~3 | pulls)
        seen = {"pulls": pulls}

        def poll(_context) -> None:
            coins = h.read_bytes("wPlayerCoins", 2)
            if any(b >> 4 > 9 or b & 15 > 9 for b in coins):
                driver.checks.anomaly("slots", f"credits {bytes(coins).hex()} are not BCD")
            used = h.read8("wRogueFlagsBitfield2") & 3
            if used < seen["pulls"]:
                driver.checks.anomaly("slots", f"pulls used went {seen['pulls']} -> {used}")
            seen["pulls"] = used

        prepared = io.BytesIO()
        h.save_state(prepared)
        h.register_hook("MainSlotMachineLoop", poll)
        h.register_hook("JoypadOverworld", poll)
        result = driver.run(prepared.getvalue(), f"slots/{seed}", frames, buttons=BUTTONS)
        result.update(seed=seed, exposure=dict(exposure), credits=credits, pulls=pulls)
        return result
    except Exception:
        return {"seed": seed, "outcome": "error", "detail": traceback.format_exc(limit=4), "anomalies": [],
                "exposure": {}, "frames": 0}
    finally:
        h.close()


def _worker(seed, options, results) -> None:
    results.put((seed, play(seed, cgb=options["cgb_mode"], frames=options["frames"])))


def _hung(seed, timeout, _options) -> dict[str, object]:
    return {"seed": seed, "outcome": "hung", "detail": f"no result within {timeout:.0f}s", "anomalies": [],
            "exposure": {}, "frames": 0}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Random play on the Credit Exchange slot machine.")
    parser.add_argument("--seeds", default="random:60")
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    parser.add_argument("--frames", type=int, default=7000)
    parser.add_argument("--timeout", type=float, default=150)
    parser.add_argument("--cgb", action="store_true")
    args = parser.parse_args(argv)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    (ARTIFACTS / f"slot_base{'_cgb' if args.cgb else ''}.state").write_bytes(arrive(args.cgb))
    findings: dict[str, list[int]] = {}
    exposure, outcomes, started = Counter(), Counter(), time.monotonic()
    for row in run_autoplay.run_all(run_autoplay.parse_seeds(args.seeds),
                                    {"cgb_mode": args.cgb, "frames": args.frames}, args.jobs, args.timeout,
                                    worker=_worker, timeout_row=_hung):
        outcomes[row["outcome"]] += 1
        exposure.update(row["exposure"])
        found = [f"{a['check']}: {a['detail']}" for a in row["anomalies"]]
        if row["outcome"] != "ok":
            found.append(f"{row['outcome']}: {row['detail'].strip().splitlines()[-1] if row['detail'] else ''}")
        for item in found:
            findings.setdefault(item, []).append(row["seed"])
        if found:
            print(f"seed {row['seed']} (credits {row.get('credits')}, pulls {row.get('pulls')}): {'; '.join(found)[:300]}",
                  flush=True)
    print(f"{sum(outcomes.values())} seeds {dict(outcomes)}, {time.monotonic() - started:.0f}s")
    print("exposure:", dict(exposure))
    (ARTIFACTS / f"slot_fuzz{'_cgb' if args.cgb else ''}.json").write_text(json.dumps(
        {"outcomes": dict(outcomes), "findings": findings, "exposure": dict(exposure)}, indent=1) + "\n", encoding="utf-8")
    if not exposure["MainSlotMachineLoop"]:
        print("the machine was never played")
        return 2
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
