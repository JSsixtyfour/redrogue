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

from test_eevee_form_gate import CHAR_TO_BYTE

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

REPO_ROOT = Path(__file__).resolve().parents[2]
SPECIES = parse_rgbds_constants(REPO_ROOT / "constants" / "pokemon_constants.asm")
DEX = parse_rgbds_constants(REPO_ROOT / "constants" / "pokedex_constants.asm")
EVENTS = parse_rgbds_constants(REPO_ROOT / "constants" / "event_constants.asm")

CATALOG = [(name, SPECIES[species], int(form)) for name, species, form in re.findall(
    r"^\s*dex_form\s+(DEX_FORM_\w+),\s*(\w+),\s*(\d)",
    (REPO_ROOT / "data" / "pokemon" / "dex_forms.asm").read_text(encoding="utf-8"), re.M)]
SLOTS = 56          # NUM_DEX_FORM_SLOTS
FORM_BYTES = SLOTS // 8
BASE_BYTES = 32     # flag_array NUM_POKEMON (252)
OWNED, SEEN, BOTH = 1, 2, 3
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
            return {name: getattr(regs, name) for name in ("A", "D", "E", "F", "HL")}
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

    def test_non_identity_forms_credit_their_base_species(self) -> None:
        """Armored Mewtwo, the fossil ghosts, and selectors with no record (2026-11-03)."""
        cases = EXCLUDED + [("MEOWTH", 3), ("PIKACHU", 1)]
        for species, form in cases:
            self.clear_dex()
            self.assertEqual(self.register(SPECIES[species], form, BOTH), 0, (species, form))
            self.assertEqual(self.bits("wPokedexOwned", BASE_BYTES), [self.base_bit(species)])
            self.assertEqual(self.bits("wPokedexSeen", BASE_BYTES), [self.base_bit(species)])
            self.assertEqual(self.bits("wPokedexFormOwned", FORM_BYTES), [], (species, form))
            self.assertEqual(self.bits("wPokedexFormSeen", FORM_BYTES), [])
            self.assertEqual(self.register(SPECIES[species], form, BOTH), 1, "duplicate")
        # base Mewtwo already owned -> Armored Mewtwo is not new
        self.clear_dex()
        self.register(SPECIES["MEWTWO"], 0, BOTH)
        self.assertEqual(self.register(SPECIES["MEWTWO"], 1, BOTH), 1)

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


    def test_rental_add_is_seen_only(self) -> None:
        """Rentals create through _AddPartyMon with ADD_MON_DEX_SEEN_ONLY ($20)."""
        h = self.h
        for form, seen_label, bit in ((0, "wPokedexSeen", self.base_bit("RATTATA")),
                                      (1, "wPokedexFormSeen", DEX["DEX_FORM_A_RATTATA"])):
            self.clear_dex()
            h.write8("wPartyCount", 5)
            h.write8("wPartySpecies", 0xFF, offset=5)
            h.write8("wCurPartySpecies", SPECIES["RATTATA"])
            h.write8("wCurEnemyLevel", 10)
            h.write8("wSpawnForm", form)
            h.write8("wMonDataLocation", 0x20)
            h.write8("hIsInBattle", 0)
            out = self.run_routine("_AddPartyMon")
            self.assertTrue(out["F"] & FLAG_C)
            self.assertEqual(h.read8("wPartyCount"), 6, "the rental is still delivered")
            self.assertEqual(self.bits(seen_label, BASE_BYTES if form == 0 else FORM_BYTES), [bit])
            for label, size in (("wPokedexOwned", BASE_BYTES), ("wPokedexFormOwned", FORM_BYTES)):
                self.assertEqual(self.bits(label, size), [], f"{label} form {form}")


    # --- Checkpoint C: counts and Oak's rating --------------------------------

    def set_owned_total(self, owned: int, seen: int, pad_noise: bool = True) -> None:
        """First `owned` identities owned (base species first, then forms), first `seen` seen.
        With pad_noise, the 4 bits past NUM_POKEMON and the spare form slots are SET:
        they must never be counted."""
        self.clear_dex()
        base = DEX["NUM_POKEMON"] if "NUM_POKEMON" in DEX else 252
        for label, form_label, n in (("wPokedexOwned", "wPokedexFormOwned", owned),
                                     ("wPokedexSeen", "wPokedexFormSeen", seen)):
            data = [0] * BASE_BYTES
            forms = [0] * FORM_BYTES
            for i in range(n):
                if i < base:
                    data[i >> 3] |= 1 << (i & 7)
                else:
                    j = i - base
                    forms[j >> 3] |= 1 << (j & 7)
            if pad_noise:
                data[-1] |= 0xF0                      # bits 252-255
                forms[-1] |= 0xFF << (len(CATALOG) & 7) & 0xFF  # slots 51-55
            for i, v in enumerate(data):
                self.h.write8(label, v, offset=i)
            for i, v in enumerate(forms):
                self.h.write8(form_label, v, offset=i)

    def be16(self, label: str) -> int:
        hi, lo = self.h.read_bytes(label, 2)
        return hi << 8 | lo

    def test_collection_counts_are_16_bit_and_ignore_padding_bits(self) -> None:
        total = 252 + len(CATALOG)
        for owned, seen in ((0, 0), (1, 3), (254, 255), (255, 256), (256, 300), (total, total)):
            self.set_owned_total(owned, seen)
            out = self.run_routine("DexCountCollection")
            self.assertEqual(self.be16("wDexRatingNumMonsOwned"), owned)
            self.assertEqual(self.be16("wDexRatingNumMonsSeen"), seen)
            self.assertEqual(out["D"] << 8 | out["E"], owned, "de = owned")

    def rating_band(self, owned: int) -> int:
        """Run the real DisplayDexRating down its Hall of Fame branch (no printing)."""
        self.set_owned_total(owned, owned)
        self.h.set_event(EVENTS["EVENT_HALL_OF_FAME_DEX_RATING"])
        self.run_routine("DisplayDexRating")
        band = self.h.read8("hDexRatingBand")
        texts = ["DexRatingText_None", "DexRatingText_Started", "DexRatingText_Quarter",
                 "DexRatingText_Half", "DexRatingText_ThreeQuarters", "DexRatingText_Nearly",
                 "DexRatingText_Complete"]
        self.assertEqual(self.h.read_bytes("wDexRatingText", 4), list(self.rom_bytes(texts[band], 4)),
                         f"HoF copy of band {band}'s text")
        self.assertEqual(self.be16("wDexRatingNumMonsOwned"), owned)
        return band

    def test_rating_bands_at_every_threshold(self) -> None:
        total = 252 + len(CATALOG)
        ceil = lambda pct: (total * pct + 99) // 100
        edges = [(0, 0), (1, 1)]
        for band, pct in ((2, 25), (3, 50), (4, 75), (5, 90)):
            edges += [(ceil(pct) - 1, band - 1), (ceil(pct), band)]
        edges += [(total - 1, 5), (total, 6), (254, 4), (255, 4), (256, 4)]
        for owned, band in edges:
            with self.subTest(owned=owned):
                self.assertEqual(self.rating_band(owned), band)


    # --- Checkpoint D: Forms list / page pieces that need no screen ----------

    def test_forms_page_palette_hook_uses_the_identity_s_form_palette(self) -> None:
        h = self.h
        for name in ("DEX_FORM_A_MEOWTH", "DEX_FORM_P_TAUROS_AQUA", "DEX_FORM_CLODSIRE"):
            ident = DEX[name]
            _, species, form = CATALOG[ident]
            expected = self.run_routine("GetFormPalette", D=species, E=form)["E"]
            h.write8("wRewardInfoSlot", 0x80 | ident)
            try:
                got = self.run_routine("RewardInfoFormPalette")["E"]
            finally:
                h.write8("wRewardInfoSlot", 0)
            self.assertEqual(got, expected, name)
            self.assertNotEqual(got, 0, f"{name} has a palette of its own")
        self.assertEqual(self.run_routine("RewardInfoFormPalette")["E"], 0, "no page up: no override")

    def tiles(self, col: int, row: int, length: int) -> list[int]:
        return self.h.read_bytes("wTileMap", length, offset=row * 20 + col)

    def text_tiles(self, text: str) -> list[int]:
        return [CHAR_TO_BYTE[c] for c in text]

    # --- the Pokedex list: every identity, split by kind -------------------

    def display_rows(self) -> list[tuple[str, str]]:
        """(kind, name) per list row, from the generated table."""
        text = (REPO_ROOT / "data" / "pokemon" / "dex_display_rows.asm").read_text(encoding="utf-8")
        return re.findall(r"^\s*dw DEX_ROW_(SPECIES|REGIONAL|NUMBERED) \| (\w+)", text, re.M)

    def test_display_rows_cover_every_identity_once_in_split_order(self) -> None:
        rows = self.display_rows()
        self.assertEqual(len(rows), 252 + len(CATALOG))
        names = [n for _, n in rows]
        self.assertEqual(len(set(names)), len(names), "an identity appears twice")
        species = [n for k, n in rows if k == "SPECIES"]
        self.assertEqual([DEX[n] for n in species], list(range(1, 253)), "species keep their numbers")
        numbered = [n for k, n in rows if k == "NUMBERED"]
        self.assertEqual(len(numbered), 16)  # +Honchkrow, Ursaluna 2026-11-07, Overqwil 2026-11-10
        self.assertEqual([k for k, _ in rows[-16:]], ["NUMBERED"] * 16, "numbered species come last")
        for name in ("DEX_FORM_ESPEON", "DEX_FORM_UMBREON", "DEX_FORM_CLODSIRE", "DEX_FORM_PERRSERKER"):
            self.assertIn(name, numbered)
        # each regional form directly follows its base species (or a sibling form)
        for i, (kind, name) in enumerate(rows):
            if kind != "REGIONAL":
                continue
            _, base, _ = CATALOG[DEX[name]]
            j = i - 1
            while rows[j][0] == "REGIONAL":
                j -= 1
            self.assertEqual(SPECIES[rows[j][1][len("DEX_"):]], base, name)

    def test_display_rows_file_is_generated_and_current(self) -> None:
        import subprocess, sys
        result = subprocess.run([sys.executable, str(REPO_ROOT / "tools" / "gen_dex_display_rows.py"), "--check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def draw_row(self, row: int) -> None:
        for i in range(40):
            self.h.write8("wTileMap", 0x7F, offset=2 * 20 + i)  # rows 2-3 blank
        hl = self.h.address("wTileMap") + 3 * 20 + 1  # hlcoord 1, 3
        self.run_routine("DexListDrawRow", D=row >> 8, E=row & 0xFF, HL=hl)

    def test_list_rows_by_kind(self) -> None:
        rows = [n for _, n in self.display_rows()]
        blank = [0x7F] * 3
        cases = [  # (row name, registration, number tiles above, name)
            ("DEX_MEOWTH", (SPECIES["MEOWTH"], 0), self.text_tiles(f"{DEX['DEX_MEOWTH']:03d}"), "MEOWTH"),
            ("DEX_FORM_A_MEOWTH", (SPECIES["MEOWTH"], 1), blank, "A-MEOWTH"),
            ("DEX_FORM_ESPEON", (SPECIES["JOLTEON"], 1),
             self.text_tiles(f"{253 + rows[-16:].index('DEX_FORM_ESPEON'):03d}"), "ESPEON"),
        ]
        for name, (species, form), number, label in cases:
            row = rows.index(name)
            for owned, seen in ((False, False), (False, True), (True, True)):
                with self.subTest(row=name, owned=owned, seen=seen):
                    self.clear_dex()
                    if seen:
                        self.register(species, form, BOTH if owned else SEEN)
                    self.draw_row(row)
                    self.assertEqual(self.tiles(1, 2, 3), number, "number row")
                    self.assertEqual(self.tiles(3, 3, 1), [0x72 if owned else 0x7F], "owned ball")
                    shown = label if seen else "-" * len(label)
                    self.assertEqual(self.tiles(4, 3, len(shown)), self.text_tiles(shown), "name")
                    self.assertEqual(self.h.read8("wFormContextSpecies"), 0, "no form context left pending")

    def test_list_length_follows_the_last_seen_row(self) -> None:
        rows = [n for _, n in self.display_rows()]
        def count() -> int:
            return self.run_routine("DexListRowCount")["HL"]
        self.clear_dex()
        self.assertEqual(count(), 1, "nothing seen: one row of dashes")
        self.register(SPECIES["MEOWTH"], 2, SEEN)
        self.assertEqual(count(), rows.index("DEX_FORM_G_MEOWTH") + 1)
        self.register(SPECIES["QWILFISH"], 2, SEEN)  # Overqwil, the last numbered row
        self.assertEqual(count(), len(rows))

    def load_header(self, species: int, form: int) -> list[int]:
        """GetMonHeader with an explicit context (form 0 = base); returns the TM/HM learnset."""
        h = self.h
        h.write8("wMonHFormSpecies", 0)
        h.write8("wMonHForm", 0)
        h.write8("wFormContextSpecies", species)
        h.write8("wFormContextForm", form)
        h.write8("wCurSpecies", species)
        self.run_routine("GetMonHeader")
        return h.read_bytes("wMonHLearnset", 7)

    def test_form_move_page_tm_list_is_the_form_s(self) -> None:
        """PokedexFormMoveViewer leaves wMonHForm/wMonHFormSpecies naming the form, so
        the TMHM view's own GetMonHeader reloads (LearndexTMHMBitSet) keep the form."""
        h = self.h
        h.pyboy.memory[h.address("wLoadedMon") + 7] = 0  # no fusion/variant instance flags
        differing = 0
        for name, species, form in CATALOG:
            base = self.load_header(species, 0)
            own = self.load_header(species, form)   # leaves the viewer's state behind
            self.assertEqual(h.read8("wMonHForm"), form, name)
            self.assertEqual(h.read8("wMonHFormSpecies"), species, name)
            if own == base:
                continue
            differing += 1
            for index in range(55):  # NUM_TM_HM
                expect = own[index >> 3] >> (index & 7) & 1
                got = not (self.run_routine("LearndexTMHMBitSet", A=index)["F"] & 0x80)  # nz = can learn
                self.assertEqual(int(got), expect, f"{name} TM/HM #{index}")
            self.assertEqual(h.read8("wMonHForm"), form, f"{name}: the reloads kept the form")
        self.assertGreater(differing, 10, "most forms have their own TM/HM list")


if __name__ == "__main__":
    unittest.main()
