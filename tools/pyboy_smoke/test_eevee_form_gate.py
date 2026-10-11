"""Eeveelution forms obey the species-group gate (2026-10-11).

Espeon, Umbreon, Leafeon, Glaceon and Sylveon are FORMS of Flareon, Jolteon and
Vaporeon, which are Kanto species. The evolution gate checked only the target
species' group, so in a Kanto-only run a Leaf Stone made Leafeon and a Moon
Stone made Sylveon, and the Mist Stone rolled all eight Eevee branches with no
gate at all. Both paths now ask IsFormAllowed, the gate the reward roller uses:
Espeon/Umbreon are Johto (FormJohtoPairs), the other three are Time Warp.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
ITEMS = parse_rgbds_constants(REPO_ROOT / "constants" / "item_constants.asm")
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
EVENTS = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")
GROUPS = parse_rgbds_constants(REPO_ROOT / "constants" / "rogue_species_groups.asm")
RAM = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")

KANTO = 1 << GROUPS["BIT_GROUP_KANTO"]
JOHTO = 1 << GROUPS["BIT_GROUP_JOHTO"]
WARP = 1 << GROUPS["BIT_GROUP_WARP"]
FLAG_C = 0x10

# (stone, target species, group the resulting form needs)
FORM_EVOLUTIONS = (
    ("LEAF_STONE", "FLAREON", WARP),   # Leafeon
    ("SUN_STONE", "JOLTEON", JOHTO),   # Espeon
    ("DUSK_STONE", "JOLTEON", JOHTO),  # Umbreon
    ("ICE_STONE", "VAPOREON", WARP),   # Glaceon
    ("MOON_STONE", "VAPOREON", WARP),  # Sylveon
)
BASE_STONES = {ITEMS[n] for n in ("FIRE_STONE", "THUNDER_STONE", "WATER_STONE")}
STONE_GROUP = {ITEMS[stone]: group for stone, _, group in FORM_EVOLUTIONS}


class EeveeFormGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(REPO_ROOT, Path(__file__).parent / "artifacts")
        self.h.boot_to_lobby()
        # Unlock both groups, then pick the active set through the SRAM toggles.
        flags = self.h.read8("wStatusFlags6")
        self.h.write8("wStatusFlags6", flags & ~(1 << RAM["BIT_DEBUG2_MODE"]) & 0xFF)
        self.h.set_event(EVENTS["EVENT_JOHTO_ACTIVATED"])
        self.h.set_event(EVENTS["EVENT_KANTO_TIMEWARP_ACTIVATED"])

    def tearDown(self) -> None:
        self.h.close()

    def set_groups(self, enabled: int) -> None:
        self.h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [enabled], bank=1)

    def run_routine(self, label: str, **regs_in: int) -> dict[str, int]:
        """test_item_descriptions.run_routine, plus register inputs/outputs."""
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
            return {name: getattr(regs, name) for name in ("A", "E", "F")}
        finally:
            memory[0xFFFF] = saved_ie
            memory[stub], memory[stub + 1] = saved_stub
            h.write8("hLoadedROMBank", saved_bank)
            memory[0x2000] = saved_bank
            for name, value in saved.items():
                setattr(regs, name, value)

    def stone_allowed(self, stone: int, species: int) -> bool:
        self.h.write8("wEvoStoneItemID", stone)
        out = self.run_routine("IsEvoStoneFormAllowed", C=species)
        return bool(out["F"] & FLAG_C)

    def test_stone_evolution_checks_the_form_group(self) -> None:
        for enabled in (KANTO, KANTO | JOHTO, KANTO | WARP, KANTO | JOHTO | WARP):
            self.set_groups(enabled)
            for stone, target, needs in FORM_EVOLUTIONS:
                with self.subTest(enabled=enabled, stone=stone):
                    self.assertEqual(
                        self.stone_allowed(ITEMS[stone], SPECIES[target]),
                        bool(enabled & needs),
                    )
            with self.subTest(enabled=enabled, stone="FIRE_STONE"):
                # Form-preserving and plain evolutions are never blocked.
                self.assertTrue(self.stone_allowed(ITEMS["FIRE_STONE"], SPECIES["FLAREON"]))
                self.assertTrue(self.stone_allowed(ITEMS["MOON_STONE"], SPECIES["NIDOKING"]))
                self.assertTrue(self.stone_allowed(0, SPECIES["VAPOREON"]))

    def test_mist_stone_eevee_rolls_only_unlocked_forms(self) -> None:
        h = self.h
        party_slot = 0
        h.write8("wPartySpecies", SPECIES["EEVEE"], offset=party_slot)
        h.write8("hWhichPokemon", party_slot)
        for enabled in (KANTO, KANTO | JOHTO, KANTO | WARP, KANTO | JOHTO | WARP):
            self.set_groups(enabled)
            allowed = BASE_STONES | {s for s, g in STONE_GROUP.items() if enabled & g}
            seen = set()
            for _ in range(60):
                h.write8("wEvoStoneItemID", ITEMS["MIST_STONE"])
                self.run_routine("MistStoneChooseEvolution")
                seen.add(h.read8("wEvoStoneItemID"))
            with self.subTest(enabled=enabled):
                self.assertTrue(seen <= allowed, f"locked branch rolled: {sorted(seen - allowed)}")
                # 60 uniform rolls over 3-8 branches: missing one is < 1e-3.
                self.assertEqual(seen, allowed)


if __name__ == "__main__":
    unittest.main()
