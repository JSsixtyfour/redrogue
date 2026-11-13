"""AI review CP5 (2026-11-13): stage-aware setup tempo.

engine/battle/ai/ai_setup_gate.asm, AISetupTempo. A +2 or +1 boost of our best
move's category is "free" when it cuts that move's hits-to-KO on the player by one
or more. From the neutral stage with the stat under 500 the old x2 / x1.5 multiply
still decides (free). From any other stage, or a stat of 500+, the boosted stat is
projected the way effects.asm's stat-up computes it (unmodified x stage ratio,
capped at 999, minimum 1, a burned Attack halved again) and estimated uncached
(AISetupHitsAtBoost). Plan: AI_REVIEW_PLAN_2026-11-12.md.

Each board sweeps the player's HP and compares the gate byte with a Python model
fed by the estimator itself at the projected stat, so what is under test is the
stage arithmetic, the gating, the restore and the bit logic, not the damage formula.
"""

from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

MOVE_LENGTH = 6
NEUTRAL = 7
RATIOS = [(25, 100), (28, 100), (33, 100), (40, 100), (50, 100), (66, 100), (1, 1),
          (15, 10), (2, 1), (25, 10), (3, 1), (35, 10), (4, 1)]
MAX_HITS = 8


def stat_at(unmodified: int, stage: int, burned: bool = False) -> int:
    num, den = RATIOS[stage - 1]
    value = max(1, min(999, unmodified * num // den))
    return max(1, value // 2) if burned else value


def hits(hp: int, damage: int) -> int:
    if damage == 0:
        return MAX_HITS + 1
    for n in range(1, MAX_HITS + 1):
        if n * damage >= hp:
            return n
    return MAX_HITS + 1


class SetupTempoTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.species = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
        self.moves = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
        self.battle = parse_rgbds_constants(REPO_ROOT / "constants" / "battle_constants.asm")
        self.ai = parse_rgbds_constants(REPO_ROOT / "constants" / "ai_constants.asm")
        self.types = parse_rgbds_constants(REPO_ROOT / "constants" / "type_constants.asm")
        self.trainers = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")
        self.rom = (REPO_ROOT / "pokeblue_debug.gbc").read_bytes()

    def tearDown(self) -> None:
        self.h.close()

    # --- helpers ---------------------------------------------------------------
    def mon(self, species: str, moves: list[str], level: int = 50) -> dict[str, object]:
        return {"species": self.species[species], "level": level,
                "moves": [self.moves[name] for name in moves]}

    def boot(self, enemy_moves: list[str], enemy: str = "NIDOKING", player: str = "SNORLAX") -> None:
        self.h.inject_fight2_spec([self.mon(player, ["SPLASH"])], [self.mon(enemy, enemy_moves)],
                                  trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
        self.h.boot_fight2(seed=1)
        self.move = enemy_moves[0]

    def word(self, label: str, offset: int = 0) -> int:
        return self.h.read8(label, offset) << 8 | self.h.read8(label, offset + 1)

    def write_word(self, label: str, value: int, offset: int = 0) -> None:
        self.h.write8(label, value >> 8, offset=offset)
        self.h.write8(label, value & 0xFF, offset=offset + 1)

    def physical(self) -> bool:
        return self.ai_category_mask() == self.mask("AI_SG_ATK2_FREE_BIT", "AI_SG_ATK1_FREE_BIT")

    def mask(self, *names: str) -> int:
        return sum(1 << self.ai[name] for name in names)

    def ai_category_mask(self) -> int:
        move_type = self.rom_move(self.move)[3]
        if move_type < self.types["FIRE"]:  # FIRE is SPECIAL, the first special type
            return self.mask("AI_SG_ATK2_FREE_BIT", "AI_SG_ATK1_FREE_BIT")
        return self.mask("AI_SG_SPC2_FREE_BIT", "AI_SG_SPC1_FREE_BIT")

    def rom_move(self, move: str) -> bytes:
        bank, address = self.h.symbols.get("Moves")
        start = bank * 0x4000 + address - 0x4000 + (self.moves[move] - 1) * MOVE_LENGTH
        return self.rom[start:start + MOVE_LENGTH]

    def labels(self) -> tuple[str, str, str]:
        if self.physical():
            return "wEnemyMonAttack", "wEnemyMonUnmodifiedAttack", "wEnemyMonAttackMod"
        return "wEnemyMonSpecial", "wEnemyMonUnmodifiedSpecial", "wEnemyMonSpecialMod"

    def set_stage(self, stage: int, unmodified: int | None = None, burned: bool = False) -> int:
        """Our category's stage, with the stat the engine would hold there."""
        stat, unmod_label, mod = self.labels()
        if unmodified is not None:
            self.write_word(unmod_label, unmodified)
        self.h.write8(mod, stage)
        self.h.write8("wEnemyMonStatus", (1 << self.battle["BRN"]) if burned else 0)
        value = stat_at(self.word(unmod_label), stage, burned and self.physical())
        self.write_word(stat, value)
        return value

    def estimate_with(self, stat_value: int, delivery: bool = True) -> int:
        """The estimator's answer for our best move with our stat = stat_value:
        AIEstimateDamage, then AIAdjustEnemyDamageForExpectedDelivery as the
        tempo does (it caps each hit-count outcome at the player's current HP,
        so it depends on wBattleMonHP). Puts the stat back."""
        stat = self.labels()[0]
        saved = self.word(stat)
        for offset, value in enumerate(self.rom_move(self.move)):
            self.h.write8("wEnemyMoveNum", value, offset=offset)
        self.write_word(stat, stat_value)
        self.h.call_routine("AIEstimateDamage", limit=240)
        if delivery:
            self.h.call_routine("AIAdjustEnemyDamageForExpectedDelivery", limit=240)
        self.write_word(stat, saved)
        return self.word("wAIDamageEstimate")

    def tempo(self, hp: int) -> tuple[int, dict[str, int]]:
        """AISetupTempo with the player at hp: (gate byte, state read at return)."""
        h = self.h
        self.write_word("wBattleMonHP", hp)
        h.write8("wBuffer", 0, offset=self.ai["AI_BUF_BESTSLOT"])
        stat = self.labels()[0]

        def capture(hh):
            return {"gate": hh.read8("wBuffer", self.ai["AI_BUF_SETUPGATE"]),
                    "stat": self.word(stat),
                    "cache0": self.word("wAIEnemyEstimateCache"),
                    "cycles": hh.cycle_count()}

        start = h.cycle_count()
        state = h.call_routine("AISetupTempo", limit=240, capture=capture)
        state["cycles"] -= start
        return state["gate"], state

    def model(self, hp: int, now: int, plus2: int | None, plus1: int | None) -> int:
        """ai_setup_gate.asm's bits from the three deliveries (None: no gain)."""
        n = hits(hp, now)
        def free(d):
            return d is not None and hits(hp, d) + 1 <= n
        if not free(plus2):
            return 0
        bits = self.mask("AI_SG_ATK2_FREE_BIT", "AI_SG_SPC2_FREE_BIT")
        if free(plus1):
            bits |= self.mask("AI_SG_ATK1_FREE_BIT", "AI_SG_SPC1_FREE_BIT")
        return bits & self.ai_category_mask()

    def deliveries(self, stage: int, burned: bool = False) -> tuple[int, int | None, int | None]:
        """(now, after +2, after +1) for the board's stage, through the estimator."""
        unmod = self.word(self.labels()[1])
        burn = burned and self.physical()
        now = self.estimate_with(stat_at(unmod, stage, burn))
        after = []
        for boost in (2, 1):
            target = min(stage + boost, 13)
            after.append(None if target == stage else self.estimate_with(stat_at(unmod, target, burn)))
        return now, after[0], after[1]

    def sweep(self, stage: int, unmodified: int | None = None, burned: bool = False,
              expect_exact: bool = True) -> dict[str, int]:
        """HP from 1 to past 9 hits: the gate byte must equal the model (the
        exact one where the asm projects, the old x2 / x1.5 one where it keeps
        the multiply), and the stat and the slot cache must be as found. Returns
        how often the other model would have disagreed, and the worst cycles."""
        exact = self.h.hook_flag("AISetupHitsAtBoost")
        stored = self.set_stage(stage, unmodified, burned)
        self.write_word("wBattleMonHP", 999)
        raw = self.estimate_with(stored, delivery=False)
        self.assertGreater(raw, 0)
        valid = 1 << self.ai["AI_ESTIMATE_VALID_BIT"]
        stats = {"checked": 0, "other_differs": 0, "cycles": 0}
        top = min(raw * (MAX_HITS + 2), 999)
        for hp in sorted(set(list(range(1, top, max(1, raw // 7))) + [raw, 2 * raw, 3 * raw])):
            self.write_word("wBattleMonHP", hp)
            now, plus2, plus1 = self.deliveries(stage, burned)
            before = exact["count"]
            gate, state = self.tempo(hp)
            projected = self.model(hp, now, plus2, plus1)
            multiplied = self.model(hp, now, 2 * now, now + now // 2)
            want, other = (projected, multiplied) if expect_exact else (multiplied, projected)
            label = dict(hp=hp, stage=stage - NEUTRAL, now=now, plus2=plus2, plus1=plus1, gate=gate)
            self.assertEqual(gate & 0x0F, want, label)
            self.assertEqual(state["stat"], stored, label)
            self.assertEqual(state["cache0"], raw | (valid << 8), label)  # the real stat's answer
            self.assertEqual(exact["count"] > before, expect_exact, label)
            stats["checked"] += 1
            stats["other_differs"] += want != other
            stats["cycles"] = max(stats["cycles"], state["cycles"])
        print(f"\n{self.move} stage {stage - NEUTRAL:+d} unmod={self.word(self.labels()[1])} "
              f"burned={burned} raw={raw} checked={stats['checked']} "
              f"x2/x1.5 differs={stats['other_differs']} max_cycles={stats['cycles']}")
        return stats

    # --- fixtures --------------------------------------------------------------
    def test_neutral_stage_keeps_the_free_multiply(self) -> None:
        self.boot(["BODY_SLAM", "SWORDS_DANCE"])
        stats = self.sweep(NEUTRAL, expect_exact=False)
        # The asm's neutral path IS the old model; sweep compared against the
        # exact one, so a disagreement there is the old approximation itself.
        self.assertGreater(stats["checked"], 20)

    def test_from_plus_two_another_plus_two_is_x1_5(self) -> None:
        self.boot(["BODY_SLAM", "SWORDS_DANCE"])
        stats = self.sweep(NEUTRAL + 2)
        self.assertGreater(stats["other_differs"], 0, "x2 from +2 must have overstated the boost somewhere")

    def test_at_plus_six_nothing_is_free(self) -> None:
        self.boot(["BODY_SLAM", "SWORDS_DANCE"])
        stats = self.sweep(13)
        self.assertGreater(stats["other_differs"], 0)

    def test_at_plus_five_plus_two_caps_to_plus_one(self) -> None:
        self.boot(["BODY_SLAM", "SWORDS_DANCE"])
        self.sweep(12)

    def test_after_a_drop(self) -> None:
        self.boot(["BODY_SLAM", "SWORDS_DANCE"])
        for stage in (NEUTRAL - 1, NEUTRAL - 2, 1):
            with self.subTest(stage=stage):
                self.sweep(stage)

    def test_a_stat_of_500_or_more_projects_into_the_cap(self) -> None:
        self.boot(["BODY_SLAM", "SWORDS_DANCE"])
        self.sweep(NEUTRAL, unmodified=600)
        self.sweep(NEUTRAL, unmodified=499, expect_exact=False)

    def test_special_category(self) -> None:
        self.boot(["PSYCHIC_M", "AMNESIA"], enemy="ALAKAZAM")
        self.assertFalse(self.physical())
        self.sweep(NEUTRAL + 2)
        self.sweep(NEUTRAL - 1)

    def test_burned_attack_is_halved_after_the_boost(self) -> None:
        self.boot(["BODY_SLAM", "SWORDS_DANCE"])
        self.sweep(NEUTRAL + 2, burned=True)

    def test_multi_hit_counts_its_delivery(self) -> None:
        self.boot(["DOUBLE_KICK", "SWORDS_DANCE"])
        self.sweep(NEUTRAL + 2)

    def test_fixed_damage_is_never_free(self) -> None:
        self.boot(["SEISMIC_TOSS", "SWORDS_DANCE"])
        exact = self.h.hook_flag("AISetupHitsAtBoost")
        self.set_stage(NEUTRAL + 2)
        for hp in (10, 60, 120):
            gate, _ = self.tempo(hp)
            self.assertEqual(gate, 0)
        self.assertEqual(exact["count"], 0)


if __name__ == "__main__":
    unittest.main()
