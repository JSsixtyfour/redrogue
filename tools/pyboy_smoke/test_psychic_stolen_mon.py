"""The mon the Psychic stage event steals joins the Psychic's team as its last
slot. Found by the autoplay data checks (2026-10-20): CalcStats took the level
from wCurEnemyLevel, still the Psychic's own, so a level 90 Exeggutor fought
with level 13 stats at 294/58 HP. It must field the stats it had in the
player's party, and leave wCurEnemyLevel to ReadTrainer's prize money."""
import unittest

from source_constants import parse_map_constants
from test_smoke import HarnessTestCase, REPO_ROOT

BOXMON_STRUCT_LENGTH = 0x21
PARTYMON_STRUCT_LENGTH = 0x2C
MON_LEVEL, MON_STATS, STATS_LENGTH = 0x21, 0x22, 10
MON_DVS = 0x1B
RECORD_BANK = 1
STOLEN_MON = 1
PSYCHIC_TR = 0x13
OPP_ID_OFFSET = 160
STAGE_EVENT_PSYCHIC = 2


class PsychicStolenMonTest(HarnessTestCase):
    def test_stolen_mon_keeps_its_level_and_stats(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_to_lobby()
        party = [list(h.read_bytes("wPartyMon1", PARTYMON_STRUCT_LENGTH, i * PARTYMON_STRUCT_LENGTH))
                 for i in range(h.read8("wPartyCount"))]
        h.write8("wStageEvent", STAGE_EVENT_PSYCHIC)
        cave = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")["PROCEDURAL_CAVE_1"]
        h.preload_and_enter_wild_area(cave, "Procedural Cave")
        for _ in range(6):
            h.tap("a", frames=12)
            h.tick(40)
        if h.read_sram_bytes("sStolenKind", 1, bank=RECORD_BANK)[0] != STOLEN_MON:
            self.skipTest("this seed's Psychic stole an item, not a mon")
        record = h.read_sram_bytes("sStolenBoxMon", BOXMON_STRUCT_LENGTH, bank=RECORD_BANK)
        original = next(mon for mon in party
                        if mon[0] == record[0] and mon[MON_DVS:MON_DVS + 2] == record[MON_DVS:MON_DVS + 2])

        levels = []
        h.register_hook("StageEventInjectStolenMon", lambda _c: levels.append(h.read8("wCurEnemyLevel")))
        h.write8("wTrainerClass", PSYCHIC_TR)
        h.write8("wCurOpponent", PSYCHIC_TR + OPP_ID_OFFSET)
        h.write8("wTrainerNo", 1)
        h.call_routine("ReadTrainer", limit=40000)

        count = h.read8("wEnemyPartyCount")
        last = h.read_bytes("wEnemyMon1", PARTYMON_STRUCT_LENGTH, (count - 1) * PARTYMON_STRUCT_LENGTH)
        self.assertEqual(last[0], record[0], "the stolen mon is not the Psychic's last slot")
        self.assertEqual(last[MON_LEVEL], original[MON_LEVEL])
        self.assertEqual(last[MON_STATS:MON_STATS + STATS_LENGTH],
                         original[MON_STATS:MON_STATS + STATS_LENGTH],
                         "max HP, Attack, Defense, Speed, Special differ from the player's mon")
        self.assertEqual(len(levels), 1)
        self.assertEqual(h.read8("wCurEnemyLevel"), levels[0],
                         "wCurEnemyLevel changed: the prize money would follow the stolen mon's level")


if __name__ == "__main__":
    unittest.main(verbosity=2)
