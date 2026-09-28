from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

PARTYMON_STRUCT_LENGTH = 44
MON_HP = 1
NAME_LENGTH = 11
BIT_IRONMAN = 0
# Arbitrary distinct internal species ids; only their order is asserted.
SPECIES = [0x99, 0xB0, 0xB1, 0xB2]
FALLEN_LOG_CAPACITY = 12
FALLEN_ENTRY_SIZE = PARTYMON_STRUCT_LENGTH + NAME_LENGTH + NAME_LENGTH
FALLEN_LOG_BANK = 2


class IronmanRuntimeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.harness.boot_to_lobby()

    def tearDown(self) -> None:
        self.harness.close()

    def set_ironman(self, on: bool) -> None:
        self.harness.write8("wOptions3", (1 << BIT_IRONMAN) if on else 0)

    def build_party(self, hps: list[int]) -> None:
        """One mon per HP entry; species SPECIES[i], nickname first byte 0x80+i."""
        h = self.harness
        count = len(hps)
        h.write8("wPartyCount", count)
        for i in range(count):
            h.write8("wPartySpecies", SPECIES[i], offset=i)
            h.write8("wPartyMons", SPECIES[i], offset=i * PARTYMON_STRUCT_LENGTH)
            h.write8("wPartyMons", hps[i] >> 8, offset=i * PARTYMON_STRUCT_LENGTH + MON_HP)
            h.write8("wPartyMons", hps[i] & 0xFF, offset=i * PARTYMON_STRUCT_LENGTH + MON_HP + 1)
            h.write8("wPartyMonNicks", 0x80 + i, offset=i * NAME_LENGTH)
            h.write8("wPartyMonNicks", 0x50, offset=i * NAME_LENGTH + 1)
            h.write8("wPartyMonOT", 0x90 + i, offset=i * NAME_LENGTH)
            h.write8("wPartyMonOT", 0x50, offset=i * NAME_LENGTH + 1)
        h.write8("wPartySpecies", 0xFF, offset=count)

    def party(self) -> list[tuple[int, int, int]]:
        """(species list entry, struct species, nickname byte) per slot."""
        h = self.harness
        out = []
        for i in range(h.read8("wPartyCount")):
            out.append((
                h.read8("wPartySpecies", offset=i),
                h.read8("wPartyMons", offset=i * PARTYMON_STRUCT_LENGTH),
                h.read8("wPartyMonNicks", offset=i * NAME_LENGTH),
            ))
        return out

    def test_releases_one_fainted_mon_and_keeps_order(self) -> None:
        self.set_ironman(True)
        self.build_party([20, 0, 30])
        self.harness.call_routine("IronmanReleaseFaintedMonsSilent")
        self.assertEqual(self.party(), [(0x99, 0x99, 0x80), (0xB1, 0xB1, 0x82)])
        self.assertEqual(self.harness.read8("wPartySpecies", offset=2), 0xFF)

    def test_releases_two_non_adjacent_fainted_mons(self) -> None:
        self.set_ironman(True)
        self.build_party([0, 15, 0, 40])
        self.harness.call_routine("IronmanReleaseFaintedMonsSilent")
        self.assertEqual(self.party(), [(0xB0, 0xB0, 0x81), (0xB2, 0xB2, 0x83)])

    def test_ironman_off_is_a_no_op(self) -> None:
        self.set_ironman(False)
        self.build_party([20, 0, 30])
        self.harness.call_routine("IronmanReleaseFaintedMonsSilent")
        self.assertEqual(len(self.party()), 3)

    def test_never_empties_the_party(self) -> None:
        self.set_ironman(True)
        self.build_party([0, 0])
        self.harness.call_routine("IronmanReleaseFaintedMonsSilent")
        self.assertEqual(len(self.party()), 2)

    def test_fainted_mon_evolve_flag_cleared_in_ironman(self) -> None:
        self.set_ironman(True)
        self.build_party([20, 0, 30])
        self.harness.write8("wCanEvolveFlags", 0b111)
        self.harness.call_routine("IronmanClearFaintedEvolveFlags")
        self.assertEqual(self.harness.read8("wCanEvolveFlags"), 0b101)

    def test_evolve_flags_untouched_when_ironman_off(self) -> None:
        self.set_ironman(False)
        self.build_party([20, 0, 30])
        self.harness.write8("wCanEvolveFlags", 0b111)
        self.harness.call_routine("IronmanClearFaintedEvolveFlags")
        self.assertEqual(self.harness.read8("wCanEvolveFlags"), 0b111)


