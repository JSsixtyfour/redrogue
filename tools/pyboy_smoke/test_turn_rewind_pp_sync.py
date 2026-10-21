"""TURN REWIND keeps the party PP in step with the battle PP it refunds.

TurnRewindRestore refunds the rewound turn's PP in wBattleMonPP but used to sync
only HP and status back to the party struct. The battle copy then ran one ahead,
and when it next reached 0, DecrementPP took the party byte from 0 to $FF (PP 63
with three PP Ups): autoplay seed 124 (--vary --runs 2), Oddish's Absorb on
Route 12, measured 2026-10-21. A Transformed mon's battle PP belongs to the
copied moves, so it is not synced then (DecrementPP's own rule).
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants, parse_trainer_constants

ROOT = Path(__file__).resolve().parents[2]
PARTYMON_STRUCT_LENGTH = 44


class TurnRewindPPSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ROOT / "tools/pyboy_smoke/artifacts")
        species = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
        moves = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
        self.battle = parse_rgbds_constants(ROOT / "constants/battle_constants.asm")
        trainers = parse_trainer_constants(ROOT / "constants/trainer_constants.asm")
        self.h.inject_fight2_spec(
            [{"species": species["ODDISH"], "level": 30,
              "moves": [moves["ABSORB"], moves["POISONPOWDER"], moves["SLEEP_POWDER"]]}],
            [{"species": species["RATTATA"], "level": 30, "moves": [moves["TACKLE"]]}],
            trainer_class=trainers["YOUNGSTER"], ai_tier=0)
        self.h.boot_fight2(seed=1)

    def tearDown(self) -> None:
        self.h.close()

    def restore(self, *, snapshot_pp, battle_pp, party_pp, transformed=False):
        h = self.h
        h.park_before_hijack()
        slot = h.read8("wPlayerMonNumber")
        buffer = h.read_sram_bytes("sTurnRewindBuf", 34)
        buffer[0] = slot
        buffer[1:3] = h.read_bytes("wBattleMonHP", 2)
        buffer[3] = h.read8("wBattleMonStatus")
        buffer[4:8] = snapshot_pp
        buffer[8:16] = h.read_bytes("wBattleMonAttack", 8)
        buffer[26] = (1 << self.battle["TRANSFORMED"]) if transformed else 0  # wPlayerBattleStatus3
        h.write_sram_bytes("sTurnRewindBuf", buffer)
        for index in range(4):
            h.write8("wBattleMonPP", battle_pp[index], offset=index)
            h.write8("wPartyMon1PP", party_pp[index], offset=slot * PARTYMON_STRUCT_LENGTH + index)
        h.call_routine("TurnRewindRestore", limit=300)
        return h.read_bytes("wBattleMonPP", 4), h.read_bytes("wPartyMon1PP", 4, offset=slot * PARTYMON_STRUCT_LENGTH)

    def test_refunded_pp_reaches_the_party_copy(self) -> None:
        # The rewound turn used Absorb (5 -> 4 in both copies); the rewind refunds it.
        battle, party = self.restore(snapshot_pp=[5, 35, 15, 0], battle_pp=[4, 35, 15, 0],
                                     party_pp=[4, 35, 15, 0])
        self.assertEqual(battle, [5, 35, 15, 0])
        self.assertEqual(party, [5, 35, 15, 0])

    def test_a_transformed_mon_keeps_its_party_pp(self) -> None:
        battle, party = self.restore(snapshot_pp=[5, 5, 5, 5], battle_pp=[4, 5, 5, 5],
                                     party_pp=[9, 35, 15, 0], transformed=True)
        self.assertEqual(battle, [5, 5, 5, 5])
        self.assertEqual(party, [9, 35, 15, 0])


if __name__ == "__main__":
    unittest.main()
