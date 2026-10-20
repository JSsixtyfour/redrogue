"""The cemetery ghost boss's ghost move (PCemApplyGhostBoss).

It runs from the battle hook on the boss and again from the gift hook, and the
gifted mon can be a copy of the converted battle mon: autoplay found a Vulpix
gifted with LICK twice. A copy (ghost-variant bit already set) keeps its move;
a fresh mon that already knows the rolled move gets the next ghost move it does
not know, saved back so battle and gift agree; knowing all three, nothing new
is added.
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
MON_CATCH_RATE, MON_MOVES = 7, 8


class CemeteryGhostMoveTest(unittest.TestCase):
    def setUp(self) -> None:
        self.moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.harness.boot_to_lobby()

    def tearDown(self) -> None:
        self.harness.close()

    def apply(self, moves: list[str], rolled: str, *, converted: bool) -> tuple[list[int], int]:
        h = self.harness
        memory = h.pyboy.memory
        base = h.address("wPartyMon1")
        memory[base + MON_MOVES: base + MON_MOVES + 4] = [self.moves[m] if m else 0 for m in moves]
        catch = memory[base + MON_CATCH_RATE] & ~1
        memory[base + MON_CATCH_RATE] = catch | int(converted)
        h.write_sram_bytes("sProcCemeteryBossMove", [self.moves[rolled]], bank=0)
        bank, address = h.symbols.get("PCemApplyGhostBoss")

        def inject(_context) -> None:  # call_routine enters through Bankswitch, so set de here
            h.pyboy.register_file.D = base >> 8
            h.pyboy.register_file.E = base & 0xFF

        h.pyboy.hook_register(bank, address, inject, None)
        try:
            h.call_routine("PCemApplyGhostBoss", limit=4000)
        finally:
            h.pyboy.hook_deregister(bank, address)
        saved = h.read_sram_bytes("sProcCemeteryBossMove", 1, bank=0)[0]
        return list(memory[base + MON_MOVES: base + MON_MOVES + 4]), saved

    def ids(self, names: list[str]) -> list[int]:
        return [self.moves[m] if m else 0 for m in names]

    def test_fresh_mon_gets_the_rolled_move(self) -> None:
        moves, saved = self.apply(["TACKLE", "", "", ""], "CONFUSE_RAY", converted=False)
        self.assertEqual(moves, self.ids(["TACKLE", "CONFUSE_RAY", "", ""]))
        self.assertEqual(saved, self.moves["CONFUSE_RAY"])

    def test_fresh_mon_that_knows_it_gets_the_next_ghost_move(self) -> None:
        moves, saved = self.apply(["TACKLE", "LICK", "", ""], "LICK", converted=False)
        self.assertEqual(moves, self.ids(["TACKLE", "LICK", "NIGHT_SHADE", ""]))
        self.assertEqual(saved, self.moves["NIGHT_SHADE"])

    def test_copy_of_the_converted_boss_keeps_its_move(self) -> None:
        # The gift after the battle: the move is already there, once.
        moves, saved = self.apply(["EMBER", "QUICK_ATTACK", "LICK", ""], "LICK", converted=True)
        self.assertEqual(moves, self.ids(["EMBER", "QUICK_ATTACK", "LICK", ""]))
        self.assertEqual(saved, self.moves["LICK"])

    def test_knowing_all_three_adds_nothing(self) -> None:
        moves, _ = self.apply(["LICK", "NIGHT_SHADE", "CONFUSE_RAY", "TACKLE"], "LICK", converted=False)
        self.assertEqual(moves, self.ids(["LICK", "NIGHT_SHADE", "CONFUSE_RAY", "TACKLE"]))


if __name__ == "__main__":
    unittest.main()
