"""Phase 5 latency probe (2026-09-29 AI review): TrainerAI cost now that every
T2+ trainer runs the smart switch predicate each turn.

Probe, not a smoke test. Worst practical case for the new code: T3, six equal
enemy mons (so every reserve is ranked), three revealed player attack types
(so each candidate costs three PreviewTypeMatchup calls), and a live KO threat
(so AIReplacementIsBetter runs). No reserve is better off, so the AI stays and
the timed span ends at ExecuteEnemyMove. Budget: one DMG frame, 70,224 cycles.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
DMG_FRAME = 70224


class SwitchLatencyProbe(unittest.TestCase):
    def test_trainer_ai_switch_path_fits_one_frame(self):
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
            h.boot_fight2(seed=1)
            calls = h.hook_trainer_ai_calls()
            ranked = h.hook_flag("AIRankSendOutCandidatesBelow")
            switched = h.hook_flag("SwitchEnemyMon")
            h.hook_flag("TrainerAI", action=lambda: h.reveal_player_moves(0, [0, 1, 2, 3]))
            # Inclusive per-routine timing: entry hook -> the routine's own
            # return seam, found by watching SP drop back at the return address.
            spans: dict[str, list[int]] = {}

            def time_routine(label: str, exits: list[str]) -> None:
                state = {"start": None}

                def enter(_ctx) -> None:
                    state["start"] = h.cycle_count()

                def leave(_ctx) -> None:
                    if state["start"] is not None:
                        spans.setdefault(label, []).append(h.cycle_count() - state["start"])
                        state["start"] = None

                h.register_hook(label, enter)
                for exit_label in exits:
                    h.register_hook(exit_label, leave)

            time_routine("AIShouldSwitch", ["AIShouldSwitch.stay", "AIShouldSwitch.switch"])
            time_routine("AIRankSendOutCandidatesBelow", ["AIRankSendOutCandidatesBelow.done"])
            time_routine("AIPlayerWouldKO", ["_AIScanPlayerMovesForKO.yesKO", "_AIScanPlayerMovesForKO.noKO"])
            time_routine("AIEnemyHasReliableFirstKO", ["AIEnemyHasReliableFirstKO.restoreNoKO", "AIEnemyHasReliableFirstKO.noKO"])
            h.hook_flag("DisplayBattleMenu", action=lambda:
                        h.write8("wBattleAndStartSavedMenuItem", 0))
            for _ in range(2400):
                if len(calls) >= 4:
                    break
                h.tap("a", 1)
                h.tick(8)
            cycles = [c["cycles"] for c in calls if c["outcome"] == "move"]
            print(f"\nTrainerAI move-path cycles={cycles} max={max(cycles)} "
                  f"({max(cycles) / DMG_FRAME:.2f} DMG frames) "
                  f"rankings={ranked['count']} switches={switched['count']}")
            for label, values in spans.items():
                print(f"  {label}: {values}")
            self.assertGreaterEqual(len(cycles), 3)
            self.assertGreaterEqual(ranked["count"], 3, "the ranking path must actually run")
            self.assertLess(max(cycles), DMG_FRAME)
        finally:
            h.close()


    def test_quiet_turn_cost(self):
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
            h.boot_fight2(seed=1)
            calls = h.hook_trainer_ai_calls()
            h.hook_flag("TrainerAI", action=lambda: h.reveal_player_moves(0, [0]))
            h.hook_flag("DisplayBattleMenu", action=lambda:
                        h.write8("wBattleAndStartSavedMenuItem", 0))
            for _ in range(2400):
                if len(calls) >= 4:
                    break
                h.tap("a", 1)
                h.tick(8)
            cycles = [c["cycles"] for c in calls if c["outcome"] == "move"]
            print(f"\nquiet-turn TrainerAI cycles={cycles} max={max(cycles)} "
                  f"({max(cycles) / DMG_FRAME:.2f} DMG frames)")
            self.assertLess(max(cycles), DMG_FRAME)
        finally:
            h.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
