"""The FIGHT 2 battle driver shared by run_ai_benchmark and ai_counterfactual.

Factored out of run_ai_benchmark.run_tier (AI_T4_REGRET_PLAN Phase A, 2026-11-17) without
changing what it registers or the order it registers it in: the policy hook must stay ahead of
the turn telemetry, so the telemetry records the move the policy actually chose. Callers that
need hooks in between (the benchmark's score and TrainerAI timing hooks, its switch and item
flags) pass them as before_policy / after_telemetry.
"""
from __future__ import annotations

from pathlib import Path

import benchmark_policies
from harness import RedRogueHarness


class Fight2Driver:
    """Registers the benchmark's FIGHT 2 hooks on `harness` and drives battles to their end.

    tier: forced AI tier 0-3, or None for the game's own choice. player_policy: a name from
    benchmark_policies.POLICIES. move_powers: run_ai_benchmark.parse_move_powers().
    """

    def __init__(self, harness: RedRogueHarness, *, tier: int | None, player_policy: str,
                 move_powers: dict[int, int], rules=None, before_policy=None,
                 after_telemetry=None) -> None:
        # Imported here: run_ai_benchmark imports this module.
        import run_ai_benchmark as rab

        self.h = harness
        self.player_policy = player_policy
        self.move_powers = move_powers
        self.tier_override = 0 if tier is None else tier + 1
        rules = rules if rules is not None else rab.policy_rules()
        h = harness
        h.write8("wAIDebugTierOverride", self.tier_override)
        h.hook_flag("DebugFight2Setup",
                    action=lambda: h.write8("wAIDebugTierOverride", self.tier_override))
        if before_policy is not None:
            before_policy(h)
        # A policy override (lookahead) may replace the move the policy would choose.
        self.move_override: int | None = None
        h.register_hook("MainInBattleLoop.noLinkBattle", lambda _context: h.write8(
            "wTestBattlePlayerSelectedMove", self._player_move(rab)))
        self.turns = h.hook_turn_telemetry()
        if after_telemetry is not None:
            after_telemetry(h)
        self.victories = h.hook_flag("TrainerBattleVictory")
        self.defeats = h.hook_flag("HandlePlayerBlackOut")
        # FIGHT, or PKMN (saved item 2) when a switching policy wants out.
        self.voluntary: dict[str, int | None] = {"target": None, "count": 0}
        self.switch_memo = {"last_turn": False}
        # A forced player switch for this turn (lookahead), else the policy's.
        self.switch_override: int | None = None

        def battle_menu() -> None:
            target = None
            if self.switch_override is not None:
                target = self.switch_override
            elif player_policy in benchmark_policies.SWITCHING_POLICIES:
                target = benchmark_policies.choose_switch(
                    rules, benchmark_policies.read_state(h), player_policy,
                    self.switch_memo["last_turn"])
            self.switch_memo["last_turn"] = target is not None
            self.voluntary["target"] = target
            h.write8("wBattleAndStartSavedMenuItem", 0 if target is None else 2)

        h.hook_flag("DisplayBattleMenu", action=battle_menu)
        # Open the move menu with the cursor ON the chosen slot: SelectMenuItem mirrors the
        # cursor's move into wTestBattlePlayerSelectedMove (see run_ai_benchmark's history).
        h.hook_flag("MoveSelectionMenu", action=lambda: h.write8(
            "wPlayerMoveListIndex", self._player_slot(rab)))
        self.party_inputs, self.party_modes, self.party_trace = rab.prepare_party_driver(
            h, self.voluntary)
        self._handled = 0
        self._mode_index = 0

    def _player_slot(self, rab) -> int:
        if self.move_override is not None:
            return self.move_override
        return rab.choose_player_slot(self.h, self.player_policy, self.move_powers)[0]

    def _player_move(self, rab) -> int:
        if self.move_override is not None:
            return self.h.read8("wBattleMonMoves", offset=self.move_override)
        return rab.choose_player_move(self.h, self.player_policy, self.move_powers)

    def boot(self, seed: int) -> None:
        self.h.boot_fight2(seed=seed)
        self.resync()

    def resync(self) -> None:
        """Call after load_state: the party-menu counters live on the host, not in the save."""
        self._handled = self.party_inputs["count"]
        self._mode_index = len(self.party_modes)
        self.h.write8("wAIDebugTierOverride", self.tier_override)

    def finished(self, victory_start: int, defeat_start: int) -> str | None:
        if self.victories["count"] > victory_start:
            return "win"
        if self.defeats["count"] > defeat_start:
            return "loss"
        return None

    def play(self, max_steps: int, stop=None) -> str:
        """Tap through the battle until it ends ("win" = the player won, "loss"), stop()
        returns true ("stopped", checked after every step, outside any hook), or max_steps
        pass ("timeout"). Resumable: call again after a stop."""
        h = self.h
        victory_start, defeat_start = self.victories["count"], self.defeats["count"]
        for _ in range(max_steps):
            if self.party_inputs["count"] > self._handled:
                h.tick(2)
                h.tap("a" if self.party_modes[self._mode_index] else "b")
                self._handled = self.party_inputs["count"]
                self._mode_index += 1
            else:
                h.tap("a", 1)
                h.tick(8)
            result = self.finished(victory_start, defeat_start)
            if result is not None:
                return result
            if stop is not None and stop():
                return "stopped"
        return "timeout"


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]
