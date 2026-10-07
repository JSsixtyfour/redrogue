"""Form palettes (GetFormPalette / GetFormPaletteForStruct, func_forms.asm).

Each form record ends in a PAL_*MON byte (form_end's argument). Checks: the ROM
table has one in range for every record, the lookup returns A-Vulpix's CYAN for
both entry points, and form 0 / an unrecorded form return 0 (keep the species
palette). Kept to four call_routine invocations per boot
(project_call_routine_harness_limits).
"""
from __future__ import annotations

from pathlib import Path
import unittest

from harness import RedRogueHarness


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

VULPIX = 0x52          # constants/pokemon_constants.asm
PAL_MEWMON = 0x10      # constants/palette_constants.asm
PAL_CYANMON = 0x13
PAL_GRAYMON = 0x19
FORM_REC_SIZE = 41     # 2 + BASE_DATA_SIZE (28) + name (10) + palette (1)
FORM_REC_PAL = 40
CATCH_RATE_OFFSET = 7  # MON_CATCH_RATE
FORM_SHIFT = 5


class FormPalettesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.harness.boot_to_lobby()

    def tearDown(self) -> None:
        self.harness.close()

    def form_records(self) -> list[tuple[int, int, int]]:
        bank, address = self.harness.symbols.get("FormOverrides")
        rom = self.harness.rom_path.read_bytes()
        offset = bank * 0x4000 + address - 0x4000
        records = []
        while rom[offset] != 0:
            records.append((rom[offset], rom[offset + 1], rom[offset + FORM_REC_PAL]))
            offset += FORM_REC_SIZE
        return records

    def lookup(self, label: str, d: int, e: int) -> int:
        regs = self.harness.pyboy.register_file
        regs.D = d
        regs.E = e
        self.harness.call_routine(label, limit=4000)
        return self.harness.last_call_registers["E"]

    def test_form_palettes(self) -> None:
        records = self.form_records()
        self.assertEqual(len(records), 52)
        for species, form, palette in records:
            self.assertTrue(1 <= form <= 3, (species, form))
            self.assertTrue(PAL_MEWMON <= palette <= PAL_GRAYMON, (species, form, palette))
        self.assertIn((VULPIX, 1, PAL_CYANMON), records)

        self.assertEqual(self.lookup("GetFormPalette", VULPIX, 1), PAL_CYANMON)
        self.assertEqual(self.lookup("GetFormPalette", VULPIX, 0), 0, "form 0 keeps the species palette")
        self.assertEqual(self.lookup("GetFormPalette", VULPIX, 3), 0, "no record: no override")

        # Struct entry: a party mon flagged as Vulpix form 1, other catch-rate bits kept.
        h = self.harness
        h.write8("wPartyMon1", VULPIX)
        h.write8("wPartyMon1", (1 << FORM_SHIFT) | 0x01, offset=CATCH_RATE_OFFSET)
        struct = h.address("wPartyMon1")
        self.assertEqual(self.lookup("GetFormPaletteForStruct", struct >> 8, struct & 0xFF), PAL_CYANMON)

    def test_hall_of_fame_and_trade_carry_forms(self) -> None:
        h = self.harness
        # Party slot 1 is a form-1 mon (other catch-rate flag bits kept).
        h.write8("wPartyMon1", (1 << FORM_SHIFT) | 0x01, offset=CATCH_RATE_OFFSET)

        # Hall of Fame record: the form lands in the record's pad byte 13
        # (HOF_MON_FORM); the bytes after it stay untouched.
        for offset in range(16):
            h.write8("wHallOfFame", 0, offset=offset)
        h.write8("wHoFPartyMonIndex", 0)
        h.write8("wHoFMonSpecies", VULPIX)
        h.write8("wHoFMonLevel", 50)
        h.call_routine("HoFRecordMonInfo", limit=4000)
        record = h.read_bytes("wHallOfFame", 16)
        self.assertEqual(record[0], VULPIX)
        self.assertEqual(record[1], 50)
        self.assertEqual(record[13], 1, "HOF_MON_FORM")
        self.assertEqual(record[14:16], [0, 0])

        # Trade data: the given mon's form from its party struct, the received
        # one from the rogue offer only when the species matches it.
        h.write8("hWhichPokemon", 0)
        h.write8("wInGameTradeGiveMonSpecies", VULPIX)
        h.write8("wInGameTradeReceiveMonSpecies", VULPIX)
        h.write8("wRoguePokemon1", VULPIX)
        h.write8("wRoguePokemonForm1", 1)
        h.call_routine("InGameTrade_PrepareTradeData", limit=20000)
        self.assertEqual(h.read8("wTradedPlayerMonForm"), 1)
        self.assertEqual(h.read8("wTradedEnemyMonForm"), 1)

        h.write8("wPartyMon1", 0x01, offset=CATCH_RATE_OFFSET)   # form 0
        h.write8("wRoguePokemon1", VULPIX ^ 1)                   # not the offer
        h.call_routine("InGameTrade_PrepareTradeData", limit=20000)
        self.assertEqual(h.read8("wTradedPlayerMonForm"), 0)
        self.assertEqual(h.read8("wTradedEnemyMonForm"), 0, "authored trades never inherit an offer form")


if __name__ == "__main__":
    unittest.main(verbosity=2)
