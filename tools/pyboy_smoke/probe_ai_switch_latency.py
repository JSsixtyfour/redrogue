"""Phase 5 / turn-plan latency probe (2026-09-29 AI review; re-pointed
2026-10-22 for the pre-menu turn plan, ai_turn_plan.asm).

Probe, not a smoke test. The enemy's whole turn - move, T2+ switch decision,
and the replacement ranking - is now decided ONCE PER TURN by AIPlanEnemyTurn,
BEFORE the player's battle menu appears (core.asm MainInBattleLoop), not at
TrainerAI's old commit-time call. The old span this file measured (TrainerAI
entry through ExecuteEnemyMove/the AIActionUsed* branches) no longer isolates
that work: TrainerAI now runs before the turn-order (QUICK_ATTACK/COUNTER/
Speed) comparison is even made, so its own "move" span was measured inflated
by that comparison and, on a player-first turn, by the player's own move
execution too (measured: 10.4M-plus cycles, a whole turn). The span that
matters now is AIPlanEnemyTurn's own entry-to-DisplayBattleMenu: that is the
delay the player actually sits through before the next menu appears.

hook_trainer_ai_calls() (harness.py) is NOT reused here for the same reason:
its "caller_path" hooks (MainInBattleLoop.enemyMovesFirst /
.playerFirstPoisonPlayerAlive) fire AFTER TrainerAI now, not before, so the
path label it would attach is one turn stale. It is unchanged for now since
nothing in `make smoke` depends on its "caller_path" field; ai_telemetry.py
and run_ai_benchmark.py (make ai_benchmark, not make smoke) use it only for
its "cycles"/"outcome" fields on the "move" path, unaffected by this probe.

All hooks (the per-routine timers, and the fixture's own reveal) are
registered BEFORE boot_fight2: turn 1's plan is made INSIDE it (the pre-menu
plan runs before boot_fight2's own first battle menu), so anything registered
after boot would miss turn 1 entirely - and this probe explicitly wants to
report turn 1 (cold, no cached state) separately from the steady state.

Worst practical case for the new code: T3, six equal enemy mons (so every
reserve is ranked), four revealed player attack types (so each candidate
costs several PreviewTypeMatchup calls), and a live KO threat (so
AIReplacementIsBetter runs). No reserve is better off, so the AI stays.
Budget: see the user-agreed thresholds below.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
DMG_FRAME = 70224

# Measured 2026-10-22 (ai_turn_plan.asm), steady state (turn 1 is reported
# separately, cold with no cached KO/estimate state): quiet board 94,308
# cycles (1.34 DMG frames), worst board (6 reserves, 4 revealed player moves)
# 155,904 cycles (2.22 frames). Budget is measured + 20% (user decision,
# 2026-10-22): enough headroom for normal matchup variance without hiding a
# real regression. Re-measure and update both constants together if the
# underlying routines change.
QUIET_BUDGET = round(94_308 * 1.2)  # 113,170 (1.61 frames)
WORST_BUDGET = round(155_904 * 1.2)  # 187,085 (2.66 frames)


def time_plan_to_menu(h):
    """Registers AIPlanEnemyTurn-entry -> DisplayBattleMenu-entry timing, plus
    the per-routine breakdowns inside that window (unchanged routines, just
    called earlier now). Call before boot_fight2. Returns (spans, routine_spans,
    run) where run(decision_count) drives taps until that many spans exist."""
    spans: list[int] = []
    state = {"start": None}
    routine_spans: dict[str, list[int]] = {}

    def plan_enter(_ctx) -> None:
        state["start"] = h.cycle_count()

    def menu_enter(_ctx) -> None:
        if state["start"] is not None:
            spans.append(h.cycle_count() - state["start"])
            state["start"] = None

    h.register_hook("AIPlanEnemyTurn", plan_enter)
    h.register_hook("DisplayBattleMenu", menu_enter)

    def time_routine(label: str, exits: list[str]) -> None:
        inner = {"start": None}

        def enter(_ctx) -> None:
            inner["start"] = h.cycle_count()

        def leave(_ctx) -> None:
            if inner["start"] is not None:
                routine_spans.setdefault(label, []).append(h.cycle_count() - inner["start"])
                inner["start"] = None

        h.register_hook(label, enter)
        for exit_label in exits:
            h.register_hook(exit_label, leave)

    time_routine("AIShouldSwitch", ["AIShouldSwitch.stay", "AIShouldSwitch.switch"])
    time_routine("AIRankSendOutCandidatesBelow", ["AIRankSendOutCandidatesBelow.done"])
    time_routine("AIPlayerWouldKO", ["_AIScanPlayerMovesForKO.yesKO", "_AIScanPlayerMovesForKO.noKO"])
    time_routine("AIEnemyHasReliableFirstKO", ["AIEnemyHasReliableFirstKO.restoreNoKO", "AIEnemyHasReliableFirstKO.noKO"])

    h.hook_flag("DisplayBattleMenu", action=lambda:
                h.write8("wBattleAndStartSavedMenuItem", 0))

    def run(decision_count: int = 4) -> None:
        for _ in range(2400):
            if len(spans) >= decision_count:
                break
            h.tap("a", 1)
            h.tick(8)

    return spans, routine_spans, run


class SwitchLatencyProbe(unittest.TestCase):
    def test_plan_to_menu_fits_budget_worst_board(self):
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
            moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
            trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

            def mon(name, move_names, level=50):
                return {"species": species[name], "level": level,
                        "moves": [moves[m] for m in move_names]}

            h.inject_fight2_spec(
                [mon("MEWTWO", ["GROWL", "PSYCHIC_M", "THUNDERBOLT", "ICE_BEAM"])],
                [mon("RATTATA", ["TACKLE"]) for _ in range(6)],
                trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
            h.hook_flag("AIPlanEnemyTurn", action=lambda: h.reveal_player_moves(0, [0, 1, 2, 3]))
            ranked = h.hook_flag("AIRankSendOutCandidatesBelow")
            switched = h.hook_flag("SwitchEnemyMon")
            spans, routine_spans, run = time_plan_to_menu(h)
            h.boot_fight2(seed=1)
            run(4)
            print(f"\nplan-to-menu cycles={spans} max={max(spans)} "
                  f"({max(spans) / DMG_FRAME:.2f} DMG frames) "
                  f"rankings={ranked['count']} switches={switched['count']}")
            for label, values in routine_spans.items():
                print(f"  {label}: {values}")
            self.assertGreaterEqual(len(spans), 3)
            self.assertGreaterEqual(ranked["count"], 3, "the ranking path must actually run")
            print(f"  turn 1 (cold) {spans[0]}; steady state max {max(spans[1:])}")
            self.assertLess(max(spans[1:]), WORST_BUDGET)
        finally:
            h.close()

    def test_plan_to_menu_fits_budget_quiet_board(self):
        """Typical turn: no believed damaging move (Splash revealed), so no
        KO threat, no veto estimate and no ranking - only the cheap checks."""
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
            moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
            trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
            h.inject_fight2_spec(
                [{"species": species["MEWTWO"], "level": 50, "moves": [moves["SPLASH"]]}],
                [{"species": species["RATTATA"], "level": 50, "moves": [moves["TACKLE"]]}
                 for _ in range(6)],
                trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
            h.hook_flag("AIPlanEnemyTurn", action=lambda: h.reveal_player_moves(0, [0]))
            spans, _, run = time_plan_to_menu(h)
            h.boot_fight2(seed=1)
            run(4)
            print(f"\nquiet plan-to-menu cycles={spans} max={max(spans)} "
                  f"({max(spans) / DMG_FRAME:.2f} DMG frames)")
            print(f"  turn 1 (cold) {spans[0]}; steady state max {max(spans[1:])}")
            self.assertLess(max(spans[1:]), QUIET_BUDGET)
        finally:
            h.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
