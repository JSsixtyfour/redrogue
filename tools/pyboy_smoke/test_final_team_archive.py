"""Checkpoint 8 runtime contracts for the final-team SRAM archive."""

from test_smoke import HarnessTestCase


ARCHIVE_BANK = 1
PARTY_SIZE = 404
RECORD_SIZE = 406
HEADER_SIZE = 11


class FinalTeamArchiveTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        assert self.harness is not None
        self.harness.boot_fight2(seed=7)

    def _empty_archive(self) -> None:
        h = self.harness
        assert h is not None
        h.write_sram_bytes(
            "sFinalTeamArchive", [0xFF] * (HEADER_SIZE + 4 * RECORD_SIZE), bank=ARCHIVE_BANK
        )
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveInit")

    def _party(self, species: int, hp: int = 1, max_hp: int = 50) -> None:
        h = self.harness
        assert h is not None
        start = h.address("wPartyDataStart")
        for offset in range(PARTY_SIZE):
            h.pyboy.memory[start + offset] = 0
        h.write8("wPartyCount", 1)
        h.write8("wPartySpecies", species)
        h.write8("wPartySpecies", 0xFF, offset=1)
        h.write8("wPartyMon1Species", species)
        h.write8("wPartyMon1HP", 0)
        h.write8("wPartyMon1HP", hp, offset=1)
        h.write8("wPartyMon1MaxHP", 0)
        h.write8("wPartyMon1MaxHP", max_hp, offset=1)
        h.write8("wPartyMon1Status", 0x40)
        h.write8("wFusionSecondarySpecies", 0)
        h.write8("wFusionSecondaryForm", 0)

    def _capture(self) -> None:
        h = self.harness
        assert h is not None
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)

    def test_fresh_ff_sram_is_explicitly_initialized(self) -> None:
        self._empty_archive()
        h = self.harness
        assert h is not None
        header = h.read_sram_bytes("sFinalTeamArchive", HEADER_SIZE, bank=ARCHIVE_BANK)
        # RGBDS character literals use the game's charmap, not ASCII.
        self.assertEqual(header[:6], [0x91, 0x91, 1, 0, 0, 0xFF])
        self.assertEqual(header[6:10], [0xFF] * 4)
        self.assertNotEqual(header[10], 0xFF)

    def test_four_slot_archive_rolls_and_latest_restores_healed(self) -> None:
        self._empty_archive()
        for species in (1, 2, 3, 4, 5):
            self._party(species)
            self._capture()
        h = self.harness
        assert h is not None
        self.assertEqual(
            h.read_sram_bytes("sFinalTeamArchiveCount", 3, bank=ARCHIVE_BANK),
            [4, 1, 0],
        )
        self._party(25, hp=3, max_hp=9)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveRestoreLatest")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)
        self.assertEqual(h.read8("wPartyMon1Species"), 5)
        self.assertEqual(h.read_bytes("wPartyMon1HP", 2), [0, 50])
        self.assertEqual(h.read8("wPartyMon1Status"), 0)

    def test_corrupt_latest_falls_back_and_random_enemy_skips_it(self) -> None:
        self._empty_archive()
        self._party(10, hp=2, max_hp=40)
        self._capture()
        self._party(20, hp=3, max_hp=60)
        self._capture()
        h = self.harness
        assert h is not None
        # Corrupt record 1 without updating its checksum.
        record1_species = RECORD_SIZE + 1
        base = h.address("sFinalTeamArchiveRecords")
        h.pyboy.memory[0x0000] = 0x0A
        h.pyboy.memory[0x4000] = ARCHIVE_BANK
        h.pyboy.memory[base + record1_species] = 99
        h.pyboy.memory[0x0000] = 0
        self.assertEqual(
            h.read_sram_bytes("sFinalTeamArchiveRecords", RECORD_SIZE * 2, bank=1)[
                record1_species
            ],
            99,
        )
        records = h.read_sram_bytes("sFinalTeamArchiveRecords", RECORD_SIZE * 2, bank=1)
        checks = h.read_sram_bytes("sFinalTeamArchiveRecordChecksums", 2, bank=1)
        self.assertEqual(checks[0], (~sum(records[:RECORD_SIZE])) & 0xFF)
        self.assertNotEqual(checks[1], (~sum(records[RECORD_SIZE:])) & 0xFF)

        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveRestoreLatest")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)
        self.assertEqual(h.read8("wPartyMon1Species"), 10)

        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveLoadRandomEnemy")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)
        self.assertEqual(h.read8("wEnemyMon1Species"), 10)
        self.assertEqual(h.read_bytes("wEnemyMon1HP", 2), [0, 40])
        self.assertEqual(h.read8("wEnemyMon1Status"), 0)

    def test_fusion_sidecar_round_trips_and_ambiguous_party_is_rejected(self) -> None:
        self._empty_archive()
        h = self.harness
        assert h is not None
        self._party(25)
        h.write8("wPartyMon1CatchRate", 1 << 1)
        h.write8("wFusionSecondarySpecies", 26)
        h.write8("wFusionSecondaryForm", 2)
        self._capture()
        record = h.read_sram_bytes("sFinalTeamArchiveRecords", RECORD_SIZE, bank=1)
        self.assertEqual(record[0:3], [1, 25, 0xFF])
        self.assertEqual(record[-2:], [26, 2])

        h.write8("wFusionSecondarySpecies", 0)
        h.write8("wFusionSecondaryForm", 0)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveLoadRandomEnemy")
        self.assertEqual(h.read8("wFinalAISecondarySpecies"), 26)
        self.assertEqual(h.read8("wFinalAISecondaryForm"), 2)

        self._party(25)
        h.write8("wPartyCount", 2)
        h.write8("wPartySpecies", 26, offset=1)
        h.write8("wPartySpecies", 0xFF, offset=2)
        h.write8("wPartyMon1CatchRate", 1 << 1)
        h.write8("wPartyMon2CatchRate", 1 << 1)
        h.write8("wFusionSecondarySpecies", 26)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 0)
        self.assertEqual(h.read_sram_bytes("sFinalTeamArchiveCount", 1, bank=1), [1])

    def test_archive_survives_main_save_and_load(self) -> None:
        self._empty_archive()
        self._party(42, hp=4, max_hp=70)
        self._capture()
        h = self.harness
        assert h is not None

        h.park_before_hijack()
        h.call_routine("SaveGameData")
        self._party(25, hp=1, max_hp=8)
        h.park_before_hijack()
        h.call_routine("LoadMainData")

        # The archive is outside sGameData and keeps its independent checksum.
        self.assertEqual(h.read_sram_bytes("sFinalTeamArchiveCount", 1, bank=1), [1])
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveRestoreLatest")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)
        self.assertEqual(h.read8("wPartyMon1Species"), 42)
        self.assertEqual(h.read_bytes("wPartyMon1HP", 2), [0, 70])
