"""Body Armor (a bridge gift) refuses moves without base power. Found by the
autoplay soak test (2026-10-20): when every move the holder could select was
one it refuses, the move menu accepted nothing and Struggle never came, so a
last Pokemon with only status moves left could not go on. It now Struggles."""
from pathlib import Path
import unittest

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT

MOVES = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
BODY_ARMOR = parse_rgbds_constants(
    REPO_ROOT / "constants/pokemon_data_constants.asm")["BRIDGE_SELECTED_EFFECT_BODY_ARMOR"]
PARTYMON_STRUCT_LENGTH = 0x2C


class BodyArmorTest(HarnessTestCase):
    def _battle(self, moves):
        """FIGHT 2 with the active mon wearing Body Armor and knowing `moves`
        (full PP), the rest of the party fainted so it cannot switch out."""
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        # The enemy FIGHT 2 rolls follows VBlank-time RNG, so its moves drift with engine
        # timing (an Arbok's Wrap left the player unable to select anything). Pin it to
        # Splash: this test is about the player's menu, not the enemy's choice.
        for i in range(4):
            h.write8("wEnemyMonMoves", MOVES["SPLASH"] if i == 0 else 0, offset=i)
            h.write8("wEnemyMonPP", 30 if i == 0 else 0, offset=i)
        h.write8("wEnemySelectedMove", MOVES["SPLASH"])  # the AI picks before the menu opens
        slot = h.read8("wPlayerMonNumber")
        h.write8("wBridgeSelectedEffectOwner1", slot + 1)
        h.write8("wBridgeSelectedEffect1", BODY_ARMOR)
        for i in range(4):
            move = MOVES[moves[i]] if i < len(moves) else 0
            pp = 30 if move else 0
            h.write8("wBattleMonMoves", move, offset=i)
            h.write8("wBattleMonPP", pp, offset=i)
            h.write8("wPartyMon1Moves", move, offset=slot * PARTYMON_STRUCT_LENGTH + i)
            h.write8("wPartyMon1PP", pp, offset=slot * PARTYMON_STRUCT_LENGTH + i)
        for other in range(h.read8("wPartyCount")):
            if other != slot:
                h.write8("wPartyMon1HP", 0, offset=other * PARTYMON_STRUCT_LENGTH)
                h.write8("wPartyMon1HP", 0, offset=other * PARTYMON_STRUCT_LENGTH + 1)
        used = []
        h.register_hook("ExecutePlayerMove", lambda _c: used.append(h.read8("wPlayerSelectedMove")))
        refusals = h.hook_flag("BridgeBodyArmorBlocksSelectedMove")
        return used, refusals

    def _press_fight_on_first_move(self, rounds=3):
        h = self.harness
        assert h is not None
        for _ in range(rounds):
            h.tap("a", 3)   # FIGHT
            h.tick(40)
            h.tap("a", 3)   # the first move
            h.tick(240)
            for _ in range(10):
                h.tap("a", 3)
                h.tick(20)

    def test_only_refused_moves_left_means_struggle(self):
        used, _ = self._battle(["GROWL", "LEER"])
        self._press_fight_on_first_move()
        self.assertTrue(used, "no player move ever ran: the battle is stuck")
        self.assertEqual(set(used), {MOVES["STRUGGLE"]})

    def test_a_refused_move_is_still_refused_while_another_works(self):
        used, refusals = self._battle(["GROWL", "TACKLE"])
        self._press_fight_on_first_move(rounds=1)
        self.assertGreaterEqual(refusals["count"], 1)
        self.assertNotIn(MOVES["STRUGGLE"], used)
        self.assertNotIn(MOVES["GROWL"], used)


if __name__ == "__main__":
    unittest.main()
