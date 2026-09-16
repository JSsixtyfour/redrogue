"""Audit: selecting RUN in a procedural wild battle behaves like a trainer battle.

Release expectation (BIT_DEBUG_MODE clear):
  - .procBattle -> .normalTrainerBattle -> .printCantEscapeOrNoRunningText,
  - .canEscape never runs (the player cannot leave),
  - wActionResultOrTookBattleTurn stays 0, so the turn is NOT consumed. This is
    the behavioural fix: the old .procNoRun set that flag, so RUN cost a turn in
    a procedural wild battle but never in a real trainer battle.

Debug expectation (BIT_DEBUG_MODE set):
  - the battle ends as a win,
  - TrainerBattleVictory is NOT called. Routing there would inc wBattleCount,
    fire RogueAwardCredits1 (its wild-area-boss branch matches all three
    procedural map ids, so every wild mon would pay out) and scroll a trainer
    pic that does not exist.

Usage:
    python3 tools/pyboy_smoke/audit_procedural_run.py [--scenario debug|release|both]

⚠ Driving the battle menu, learned the hard way and easy to get wrong:

1. The menu is NOT up when hIsInBattle first goes non-zero. The "Wild X
   appeared!" intro is still running and every d-pad press is ignored - measured,
   the cursor does not move at all. Advance with A until the DisplayBattleMenu
   hook fires.
2. hCurrentMenuItem NEVER reads 2 or 3 while you are browsing. The battle menu
   is two 1-D column menus; the cursor reads 0/1 WITHIN the active column, and
   DisplayBattleMenu only applies `add $2` for the right column at
   .AButtonPressed. Polling for 3 before pressing A loops forever.
   RUN is therefore: right (switch column), down (lower item), A.
3. Do not mash A to "finish" the battle before reading results. A presses on
   FIGHT simply fight, and the battle can end in a perfectly ordinary win that
   looks exactly like a successful quick-win.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "pyboy_smoke"))

from harness import RedRogueHarness  # noqa: E402
from source_constants import parse_map_constants  # noqa: E402

ARTIFACTS = REPO_ROOT / "tools" / "pyboy_smoke" / "artifacts"

BIT_DEBUG_MODE_MASK = 1 << 1  # wStatusFlags6, constants/ram_constants.asm

HOOKS = [
    "TryRunningFromBattle",
    "TryRunningFromBattle.trainerBattle",
    "TryRunningFromBattle.procBattle",
    "TryRunningFromBattle.normalTrainerBattle",
    "TryRunningFromBattle.printCantEscapeOrNoRunningText",
    "TryRunningFromBattle.canEscape",
    "BattleMenu_RunWasSelected",
    "TrainerBattleVictory",
]


def run_scenario(scenario: str) -> bool:
    ids = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
    harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
    try:
        counters = {label: harness.hook_flag(label) for label in HOOKS}
        menu_up = harness.hook_flag("DisplayBattleMenu")

        harness.boot_to_lobby()
        harness.preload_and_enter_wild_area(ids["PROCEDURAL_CAVE_1"], "Procedural Cave")
        battles_before = harness.read8("wBattleCount")

        for step in range(400):
            if harness.read8("hIsInBattle") != 0:
                break
            harness.move_tile(["left", "right", "up", "down"][step % 4])
        else:
            print("  no wild encounter after 400 steps")
            return False

        harness.tick(60)
        for _ in range(200):
            if menu_up["count"]:
                break
            harness.tap("a", 1)
            harness.tick(8)
        if not menu_up["count"]:
            print("  battle menu never appeared")
            return False
        harness.tick(20)

        if scenario == "release":
            flags = harness.read8("wStatusFlags6")
            harness.write8("wStatusFlags6", flags & ~BIT_DEBUG_MODE_MASK)

        turn_before = harness.read8("wActionResultOrTookBattleTurn")
        harness.tap("right", 2)
        harness.tick(20)
        harness.tap("down", 2)
        harness.tick(20)
        harness.tap("a", 2)
        harness.tick(60)

        counts = {label: counters[label]["count"] for label in HOOKS}
        for label in HOOKS:
            print(f"    {label:52s} {counts[label]}")

        turn_after = harness.read8("wActionResultOrTookBattleTurn")
        battles_after = harness.read8("wBattleCount")
        in_battle_idle = harness.read8("hIsInBattle")
        print(f"    wActionResultOrTookBattleTurn {turn_before} -> {turn_after}")
        print(f"    wBattleCount {battles_before} -> {battles_after}")

        checks = [
            ("RUN was selected", counts["BattleMenu_RunWasSelected"] == 1),
            ("the procedural path ran", counts["TryRunningFromBattle.procBattle"] == 1),
            ("the player never escaped", counts["TryRunningFromBattle.canEscape"] == 0),
            ("TrainerBattleVictory not called", counts["TrainerBattleVictory"] == 0),
            ("the turn was not consumed", turn_before == turn_after == 0),
            ("wBattleCount unchanged", battles_before == battles_after),
        ]
        if scenario == "release":
            checks += [
                ("trainer no-running text shown",
                 counts["TryRunningFromBattle.normalTrainerBattle"] == 1
                 and counts["TryRunningFromBattle.printCantEscapeOrNoRunningText"] == 1),
                ("battle continues", in_battle_idle == 1),
            ]
        else:
            checks += [
                ("no no-running text on the debug win",
                 counts["TryRunningFromBattle.printCantEscapeOrNoRunningText"] == 0),
                ("result is a win", harness.read8("wBattleResult") == 0),
            ]
            for _ in range(60):
                if harness.read8("hIsInBattle") == 0:
                    break
                harness.tap("a", 1)
                harness.tick(20)
            checks.append(("battle ended", harness.read8("hIsInBattle") == 0))
            checks.append(("back on the cave map",
                           harness.read8("hCurMap") == ids["PROCEDURAL_CAVE_1"]))

        ok = True
        for name, passed in checks:
            print(f"    [{'ok' if passed else 'FAIL'}] {name}")
            ok = ok and passed
        return ok
    finally:
        try:
            harness.close()
        except Exception:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["debug", "release", "both"], default="both")
    args = parser.parse_args()

    scenarios = ["debug", "release"] if args.scenario == "both" else [args.scenario]
    failures = 0
    for scenario in scenarios:
        print(f"--- {scenario} ---")
        if not run_scenario(scenario):
            failures += 1
    print("RESULT:", "PASS" if failures == 0 else f"FAIL ({failures} scenario(s))")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
