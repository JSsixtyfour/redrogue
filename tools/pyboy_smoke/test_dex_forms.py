"""Pokedex form collection, Checkpoint B (2026-11-03).

DexRegisterMon (custom_functions/dex_forms.asm) credits EXACTLY the identity
registered: form 0 -> the base species' bit; a cataloged form -> its DEX_FORM_*
bit in wPokedexFormOwned/Seen; any other form record (Armored Mewtwo, the fossil
ghosts) or a selector with no record -> nothing. These tests run the real
routines against the built ROM, plus one real _AddPartyMon (the gift/party path).
See POKEDEX_FORMS_CHECKPOINT_A_2026-11-03.md.
"""
from pathlib import Path
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
DEX = parse_rgbds_constants(REPO_ROOT / "constants" / "pokedex_constants.asm")

CATALOG = [(name, SPECIES[species], int(form)) for name, species, form in re.findall(
    r"^\s*dex_form\s+(DEX_FORM_\w+),\s*(\w+),\s*(\d)",
    (REPO_ROOT / "data" / "pokemon" / "dex_forms.asm").read_text(encoding="utf-8"), re.M)]
SLOTS = 56          # NUM_DEX_FORM_SLOTS
FORM_BYTES = SLOTS // 8
BASE_BYTES = 32     # flag_array NUM_POKEMON (252)
OWNED, SEEN, BOTH = 1, 2, 3
NOT_IDENTITY = 0xFF
EXCLUDED = [("MEWTWO", 1), ("AERODACTYL", 1), ("KABUTOPS", 1)]
FLAG_C = 0x10
FORM_REC_SIZE = 2 + 28 + 10 + 1  # FORM_REC_* (an _RS block the constant parser can't evaluate)


class DexFormsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.h = RedRogueHarness(REPO_ROOT, Path(__file__).parent / "artifacts")
        cls.h.boot_to_lobby()
        cls.rom = cls.h.rom_path.read_bytes()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.h.close()

    # --- helpers -----------------------------------------------------------

    def rom_bytes(self, label: str, length: int) -> bytes:
        bank, address = self.h.symbols.get(label)
        start = bank * 0x4000 + (address - 0x4000 if bank else address)
        return self.rom[start:start + length]

    def run_routine(self, label: str, **regs_in: int) -> dict[str, int]:
        """Direct stub executor (test_eevee_form_gate.run_routine): no park point."""
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
            for _ in range(60):
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

    def clear_dex(self) -> None:
        for label, size in (("wPokedexOwned", BASE_BYTES), ("wPokedexSeen", BASE_BYTES),
                            ("wPokedexFormOwned", FORM_BYTES), ("wPokedexFormSeen", FORM_BYTES)):
            for i in range(size):
                self.h.write8(label, 0, offset=i)

    def bits(self, label: str, size: int) -> list[int]:
        data = self.h.read_bytes(label, size)
        return [i for i in range(size * 8) if data[i >> 3] >> (i & 7) & 1]

    def register(self, species: int, form: int, actions: int) -> int:
        out = self.run_routine("DexRegisterMon", D=species, E=(form << 5) | actions)
        return out["E"]

    def base_bit(self, species_name: str) -> int:
        return DEX["DEX_" + species_name] - 1

    # --- layout -------------------------------------------------------------

    def test_arrays_follow_the_base_dex_and_fit_one_partial_save_span(self) -> None:
        a = self.h.address
        self.assertEqual(a("wPokedexFormOwned"), a("wPokedexSeen") + BASE_BYTES)
        self.assertEqual(a("wPokedexFormSeen"), a("wPokedexFormOwned") + FORM_BYTES)
        self.assertEqual(a("wPokedexDataEnd"), a("wPokedexFormSeen") + FORM_BYTES)
        self.assertLessEqual(len(CATALOG), SLOTS)

    def test_catalog_names_real_form_records_and_omits_the_excluded_ones(self) -> None:
        keys = self.rom_bytes("DexFormKeys", 2 * len(CATALOG) + 1)
        self.assertEqual(keys[-1], 0, "terminator")
        rom_pairs = [(keys[2 * i], keys[2 * i + 1]) for i in range(len(CATALOG))]
        self.assertEqual(rom_pairs, [(s, f) for _, s, f in CATALOG])
        self.assertEqual(len(set(rom_pairs)), len(rom_pairs), "duplicate identity")
        for name, _, _ in CATALOG:
            self.assertEqual(DEX[name], [n for n, _, _ in CATALOG].index(name), name)
        size = FORM_REC_SIZE
        table = self.rom_bytes("FormOverrides", size * 64)
        records = set()
        for i in range(64):
            if table[i * size] == 0:
                break
            records.add((table[i * size], table[i * size + 1]))
        excluded = {(SPECIES[s], f) for s, f in EXCLUDED}
        self.assertEqual(records - excluded, set(rom_pairs),
                         "every form record except the excluded three is an identity")
        self.assertTrue(excluded <= records)

    # --- registration -------------------------------------------------------

    def test_base_registration_credits_only_the_base_species(self) -> None:
        self.clear_dex()
        self.assertEqual(self.register(SPECIES["MEOWTH"], 0, BOTH), 0, "new")
        self.assertEqual(self.bits("wPokedexOwned", BASE_BYTES), [self.base_bit("MEOWTH")])
        self.assertEqual(self.bits("wPokedexSeen", BASE_BYTES), [self.base_bit("MEOWTH")])
        self.assertEqual(self.bits("wPokedexFormOwned", FORM_BYTES), [])
        self.assertEqual(self.register(SPECIES["MEOWTH"], 0, BOTH), 1, "duplicate")

    def test_form_registration_credits_only_the_form(self) -> None:
        self.clear_dex()
        self.assertEqual(self.register(SPECIES["MEOWTH"], 1, BOTH), 0, "new")
        self.assertEqual(self.bits("wPokedexFormOwned", FORM_BYTES), [DEX["DEX_FORM_A_MEOWTH"]])
        self.assertEqual(self.bits("wPokedexFormSeen", FORM_BYTES), [DEX["DEX_FORM_A_MEOWTH"]])
        self.assertEqual(self.bits("wPokedexOwned", BASE_BYTES), [], "no base credit")
        self.assertEqual(self.bits("wPokedexSeen", BASE_BYTES), [])
        self.assertEqual(self.register(SPECIES["MEOWTH"], 1, BOTH), 1, "duplicate")
        # base then a second form of the same species: three independent bits
        self.register(SPECIES["MEOWTH"], 0, BOTH)
        self.register(SPECIES["MEOWTH"], 2, BOTH)
        self.assertEqual(self.bits("wPokedexFormOwned", FORM_BYTES),
                         sorted([DEX["DEX_FORM_A_MEOWTH"], DEX["DEX_FORM_G_MEOWTH"]]))
        self.assertEqual(self.bits("wPokedexOwned", BASE_BYTES), [self.base_bit("MEOWTH")])

    def test_seen_only_does_not_grant_ownership(self) -> None:
        self.clear_dex()
        self.assertEqual(self.register(SPECIES["TAUROS"], 3, SEEN), 0)
        self.assertEqual(self.bits("wPokedexFormSeen", FORM_BYTES), [DEX["DEX_FORM_P_TAUROS_AQUA"]])
        self.assertEqual(self.bits("wPokedexFormOwned", FORM_BYTES), [])
        self.assertEqual(self.register(SPECIES["TAUROS"], 3, OWNED), 0, "first ownership is new")

    def test_every_identity_lands_on_its_own_bit_and_never_on_padding(self) -> None:
        self.clear_dex()
        for name, species, form in CATALOG:
            self.assertEqual(self.register(species, form, BOTH), 0, name)
        expected = list(range(len(CATALOG)))
        self.assertEqual(self.bits("wPokedexFormOwned", FORM_BYTES), expected)
        self.assertEqual(self.bits("wPokedexFormSeen", FORM_BYTES), expected)
        self.assertEqual(self.bits("wPokedexOwned", BASE_BYTES), [])

    def test_excluded_and_invalid_selectors_register_nothing(self) -> None:
        self.clear_dex()
        # the three excluded records, a selector past Meowth's two forms, a species with no forms
        for species, form in EXCLUDED + [("MEOWTH", 3), ("PIKACHU", 1)]:
            self.assertEqual(self.register(SPECIES[species], form, BOTH), NOT_IDENTITY, (species, form))
        for label, size in (("wPokedexOwned", BASE_BYTES), ("wPokedexSeen", BASE_BYTES),
                            ("wPokedexFormOwned", FORM_BYTES), ("wPokedexFormSeen", FORM_BYTES)):
            self.assertEqual(self.bits(label, size), [], label)

    def test_add_party_mon_registers_the_spawned_form(self) -> None:
        """The real gift/catch party path: _AddPartyMon reads wSpawnForm."""
        h = self.h
        self.clear_dex()
        if h.read8("wPartyCount") >= 6:   # the lobby party may be full: make one slot
            h.write8("wPartyCount", 5)
            h.write8("wPartySpecies", 0xFF, offset=5)
        count = h.read8("wPartyCount")
        h.write8("wCurPartySpecies", SPECIES["DUGTRIO"])
        h.write8("wCurEnemyLevel", 20)
        h.write8("wSpawnForm", 2)            # Wugtrio
        h.write8("wMonDataLocation", 0x10)   # player party, no naming screen
        h.write8("hIsInBattle", 0)
        out = self.run_routine("_AddPartyMon")
        self.assertTrue(out["F"] & FLAG_C, "_AddPartyMon reported failure")
        self.assertEqual(h.read8("wPartyCount"), count + 1)
        self.assertEqual(self.bits("wPokedexFormOwned", FORM_BYTES), [DEX["DEX_FORM_WUGTRIO"]])
        self.assertEqual(self.bits("wPokedexOwned", BASE_BYTES), [], "Dugtrio itself not credited")
        self.assertEqual(h.read8("wSpawnForm"), 0, "one-shot form request consumed")


if __name__ == "__main__":
    unittest.main()
