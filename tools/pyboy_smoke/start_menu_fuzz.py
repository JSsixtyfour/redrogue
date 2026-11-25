"""START menu fuzzer: random, menu-heavy input in the lobby, with a coverage map.

The bots open the START menu only to heal. This stays in it: Pokedex (forms included), party
STATS and the Learndex pages, bag pockets, trainer card, options, SAVE, with the party given
random forms of damage and status so every page has something to draw. autoplay_checks (crash,
stack, garbled screen, party and item data) and the freeze watch are armed.

    python3 tools/pyboy_smoke/start_menu_fuzz.py --seeds 1-200 --jobs 6 [--cgb]

Prints which routines of the watched files ran at all: a clean run proves nothing about a page
that was never drawn.
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
import coverage_inventory
import run_autoplay
from harness import RedRogueHarness

ROOT, ARTIFACTS = autoplay.ROOT, autoplay.ARTIFACTS
BUTTONS = (("a", 34), ("b", 10), ("up", 9), ("down", 17), ("left", 8), ("right", 10), ("start", 10), ("select", 2))
WATCHED = ("engine/pokemon/status_view.asm", "engine/pokemon/status_screen.asm", "custom_functions/form_dex.asm",
           "engine/menus/options_menu.asm", "engine/menus/pokedex.asm", "engine/menus/start_sub_menus.asm",
           "engine/menus/save.asm", "custom_functions/trainer_card_slots.asm", "custom_functions/tm_bag.asm",
           "custom_functions/dex_forms.asm")


def watched_labels() -> dict[str, list[str]]:
    by_file: dict[str, list[str]] = {}
    for row in coverage_inventory.code_labels(autoplay.DEBUG_ROM):
        if row["file"] in WATCHED and row["global"]:
            by_file.setdefault(row["file"], []).append(row["name"])
    return by_file


def coverage_hooks(rom: bytes) -> dict[str, tuple[int, int]]:
    """Hook addresses that cannot wedge PyBoy (coverage_inventory.hook_plan)."""
    wanted = {label for labels in watched_labels().values() for label in labels}
    plan, _inferred = coverage_inventory.hook_plan(coverage_inventory.code_labels(autoplay.DEBUG_ROM), rom)
    return {label: key for label, key in plan.items() if label in wanted}


def play(seed: int, *, cgb: bool, frames: int) -> dict[str, object]:
    rng = random.Random(f"start_menu/{seed}")
    h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=cgb)
    try:
        driver = autoplay_branch.BranchDriver(h)
        autoplay_hooks = coverage_hooks(h.rom_path.read_bytes())
        autoplay.boot(h, seed)
        hit, _skipped = h.track_coverage(autoplay_hooks)
        for slot in range(h.read8("wPartyCount")):
            if rng.random() < 0.4:
                h.write8("wPartyMon1Status", rng.choice((1, 8, 16, 32, 64)), slot * 0x2C)
            if rng.random() < 0.3:
                h.write8("wPartyMon1HP", 0, slot * 0x2C)
                h.write8("wPartyMon1HP", rng.randint(0 if slot else 1, 9), slot * 0x2C + 1)
        state = io.BytesIO()
        h.save_state(state)
        result = driver.run(state.getvalue(), f"start_menu/{seed}", frames, buttons=BUTTONS)
        result.update(seed=seed, hit=sorted(hit))
        if result["anomalies"] or result["outcome"] != "ok":
            path = ARTIFACTS / f"start_menu_{'cgb_' if cgb else ''}{seed}.start.state"
            path.write_bytes(state.getvalue())
            result["state"] = str(path)
        return result
    except Exception:
        return {"seed": seed, "outcome": "error", "detail": traceback.format_exc(limit=4), "anomalies": [],
                "hit": [], "frames": 0}
    finally:
        h.close()


def _worker(seed, options, results) -> None:
    results.put((seed, play(seed, cgb=options["cgb_mode"], frames=options["frames"])))


def _hung(seed, timeout, _options) -> dict[str, object]:
    return {"seed": seed, "outcome": "hung", "detail": f"no result within {timeout:.0f}s", "anomalies": [],
            "hit": [], "frames": 0}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="START-menu-heavy random input from the lobby.")
    parser.add_argument("--seeds", default="random:60")
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    parser.add_argument("--frames", type=int, default=9000)
    parser.add_argument("--timeout", type=float, default=200)
    parser.add_argument("--cgb", action="store_true")
    args = parser.parse_args(argv)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    by_file = watched_labels()
    findings: dict[str, list[int]] = {}
    outcomes, hit, frames, started = Counter(), set(), 0, time.monotonic()
    for row in run_autoplay.run_all(run_autoplay.parse_seeds(args.seeds),
                                    {"cgb_mode": args.cgb, "frames": args.frames}, args.jobs, args.timeout,
                                    worker=_worker, timeout_row=_hung):
        outcomes[row["outcome"]] += 1
        frames += row["frames"]
        hit |= set(row["hit"])
        found = [f"{a['check']}: {a['detail']}" for a in row["anomalies"]]
        if row["outcome"] != "ok":
            found.append(f"{row['outcome']}: {row['detail'].strip().splitlines()[-1] if row['detail'] else ''}")
        for item in found:
            findings.setdefault(item, []).append(row["seed"])
        if found:
            print(f"seed {row['seed']}: {'; '.join(found)[:400]}", flush=True)
    print(f"{sum(outcomes.values())} seeds {dict(outcomes)}, {frames} frames, {time.monotonic() - started:.0f}s")
    for file, labels in sorted(by_file.items()):
        missed = [label for label in labels if label not in hit]
        print(f"  {file}: {len(labels) - len(missed)}/{len(labels)} routines" + (f", never {missed[:8]}" if missed else ""))
    for item, seeds in sorted(findings.items(), key=lambda kv: -len(kv[1])):
        print(f"  {len(seeds)}x {item[:220]}  seeds {seeds[:6]}")
    (ARTIFACTS / f"start_menu_fuzz{'_cgb' if args.cgb else ''}.json").write_text(json.dumps(
        {"outcomes": dict(outcomes), "findings": findings, "hit": sorted(hit)}, indent=1) + "\n", encoding="utf-8")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
