"""The party menu must not write on the enemy's Bide tally.

wEnemyBideAccumulatedDamage used to share $cc98 with the fifth mon's entry in
wMonPartySpritesSavedOAM. With 5+ mons, switching while the enemy stored energy put OAM bytes
(20496) in the tally, and Bide unleashed 40992 damage without ever being hit. The party of 2
is the control: it never reached that entry.
"""
from __future__ import annotations

import unittest
from pathlib import Path

import fight2_driver
import run_ai_benchmark as rab
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
STORING_ENERGY = 1 << 0


class BidePartyMenuTest(unittest.TestCase):
    def play(self, party_size: int, *, hit_on_turn_three: bool = False) -> dict:
        """T1 hit, then the enemy uses Bide; T2 switch; T3 Bide unleashes."""
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        # The reserves are slower than the Bide user, so it unleashes before they act; when
        # the turn-3 hit is wanted they are faster.
        reserve = "JOLTEON" if hit_on_turn_three else "SNORLAX"
        h.inject_fight2_spec(
            [{"species": species["JOLTEON"], "level": 50, "moves": [moves["SWIFT"]]}]
            + [{"species": species[reserve], "level": 50, "moves": [moves["SWIFT"]]}]
            * (party_size - 1),
            [{"species": species["TAUROS"], "level": 50, "moves": [moves["BIDE"]]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=0)
        driver = fight2_driver.Fight2Driver(
            h, tier=0, player_policy="random",
            move_powers=rab.parse_move_powers(ROOT / "data/moves/moves.asm"))
        driver.move_override = 0
        seen = {"turn": 0, "switched": False, "tally_t2": None, "tally_t3": None,
                "unleashed": None, "hits": [], "done": False}

        def word(label: str) -> int:
            high, low = h.read_bytes(label, 2)
            return high << 8 | low

        def menu(_context) -> None:
            seen["turn"] += 1
            driver.switch_override = 1 if seen["turn"] == 2 else None
            seen["done"] = seen["turn"] >= 4

        def enemy_turn(_context) -> None:
            if seen["turn"] in (2, 3):
                seen["switched"] = h.read8("wPlayerMonNumber") == 1
                seen[f"biding_t{seen['turn']}"] = bool(
                    h.read8("wEnemyBattleStatus1") & STORING_ENERGY)
                seen[f"tally_t{seen['turn']}"] = word("wEnemyBideAccumulatedDamage")
            if seen["turn"] == 2:
                h.write8("wEnemyNumAttacksLeft", 2)  # unleash on turn 3, not 4

        def unleash(_context) -> None:
            seen["unleashed"] = word("wEnemyBideAccumulatedDamage")

        def player_hit(_context) -> None:
            seen["hits"].append((seen["turn"], word("wDamage")))

        h.register_hook("AIPlanEnemyTurn", menu)
        h.register_hook("ExecuteEnemyMove", enemy_turn)
        h.register_hook("CheckEnemyStatusConditions.unleashEnergy", unleash)
        h.register_hook("ApplyAttackToEnemyPokemon", player_hit)
        driver.boot(1)
        driver.play(1200, stop=lambda: seen["done"])
        self.assertTrue(seen["switched"], f"the switch never happened: {seen}")
        self.assertTrue(seen["biding_t2"] and seen["biding_t3"], f"Bide was not up: {seen}")
        self.assertIsNotNone(seen["unleashed"], f"Bide never unleashed: {seen}")
        return seen

    def test_switching_leaves_an_unhit_tally_at_zero(self) -> None:
        for party_size in (2, 5, 6):
            with self.subTest(party_size=party_size):
                seen = self.play(party_size)
                self.assertEqual((seen["tally_t2"], seen["tally_t3"], seen["unleashed"]),
                                 (0, 0, 0), seen)

    def test_a_real_hit_after_the_switch_still_counts(self) -> None:
        seen = self.play(6, hit_on_turn_three=True)
        damage = dict(seen["hits"]).get(3)
        self.assertTrue(damage, f"the turn 3 hit never landed: {seen}")
        self.assertEqual(seen["unleashed"], damage, seen)


if __name__ == "__main__":
    unittest.main()
