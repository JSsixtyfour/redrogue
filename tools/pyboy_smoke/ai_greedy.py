"""A "go for the kill" control AI for autoplay comparisons (2026-11-12).

Same ROM, a different decision rule, applied from the harness so the comparison
isolates the rule. At T2/T3 (the tiers that run AI_DAMAGE):
  - moves: the best-damage slot among those that can KO this turn (AI_DAMAGE's
    possible-KO mask), else AI_DAMAGE's best-damage slot. Never a setup or status
    move. The legality filter, the Explosion trade veto and the reliable-KO pass
    still run after it.
  - switching: never voluntarily; AIShouldSwitch always answers "stay". A fainted
    mon is still replaced (AISelectSendOut).
T0/T1 keep their own AI: they run no damage layer to pick from.

Enabled by AI_GREEDY=1 in the environment (autoplay.play installs it), so
run_autoplay's worker processes inherit it.
"""
from __future__ import annotations

import os

AI_BUF_BESTSLOT = 16
AI_BUF_POSSKO = 18
AI_BUF_SLOTDMG = 20
NUM_MOVES = 4


def enabled() -> bool:
    return os.environ.get("AI_GREEDY") == "1"


def install(harness) -> dict[str, int]:
    """Hook the policy in. Returns live counters (forced picks, vetoed switches)."""
    stats = {"forced_picks": 0, "kill_picks": 0, "switches_vetoed": 0}
    choice: dict[str, int | None] = {"slot": None}

    def tier() -> int:
        return max(0, harness.read8("wAITier") - 1)

    def at_apply_best(_context) -> None:
        if tier() < 2:
            choice["slot"] = None
            return
        mask = harness.read8("wBuffer", AI_BUF_POSSKO)
        damage = [harness.read8("wBuffer", AI_BUF_SLOTDMG + 2 * slot) << 8
                  | harness.read8("wBuffer", AI_BUF_SLOTDMG + 2 * slot + 1) for slot in range(NUM_MOVES)]
        kills = [slot for slot in range(NUM_MOVES) if mask >> slot & 1]
        if kills:
            choice["slot"] = max(kills, key=lambda slot: (damage[slot], -slot))
            choice["kill"] = True
        else:
            best = harness.read8("wBuffer", AI_BUF_BESTSLOT)
            choice["slot"] = best if best < NUM_MOVES else None
            choice["kill"] = False

    def at_min_find(_context) -> None:
        slot = choice.get("slot")
        if slot is None or tier() < 2:
            return
        harness.write8("wBuffer", 1, offset=slot)  # strictly below every real score
        stats["forced_picks"] += 1
        stats["kill_picks"] += bool(choice.get("kill"))
        choice["slot"] = None

    def at_switch_return(_context) -> None:
        if tier() < 2:
            return  # T0/T1's vanilla path shares this exit
        harness.pyboy.register_file.F &= ~0x10  # clear carry: "stay"
        stats["switches_vetoed"] += 1

    harness.register_hook("AILayerDamage.applyBest", at_apply_best)
    harness.register_hook("AIEnemyTrainerChooseMoves.loopFindMinimumEntries", at_min_find)
    bank, address = harness.symbols.get("AIShouldSwitch.switch")
    harness._register_at((bank, address + 1), at_switch_return)  # the `ret` after `scf`
    return stats
