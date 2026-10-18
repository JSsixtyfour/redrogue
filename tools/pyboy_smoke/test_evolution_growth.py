"""Evolution must preserve the level represented by these families' EXP."""
from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT


class EvolutionGrowthTest(HarnessTestCase):
    def check_level(self, name: str, experience: int, level: int) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        species = parse_rgbds_constants(REPO_ROOT / "constants/pokemon_constants.asm")
        h.write8("wLoadedMonSpecies", species[name])
        h.write8("wFormContextSpecies", species[name])
        h.write8("wFormContextForm", 0)
        for offset, byte in enumerate(experience.to_bytes(3, "big")):
            h.write8("wLoadedMonExp", byte, offset)

        # Capture D at the calculator's RET, before the probe restores state.
        bank = h.symbols.bank("CalcLevelFromExperience")
        address = h.address("CalcExperience") - 1
        rom = h.rom_path.read_bytes()
        self.assertEqual(rom[bank * 0x4000 + address - 0x4000], 0xC9)
        observed = []
        h.pyboy.hook_register(
            bank, address, lambda _: observed.append(h.pyboy.register_file.D), None
        )
        try:
            h.probe_routine_until("CalcLevelFromExperience", lambda: bool(observed))
        finally:
            h.pyboy.hook_deregister(bank, address)
        self.assertEqual(observed, [level])

    def test_piloswine_evolution_keeps_level_44(self):
        self.check_level("MAMOSWINE", 106480, 44)

    def test_misdreavus_evolution_keeps_level_40(self):
        self.check_level("MISMAGIUS", 51200, 40)

    def test_piloswine_evolution_keeps_level_100(self):
        self.check_level("MAMOSWINE", 1250000, 100)

    def test_misdreavus_evolution_keeps_level_100(self):
        self.check_level("MISMAGIUS", 800000, 100)
