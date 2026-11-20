"""The Cemetery resurrection NPC's restore (CEMETERY_RESURRECTION_NPC_SPEC.md).

CemResurrectRestore brings a fallen-log entry back: party first, the current box
when the party is full, at max(its level, the reward level), with full HP, no
status and full PP, its Bridge effect re-registered when a record is free, and
the entry removed from the log. FallenLogRecord stamps the effect into the
entry's MON_BOX_LEVEL.

The stats are checked against the game's own recalculation, not a formula: a
copy of the restored mon is put in the box and withdrawn with MoveMon, which
recomputes its level from its exp and its stats from scratch.
"""

from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness
import save_reload


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

PARTYMON_STRUCT_LENGTH = 44
BOXMON_STRUCT_LENGTH = 33
NAME_LENGTH = 11
FALLEN_ENTRY_SIZE = PARTYMON_STRUCT_LENGTH + 2 * NAME_LENGTH
FALLEN_LOG_BANK = 2
FALLEN_STAMP = 0xF0
PARTY_LENGTH = 6
MONS_PER_BOX = 20

MON_SPECIES = 0
MON_HP = 1
MON_BOX_LEVEL = 3
MON_STATUS = 4
MON_MOVES = 8
MON_EXP = 14
MON_PP = 29
MON_LEVEL = 33
MON_STATS = 34
MON_MAXHP = 34

RESURRECT_TO_BOX = 1
RESURRECT_EFFECT_LOST = 2
BOX_TO_PARTY = 0
BRIDGE_RECORDS = 4
SHRINK_RAY = 2  # BRIDGE_SELECTED_EFFECT_SHRINK_RAY
CRITICAL_RATE = 1


class CemeteryResurrectorRestoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.h.boot_to_lobby()
        self.template = self.h.read_bytes("wPartyMons", PARTYMON_STRUCT_LENGTH)
        self.ot = self.h.read_bytes("wPartyMonOT", NAME_LENGTH)
        self.reward = self.reward_level()
        self.assertGreater(self.reward, 8, "the fixture needs room below the reward level")
        for i in range(BRIDGE_RECORDS * 2):
            self.h.write8("wBridgeSelectedEffects", 0, offset=i)

    def tearDown(self) -> None:
        self.h.close()

    # --- helpers -------------------------------------------------------------

    def reward_level(self) -> int:
        self.h.park_before_hijack()
        self.h.call_routine("GetRewardMonLevel")
        return self.h.read8("wCurEnemyLevel")

    def make_entry(self, level: int, marker: int, stamp: int = FALLEN_STAMP) -> list[int]:
        mon = list(self.template)
        mon[MON_LEVEL] = level
        mon[MON_BOX_LEVEL] = stamp
        mon[MON_HP] = 0
        mon[MON_HP + 1] = 0
        mon[MON_STATUS] = 0x08  # poisoned
        mon[MON_PP] = 0xC0 | 1  # three PP Ups, 1 PP left
        for i in range(1, 4):
            mon[MON_PP + i] = mon[MON_PP + i] & 0xC0
        ot = list(self.ot)
        nick = [marker, 0x50] + [0x50] * (NAME_LENGTH - 2)
        return mon + ot + nick

    def write_log(self, entries: list[list[int]]) -> None:
        flat = [b for entry in entries for b in entry]
        self.h.write_sram_bytes("sFallenLog", flat, bank=FALLEN_LOG_BANK)
        self.h.write8("wFallenCount", len(entries))

    def log_entry(self, index: int) -> list[int]:
        return self.h.read_sram_bytes(
            "sFallenLog", FALLEN_ENTRY_SIZE * (index + 1), bank=FALLEN_LOG_BANK
        )[FALLEN_ENTRY_SIZE * index:]

    def restore(self, index: int) -> tuple[int, bool]:
        """Returns (a, carry) at CemResurrectRestore's own return."""
        h = self.h

        def argument(_context) -> None:
            h.pyboy.register_file.A = index

        def capture(harness) -> tuple[int, bool]:
            rf = harness.pyboy.register_file
            return rf.A, bool(rf.F & 0x10)

        h.register_hook("CemResurrectRestore", argument)
        try:
            h.park_before_hijack()
            return h.call_routine("CemResurrectRestore", limit=200000, capture=capture)
        finally:
            h.unregister_hook("CemResurrectRestore", argument)

    def party_mon(self, slot: int) -> list[int]:
        return self.h.read_bytes(
            "wPartyMons", PARTYMON_STRUCT_LENGTH, offset=slot * PARTYMON_STRUCT_LENGTH
        )

    def set_party_count(self, count: int) -> None:
        # Copies of slot 0 fill the party; only the count and species list matter.
        h = self.h
        for slot in range(1, count):
            for i, b in enumerate(self.template):
                h.write8("wPartyMons", b, offset=slot * PARTYMON_STRUCT_LENGTH + i)
            h.write8("wPartySpecies", self.template[0], offset=slot)
        h.write8("wPartyCount", count)
        h.write8("wPartySpecies", 0xFF, offset=count)

    def recalculated_copy(self, mon: list[int]) -> list[int]:
        """mon put in the box and withdrawn by MoveMon: the game's own level
        from exp and stats from scratch."""
        h = self.h
        count = h.read8("wBoxCount")
        self.assertLess(count, MONS_PER_BOX)
        for i in range(BOXMON_STRUCT_LENGTH):
            h.write8("wBoxMons", mon[i], offset=count * BOXMON_STRUCT_LENGTH + i)
        h.write8("wBoxSpecies", mon[0], offset=count)
        h.write8("wBoxSpecies", 0xFF, offset=count + 1)
        h.write8("wBoxCount", count + 1)
        party = h.read8("wPartyCount")
        self.assertLess(party, PARTY_LENGTH)
        h.write8("wMoveMonType", BOX_TO_PARTY)
        h.write8("hWhichPokemon", count)
        h.write8("wCurPartySpecies", mon[0])
        h.park_before_hijack()
        h.call_routine("MoveMon", limit=200000)
        self.assertEqual(h.read8("wPartyCount"), party + 1)
        return self.party_mon(party)

    # --- tests ---------------------------------------------------------------

    def test_restores_the_middle_entry_at_the_reward_level_and_compacts(self) -> None:
        h = self.h
        low = self.reward - 5
        self.write_log([
            self.make_entry(3, 0x81),
            self.make_entry(low, 0x82),
            self.make_entry(self.reward + 3, 0x83),
        ])
        self.set_party_count(1)
        a, carry = self.restore(1)
        self.assertFalse(carry)
        self.assertEqual(a, 0)

        self.assertEqual(h.read8("wPartyCount"), 2)
        self.assertEqual(h.read8("wPartySpecies", offset=1), self.template[0])
        self.assertEqual(h.read8("wPartySpecies", offset=2), 0xFF)
        mon = self.party_mon(1)
        self.assertEqual(mon[MON_LEVEL], self.reward)
        self.assertEqual(mon[MON_BOX_LEVEL], self.reward)
        self.assertEqual(mon[MON_STATUS], 0)
        self.assertEqual(mon[MON_HP:MON_HP + 2], mon[MON_MAXHP:MON_MAXHP + 2])
        self.assertGreater(mon[MON_HP] * 256 + mon[MON_HP + 1], 0)
        # The form and the rest of the identity came through.
        for offset in (MON_SPECIES, 7, 12, 13, 27, 28):  # catch rate, OT id, DVs
            self.assertEqual(mon[offset], self.template[offset], offset)
        self.assertEqual(mon[MON_MOVES:MON_MOVES + 4], self.template[MON_MOVES:MON_MOVES + 4])
        self.assertEqual(h.read8("wPartyMonNicks", offset=NAME_LENGTH), 0x82)
        self.assertEqual(
            h.read_bytes("wPartyMonOT", NAME_LENGTH, offset=NAME_LENGTH), self.ot
        )
        # PP: the PP Up bits are kept and the PP is no longer the 1 left.
        self.assertEqual(mon[MON_PP] & 0xC0, 0xC0)
        self.assertGreater(mon[MON_PP] & 0x3F, 1)

        # Exp and stats agree with the game's own recalculation.
        copy = self.recalculated_copy(mon)
        self.assertEqual(copy[MON_LEVEL], self.reward, "exp is not the reward level's")
        self.assertEqual(copy[MON_STATS:MON_STATS + 10], mon[MON_STATS:MON_STATS + 10])

        # The log: the third entry moved down, the tail is zeroed, count 2.
        self.assertEqual(h.read8("wFallenCount"), 2)
        self.assertEqual(self.log_entry(0)[PARTYMON_STRUCT_LENGTH + NAME_LENGTH], 0x81)
        self.assertEqual(self.log_entry(1)[PARTYMON_STRUCT_LENGTH + NAME_LENGTH], 0x83)
        self.assertEqual(self.log_entry(1)[MON_LEVEL], self.reward + 3)
        self.assertEqual(set(self.log_entry(2)), {0})

    def test_a_higher_level_is_kept_with_its_exp(self) -> None:
        h = self.h
        high = self.reward + 3
        entry = self.make_entry(high, 0x81)
        self.write_log([entry])
        self.set_party_count(1)
        _, carry = self.restore(0)
        self.assertFalse(carry)
        mon = self.party_mon(1)
        self.assertEqual(mon[MON_LEVEL], high)
        self.assertEqual(mon[MON_EXP:MON_EXP + 3], entry[MON_EXP:MON_EXP + 3])
        self.assertEqual(h.read8("wFallenCount"), 0)
        self.assertEqual(set(self.log_entry(0)), {0})

    def test_full_party_goes_to_the_box(self) -> None:
        h = self.h
        self.write_log([self.make_entry(self.reward - 2, 0x81)])
        self.set_party_count(PARTY_LENGTH)
        box = h.read8("wBoxCount")
        self.assertLess(box, MONS_PER_BOX)
        a, carry = self.restore(0)
        self.assertFalse(carry)
        self.assertEqual(a, RESURRECT_TO_BOX)
        self.assertEqual(h.read8("wPartyCount"), PARTY_LENGTH)
        self.assertEqual(h.read8("wBoxCount"), box + 1)
        self.assertEqual(h.read8("wBoxSpecies", offset=box), self.template[0])
        self.assertEqual(h.read8("wBoxSpecies", offset=box + 1), 0xFF)
        mon = h.read_bytes("wBoxMons", BOXMON_STRUCT_LENGTH, offset=box * BOXMON_STRUCT_LENGTH)
        self.assertEqual(mon[MON_BOX_LEVEL], self.reward)
        self.assertEqual(mon[MON_STATUS], 0)
        self.assertGreater(mon[MON_HP] * 256 + mon[MON_HP + 1], 0)
        self.assertEqual(h.read8("wBoxMonNicks", offset=box * NAME_LENGTH), 0x81)
        self.assertEqual(h.read8("wFallenCount"), 0)
        # Withdrawn, it is exactly the reward level at full HP.
        h.write8("wPartyCount", PARTY_LENGTH - 1)
        h.write8("wPartySpecies", 0xFF, offset=PARTY_LENGTH - 1)
        copy = self.recalculated_copy(mon + [0] * (PARTYMON_STRUCT_LENGTH - BOXMON_STRUCT_LENGTH))
        self.assertEqual(copy[MON_LEVEL], self.reward)
        self.assertEqual(mon[MON_HP:MON_HP + 2], copy[MON_MAXHP:MON_MAXHP + 2])

    def test_party_and_box_full_changes_nothing(self) -> None:
        h = self.h
        self.write_log([self.make_entry(5, 0x81)])
        self.set_party_count(PARTY_LENGTH)
        h.write8("wBoxCount", MONS_PER_BOX)
        _, carry = self.restore(0)
        self.assertTrue(carry)
        self.assertEqual(h.read8("wPartyCount"), PARTY_LENGTH)
        self.assertEqual(h.read8("wBoxCount"), MONS_PER_BOX)
        self.assertEqual(h.read8("wFallenCount"), 1)
        self.assertEqual(self.log_entry(0)[PARTYMON_STRUCT_LENGTH + NAME_LENGTH], 0x81)

    def test_bridge_effect_comes_back_to_its_new_owner(self) -> None:
        h = self.h
        self.write_log([self.make_entry(self.reward - 2, 0x81, FALLEN_STAMP | CRITICAL_RATE)])
        self.set_party_count(2)
        a, carry = self.restore(0)
        self.assertFalse(carry)
        self.assertEqual(a, 0)
        records = h.read_bytes("wBridgeSelectedEffects", BRIDGE_RECORDS * 2)
        self.assertEqual(records[:2], [3, CRITICAL_RATE])  # party slot 2 -> owner 3
        self.assertEqual(self.party_mon(2)[MON_BOX_LEVEL], self.reward)

    def test_bridge_effect_is_lost_when_every_record_is_taken(self) -> None:
        h = self.h
        for i in range(BRIDGE_RECORDS):
            h.write8("wBridgeSelectedEffects", 0x40 + i, offset=2 * i)
            h.write8("wBridgeSelectedEffects", CRITICAL_RATE, offset=2 * i + 1)
        self.write_log([self.make_entry(self.reward - 2, 0x81, FALLEN_STAMP | SHRINK_RAY)])
        self.set_party_count(1)
        a, carry = self.restore(0)
        self.assertFalse(carry)
        self.assertEqual(a, RESURRECT_EFFECT_LOST)
        self.assertEqual(h.read8("wPartyCount"), 2)
        owners = h.read_bytes("wBridgeSelectedEffects", BRIDGE_RECORDS * 2)[::2]
        self.assertEqual(owners, [0x40, 0x41, 0x42, 0x43])

    def test_release_stamps_the_bridge_effect(self) -> None:
        h = self.h
        h.write8("wOptions3", 1)  # BIT_IRONMAN
        h.write8("wFallenCount", 0)
        self.set_party_count(3)
        for slot in (1, 2):
            base = slot * PARTYMON_STRUCT_LENGTH
            h.write8("wPartyMons", 0, offset=base + MON_HP)
            h.write8("wPartyMons", 0, offset=base + MON_HP + 1)
        # Slot 2 (owner 3) owns Shrink Ray; slot 1 owns nothing.
        h.write8("wBridgeSelectedEffects", 3, offset=0)
        h.write8("wBridgeSelectedEffects", SHRINK_RAY, offset=1)
        h.park_before_hijack()
        h.call_routine("IronmanReleaseFaintedMonsSilent", limit=200000)
        self.assertEqual(h.read8("wPartyCount"), 1)
        self.assertEqual(h.read8("wFallenCount"), 2)
        # The sweep runs from the last slot down: slot 2 is entry 0.
        self.assertEqual(self.log_entry(0)[MON_BOX_LEVEL], FALLEN_STAMP | SHRINK_RAY)
        self.assertEqual(self.log_entry(1)[MON_BOX_LEVEL], FALLEN_STAMP)
        self.assertEqual(self.log_entry(0)[MON_LEVEL], self.template[MON_LEVEL])

    def test_continue_after_a_resurrection_keeps_the_pokemon(self) -> None:
        """Save after a resurrection, power on a fresh emulator on that cartridge
        RAM and CONTINUE: the Pokemon, its nickname and its Bridge effect are
        back, and the log still holds exactly the entries its count says."""
        h = self.h
        self.write_log([
            self.make_entry(self.reward - 2, 0x81, FALLEN_STAMP | CRITICAL_RATE),
            self.make_entry(self.reward - 3, 0x82),
        ])
        self.set_party_count(1)
        _, carry = self.restore(0)
        self.assertFalse(carry)
        mon = self.party_mon(1)
        records = h.read_bytes("wBridgeSelectedEffects", BRIDGE_RECORDS * 2)
        self.assertEqual(records[:2], [2, CRITICAL_RATE])  # party slot 1 -> owner 2
        log = [self.log_entry(i) for i in range(2)]

        h.park_before_hijack()
        h.call_routine("SaveGameData", limit=60_000)
        reboot = save_reload.Reboot(save_reload.sram_image(h),
                                    cgb_mode=h.hardware_mode == "CGB")
        try:
            reboot.load()
            r = reboot.h
            self.assertEqual(reboot.status, 2, "the save did not load")
            self.assertTrue(reboot.overworld, "CONTINUE never reached the overworld")
            self.assertEqual(r.read8("wPartyCount"), 2)
            self.assertEqual(r.read8("wPartySpecies", offset=1), self.template[0])
            self.assertEqual(r.read_bytes("wPartyMons", PARTYMON_STRUCT_LENGTH,
                                          offset=PARTYMON_STRUCT_LENGTH), mon)
            self.assertEqual(r.read8("wPartyMonNicks", offset=NAME_LENGTH), 0x81)
            self.assertEqual(r.read_bytes("wBridgeSelectedEffects", BRIDGE_RECORDS * 2), records)
            # The log: one entry left (the second, moved down), a zeroed tail,
            # and the saved count agrees with it.
            self.assertEqual(r.read8("wFallenCount"), 1)
            reloaded = r.read_sram_bytes("sFallenLog", FALLEN_ENTRY_SIZE * 2, bank=FALLEN_LOG_BANK)
            self.assertEqual(reloaded[:FALLEN_ENTRY_SIZE], log[0])
            self.assertEqual(reloaded[PARTYMON_STRUCT_LENGTH + NAME_LENGTH], 0x82)
            self.assertEqual(set(reloaded[FALLEN_ENTRY_SIZE:]), {0})
            self.assertEqual(set(log[1]), {0})
        finally:
            reboot.close()


if __name__ == "__main__":
    unittest.main()
