"""The special collection (custom_functions/special_collection.asm, RECORDS_PC_PLAN_2026-11-03.md).

Credit only on real acquisition: the main trap is that an optional encounter runs
ApplySpecialForm on wEnemyMon at battle start, when the player has merely met it.
The page's shadow is a tile transform, so every pixel must end up color 0 or 3.
"""
import os
import re
import unittest

import test_dex_forms
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
from test_eevee_form_gate import CHAR_TO_BYTE
from test_save_header import ARTIFACTS, REPO_ROOT

SPECIES = test_dex_forms.SPECIES
DEX = test_dex_forms.DEX
MAPS = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")
SOURCE = (REPO_ROOT / "custom_functions" / "special_collection.asm").read_text(encoding="utf-8")
DATA = (REPO_ROOT / "data" / "pokemon" / "special_collection.asm").read_text(encoding="utf-8")
PACKAGES = re.findall(r"^\s*special_package\s+(\w+),\s*(SPECIAL_\w+)", SOURCE, re.M)
BIT_SPECIAL = 0x08
NUM = sum(1 for name in DEX if name.startswith("SPECIAL_"))
CATCH_RATE = 7


def tiles(text):
    """Rendered width: 's and friends are one tile, # would be four."""
    text = re.sub(r"'[a-z]", "x", text)
    return len(text) + 3 * text.count("#")


class DataTest(unittest.TestCase):
    def entries(self):
        return re.findall(r"^\s*special_entry\s+(SPECIAL_\w+),\s*(\w+),\s*(\w+),\s*(\w+),\s*\.(\w+),\s*\.(\w+),\s*\.(\w+)",
                          DATA, re.M)

    def string(self, label):
        """A local label's lines (db or next, up to the @)."""
        match = re.search(r"^\.%s\s+db\s+\"([^\"]*)\"" % label, DATA, re.M)
        if match:
            return match.group(1).rstrip("@").split("<NEXT>")
        match = re.search(r"^\.%s\n((?:\s+(?:db|next)\s+\"[^\"]*\"\n?)+)" % label, DATA, re.M)
        self.assertIsNotNone(match, label)
        return [line.rstrip("@") for line in re.findall(r"\"([^\"]*)\"", match.group(1))]

    def test_every_identity_has_a_row_in_id_order_and_fits_the_page(self):
        rows = self.entries()
        self.assertEqual(len(rows), NUM)
        self.assertEqual([DEX[r[0]] for r in rows], list(range(NUM)))
        self.assertLessEqual(NUM, 16, "wSpecialCollected is 2 B; see WRAM_BIBLE")
        for _, _, _, _, name, found, effect in rows:
            lines = self.string(name)
            self.assertEqual(len(lines), 1, name)
            self.assertLessEqual(tiles(lines[0]), 18, name)
            where = self.string(found)
            self.assertLessEqual(len(where), 3, found)
            for line in where:
                self.assertLessEqual(tiles(line), 10, (found, line))
            what = self.string(effect)
            self.assertLessEqual(len(what), 5, effect)
            for line in what:
                self.assertLessEqual(tiles(line), 18, (effect, line))

    def test_every_capability_species_is_in_the_collection(self):
        """A new SpecialFormCaps row with no collection row would silently never be collected."""
        caps = (REPO_ROOT / "custom_functions" / "func_special_form.asm").read_text(encoding="utf-8")
        table = re.findall(r"^\s*db (\w+),\s+\(?1 << SF", caps, re.M)
        types = (REPO_ROOT / "custom_functions" / "bridge_effects_extended.asm").read_text(encoding="utf-8")
        table += re.findall(r"^\s*db (ONIX|SNORLAX|PSYDUCK|GOLDUCK),", types, re.M)
        listed = {species for species, _ in PACKAGES}
        self.assertTrue(table)
        self.assertEqual(set(table) - listed, set())

    def test_every_identity_has_a_way_in(self):
        ids = {DEX[identity] for _, identity in PACKAGES}
        ids.add(DEX["SPECIAL_ARMORED_MEWTWO"])
        self.assertEqual(ids, set(range(NUM)))


class CreditTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS)
        self.addCleanup(self.h.close)
        self.h.boot_to_lobby()
        self.runner = test_dex_forms.DexFormsTest()
        self.runner.h = self.h
        self.clear()

    def clear(self):
        self.h.write8("wSpecialCollected", 0)
        self.h.write8("wSpecialCollected", 0, offset=1)

    def collected(self):
        low, high = self.h.read_bytes("wSpecialCollected", 2)
        word = low | high << 8
        return [i for i in range(16) if word >> i & 1]

    def party_struct(self, species, flags=0, slot=0):
        h = self.h
        base = h.address("wPartyMon1") + slot * 44
        h.pyboy.memory[base] = species
        h.pyboy.memory[base + CATCH_RATE] = flags
        return base

    def finalize(self, species, finalizer):
        """The real delivery path: the mon in the last party slot, then the gift's finalizer."""
        h = self.h
        count = h.read8("wPartyCount")
        self.party_struct(species, 0, count - 1)
        h.write8("wAddedToParty", 1)
        self.runner.run_routine("BridgeFinalizeGiftMonFar", E=finalizer)

    def test_each_package_through_apply_special_form(self):
        for species, identity in PACKAGES:
            with self.subTest(species=species):
                self.clear()
                base = self.party_struct(SPECIES[species])
                self.runner.run_routine("ApplySpecialForm", D=base >> 8, E=base & 0xFF)
                self.assertEqual(self.collected(), [DEX[identity]])

    def test_gift_finalizers_credit_their_identity_and_tutor_gifts_nothing(self):
        cases = ((("CUBONE", 1), "SPECIAL_THICK_CLUB"), (("FARFETCHD", 2), "SPECIAL_ALWAYS_CRIT"),
                 (("NIDORINA", 3), "SPECIAL_QUICK_CLAW"), (("ARCANINE", 4), "SPECIAL_INTIMIDATE"),
                 (("CHARIZARD", 9), "SPECIAL_DRAGON"), (("MACHOP", 1), "SPECIAL_NO_GUARD"),
                 (("BUTTERFREE", 1), "SPECIAL_PINK"))
        for (species, finalizer), identity in cases:
            with self.subTest(species=species):
                self.clear()
                self.finalize(SPECIES[species], finalizer)
                self.assertEqual(self.collected(), [DEX[identity]])
        for species, finalizer in (("EKANS", 5), ("ODDISH", 6), ("BULBASAUR", 7), ("SQUIRTLE", 8)):
            with self.subTest(species=species):
                self.clear()
                self.finalize(SPECIES[species], finalizer)
                self.assertEqual(self.collected(), [])

    def test_a_boxed_gift_credits_too(self):
        h = self.h
        h.write8("wAddedToParty", 0)
        base = h.address("wBoxMon1")
        h.pyboy.memory[base] = SPECIES["HITMONCHAN"]
        h.pyboy.memory[base + CATCH_RATE] = 0
        self.runner.run_routine("BridgeFinalizeGiftMonFar", E=1)
        self.assertEqual(self.collected(), [DEX["SPECIAL_MYSTIC"]])

    def enemy(self, species, flags):
        h = self.h
        h.write8("wEnemyMonSpecies", species)
        h.write8("wEnemyMonSpecies2", species)
        h.write8("wEnemyMonCatchRate", flags)

    def test_meeting_an_optional_encounter_credits_nothing_but_catching_it_does(self):
        h = self.h
        self.enemy(SPECIES["SNORLAX"], 0)
        base = h.address("wEnemyMon")
        self.runner.run_routine("ApplySpecialForm", D=base >> 8, E=base & 0xFF)
        self.assertTrue(h.read8("wEnemyMonCatchRate") & BIT_SPECIAL, "the battle's mon does get the package")
        self.assertEqual(self.collected(), [], "only met so far")
        self.runner.run_routine("DexRegisterCaught")
        self.assertEqual(self.collected(), [DEX["SPECIAL_ICE"]])

    def test_catching_an_ordinary_mon_credits_nothing(self):
        self.enemy(SPECIES["SNORLAX"], 0)
        self.runner.run_routine("DexRegisterCaught")
        self.assertEqual(self.collected(), [])

    def test_form_specials_credit_only_when_owned(self):
        for species, identity in (("MEWTWO", "SPECIAL_ARMORED_MEWTWO"),):
            with self.subTest(species=species):
                self.clear()
                self.runner.register(SPECIES[species], 1, test_dex_forms.SEEN)
                self.assertEqual(self.collected(), [], "a boss seen in battle")
                self.runner.register(SPECIES[species], 1, test_dex_forms.OWNED)
                self.assertEqual(self.collected(), [DEX[identity]])
        for species, form in (("MEWTWO", 0), ("MEOWTH", 1), ("MEOWTH", 3), ("PIKACHU", 1),
                              ("AERODACTYL", 1), ("KABUTOPS", 1)):
            with self.subTest(species=species, form=form):
                self.clear()
                self.runner.register(SPECIES[species], form, test_dex_forms.BOTH)
                self.assertEqual(self.collected(), [], "base form, Dex form, no record, or a fossil ghost")

    def add_party_mon(self, species, form, location):
        h = self.h
        h.write8("wPartyCount", 5)
        h.write8("wPartySpecies", 0xFF, offset=5)
        h.write8("wCurPartySpecies", SPECIES[species])
        h.write8("wCurEnemyLevel", 50)
        h.write8("wSpawnForm", form)
        h.write8("wMonDataLocation", location)
        h.write8("hIsInBattle", 0)
        self.runner.run_routine("_AddPartyMon")

    def test_the_armored_mewtwo_gift_path_credits_and_a_rental_does_not(self):
        self.add_party_mon("MEWTWO", 1, 0x20)  # ADD_MON_DEX_SEEN_ONLY: a rental
        self.assertEqual(self.collected(), [])
        self.add_party_mon("MEWTWO", 1, 0x10)  # the trade's _AddPartyMon
        self.assertEqual(self.collected(), [DEX["SPECIAL_ARMORED_MEWTWO"]])

    def test_ghost_fusion_and_plain_flags_are_no_identity(self):
        for flags in (0x01, 0x02, 0x04):
            base = self.party_struct(SPECIES["PIKACHU"], flags)
            self.runner.run_routine("SpecialCreditStruct", D=base >> 8, E=base & 0xFF)
            self.assertEqual(self.collected(), [], flags)

    def test_the_flags_live_through_a_run_reset_and_a_save(self):
        h = self.h
        base = self.party_struct(SPECIES["DITTO"], BIT_SPECIAL)
        self.runner.run_routine("SpecialCreditStruct", D=base >> 8, E=base & 0xFF)
        h.call_routine("RogueResetRunState")
        self.assertEqual(self.collected(), [DEX["SPECIAL_SUPER_DITTO"]])
        h.call_routine("SaveGameData")
        self.clear()
        h.call_routine("LoadMainData")
        self.assertEqual(self.collected(), [DEX["SPECIAL_SUPER_DITTO"]])

    def test_a_palette_form_byte_names_the_palette(self):
        palette = parse_rgbds_constants(REPO_ROOT / "constants" / "palette_constants.asm")["PAL_PINKMON"]
        self.assertEqual(self.runner.run_routine("GetFormPalette", D=SPECIES["BUTTERFREE"], E=0x80 | palette)["E"], palette)
        self.assertEqual(self.runner.run_routine("GetFormPalette", D=SPECIES["PIKACHU"], E=0)["E"], 0)


