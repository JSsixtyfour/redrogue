"""Form-aware curated sets (MSRC_SET), driven on the real ROM.

A mon whose form index is nonzero reads ONLY its own form's records, found
through MovesetFormIndex (data/trainers/movesets.asm, tools/gen_movesets.py),
and never its base species' list: a base set can carry moves the form cannot
learn. A form with no records takes the caller's fallback (carry clear, moves
untouched), even when its base species has plenty.

The expected answer is computed from the ROM's own tables (MovesetFormIndex,
MovesetSpeciesIndex, the 8-byte records), so the test checks the lookup, not a
copy of the data. Every found case also asserts the chosen record is NOT one
only the base species owns, which is the bug this closes.
"""
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).parent / "artifacts"
SPECIES = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
PARTY = parse_rgbds_constants(ROOT / "constants/party_spec_constants.asm")
SLACK = parse_rgbds_constants(ROOT / "constants/balance_constants.asm")["SET_LEVEL_SLACK_BELOW"]
TIERS = 0x1F  # TIER_BAD..TIER_ELITE (1 << 0..4); the parser skips `1 << n` lines
ENTRY = PARTY["MOVESET_FORM_ENTRY_SIZE"]


class FormCuratedSetTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.boot_fight2(seed=1)

    def tearDown(self):
        self.h.close()

    # --- oracle: read the ROM's tables directly ------------------------------
    def _records(self, ptr, count, bank):
        mem = self.h.pyboy.memory
        return [[mem[bank, ptr + 8 * i + j] for j in range(8)] for i in range(count)]

    def form_records(self, species, form):
        mem = self.h.pyboy.memory
        bank, addr = self.h.symbols.get("MovesetFormIndex")
        while mem[bank, addr]:
            e = [mem[bank, addr + i] for i in range(ENTRY)]
            if e[0] == SPECIES[species] and e[1] == form:
                return self._records(e[2] + 256 * e[3], e[4], e[5])
            addr += ENTRY
        return None

    def base_records(self, species):
        mem = self.h.pyboy.memory
        bank, addr = self.h.symbols.get("MovesetSpeciesIndex")
        e = [mem[bank, addr + 4 * SPECIES[species] + i] for i in range(4)]
        return self._records(e[0] + 256 * e[1], e[2], e[3]) if e[2] else []

    @staticmethod
    def eligible(records, level):
        ok = [r for r in records if r[4] & TIERS and r[6] <= level <= r[7]]
        return ok or [r for r in records if r[4] & TIERS and r[6] <= level <= r[7] + SLACK]

    # --- drive PartyGenApplySetMovesetMask ----------------------------------
    def select(self, species, form, level):
        h = self.h
        h.park_before_hijack()
        h.write8("wEnemyPartyCount", 1)
        h.write8("wPartyGenSlot", 0)
        h.write8("wEnemyMon1", SPECIES[species])
        h.write8("wEnemyMon1CatchRate", form << 5)
        h.write8("wCurEnemyLevel", level)
        for i in range(4):
            h.write8("wEnemyMon1Moves", 0xEE, offset=i)
        verdict = []
        h.register_hook("PartyGenApplySetMovesetMask.noMatch",
                        lambda ctx: verdict.append("none"))
        h.register_hook("PartyGenApplySetMovesetMask.formFound",
                        lambda ctx: verdict.append("form"))
        h.pyboy.register_file.E = TIERS
        h.call_routine("PartyGenApplySetMovesetMask", limit=4000)
        return verdict, h.read_bytes("wEnemyMon1Moves", 4)

    def check_form_draws_own_sets(self, species, form, level):
        own = self.form_records(species, form)
        self.assertIsNotNone(own, f"{species} form {form} has no MovesetFormIndex entry")
        eligible = self.eligible(own, level)
        self.assertTrue(eligible, f"pick a level {species} form {form} has sets near")
        verdict, moves = self.select(species, form, level)
        self.assertEqual(verdict, ["form"], "expected exactly one form-index hit")
        self.assertIn(moves, [r[:4] for r in eligible])
        base_only = {tuple(r[:4]) for r in self.base_records(species)} \
            - {tuple(r[:4]) for r in own}
        self.assertNotIn(tuple(moves), base_only, "a form drew its base species' set")

    def test_alolan_raichu_draws_its_own_sets(self):
        self.check_form_draws_own_sets("RAICHU", 1, 50)

    def test_umbreon_and_glaceon_draw_their_own_sets(self):
        self.check_form_draws_own_sets("JOLTEON", 2, 50)   # Umbreon
        self.check_form_draws_own_sets("VAPOREON", 1, 50)  # Glaceon

    def test_galarian_slowbro_at_a_band_edge(self):
        self.check_form_draws_own_sets("SLOWBRO", 1, 42)

    def test_form_without_sets_falls_back_instead_of_borrowing_base_sets(self):
        # A (species, form) with no MovesetFormIndex entry whose base species has sets.
        # Toedscool (TENTACOOL form 1) was the example until the 2026-10-27 revision gave
        # every shipped form sets, so look for an unused form index instead.
        species, form = next((sp, f) for sp in ("TENTACOOL", "PIKACHU", "EXEGGUTOR", "SLOWBRO") for f in (3, 2, 1)
                             if self.form_records(sp, f) is None
                             and self.eligible(self.base_records(sp), 25))
        self.assertIsNone(self.form_records(species, form))
        self.assertTrue(self.eligible(self.base_records(species), 25),
                        f"control: base {species} must have a set at 25, or this proves nothing")
        # The selector has no form bounds check: any nonzero form scans MovesetFormIndex
        # to its end, so an unused index takes the same path a set-less real form would.
        scanned = self.h.hook_flag("PartyGenApplySetMovesetMask.formLookup")
        base_read = self.h.hook_flag("PartyGenApplySetMovesetMask.haveIndex")
        verdict, moves = self.select(species, form, 25)
        self.assertEqual(verdict, ["none"])
        self.assertEqual(scanned["count"], 1, "the form index scan did not run")
        self.assertEqual(base_read["count"], 0, "a set-less form read a species index")
        self.assertEqual(moves, [0xEE] * 4, "a fallback must not write moves")

    def test_plain_form_still_uses_the_species_index(self):
        eligible = self.eligible(self.base_records("RAICHU"), 50)
        self.assertTrue(eligible)
        verdict, moves = self.select("RAICHU", 0, 50)
        self.assertEqual(verdict, [], "form 0 must not touch MovesetFormIndex")
        self.assertIn(moves, [r[:4] for r in eligible])


if __name__ == "__main__":
    unittest.main()