class FallenLogRuntimeTest(IronmanRuntimeTest):
    # Inherit setUp/helpers only; don't re-run the parent's tests here.
    test_releases_one_fainted_mon_and_keeps_order = None
    test_releases_two_non_adjacent_fainted_mons = None
    test_ironman_off_is_a_no_op = None
    test_never_empties_the_party = None
    test_fainted_mon_evolve_flag_cleared_in_ironman = None
    test_evolve_flags_untouched_when_ironman_off = None

    def entry(self, index: int) -> list[int]:
        return self.harness.read_sram_bytes(
            "sFallenLog", FALLEN_ENTRY_SIZE * (index + 1), bank=FALLEN_LOG_BANK
        )[FALLEN_ENTRY_SIZE * index:]

    def fill_log(self, value: int) -> None:
        self.harness.write_sram_bytes(
            "sFallenLog", [value] * (FALLEN_LOG_CAPACITY * FALLEN_ENTRY_SIZE),
            bank=FALLEN_LOG_BANK,
        )

    def test_release_records_struct_ot_and_nickname(self) -> None:
        self.set_ironman(True)
        self.harness.write8("wFallenCount", 0)
        self.build_party([20, 0, 30])
        self.harness.call_routine("IronmanReleaseFaintedMonsSilent")
        self.assertEqual(self.harness.read8("wFallenCount"), 1)
        entry = self.entry(0)
        self.assertEqual(entry[0], 0xB0)                      # struct species
        self.assertEqual(entry[MON_HP:MON_HP + 2], [0, 0])    # it fainted
        self.assertEqual(entry[PARTYMON_STRUCT_LENGTH], 0x91)  # OT marker
        self.assertEqual(entry[PARTYMON_STRUCT_LENGTH + NAME_LENGTH], 0x81)  # nick

    def test_two_releases_log_in_release_order(self) -> None:
        # The sweep walks from the last slot down, so slot 2 is logged first.
        self.set_ironman(True)
        self.harness.write8("wFallenCount", 0)
        self.build_party([0, 15, 0, 40])
        self.harness.call_routine("IronmanReleaseFaintedMonsSilent")
        self.assertEqual(self.harness.read8("wFallenCount"), 2)
        self.assertEqual(self.entry(0)[0], 0xB1)
        self.assertEqual(self.entry(1)[0], 0x99)

    def test_full_log_still_releases_but_stops_logging(self) -> None:
        self.set_ironman(True)
        self.harness.write8("wFallenCount", FALLEN_LOG_CAPACITY)
        self.build_party([20, 0])
        self.harness.call_routine("IronmanReleaseFaintedMonsSilent")
        self.assertEqual(len(self.party()), 1)
        self.assertEqual(self.harness.read8("wFallenCount"), FALLEN_LOG_CAPACITY)

    def test_fallen_log_clear_zeroes_every_entry(self) -> None:
        self.fill_log(0xAA)
        self.harness.call_routine("FallenLogClear")
        self.assertEqual(
            set(self.harness.read_sram_bytes(
                "sFallenLog", FALLEN_LOG_CAPACITY * FALLEN_ENTRY_SIZE,
                bank=FALLEN_LOG_BANK)),
            {0},
        )

    def test_new_game_sram_init_clears_the_log(self) -> None:
        self.fill_log(0xAA)
        self.harness.call_routine("IronmanNewGameSRAMInit")
        self.assertEqual(set(self.entry(FALLEN_LOG_CAPACITY - 1)), {0})

    def test_run_reset_wipes_count_and_entries(self) -> None:
        self.harness.write8("wFallenCount", 3)
        self.fill_log(0xAA)
        self.harness.call_routine("RogueResetRunState", limit=200000)
        self.assertEqual(self.harness.read8("wFallenCount"), 0)
        self.assertEqual(set(self.entry(0)), {0})
        self.assertEqual(set(self.entry(FALLEN_LOG_CAPACITY - 1)), {0})


class IronmanSourceContractTest(unittest.TestCase):
    def test_evolve_filter_runs_before_evolution_and_release_after(self) -> None:
        source = (REPO_ROOT / "engine/battle/end_of_battle.asm").read_text()
        clear = source.index("farcall IronmanClearFaintedEvolveFlags")
        evolve = source.index("predef EvolutionAfterBattle")
        release = source.index("farcall IronmanReleaseFaintedMons")
        loss_gate = source.index("jr nz, .noPPTonic")
        self.assertLess(clear, evolve)
        self.assertLess(evolve, release)
        self.assertLess(loss_gate, release)


if __name__ == "__main__":
    unittest.main()