class PageTest(unittest.TestCase):
    """The real Dorm PC -> RECORDS -> SPECIAL FORMS, every entry in both states."""

    cgb = False

    def setUp(self):
        self.h = RedRogueHarness(REPO_ROOT, ARTIFACTS, cgb_mode=self.cgb)
        self.addCleanup(self.h.close)
        self.h.boot_debug1(MAPS["SILPH_CO_DORM"])

    def press(self, button, settle=8):
        self.h.tap(button, 4)
        self.h.tick(settle)

    def step(self, direction):
        h = self.h
        h.pyboy.button_press(direction)
        h.tick(3)
        h.pyboy.button_release(direction)
        h.tick(30)

    def open_list(self):
        h = self.h
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (1, 7), "spawn moved; re-plan the walk")
        for _ in range(10):
            if h.read8("wYCoord") <= 2:
                break
            self.step("up")
        self.step("left")
        self.step("up")
        self.press("a", 60)
        for _ in range(40):
            if h.read8("wMaxMenuItem") >= 4 and h.read8("wTopMenuItemY") == 2:
                break
            self.press("a", 20)
        for _ in range(3):
            self.press("down")       # RECORDS
        self.press("a", 30)
        for _ in range(3):
            self.press("down")       # SPECIAL FORMS
        self.press("a", 60)

    def text(self, value):
        return [CHAR_TO_BYTE[c] if not c.isdigit() else 0xF6 + int(c) for c in value]

    def pic_rows(self):
        data = self.h.pyboy.memory[0x9000:0x9000 + 49 * 16]
        return [(data[i], data[i + 1]) for i in range(0, len(data), 2)]

    @staticmethod
    def pixels(rows):
        """{(x, y)} of the non-white pixels. Tiles run down each 7-tile column."""
        found = set()
        for index, (a, b) in enumerate(rows):
            column, y = index // 56, index % 56
            for bit in range(8):
                if (a | b) >> (7 - bit) & 1:
                    found.add((column * 8 + bit, y))
        return found

    @staticmethod
    def expected_shadow(solid):
        """SpecialShadowPic's rule: opaque on both sides horizontally and vertically."""
        out = set(solid)
        for x in range(56):
            for y in range(56):
                across = [p for p, q in solid if q == y]
                down = [q for p, q in solid if p == x]
                if across and down and min(across) < x < max(across) and min(down) < y < max(down):
                    out.add((x, y))
        return out

    def shot(self, name):
        self.h.tick(3, render=True)
        ARTIFACTS.mkdir(exist_ok=True)
        suffix = "cgb" if self.cgb else "dmg"
        self.h.pyboy.screen.image.save(ARTIFACTS / f"special_{name}_{suffix}.png")

    def test_list_then_every_page_as_a_shadow_and_then_collected(self):
        h = self.h
        h.write8("wSpecialCollected", 0)
        h.write8("wSpecialCollected", 0, offset=1)
        self.open_list()
        self.shot("list_empty")
        self.assertEqual(h.read_bytes("wTileMap", 13, 1), self.text("SPECIAL FORMS"))
        self.assertEqual(h.read_bytes("wTileMap", 5, 15), [0x7F, 0xF6] + self.text("/15"))
        self.assertEqual(h.read_bytes("wTileMap", 5, 22), self.text("?????"))
        self.assertEqual(h.read8("wMaxMenuItem"), NUM - 1)
        shadows = {}
        for identity in range(NUM):
            self.press("a", 120)
            rows = self.pic_rows()
            self.assertTrue(any(a or b for a, b in rows), f"{identity}: no pic at all")
            self.assertTrue(all(a == b for a, b in rows), f"{identity}: not a flat shadow")
            shadows[identity] = self.pixels(rows)
            self.assertEqual(h.read_bytes("wTileMap", 5, 9 * 20 + 1), self.text("?????"), identity)
            self.shot(f"{identity:02d}_shadow")
            self.press("b", 60)
            self.assertEqual(h.read8("hCurrentMenuItem"), identity, "the cursor comes back")
            self.press("down")
        for _ in range(NUM):
            self.press("up")
        h.write8("wSpecialCollected", 0xFF)
        h.write8("wSpecialCollected", 0xFF, offset=1)
        for identity in range(NUM):
            self.press("a", 150)
            rows = self.pic_rows()
            self.assertFalse(all(a == b for a, b in rows), f"{identity}: still a shadow")
            solid = self.pixels(rows)
            self.assertEqual(shadows[identity], self.expected_shadow(solid), f"{identity}: the fill")
            self.assertGreater(len(shadows[identity]), len(solid), f"{identity}: nothing was filled")
            self.assertEqual(h.read_bytes("wTileMap", 9, 2 * 20 + 9), self.text("FOUND AT:"), identity)
            self.shot(f"{identity:02d}_collected")
            self.press("b", 60)
            self.press("down")
        self.shot("list_full")
        self.assertEqual(h.read_bytes("wTileMap", 5, 15), [0xF7, 0xF6 + 5] + self.text("/15"))
        self.assertEqual(h.read_bytes("wTileMap", 14, 22), self.text("ARMORED MEWTWO"))
        self.assertFalse(h.hook_errors, h.hook_errors)

    def test_leaving_restores_the_dorm_tileset_and_the_room_menu(self):
        h = self.h
        before = bytes(h.pyboy.memory[0x9000:0x9000 + 0x60 * 16])
        h.write8("wSpecialCollected", 0x01)
        self.open_list()
        self.press("a", 120)
        self.assertNotEqual(bytes(h.pyboy.memory[0x9000:0x9000 + 0x60 * 16]), before, "vacuous: no pic drawn")
        self.press("b", 60)
        flags = h.read8("hUILayoutFlags")
        self.press("b", 60)      # the list -> RECORDS, reloaded
        self.shot("back_at_records")
        self.assertEqual(h.read8("wMaxMenuItem"), 4)
        self.assertEqual(h.read8("hUILayoutFlags") & 0x06, 0, f"layout flags left set (were {flags:02x})")
        self.press("b", 30)      # RECORDS -> room menu
        self.press("b", 120)     # LOG OFF
        h.tick(60, render=True)
        after = bytes(h.pyboy.memory[0x9000:0x9000 + 0x60 * 16])
        bad = [t for t in range(0x60) if after[t * 16:t * 16 + 16] != before[t * 16:t * 16 + 16]]
        self.assertEqual(bad, [], "Dorm tiles differ after the pages")


if __name__ == "__main__":
    unittest.main()
