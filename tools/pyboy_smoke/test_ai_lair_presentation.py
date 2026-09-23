"""Checkpoint 9 runtime contracts for the AI Lair presentation."""

from test_smoke import HarnessTestCase


APPEARANCE_COUNT = 31  # data/player/appearance.asm; build-enforced by assert_table_length
APPEARANCE_STRIDE = 8  # overworld sprite, front pic, back pic, name (dw each)
SPRITE_TABLE_STRIDE = 4  # graphics ptr (2), tile count, bank

# Numeric SPRITE_* ids from constants/sprite_constants.asm, used only to assert
# AILairPatchMirrorSprite's output; these are not address symbols so they are
# not resolvable from the .sym file.
SPRITE_RED = 1
SPRITE_HIKER = 0x0E
SPRITE_GREEN = 0x4E


class AILairMirrorTableTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        self.harness.boot_fight2(seed=1)

    def _read_rom_bytes(self, bank: int, addr: int, length: int) -> list[int]:
        h = self.harness
        assert h is not None
        saved_bank = h.read8("hLoadedROMBank")
        h.pyboy.memory[0x2000] = bank
        data = list(h.pyboy.memory[addr : addr + length])
        h.pyboy.memory[0x2000] = saved_bank
        return data

    def test_mirror_table_matches_each_appearances_own_walk_sheet(self) -> None:
        h = self.harness
        assert h is not None
        appearance_bank, appearance_addr = h.symbols.get("PlayerAppearanceTable")
        mirror_bank, mirror_addr = h.symbols.get("AILairMirrorSpriteIDs")
        sheet_bank, sheet_addr = h.symbols.get("SpriteSheetPointerTable")
        expected_sprite_bank = h.symbols.bank("RedSprite")

        appearance_bytes = self._read_rom_bytes(
            appearance_bank, appearance_addr, APPEARANCE_COUNT * APPEARANCE_STRIDE
        )
        mirror_ids = self._read_rom_bytes(mirror_bank, mirror_addr, APPEARANCE_COUNT)

        for i in range(APPEARANCE_COUNT):
            row = appearance_bytes[i * APPEARANCE_STRIDE : i * APPEARANCE_STRIDE + 2]
            sprite_id = mirror_ids[i]
            with self.subTest(appearance_index=i, sprite_id=sprite_id):
                self.assertGreater(sprite_id, 0)
                sheet_row = self._read_rom_bytes(
                    sheet_bank,
                    sheet_addr + (sprite_id - 1) * SPRITE_TABLE_STRIDE,
                    SPRITE_TABLE_STRIDE,
                )
                self.assertEqual(sheet_row[0:2], row, "graphics pointer mismatch")
                self.assertEqual(sheet_row[3], expected_sprite_bank, "bank mismatch")


class AILairPatchRoutineTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        self.harness.boot_fight2(seed=1)

    def _patch_for(self, appearance_index: int) -> int:
        h = self.harness
        assert h is not None
        h.write8("wPlayerAppearance", appearance_index)
        h.park_before_hijack()
        h.call_routine("AILairPatchMirrorSprite")
        return h.read8("wSprite01StateData1PictureID")

    def test_red_appearance_mirrors_red_sprite(self) -> None:
        self.assertEqual(self._patch_for(0), SPRITE_RED)

    def test_biker_appearance_mirrors_hiker_sprite(self) -> None:
        # Index 1 = biker, whose walk sheet borrows HikerSprite.
        self.assertEqual(self._patch_for(1), SPRITE_HIKER)

    def test_first_female_appearance_mirrors_green_sprite(self) -> None:
        # Index 25 = green, the first female row.
        self.assertEqual(self._patch_for(25), SPRITE_GREEN)

    def test_out_of_range_appearance_falls_back_to_red(self) -> None:
        self.assertEqual(self._patch_for(APPEARANCE_COUNT + 5), SPRITE_RED)


class AILairArchiveQueryTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        self.harness.boot_fight2(seed=7)

    def _has_valid_team(self) -> int:
        h = self.harness
        assert h is not None
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveHasValidTeam")
        return h.read8("wActionResultOrTookBattleTurn")

    def test_empty_archive_publishes_zero(self) -> None:
        h = self.harness
        assert h is not None
        h.write_sram_bytes("sFinalTeamArchive", [0xFF] * (11 + 4 * 406), bank=1)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveInit")
        self.assertEqual(self._has_valid_team(), 0)

    def test_one_capture_publishes_one(self) -> None:
        h = self.harness
        assert h is not None
        h.write_sram_bytes("sFinalTeamArchive", [0xFF] * (11 + 4 * 406), bank=1)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveInit")

        start = h.address("wPartyDataStart")
        for offset in range(404):
            h.pyboy.memory[start + offset] = 0
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", 25)
        h.write8("wPartySpecies", 0xFF, offset=1)
        h.write8("wPartyMon1Species", 25)
        h.write8("wPartyMon1HP", 0)
        h.write8("wPartyMon1HP", 1, offset=1)
        h.write8("wPartyMon1MaxHP", 0)
        h.write8("wPartyMon1MaxHP", 50, offset=1)
        h.write8("wPartyMon1Status", 0x40)
        h.write8("wFusionSecondarySpecies", 0)
        h.write8("wFusionSecondaryForm", 0)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)

        self.assertEqual(self._has_valid_team(), 1)

    def test_only_corrupted_record_publishes_zero(self) -> None:
        h = self.harness
        assert h is not None
        record_size = 406
        h.write_sram_bytes("sFinalTeamArchive", [0xFF] * (11 + 4 * record_size), bank=1)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveInit")

        start = h.address("wPartyDataStart")
        for offset in range(404):
            h.pyboy.memory[start + offset] = 0
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", 25)
        h.write8("wPartySpecies", 0xFF, offset=1)
        h.write8("wPartyMon1Species", 25)
        h.write8("wPartyMon1HP", 0)
        h.write8("wPartyMon1HP", 1, offset=1)
        h.write8("wPartyMon1MaxHP", 0)
        h.write8("wPartyMon1MaxHP", 50, offset=1)
        h.write8("wPartyMon1Status", 0x40)
        h.write8("wFusionSecondarySpecies", 0)
        h.write8("wFusionSecondaryForm", 0)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)

        # Corrupt the one record's species byte without updating its checksum.
        base = h.address("sFinalTeamArchiveRecords")
        record_species_offset = 1
        h.pyboy.memory[0x0000] = 0x0A
        h.pyboy.memory[0x4000] = 1
        h.pyboy.memory[base + record_species_offset] = 99
        h.pyboy.memory[0x0000] = 0

        self.assertEqual(self._has_valid_team(), 0)
