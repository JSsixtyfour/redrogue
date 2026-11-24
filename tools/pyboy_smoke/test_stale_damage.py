"""wDamage must not outlive the round that dealt it.

Ported from Shin Pokemon Red (EnemyBideAccum / PlayerBideAccum / ZeroLastDamage):
- Counter used to reflect last round's damage onto a mon that just switched in (34 -> 68 -> 136).
- Bide added wDamage once per turn, so one hit was counted again on a turn nobody attacked.
- Counter could reflect damage the other mon did to itself.
Trapping moves are the exception: their continuation turns deal the same wDamage again.
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
CONFUSED = 1 << 7


class StaleDamageTest(unittest.TestCase):
    def battle(self, player: list[tuple[str, str]], enemy: tuple[str, str], *, turns: int,
               switch_turn: int | None = None, on_enemy=None, on_player=None) -> dict:
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

        def mon(name_move):
            return {"species": species[name_move[0]], "level": 50, "moves": [moves[name_move[1]]]}

        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.inject_fight2_spec([mon(m) for m in player], [mon(enemy)],
                             trainer_class=trainers["COOLTRAINER_M"], ai_tier=0)
        driver = fight2_driver.Fight2Driver(
            h, tier=0, player_policy="random",
            move_powers=rab.parse_move_powers(ROOT / "data/moves/moves.asm"))
        driver.move_override = 0
        seen = {"turn": 0, "done": False, "player_hits": [], "enemy_hits": [], "unleash": [],
                "enemy_acts": [], "self_hits": 0, "trap_turns": set(),
                "crashes": [], "counter_damage": []}

        def word(label: str) -> int:
            high, low = h.read_bytes(label, 2)
            return high << 8 | low

        def menu(_context) -> None:
            seen["turn"] += 1
            driver.switch_override = 1 if seen["turn"] == switch_turn else None
            seen["done"] = seen["turn"] > turns

        def enemy_turn(_context) -> None:
            seen["enemy_acts"].append(
                (seen["turn"], h.read8("wPlayerMonNumber"), word("wDamage")))
            if on_enemy is not None:
                on_enemy(h, seen["turn"])

        def player_turn(_context) -> None:
            if h.read8("wPlayerBattleStatus1") & USING_TRAPPING_MOVE:
                seen["trap_turns"].add(seen["turn"])
            if on_player is not None:
                on_player(h, seen["turn"])

        def self_hit(_context) -> None:
            seen["self_hits"] += 1

        def crash(_context) -> None:
            seen["crashes"].append((seen["turn"], h.read8("hWhoseTurn")))

        def counter(_context) -> None:
            seen["counter_damage"].append(
                (seen["turn"], h.read8("hWhoseTurn"), word("wDamage")))

        h.register_hook("PrintMoveFailureText.applyRecoil", crash)
        h.register_hook("HandleCounterMove", counter)
        h.register_hook("AIPlanEnemyTurn", menu)
        h.register_hook("ExecuteEnemyMove", enemy_turn)
        h.register_hook("ExecutePlayerMove", player_turn)
        h.register_hook("HandleSelfConfusionDamage", self_hit)
        h.register_hook("ApplyAttackToEnemyPokemon", lambda _c: seen["player_hits"].append(
            (seen["turn"], word("wDamage"))))
        h.register_hook("ApplyAttackToPlayerPokemon", lambda _c: seen["enemy_hits"].append(
            (seen["turn"], word("wDamage"))))
        h.register_hook("CheckEnemyStatusConditions.unleashEnergy", lambda _c: seen[
            "unleash"].append(("enemy", word("wEnemyBideAccumulatedDamage"))))
        h.register_hook("CheckPlayerStatusConditions.UnleashEnergy", lambda _c: seen[
            "unleash"].append(("player", word("wPlayerBideAccumulatedDamage"))))
        driver.boot(1)
        driver.play(1600, stop=lambda: seen["done"])
        self.assertEqual(h.hook_errors, [])
        self.assertTrue(seen["done"], f"the battle never reached turn {turns + 1}: {seen}")
        return seen

    @staticmethod
    def two_turn_bide(label: str):
        def act(h, turn) -> None:
            if turn == 2:
                h.write8(label, 2)  # unleash on turn 3, not 4
        return act

    def test_counter_does_not_reach_back_over_a_switch(self) -> None:
        seen = self.battle([("JOLTEON", "SWIFT"), ("SNORLAX", "SWIFT")], ("TAUROS", "COUNTER"),
                           turns=2, switch_turn=2)
        self.assertEqual(seen["enemy_acts"][1][:2], (2, 1), f"no switch on turn 2: {seen}")
        self.assertEqual([hit for hit in seen["enemy_hits"] if hit[0] == 2], [], seen)
        # Control: Counter answered the real turn 1 hit, doubled.
        self.assertEqual(seen["enemy_hits"][0], (1, seen["player_hits"][0][1] * 2), seen)

    def test_enemy_bide_counts_a_hit_once(self) -> None:
        # Snorlax is slower: turn 1 is Bide, then the hit. Switch on turn 2, unleash on turn 3.
        seen = self.battle([("SNORLAX", "SWIFT"), ("SNORLAX", "SWIFT")], ("TAUROS", "BIDE"),
                           turns=3, switch_turn=2,
                           on_enemy=self.two_turn_bide("wEnemyNumAttacksLeft"))
        self.assertEqual(seen["unleash"], [("enemy", seen["player_hits"][0][1])], seen)
        self.assertEqual(seen["enemy_hits"][0][1], seen["player_hits"][0][1] * 2, seen)

    def test_enemy_bide_counts_every_hit_of_a_multi_hit_move(self) -> None:
        # Chansey is faster: its turn 1 hits land before Bide starts, turns 2 and 3 after.
        seen = self.battle([("CHANSEY", "DOUBLE_KICK")], ("SLOWBRO", "BIDE"), turns=3,
                           on_enemy=self.two_turn_bide("wEnemyNumAttacksLeft"))
        taken = [damage for turn, damage in seen["player_hits"] if turn in (2, 3)]
        self.assertEqual(len(taken), 4, f"two double hits expected: {seen}")
        self.assertEqual(seen["unleash"], [("enemy", sum(taken))], seen)

    def test_player_bide_counts_what_hit_it(self) -> None:
        seen = self.battle([("SNORLAX", "BIDE")], ("JOLTEON", "SWIFT"), turns=3,
                           on_player=self.two_turn_bide("wPlayerNumAttacksLeft"))
        # The enemy is faster: its turn 1 hit lands before Bide starts, 2 and 3 after.
        taken = [damage for turn, damage in seen["enemy_hits"] if turn in (2, 3)]
        self.assertEqual(len(taken), 2, seen)
        self.assertEqual(seen["unleash"], [("player", sum(taken))], seen)

    def test_trapping_continuation_repeats_its_damage(self) -> None:
        seen = self.battle([("JOLTEON", "WRAP")], ("SNORLAX", "SPLASH"), turns=6)
        pairs = [(a, b) for a, b in zip(seen["player_hits"], seen["player_hits"][1:])
                 if b[0] == a[0] + 1 and b[0] in seen["trap_turns"]]
        self.assertTrue(pairs, f"no Wrap continuation happened: {seen}")
        for first, second in pairs:
            self.assertGreater(first[1], 0)
            self.assertEqual(second[1], first[1], seen)

    def test_counter_cannot_reflect_self_inflicted_confusion(self) -> None:
        def confuse(h, _turn) -> None:
            h.write8("wPlayerBattleStatus1", h.read8("wPlayerBattleStatus1") | CONFUSED)
            h.write8("wPlayerConfusedCounter", 5)

        seen = self.battle([("SNORLAX", "SWIFT")], ("TAUROS", "COUNTER"), turns=5,
                           on_player=confuse)
        self.assertGreater(seen["self_hits"], 0, f"no self-hit in 5 turns: {seen}")
        hit_turns = {turn for turn, _ in seen["player_hits"]}
        for turn, _mon, damage in seen["enemy_acts"]:
            if turn not in hit_turns:
                self.assertEqual(damage, 0, seen)

    def check_crash(self, seen: dict, crasher: int) -> None:
        """crasher / counterer are hWhoseTurn values: 0 = player, 1 = enemy."""
        turns = {turn for turn, side in seen["crashes"] if side == crasher}
        self.assertTrue(turns, f"Jump Kick never crashed: {seen}")
        found = [damage for turn, side, damage in seen["counter_damage"]
                 if side == 1 - crasher and turn in turns]
        self.assertTrue(found, f"Counter never ran after a crash: {seen}")
        self.assertEqual(set(found), {0}, seen)
        hits = seen["enemy_hits" if crasher == 0 else "player_hits"]
        self.assertEqual([hit for hit in hits if hit[0] in turns], [], seen)

    def test_counter_cannot_reflect_a_player_jump_kick_crash(self) -> None:
        def miss(h, _turn) -> None:
            h.write8("wPlayerMonAccuracyMod", 1)
            h.write8("wEnemyMonEvasionMod", 13)

        seen = self.battle([("SNORLAX", "JUMP_KICK")], ("SLOWBRO", "COUNTER"), turns=3,
                           on_player=miss)
        self.check_crash(seen, 0)

    def test_counter_cannot_reflect_an_enemy_jump_kick_crash(self) -> None:
        def miss(h, _turn) -> None:
            h.write8("wEnemyMonAccuracyMod", 1)
            h.write8("wPlayerMonEvasionMod", 13)

        seen = self.battle([("SLOWBRO", "COUNTER")], ("SNORLAX", "JUMP_KICK"), turns=3,
                           on_enemy=miss)
        self.check_crash(seen, 1)

    def test_counter_does_not_reach_back_over_a_switch_out_of_wrap(self) -> None:
        def land(h, _turn) -> None:
            h.write8("wPlayerMonAccuracyMod", 13)
            h.write8("wEnemyMonEvasionMod", 1)

        seen = self.battle([("JOLTEON", "WRAP"), ("SNORLAX", "SWIFT")], ("TAUROS", "COUNTER"),
                           turns=2, switch_turn=2, on_player=land)
        self.assertEqual([turn for turn, _ in seen["player_hits"]][:1], [1],
                         f"Wrap missed: {seen}")
        self.assertEqual(seen["enemy_acts"][-1][:2], (2, 1), f"no switch on turn 2: {seen}")
        self.assertEqual([hit for hit in seen["enemy_hits"] if hit[0] == 2], [], seen)


if __name__ == "__main__":
    unittest.main()
