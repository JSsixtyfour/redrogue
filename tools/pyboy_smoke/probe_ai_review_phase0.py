"""Phase 0 measurements for the 2026-09-29 AI review (plan: codex-has-done-a-compiled-tarjan).

Probe, not a smoke test (probe_ prefix keeps it out of `make smoke`). Each case
prints its raw observation and asserts the BUGGY behaviour the review predicts,
so a failure here means that finding is WRONG and should be dropped.

  F1  FIXED in Phase 3: slower T2 trainer holding a reliable KO now STAYS (real turn)
  F2  FIXED in Phase 4: Spike Cannon needing 3+ hits now scores as unreliable
  F5  outclassed 2-mon party over 6 real turns: predicts a switch every turn
  F6  FIXED in Phase 1: another party member's reveal must not create a threat
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]


class Phase0Probe(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        self.species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")

    def tearDown(self):
        self.h.close()

    def mon(self, name, moves):
        return {"species": self.species[name], "level": 50,
                "moves": [self.moves[m] for m in moves]}

    def word(self, label, value, offset=0):
        self.h.write8(label, value >> 8, offset=offset)
        self.h.write8(label, value & 255, offset=offset + 1)

    def read_word(self, label):
        return int.from_bytes(bytes(self.h.read_bytes(label, 2)), "big")

    def drive_turns(self, stop, limit=900):
        h = self.h
        h.hook_flag("DisplayBattleMenu", action=lambda:
                    h.write8("wBattleAndStartSavedMenuItem", 0))
        for _ in range(limit):
            if stop():
                return True
            h.tap("a", 1)
            h.tick(8)
        return stop()

    # F1 -------------------------------------------------------------------
    def test_f1_slower_reliable_ko_stays_in(self):
        h = self.h
        h.inject_fight2_spec(
            [self.mon("ELECTRODE", ["TACKLE", "THUNDERBOLT"])],
            [self.mon("SLOWPOKE", ["TACKLE"]), self.mon("RATTATA", ["TACKLE"])],
            trainer_class=self.trainers["JUGGLER"], ai_tier=2)
        h.boot_fight2(seed=1)
        order = []
        def at_trainer_ai():
            order.append("TrainerAI")
            if order.count("TrainerAI") == 1:
                # Player has already moved this turn (Electrode is faster).
                # Both sides are now in finishing range of each other.
                self.word("wEnemyMonHP", 1)
                self.word("wBattleMonHP", 1)
                h.write8("wAICount", 0)
        h.hook_flag("ExecutePlayerMove", action=lambda: order.append("PlayerMove"))
        h.hook_flag("TrainerAI", action=at_trainer_ai)
        switch = h.hook_flag("AIShouldSwitch.switch")
        stay = h.hook_flag("AIShouldSwitch.stay")
        self.assertTrue(self.drive_turns(lambda: switch["count"] + stay["count"] > 0),
                        f"no switch decision reached: order={order}")
        print(f"\nF1 order={order[:4]} switch={switch['count']} stay={stay['count']}")
        self.assertEqual(order[:2], ["PlayerMove", "TrainerAI"])
        self.assertEqual((switch["count"], stay["count"]), (0, 1))

    # F2 -------------------------------------------------------------------
    def load_enemy_move(self, name):
        bank, address = self.h.symbols.get("Moves")
        offset = bank * 0x4000 + address - 0x4000 + (self.moves[name] - 1) * 6
        data = (ROOT / "pokeblue_debug.gbc").read_bytes()[offset:offset + 6]
        for index, value in enumerate(data):
            self.h.write8("wEnemyMoveNum", value, offset=index)

    def damage_score(self, player_hp):
        h = self.h
        self.word("wBattleMonHP", player_hp)
        h.write8("wEnemyMonMoves", self.moves["SPIKE_CANNON"])
        for slot in range(1, 4):
            h.write8("wEnemyMonMoves", 0, offset=slot)
        for slot in range(4):
            h.write8("wBuffer", 20, offset=slot)
        h.park_before_hijack()
        h.call_routine("AILayerDamage", limit=240)
        return h.read8("wBuffer")

    def test_f2_five_hit_maximum_scores_as_reliable_kill(self):
        h = self.h
        h.inject_fight2_spec(
            [self.mon("SNORLAX", ["SPLASH"])],
            [self.mon("TAUROS", ["SPIKE_CANNON"])],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=2)
        h.boot_fight2(seed=1)
        h.park_before_hijack()
        self.load_enemy_move("SPIKE_CANNON")
        h.call_routine("AIEstimateDamage", limit=120)
        one_hit = self.read_word("wAIDamageEstimate")
        needs_three = self.damage_score(3 * one_hit)      # 2 hits cannot kill
        out_of_reach = self.damage_score(5 * one_hit + 1)  # 5 hits cannot kill
        print(f"\nF2 one_hit={one_hit} score@3x={needs_three} score@5x+1={out_of_reach}")
        # Fixed: unreliable kill, AI_STRONG (2) + best-damage nudge (1) from 20.
        self.assertEqual(needs_three, 17)
        self.assertGreaterEqual(out_of_reach, needs_three)

    # F5 -------------------------------------------------------------------
    def test_f5_outclassed_party_switches_every_turn(self):
        h = self.h
        h.inject_fight2_spec(
            [self.mon("ELECTRODE", ["SPLASH", "THUNDERBOLT"])],
            [self.mon("SLOWPOKE", ["TACKLE"]), self.mon("RATTATA", ["TACKLE"])],
            trainer_class=self.trainers["JUGGLER"], ai_tier=2)
        h.boot_fight2(seed=1)
        turns = []
        switches = []
        def at_trainer_ai():
            # Keep whichever mon is active inside Thunderbolt's KO range, and
            # make Thunderbolt (slot 1) a known threat: fair play since Phase 2.
            self.word("wEnemyMonHP", 2)
            h.reveal_player_moves(0, [1])
            h.write8("wAICount", 0)
            turns.append(h.read8("wEnemyMonPartyPos"))
        h.hook_flag("TrainerAI", action=at_trainer_ai)
        h.hook_flag("SwitchEnemyMon", action=lambda:
                    switches.append(h.read8("wEnemyMonPartyPos")))
        self.drive_turns(lambda: len(turns) >= 7, limit=2400)
        print(f"\nF5 active-at-decision={turns[:6]} switched-from={switches}")
        self.assertGreaterEqual(len(turns), 6, f"only {len(turns)} decisions")
        switched_in_six = sum(1 for _ in switches[:6])
        self.assertGreaterEqual(switched_in_six, 5)

    # F6 -------------------------------------------------------------------
    def test_f6_stale_revealed_move_creates_phantom_threat(self):
        h = self.h
        h.inject_fight2_spec(
            [self.mon("SNORLAX", ["SPLASH"])],
            [self.mon("TAUROS", ["TACKLE"])],
            trainer_class=self.trainers["COOLTRAINER_M"], ai_tier=1)
        h.boot_fight2(seed=1)
        yes = h.hook_flag("_AIScanPlayerMovesForKO.yesKO")
        results = {}
        # Post-fix shape: party member 1 revealed slot 0; member 0 (active,
        # Splash only) revealed nothing. Must read as no threat either way.
        for label, stale in (("clean", False), ("stale", True)):
            h.park_before_hijack()
            h.reveal_player_moves(0, [0], clear=True)  # active mon showed Splash
            if stale:
                h.reveal_player_moves(1, [0])
            self.word("wEnemyMonHP", 5)
            before = yes["count"]
            h.call_routine("AIPlayerWouldKO", limit=240)
            results[label] = yes["count"] - before
        print(f"\nF6 real player moves=[SPLASH] phantom-KO hits={results}")
        self.assertEqual(results, {"clean": 0, "stale": 0})


if __name__ == "__main__":
    unittest.main(verbosity=2)
