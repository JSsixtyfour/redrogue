"""The run-start hook must not change which starter slot the player took.

OaksLabRivalPicksAndWalks enters with e = the slot taken (1-3), starts the run
timer and then farcalls RivalPickStarter, which reads e. RunTimerStart ends in
RunChallengesStartRun, whose difficulty check loads heat + 1 into e. Without a
save around that call the slot became 1 on NORMAL / EASY / VERY EASY, 2 on HARD
and 3 on VERY HARD: wPlayerStarter recorded the wrong species and the rival
could pick the ball the player had just taken. RunTimerStart now preserves de.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
DIFFICULTY_MASK = 0x07


class OaksLabStarterSlotTest(unittest.TestCase):
    def test_every_slot_survives_the_run_start_hook(self) -> None:
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        ram = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")
        starters = [species["BULBASAUR"], species["CHARMANDER"], species["SQUIRTLE"]]
        h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        try:
            h.boot_to_lobby()
            seen = {}
            h.hook_flag("RivalPickStarter",
                        lambda: seen.update(e=h.pyboy.register_file.E))
            for difficulty in ("DIFFICULTY_NORMAL", "DIFFICULTY_HARD",
                               "DIFFICULTY_VERY_HARD"):
                for slot in (1, 2, 3):
                    with self.subTest(difficulty=difficulty, slot=slot):
                        h.park_before_hijack()
                        for index, mon in enumerate(starters):
                            h.write8("wRoguePokemon1", mon, offset=index)
                            h.write8("wRoguePokemonForm1", 0, offset=index)
                        options = h.read8("wOptions2") & ~DIFFICULTY_MASK
                        h.write8("wOptions2", options | ram[difficulty])
                        seen.clear()
                        h.pyboy.register_file.E = slot
                        result = h.call_routine(
                            "OaksLabRivalPicksAndWalks",
                            capture=lambda x: (x.read8("wPlayerStarter"),
                                               x.read8("wRivalStarterBallSpriteIndex"),
                                               x.read8("wRivalStarter")))
                        player, rival_ball, rival = result
                        self.assertEqual(seen.get("e"), slot,
                                         "RivalPickStarter must receive the taken slot")
                        self.assertEqual(player, starters[slot - 1],
                                         "wPlayerStarter is the taken ball's species")
                        self.assertNotEqual(rival_ball, slot,
                                            "the rival never picks the player's ball")
                        self.assertEqual(rival, starters[rival_ball - 1])
        finally:
            h.close()


if __name__ == "__main__":
    unittest.main()
