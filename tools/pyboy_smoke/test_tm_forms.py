"""TM checks use the selected party mon, independent of the last loaded header."""
from pathlib import Path
import re
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")


class TMFormsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = RedRogueHarness(ROOT, Path(__file__).parent / "artifacts")
        cls.h.boot_to_lobby()

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def call(self, label):
        h = self.h
        regs, mem = h.pyboy.register_file, h.pyboy.memory
        names = ("A", "B", "C", "D", "E", "F", "HL", "PC", "SP")
        saved = {name: getattr(regs, name) for name in names}
        old_bank, old_ie = h.read8("hLoadedROMBank"), mem[0xFFFF]
        stub = h.address("wStringBuffer") + 16
        old_stub = list(mem[stub:stub + 2])
        bank, address = h.symbols.get(label)
        mem[stub:stub + 2] = [0x18, 0xFE]
        mem[0xFFFF] = 0
        if bank:
            h.write8("hLoadedROMBank", bank)
            mem[0x2000] = bank
        sp = (saved["SP"] - 2) & 0xFFFF
        mem[sp:sp + 2] = [stub & 255, stub >> 8]
        regs.SP, regs.PC = sp, address
        try:
            for _ in range(10):
                h.pyboy.tick()
                if regs.PC == stub:
                    break
            self.assertEqual(regs.PC, stub, label)
            self.assertEqual(regs.SP, (sp + 2) & 0xFFFF, label)
            return regs.C
        finally:
            mem[0xFFFF] = old_ie
            mem[stub:stub + 2] = old_stub
            h.write8("hLoadedROMBank", old_bank)
            mem[0x2000] = old_bank
            for name, value in saved.items():
                setattr(regs, name, value)

    def header(self, species, form):
        h = self.h
        h.write8("wCurSpecies", species)
        h.write8("wFormContextSpecies", species)
        h.write8("wFormContextForm", form)
        self.call("GetMonHeader")
        return list(h.pyboy.memory[h.address("wMonHLearnset"):h.address("wMonHLearnset") + 7])

    def check_all(self, primary, form, ambient, ambient_form, secondary=None, secondary_form=0):
        h = self.h
        primary, ambient = SPECIES[primary], SPECIES[ambient]
        expected = self.header(primary, form)
        if secondary:
            secondary = SPECIES[secondary]
            other = self.header(secondary, secondary_form)
            expected = [a | b for a, b in zip(expected, other)]
        h.write8("wPartyCount", 2)
        h.write8("wPartySpecies", primary)
        h.write8("wPartySpecies", ambient, offset=1)
        # Slot 0 is the selected mon; slot 1 models the last menu row drawn.
        h.write8("wPartyMon1Species", primary)
        h.write8("wPartyMon1CatchRate", (form << 5) | (2 if secondary else 0))
        h.write8("hWhichPokemon", 0)
        h.write8("wCurPartySpecies", primary)
        h.write8("wFusionSecondarySpecies", secondary or 0)
        h.write8("wFusionSecondaryForm", secondary_form)
        bank, address = h.symbols.get("TechnicalMachines")
        moves = [h.pyboy.memory[bank, address + i] for i in range(55)]
        for i, move in enumerate(moves):
            with self.subTest(machine=i + 1):
                self.header(ambient, ambient_form)
                h.write8("wMoveNum", move)
                result = self.call("CanLearnTM")
                self.assertEqual(bool(result), bool(expected[i >> 3] & (1 << (i & 7))))
                self.assertEqual(h.read8("wMonHForm"), form)
                self.assertEqual(h.read8("wMonHIndex"), primary)
                self.assertEqual(h.read8("wCurSpecies"), primary)
                self.assertEqual(h.read8("wMoveNum"), move)

    def test_sylveon_after_other_species(self):
        self.check_all("VAPOREON", 2, "MAGIKARP", 0)

    def test_sylveon_after_base_vaporeon(self):
        self.check_all("VAPOREON", 2, "VAPOREON", 0)

    def test_base_vaporeon_after_sylveon(self):
        self.check_all("VAPOREON", 0, "VAPOREON", 2)

    def test_form_primary_fusion(self):
        self.check_all("VAPOREON", 2, "MAGIKARP", 0, "MAGIKARP")

    def test_form_secondary_fusion(self):
        self.check_all("MAGIKARP", 0, "VAPOREON", 0, "VAPOREON", 2)

    def test_every_authored_form(self):
        table = (ROOT / "data/pokemon/forms.asm").read_text()
        files = re.findall(r'INCLUDE "(data/pokemon/forms/[^\"]+)"', table)
        self.assertTrue(files)
        for filename in files:
            source = (ROOT / filename).read_text()
            match = re.search(r'^\s*form_record\s+(\w+),\s*(\d+)', source, re.MULTILINE)
            self.assertIsNotNone(match, filename)
            species, form = match.group(1), int(match.group(2))
            with self.subTest(form=filename):
                self.check_all(species, form, "MAGIKARP", 0)


if __name__ == "__main__":
    unittest.main()
