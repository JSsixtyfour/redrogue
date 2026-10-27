"""Real-ROM provenance, form, level and ordinary-selector isolation checks."""
import unittest
from pathlib import Path
import sys
from harness import RedRogueHarness
from routine_session import isolated_routine_calls

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import gen_movesets as corpus


class RentalStadiumSetTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, Path(__file__).parent / "artifacts")
        self.h.boot_to_lobby()
        self.calls = isolated_routine_calls(self.h)
        self.calls.__enter__()
        self.species = corpus.parse_species_constants(ROOT / "constants/pokemon_constants.asm")

    def tearDown(self):
        try:
            self.calls.__exit__(None, None, None)
        finally:
            self.h.close()

    def select(self, species, level, tier=31, form=0):
        h = self.h
        h.write8("wEnemyPartyCount", 1)
        h.write8("wPartyGenSlot", 0)
        h.write8("wEnemyMon1", self.species[species])
        h.write8("wEnemyMon1CatchRate", form << 5)
        h.write8("wCurEnemyLevel", level)
        for i in range(4):
            h.write8("wEnemyMon1Moves", 0xee, offset=i)
            h.write8("wEnemyMon1PP", 0xdd, offset=i)
        h.pyboy.register_file.E = tier
        h.call_routine("RentalApplyStadiumSetMoveset")
        return bool(h.last_call_registers["F"] & 0x10)

    def test_origin_bitmap_covers_all_256_ids(self):
        h = self.h
        # The committed bitmap can be checked without requiring the K-drive corpus.
        bank, address = h.symbols.get("RentalStadiumOrigins")
        bitmap = [h.pyboy.memory[bank, address + i] for i in range(32)]
        self.assertGreater(sum(b.bit_count() for b in bitmap), 0)
        for origin in range(256):
            h.pyboy.register_file.E = origin
            h.call_routine("RentalIsStadiumOrigin")
            self.assertEqual(bool(h.last_call_registers["F"] & 0x10),
                             bool(bitmap[origin // 8] & (1 << (origin % 8))))

    def test_real_records_are_stadium_only_with_full_pp(self):
        h = self.h
        bank, address = h.symbols.get("RentalStadiumOrigins")
        bitmap = [h.pyboy.memory[bank, address + i] for i in range(32)]
        index_bank, index_address = h.symbols.get("MovesetSpeciesIndex")
        for species in ("BULBASAUR", "PIKACHU", "EXEGGUTOR", "MEW"):
            sid = self.species[species]
            entry = [h.pyboy.memory[index_bank, index_address + 4 * sid + i] for i in range(4)]
            ptr, count, bank = entry[0] + 256 * entry[1], entry[2], entry[3]
            records = [[h.pyboy.memory[bank, ptr + 8 * i + j] for j in range(8)]
                       for i in range(count)]
            for level in (5, 15, 25, 50, 100):
                with self.subTest(species=species, level=level):
                    eligible = [r for r in records if bitmap[r[5] // 8] & (1 << (r[5] % 8))
                                and r[4] & 31 and r[6] <= level <= r[7]]
                    if not eligible:
                        eligible = [r for r in records if bitmap[r[5] // 8] & (1 << (r[5] % 8))
                                    and r[4] & 31 and r[6] <= level <= r[7] + 10]
                    found = self.select(species, level)
                    self.assertEqual(found, bool(eligible))
                    if found:
                        chosen = h.read_bytes("wEnemyMon1Moves", 4)
                        origin = h.read8("wEnemyMoveOrigins")
                        self.assertTrue(any(r[:4] == chosen and r[5] == origin for r in eligible))
                        for move, pp in zip(chosen, h.read_bytes("wEnemyMon1PP", 4)):
                            if move:
                                self.assertGreater(pp, 0)
                    else:
                        self.assertEqual(h.read_bytes("wEnemyMon1Moves", 4), [0xee] * 4)

    def test_missing_species_form_and_tier_request_fallback(self):
        for species, tier, form in (("BAYLEEF", 31, 0), ("PIKACHU", 0, 0),
                                    ("EXEGGUTOR", 31, 1), ("PIKACHU", 31, 3)):
            with self.subTest(species=species, tier=tier, form=form):
                self.assertFalse(self.select(species, 50, tier, form))
                self.assertEqual(self.h.read_bytes("wEnemyMon1Moves", 4), [0xee] * 4)
                self.assertEqual(self.h.read_bytes("wEnemyMon1PP", 4), [0xdd] * 4)

    def test_ordinary_selector_resets_rental_filter(self):
        h = self.h
        self.assertFalse(self.select("BAYLEEF", 50))
        # Synthetic spec header matching the existing curated-set test convention.
        header = h.address("wEnemyMon2")
        constants = corpus.parse_rgbds_constants(ROOT / "data/trainers/party_specs.asm")
        for i in range(6):
            h.write8("wEnemyMon2", constants["MIX_ELITE"] if i == 4 else 0, offset=i)
        h.write8("wPartyGenSpecPtr", header & 255)
        h.write8("wPartyGenSpecPtr", header >> 8, offset=1)
        h.write8("wEnemyPartyCount", 1)
        h.write8("wPartyGenSlot", 0)
        h.write8("wCurEnemyLevel", 50)
        h.call_routine("PartyGenApplySetMoveset")
        self.assertTrue(h.last_call_registers["F"] & 0x10)
        self.assertEqual(h.read8("wPartyGenCandidates", offset=15), 0)
        self.assertNotEqual(h.read_bytes("wEnemyMon1Moves", 4), [0xee] * 4)

