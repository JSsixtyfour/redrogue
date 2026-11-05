"""SpecialTrainerMoves is empty, and the loop that reads it is kept as a feature.

Its rows overwrote fixed slots on rolled teams, so a mon could know a move twice (Officer
Jenny's Take Down on a Machamp that had it already). The two Stage-event tier 9 teams are
the ones that showed it. See SPECIAL_TRAINER_MOVES_AUDIT_2026-11-04.md.
"""
from __future__ import annotations

import random
import re
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
MON_LENGTH = 44
TIER_NINE_COUNT = 72


class SpecialTrainerMovesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)
        self.h.boot_to_lobby()
        self.h.tick(30)  # the game must be idle before a direct call

    def test_table_holds_only_its_terminator(self) -> None:
        bank, address = self.h.symbols.get("SpecialTrainerMoves")
        self.assertEqual(self.h.pyboy.memory[bank, address], 0xFF)

    def test_rows_are_still_applied_by_the_loop(self) -> None:
        source = (ROOT / "engine/battle/read_trainer_party.asm").read_text(errors="replace")
        self.assertIn("ld hl, SpecialTrainerMoves", source)
        self.assertIn(".writeAdditionalMoveDataLoop", source)

    def test_tier_nine_teams_keep_their_rolled_moves(self) -> None:
        h = self.h
        declared = re.findall(r"^\s*trainer_const\s+(\w+)", (ROOT / "constants/trainer_constants.asm").read_text(), re.M)
        mask = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")["DIFFICULTY_MASK"]
        h.write8("wOptions2", h.read8("wOptions2") & ~mask & 0xFF | 3)  # HARD
        rolled = {}

        def moves():
            base = h.address("wEnemyMon1Moves")
            return [[h.pyboy.memory[base + i * MON_LENGTH + m] for m in range(4)] for i in range(6)]

        def before_table(_context) -> None:
            rolled["moves"] = moves()

        h.register_hook("ReadTrainer.AddAdditionalMoveData", before_table)
        rng = random.Random(7)
        for name in ("NURSE_JOY", "OFFICER_JENNY"):
            for _ in range(12):
                for offset in range(10):
                    h.write8("wRandomTable", rng.randrange(1, 256), offset=offset)
                h.write8("wBattleCount", TIER_NINE_COUNT)
                h.write8("wTrainerClass", declared.index(name))
                h.write8("wTrainerNo", 9)
                rolled.clear()
                h.park_before_hijack()
                h.call_routine("ReadTrainer", limit=120000)
                self.assertIn("moves", rolled, "the team never reached the table")
                now = moves()
                self.assertEqual(now, rolled["moves"], f"{name}: the table changed a move")
                for slot in range(h.read8("wEnemyPartyCount")):
                    known = [move for move in now[slot] if move]
                    self.assertEqual(len(known), len(set(known)), f"{name} slot {slot + 1}: {now[slot]}")


if __name__ == "__main__":
    unittest.main()
