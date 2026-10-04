"""Trashed House INTIMIDATE GROWLITHE gift.

BridgeGiftAddMove must fill an empty move slot instead of overwriting slot 1,
and the Intimidate stat path must cut the enemy's live Attack to the -1 stage
value. The animation/text half of BridgeTryIntimidate waits on frames, so it is
not reachable through call_routine and is checked in game instead.
Each test boots fresh: call_routine is only good for about ten invocations per
boot (project_call_routine_harness_limits).
"""

from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

MON_CATCH_RATE = 7
MON_MOVES = 8
MON_PP = 0x1D
BIT_SPECIAL_FORM = 1 << 3
SF_INTIMIDATE = 1 << 7


class BridgeIntimidateGiftTest(unittest.TestCase):
    def setUp(self) -> None:
        self.species = parse_rgbds_constants(
            REPO_ROOT / "constants" / "pokemon_constants.asm"
        )
        self.moves = parse_rgbds_constants(REPO_ROOT / "constants" / "move_constants.asm")
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.harness.boot_to_lobby()

    def tearDown(self) -> None:
        self.harness.close()

    def add_move(self, start: list[int], move: str) -> tuple[list[int], list[int]]:
        h = self.harness
        base = h.address("wPartyMon1")
        memory = h.pyboy.memory
        memory[base] = self.species["GROWLITHE"]
        ids = [self.moves[name] if name else 0 for name in start]
        memory[base + MON_MOVES : base + MON_MOVES + 4] = ids
        memory[base + MON_PP : base + MON_PP + 4] = [0, 0, 0, 0]
        # Inject every input at entry. a, because call_routine enters through
        # Bankswitch, which overwrites it (the real caller passes the move in a
        # with a plain call). de too: call_routine snapshots the registers it
        # restores into the parked lobby code, so setting de beforehand hands
        # that code our struct pointer, and it writes two bytes at de+10
        # (measured: slots 3-4 came back 0,16 even from a no-op routine).
        bank, address = h.symbols.get("BridgeGiftAddMove")

        def inject(_context, value=self.moves[move]) -> None:
            h.pyboy.register_file.A = value
            h.pyboy.register_file.D = base >> 8
            h.pyboy.register_file.E = base & 0xFF

        h.pyboy.hook_register(bank, address, inject, None)
        try:
            h.call_routine("BridgeGiftAddMove", limit=4000)
        finally:
            h.pyboy.hook_deregister(bank, address)
        moves = list(memory[base + MON_MOVES : base + MON_MOVES + 4])
        pps = list(memory[base + MON_PP : base + MON_PP + 4])
        return moves, pps

    def test_gift_move_fills_the_first_empty_slot(self) -> None:
        moves, pps = self.add_move(["BITE", "", "", ""], "QUICK_ATTACK")
        self.assertEqual(
            moves, [self.moves["BITE"], self.moves["QUICK_ATTACK"], 0, 0]
        )
        self.assertTrue(pps[0] and pps[1])
        self.assertEqual(pps[2:], [0, 0])

    def test_gift_move_already_known_is_a_no_op(self) -> None:
        moves, _ = self.add_move(["BITE", "QUICK_ATTACK", "", ""], "QUICK_ATTACK")
        self.assertEqual(
            moves, [self.moves["BITE"], self.moves["QUICK_ATTACK"], 0, 0]
        )

    def test_gift_move_replaces_slot_1_only_when_full(self) -> None:
        full = ["BITE", "TACKLE", "EMBER", "LEER"]
        moves, _ = self.add_move(full, "QUICK_ATTACK")
        expected = [self.moves[name] for name in full]
        expected[0] = self.moves["QUICK_ATTACK"]
        self.assertEqual(moves, expected)

    def test_flagged_battle_growlithe_reports_intimidate(self) -> None:
        h = self.harness
        caps: list[int] = []
        bank, address = h.symbols.get("SpecialFormCapsLookup.found")

        def capture(_context) -> None:
            caps.append(h.pyboy.register_file.A)

        battle_mon = h.address("wBattleMon")
        h.pyboy.hook_register(bank, address, capture, None)
        try:
            for species in ("GROWLITHE", "ARCANINE"):
                h.pyboy.memory[battle_mon] = self.species[species]
                h.pyboy.memory[battle_mon + MON_CATCH_RATE] = BIT_SPECIAL_FORM
                h.pyboy.register_file.D = battle_mon >> 8
                h.pyboy.register_file.E = battle_mon & 0xFF
                h.call_routine("GetSpecialFormCaps", limit=200)
        finally:
            h.pyboy.hook_deregister(bank, address)
        self.assertEqual(caps, [SF_INTIMIDATE] * 2)

    def test_intimidate_stage_cuts_enemy_attack_to_66_percent(self) -> None:
        # StatModifierRatios' -1 stage is 66/100.
        h = self.harness
        unmodified = h.address("wEnemyMonUnmodifiedAttack")
        attack = h.address("wEnemyMonAttack")
        h.pyboy.memory[unmodified : unmodified + 2] = [0, 150]
        h.pyboy.memory[attack : attack + 2] = [0, 150]
        h.write8("wEnemyMonStatus", 0)
        h.write8("wEnemyMonAttackMod", 6)  # what BridgeTryIntimidate leaves
        h.pyboy.register_file.E = 0
        h.call_routine("BridgeRecalculateEnemyStat", limit=2000)
        memory = h.pyboy.memory
        self.assertEqual((memory[attack] << 8) | memory[attack + 1], 99)


if __name__ == "__main__":
    unittest.main()
