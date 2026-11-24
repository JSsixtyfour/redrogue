"""The battle detectors must cover every Moves lookup, stay quiet on a sound battle, and
report each bug class they were written for when it is put back by hand."""
from __future__ import annotations

import unittest
from pathlib import Path

import autoplay_battle_checks
import fight2_driver
import run_ai_benchmark as rab
from autoplay_checks import GameChecks
from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"


class Agent:
    """What GameChecks needs from the autoplay agent."""

    def __init__(self, h):
        self.h = h
        self.species_names = {}

    def map_name(self, map_id):
        return str(map_id)

    def event(self, *_args, **_data):
        pass


class BattleChecksTest(unittest.TestCase):
    def battle(self, player_moves, enemy_moves, party_size=6):
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.inject_fight2_spec(
            [{"species": species["SNORLAX"], "level": 50, "moves": [moves[m] for m in player_moves]}] * party_size,
            [{"species": species["TAUROS"], "level": 50, "moves": [moves[m] for m in enemy_moves]}],
            trainer_class=trainers["COOLTRAINER_M"], ai_tier=3)
        checks = GameChecks(Agent(h), ROOT)
        driver = fight2_driver.Fight2Driver(
            h, tier=3, player_policy="random", move_powers=rab.parse_move_powers(ROOT / "data/moves/moves.asm"))
        driver.move_override = 0
        driver.boot(1)
        return h, checks, driver

    def play(self, h, driver, turns):
        seen = h.hook_flag("MainInBattleLoop.selectEnemyMove")
        driver.play(1200, stop=lambda: seen["count"] >= turns)
        self.assertGreaterEqual(seen["count"], turns)

    def kinds(self, checks):
        self.assertFalse(checks.h.hook_errors, checks.h.hook_errors)
        return {a["check"] for a in checks.anomalies if a["check"] not in ("party", "enemy_party")}

    def test_every_move_lookup_in_the_source_is_hooked(self) -> None:
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        rom = autoplay_battle_checks.rom_move_lookups(h, ROOT)
        source = autoplay_battle_checks.source_move_lookups(ROOT)
        self.assertGreaterEqual(len(source), 21)
        self.assertEqual(len(rom), len(source), (rom, source))

    def test_a_sound_battle_is_quiet_and_is_really_checked(self) -> None:
        h, checks, driver = self.battle(["TACKLE", "GROWL"], ["TACKLE", "BIDE", "HAZE"])
        driver.switch_override = None
        self.play(h, driver, 4)
        self.assertEqual(self.kinds(checks), set(), checks.anomalies)
        self.assertGreaterEqual(checks.battle.compares, 3)
        self.assertGreater(checks.battle.lookups, 10)

    def test_a_menu_that_writes_the_enemy_side_is_reported(self) -> None:
        h, checks, driver = self.battle(["TACKLE"], ["TACKLE"])
        h.hook_flag("MoveSelectionMenu", action=lambda: h.write8("wEnemyBideAccumulatedDamage", 0x50, 1))
        self.play(h, driver, 2)
        self.assertIn("menu_changed_battle", self.kinds(checks))

    def test_an_unselected_move_is_reported_before_it_is_read(self) -> None:
        for move in (0, 0xFF):
            with self.subTest(move=move):
                h, checks, _driver = self.battle(["TACKLE"], ["TACKLE"])
                h.pyboy.register_file.A = move
                checks.battle._on_lookup(0, 0, "A")  # A is move - 1: 0 wraps to $FF
                self.assertEqual(self.kinds(checks) == {"move_lookup"}, move == 0xFF)
                h.pyboy.register_file.A = (move - 1) & 0xFF
                checks.battle._on_lookup(0, 0, "A")
                self.assertIn("move_lookup", self.kinds(checks))

    def test_a_revealed_empty_slot_is_never_looked_up(self) -> None:
        """Transform reveals four slots; back in its own body the mon may have fewer, and
        the AI's STAB guess read the empty one as move 0 (2026-11-24)."""
        h, checks, driver = self.battle(["TACKLE", "GROWL"], ["TACKLE", "GROWL"])
        typed = h.hook_flag("AIMoveDamagingType")
        h.hook_flag("AIPlanEnemyTurn", action=lambda: h.write8("wAISeenPlayerMoveMask", 0b1101))
        self.play(h, driver, 3)
        self.assertGreater(typed["count"], 0, "the guess never ran")
        self.assertEqual(self.kinds(checks), set(), checks.anomalies)


if __name__ == "__main__":
    unittest.main()
