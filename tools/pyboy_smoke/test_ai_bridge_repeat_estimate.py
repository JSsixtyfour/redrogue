"""AI_BACKLOG L4: the player-side damage estimate predicts Bridge Repeat from
the player's move history, not from the current-action state.

BridgeApplyRepeatDamageBoost (x1.15) reads wBridgeRepeatState, which is 0 at
move selection and whatever the player's last move left afterwards. The
estimator used to inherit it, so move selection never counted the boost and a
later decision counted it for every move. _AIEstimateForTurn now stages 2 only
for the move that repeats wWitchPrevPlayerMove from the same party slot, the
same test BridgePrepareRepeatAction applies, and restores the live state.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
REPEAT_BIT = 1 << 6  # BRIDGE_EFFECT_REPEAT = 6: byte 0, bit 6


class AIBridgeRepeatEstimateTest(unittest.TestCase):
    def setUp(self):
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        self.moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")

        def mon(name, moves):
            return {"species": species[name], "level": 50, "moves": [self.moves[m] for m in moves]}

        self.h.inject_fight2_spec([mon("SNORLAX", ["TACKLE", "BODY_SLAM"])],
                                  [mon("TAUROS", ["TACKLE"])],
                                  trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
        self.h.boot_fight2(seed=1)

    def tearDown(self):
        self.h.close()

    def estimate(self, name, owned, prev=None, live_state=0):
        h = self.h
        h.park_before_hijack()
        effects = h.address("wBridgeGlobalEffects")
        mem = h.pyboy.memory
        mem[effects] = (mem[effects] | REPEAT_BIT) if owned else (mem[effects] & ~REPEAT_BIT & 0xFF)
        h.write8("wWitchPrevPlayerMove", self.moves[prev] if prev else 0)
        h.write8("wWitchPrevPlayerSlot", h.read8("wPlayerMonNumber"))
        h.write8("wBridgeRepeatState", live_state)
        bank, address = h.symbols.get("Moves")
        offset = bank * 0x4000 + address - 0x4000 + (self.moves[name] - 1) * 6
        data = (ROOT / "pokeblue_debug.gbc").read_bytes()[offset:offset + 6]
        for index, value in enumerate(data):
            h.write8("wPlayerMoveNum", value, offset=index)
        h.call_routine("AIEstimatePlayerDamage", limit=120)
        self.assertEqual(h.read8("wBridgeRepeatState"), live_state, "live state restored")
        return int.from_bytes(bytes(h.read_bytes("wAIDamageEstimate", 2)), "big")

    def test_only_the_repeated_move_gets_the_boost(self):
        base = self.estimate("TACKLE", owned=False, prev="TACKLE")
        repeated = self.estimate("TACKLE", owned=True, prev="TACKLE")
        other_base = self.estimate("BODY_SLAM", owned=False, prev="TACKLE")
        other = self.estimate("BODY_SLAM", owned=True, prev="TACKLE")
        print(f"\nL4 Tackle {base} -> {repeated}; Body Slam {other_base} -> {other}")
        self.assertEqual(repeated, base * 115 // 100)
        self.assertEqual(other, other_base)

    def test_live_state_no_longer_leaks_into_the_estimate(self):
        # State 2 left by the player's last action, but the estimated move is
        # not a repeat: no boost. And state 0 (move selection) with a real
        # repeat in the history: boost.
        plain = self.estimate("BODY_SLAM", owned=False, prev="TACKLE")
        self.assertEqual(self.estimate("BODY_SLAM", owned=True, prev="TACKLE", live_state=2), plain)
        base = self.estimate("TACKLE", owned=False, prev="TACKLE")
        self.assertEqual(self.estimate("TACKLE", owned=True, prev="TACKLE", live_state=0),
                         base * 115 // 100)

    def test_a_different_party_slot_is_not_a_repeat(self):
        base = self.estimate("TACKLE", owned=False, prev="TACKLE")
        self.h.park_before_hijack()
        self.h.write8("wPlayerMonNumber", 1)  # prev slot is written per estimate
        effects = self.h.address("wBridgeGlobalEffects")
        self.h.pyboy.memory[effects] |= REPEAT_BIT
        self.h.write8("wWitchPrevPlayerMove", self.moves["TACKLE"])
        self.h.write8("wWitchPrevPlayerSlot", 0)
        bank, address = self.h.symbols.get("Moves")
        offset = bank * 0x4000 + address - 0x4000 + (self.moves["TACKLE"] - 1) * 6
        data = (ROOT / "pokeblue_debug.gbc").read_bytes()[offset:offset + 6]
        for index, value in enumerate(data):
            self.h.write8("wPlayerMoveNum", value, offset=index)
        self.h.call_routine("AIEstimatePlayerDamage", limit=120)
        self.assertEqual(int.from_bytes(bytes(self.h.read_bytes("wAIDamageEstimate", 2)), "big"), base)


if __name__ == "__main__":
    unittest.main(verbosity=2)
