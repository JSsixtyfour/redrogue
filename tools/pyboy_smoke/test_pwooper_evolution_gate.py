"""Form evolutions into Johto species with Johto off (2026-10-29).

Paldean Wooper is WOOPER form 1 and Clodsire is QUAGSIRE form 1; Galarian
Slowking is SLOWKING form 1. The target species are Johto, but the forms ride on
Time Warp (IsFormAllowed's default). Every evolution path used to gate on the
TARGET species' group, so with Time Warp on and Johto off Paldean Wooper was
rolled but never reached Clodsire (measured: it stayed P-Wooper at L30).

A FORM entry now skips the species gate on both paths (IsEvolutionTargetAllowed
for the player, EvolveFormMonByLevel for trainers). A plain entry into the same
Johto species (base Wooper -> Quagsire) must still be blocked.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
EVENTS = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
GROUPS = parse_rgbds_constants(REPO_ROOT / "constants" / "rogue_species_groups.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")

KANTO = 1 << GROUPS["BIT_GROUP_KANTO"]
JOHTO = 1 << GROUPS["BIT_GROUP_JOHTO"]
WARP = 1 << GROUPS["BIT_GROUP_WARP"]
FLAG_C = 0x10
MON_CATCH_RATE = 7
FORM_MASK = 0x60    # MON_CATCH_RATE bits 5-6
PLAIN_ENTRY = 0xFF  # wEvoNewForm after EvoEntryTakeForm reads a plain entry


class PwooperEvolutionGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(REPO_ROOT, Path(__file__).parent / "artifacts")
        self.h.boot_to_lobby()
        flags = self.h.read8("wStatusFlags6")
        self.h.write8("wStatusFlags6", flags & ~(1 << RAM["BIT_DEBUG2_MODE"]) & 0xFF)
        self.h.set_event(EVENTS["EVENT_JOHTO_ACTIVATED"])
        self.h.set_event(EVENTS["EVENT_KANTO_TIMEWARP_ACTIVATED"])

    def tearDown(self) -> None:
        self.h.close()

    def set_groups(self, enabled: int) -> None:
        self.h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [enabled], bank=1)

    def run_routine(self, label: str, **regs_in: int) -> dict[str, int]:
        """test_eevee_form_gate.run_routine, also returning D."""
        h = self.h
        regs = h.pyboy.register_file
        memory = h.pyboy.memory
        names = ("A", "B", "C", "D", "E", "F", "HL", "PC", "SP")
        saved = {name: getattr(regs, name) for name in names}
        saved_bank = h.read8("hLoadedROMBank")
        stub = h.address("wStringBuffer") + 16
        saved_stub = [memory[stub], memory[stub + 1]]
        saved_ie = memory[0xFFFF]
        bank, address = h.symbols.get(label)
        memory[stub], memory[stub + 1] = 0x18, 0xFE  # jr @
        memory[0xFFFF] = 0
        if bank:
            h.write8("hLoadedROMBank", bank)
            memory[0x2000] = bank
        sp = (saved["SP"] - 2) & 0xFFFF
        memory[sp], memory[sp + 1] = stub & 0xFF, stub >> 8
        regs.SP = sp
        for name, value in regs_in.items():
            setattr(regs, name, value)
        regs.PC = address
        try:
            for _ in range(10):
                h.pyboy.tick()
                if regs.PC == stub:
                    break
            self.assertEqual(regs.PC, stub, f"{label} did not return (PC ${regs.PC:04X})")
            self.assertEqual(regs.SP, (sp + 2) & 0xFFFF, f"{label} unbalanced the stack")
            return {name: getattr(regs, name) for name in ("A", "D", "E", "F")}
        finally:
            memory[0xFFFF] = saved_ie
            memory[stub], memory[stub + 1] = saved_stub
            h.write8("hLoadedROMBank", saved_bank)
            memory[0x2000] = saved_bank
            for name, value in saved.items():
                setattr(regs, name, value)

    def target_allowed(self, species: str) -> bool:
        out = self.run_routine("RogueIsSpeciesEvolutionAllowedFar", E=SPECIES[species])
        return bool(out["F"] & FLAG_C)

    def evolve_form(self, species: str, form: int, level: int) -> tuple[int, int]:
        self.h.write8("wCurEnemyLevel", level)
        self.h.write8("wCurPartySpecies", SPECIES[species])
        out = self.run_routine("EvolveFormMonByLevel", D=SPECIES[species], E=form)
        return out["D"], out["E"]

    def player_allowed(self, target: str, entry_form: int, mon_form: int) -> bool:
        """IsEvolutionTargetAllowed as the evolution loop calls it."""
        h = self.h
        memory = h.pyboy.memory
        h.write8("wEvoStoneItemID", 0)
        h.write8("wEvoNewForm", entry_form)
        catch_rate = h.address("wLoadedMon") + MON_CATCH_RATE
        memory[catch_rate] = (memory[catch_rate] & ~FORM_MASK & 0xFF) | (mon_form << 5)
        target_byte = h.address("wStringBuffer") + 24
        memory[target_byte] = SPECIES[target]
        out = self.run_routine("IsEvolutionTargetAllowed", HL=target_byte)
        return bool(out["F"] & FLAG_C)

    def test_form_evolution_into_johto_species_needs_only_warp(self) -> None:
        for enabled in (KANTO | WARP, KANTO | JOHTO | WARP):
            self.set_groups(enabled)
            johto = bool(enabled & JOHTO)
            with self.subTest(enabled=enabled):
                # The species gate itself is unchanged.
                self.assertEqual(self.target_allowed("QUAGSIRE"), johto)
                # Trainer path: the form lines reach their Johto-species forms.
                self.assertEqual(self.evolve_form("WOOPER", 1, 30), (SPECIES["QUAGSIRE"], 1))
                self.assertEqual(self.evolve_form("SLOWPOKE", 1, 40), (SPECIES["SLOWBRO"], 1))
                # Player path: a form entry passes, a plain entry is still gated.
                self.assertTrue(self.player_allowed("QUAGSIRE", 1, 1))
                self.assertTrue(self.player_allowed("SLOWKING", 1, 1))
                self.assertEqual(self.player_allowed("QUAGSIRE", PLAIN_ENTRY, 0), johto)
                # Control: plain Kanto targets always pass.
                self.assertTrue(self.player_allowed("SLOWBRO", PLAIN_ENTRY, 0))


if __name__ == "__main__":
    unittest.main()
