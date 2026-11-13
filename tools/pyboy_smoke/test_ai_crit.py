"""AI review CP2 (2026-11-12): crit-certain moves are estimated as crits.

engine/battle/ai/ai_crit.asm. A damaging move whose CalcCritRate threshold is at
least AI_CRIT_CERTAIN ($C0) goes through the engine's own crit path: unmodified
stats on both sides (stages and screens ignored), doubled level. Plan:
AI_REVIEW_PLAN_2026-11-12.md.
"""

from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

MOVE_LENGTH = 6
NEUTRAL_STAGE = 7


class CritCertainEstimateTest(unittest.TestCase):
    harness: RedRogueHarness | None = None

    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.species = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
        self.moves = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
        self.trainers = parse_trainer_constants(REPO_ROOT / "constants" / "trainer_constants.asm")
        self.rom = (REPO_ROOT / "pokeblue_debug.gbc").read_bytes()

    def tearDown(self) -> None:
        if self.harness is not None:
            self.harness.close()

    def mon(self, species: str, moves: list[str], level: int = 50) -> dict[str, object]:
        return {"species": self.species[species], "level": level,
                "moves": [self.moves[name] for name in moves]}

    def boot(self, player: dict[str, object], enemy: list[dict[str, object]]) -> RedRogueHarness:
        h = self.harness
        assert h is not None
        h.inject_fight2_spec([player], enemy, trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=3)
        h.boot_fight2(seed=1)
        return h

    def word(self, label: str) -> int:
        assert self.harness is not None
        return int.from_bytes(bytes(self.harness.read_bytes(label, 2)), "big")

    def write_word(self, label: str, value: int) -> None:
        assert self.harness is not None
        self.harness.write8(label, value >> 8)
        self.harness.write8(label, value & 0xFF, offset=1)

    def load_player_move(self, move: str) -> None:
        """The move's 6-byte record from the ROM's Moves table into wPlayerMove*."""
        h = self.harness
        assert h is not None
        bank, address = h.symbols.get("Moves")
        start = bank * 0x4000 + address - 0x4000 + (self.moves[move] - 1) * MOVE_LENGTH
        for offset, value in enumerate(self.rom[start:start + MOVE_LENGTH]):
            h.write8("wPlayerMoveNum", value, offset=offset)

    def estimate(self, move: str, routine: str = "AIEstimatePlayerMoveDamage") -> tuple[int, bool]:
        """(the estimate, whether the crit path ran) for the player's `move`."""
        h = self.harness
        assert h is not None
        self.load_player_move(move)
        crit = h.hook_flag("AIEstimatePlayerDamageCrit")
        before = crit["count"]
        h.call_routine(routine)
        return self.word("wAIDamageEstimate"), crit["count"] > before

    def set_enemy_defense_stage(self, stage: int) -> None:
        """Defense stage +stage on the enemy, with the stat scaled the engine's way
        for +2 (x2): enough for the ordinary path to see it."""
        h = self.harness
        assert h is not None
        h.write8("wEnemyMonDefenseMod", NEUTRAL_STAGE + stage)
        self.write_word("wEnemyMonDefense", self.word("wEnemyMonUnmodifiedDefense") * (2 if stage == 2 else 1))

    def test_slash_from_a_fast_mon_is_estimated_as_a_crit_that_ignores_defense_stages(self) -> None:
        self.boot(self.mon("PERSIAN", ["SLASH", "STRENGTH"]), [self.mon("SNORLAX", ["TACKLE"])])
        plain, _ = self.estimate("SLASH", routine="AIEstimatePlayerDamage")  # the old, non-crit number
        crit, ran = self.estimate("SLASH")
        self.assertTrue(ran, "Persian's Slash (base Speed 115) must take the crit path")
        self.assertGreaterEqual(crit * 10, plain * 17, (plain, crit))  # a crit is ~1.8-2x here
        self.set_enemy_defense_stage(2)
        boosted, ran = self.estimate("SLASH")
        self.assertTrue(ran)
        self.assertEqual(boosted, crit, "a crit ignores the defender's Defense stage")

    def test_an_ordinary_move_is_unchanged_and_still_sees_the_stage(self) -> None:
        self.boot(self.mon("PERSIAN", ["SLASH", "STRENGTH"]), [self.mon("SNORLAX", ["TACKLE"])])
        old, _ = self.estimate("STRENGTH", routine="AIEstimatePlayerDamage")
        new, ran = self.estimate("STRENGTH")
        self.assertFalse(ran, "Strength's crit chance is ~22%: not crit-certain")
        self.assertEqual(new, old)
        self.set_enemy_defense_stage(2)
        boosted, _ = self.estimate("STRENGTH")
        self.assertLess(boosted, new)

    def test_crit_estimate_puts_back_what_the_crit_path_clobbers(self) -> None:
        h = self.boot(self.mon("PERSIAN", ["SLASH"]), [self.mon("SNORLAX", ["TACKLE"])])
        sentinels = {"wCurSpecies": 0x5A, "wCurEnemyLevel": 0x3C,
                     "wFormContextSpecies": 0x21, "wFormContextForm": 0x02}
        for label, value in sentinels.items():
            h.write8(label, value)
        _, ran = self.estimate("SLASH")
        self.assertTrue(ran)
        for label, value in sentinels.items():
            self.assertEqual(h.read8(label), value, label)


if __name__ == "__main__":
    unittest.main()
