"""FOLLOWUPS #105 and #106, both as in Shin Pokemon Red.

#105: TrappingEffect asked whether the ENEMY's move affects the PLAYER on both sides' turns, so a
player's Wrap held a Ghost it could not damage, and never held a target whose own move did nothing
to the player.
#106: a trainer's burned or paralyzed mon came back in at full Attack or Speed. Rest then undid a
drop that was never applied, so a paralyzed mon ended at four times its Speed.
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
USING_TRAPPING_MOVE = 1 << 5
BRN = 1 << 4
PAR = 1 << 6
STATS = ("Attack", "Defense", "Speed", "Special")


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)

    def mon(self, species: str, move: str) -> dict:
        return {"species": self.species[species], "level": 50, "moves": [self.moves[move]]}

    def inject(self, player: list, enemy: list) -> None:
        self.h.inject_fight2_spec([self.mon(*m) for m in player], [self.mon(*m) for m in enemy],
                                  trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=0)

    def word(self, label: str) -> int:
        high, low = self.h.read_bytes(label, 2)
        return high << 8 | low


class PlayerTrapMatchupTest(Base):
    def trapped(self, player: tuple[str, str], enemy: tuple[str, str], turns: int = 4) -> bool:
        """Does the player's move ever take hold, over real turns?"""
        h = self.h
        self.inject([player], [enemy])
        driver = fight2_driver.Fight2Driver(
            h, tier=0, player_policy="random",
            move_powers=rab.parse_move_powers(ROOT / "data/moves/moves.asm"))
        driver.move_override = 0
        seen = {"turn": 0, "held": 0, "effects": 0}

        def menu(_context) -> None:
            seen["turn"] += 1

        def effect(_context) -> None:
            seen["effects"] += h.read8("hWhoseTurn") == 0

        def held(_context) -> None:
            seen["held"] += h.read8("hWhoseTurn") == 0

        h.register_hook("AIPlanEnemyTurn", menu)
        h.register_hook("TrappingEffect", effect)
        # Reached only once USING_TRAPPING_MOVE has been set.
        h.register_hook("TrappingEffect.setTrappingCounter", held)
        driver.boot(1)
        driver.play(1600, stop=lambda: seen["turn"] > turns)
        self.assertEqual(h.hook_errors, [])
        self.assertGreater(seen["effects"], 0, f"Wrap was never used: {seen}")
        return seen["held"] > 0

    def test_control_wrap_holds_an_ordinary_target(self) -> None:
        self.assertTrue(self.trapped(("DRAGONITE", "WRAP"), ("SNORLAX", "SPLASH")))

    def test_wrap_does_not_hold_a_ghost(self) -> None:
        self.assertFalse(self.trapped(("DRAGONITE", "WRAP"), ("GENGAR", "SPLASH")))

    def test_the_targets_own_move_does_not_matter(self) -> None:
        # Ground does nothing to a Flying type; the old check read that instead of Wrap.
        self.assertTrue(self.trapped(("DRAGONITE", "WRAP"), ("SNORLAX", "EARTHQUAKE")))

    def test_the_enemys_trap_keeps_its_own_check(self) -> None:
        h = self.h
        self.inject([("GENGAR", "SPLASH")], [("DRAGONITE", "WRAP")])
        h.boot_fight2(seed=1)
        types = parse_rgbds_constants(ROOT / "constants/type_constants.asm")
        for defender, other, expected in (("GHOST", "NORMAL", False), ("NORMAL", "GHOST", True)):
            h.write8("hWhoseTurn", 1)
            h.write8("wEnemyBattleStatus1", 0)
            h.write8("wEnemyMoveType", types["NORMAL"])
            h.write8("wPlayerMoveType", types["NORMAL"])
            # The other side's matchup is the opposite, so reading it flips the answer.
            for slot in ("1", "2"):
                h.write8("wBattleMonType" + slot, types[defender])
                h.write8("wEnemyMonType" + slot, types[other])
            h.call_routine("TrappingEffect")
            held = bool(h.read8("wEnemyBattleStatus1") & USING_TRAPPING_MOVE)
            self.assertEqual(held, expected, defender)


class SendOutStatusTest(Base):
    def load(self, status: int) -> dict[str, int]:
        """Run the real loader on the trainer's mon, carrying `status` in its party slot."""
        h = self.h
        self.inject([("STARMIE", "SPLASH")], [("SNORLAX", "SPLASH")])
        h.boot_fight2(seed=1)
        h.write8("wEnemyMon1Status", status)
        h.write8("hWhichPokemon", 0)
        h.write8("wEnemyMonSpecies2", self.species["SNORLAX"])
        h.write8("wCurEnemyLevel", 50)
        h.write8("hWhoseTurn", 1)

        def capture(_h) -> dict[str, int]:
            got = {"turn": h.read8("hWhoseTurn"), "status": h.read8("wEnemyMonStatus")}
            for stat in STATS:
                got[stat] = self.word("wEnemyMon" + stat)
                got["full" + stat] = self.word("wEnemyMonUnmodified" + stat)
            return got

        got = h.call_routine("LoadEnemyMonData", capture=capture)
        self.assertEqual(got["status"], status)
        return got

    def check(self, got: dict[str, int], **expected: int) -> None:
        for stat in STATS:
            self.assertGreater(got["full" + stat], 4, got)
            self.assertEqual(got[stat], got["full" + stat] // expected.get(stat, 1), (stat, got))
        self.assertEqual(got["turn"], 1, "the send-out must not move hWhoseTurn")

    def test_burned_mon_comes_in_with_half_attack(self) -> None:
        self.check(self.load(BRN), Attack=2)

    def test_paralyzed_mon_comes_in_with_a_quarter_speed(self) -> None:
        self.check(self.load(PAR), Speed=4)

    def test_control_healthy_mon_is_untouched(self) -> None:
        self.check(self.load(0))

    def test_rest_gives_back_the_real_stat_and_no_more(self) -> None:
        for status, stat in ((BRN, "Attack"), (PAR, "Speed")):
            with self.subTest(stat=stat):
                self.h.close()
                self.h = RedRogueHarness(ROOT, ARTIFACTS)
                self.addCleanup(self.h.close)
                full = self.load(status)["full" + stat]
                # The undo Rest runs (move_effects/heal.asm) on the mon just sent out.
                self.h.write8("wEnemyMonStatus", status)
                self.h.call_routine("UndoBurnParStatsForEnemy")
                after = self.word("wEnemyMon" + stat)
                self.assertTrue(full - 3 <= after <= full, (stat, full, after))


if __name__ == "__main__":
    unittest.main()
