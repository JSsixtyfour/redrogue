"""Checkpoint 10 runtime contracts for the FINAL_AI battle.

See CHECKPOINT_10_SPEC.md. FINAL_AI is a dedicated trainer class whose party
is a randomly-selected archived Champion team (custom_functions/
final_team_archive.asm), loaded link-style so its baked fusion stats/types
survive, always played at its difficulty's tier ceiling, and always
omniscient regardless of that tier.
"""

from test_ai_fairplay import call_a_preserving
from test_smoke import HarnessTestCase, REPO_ROOT
from source_constants import (
    parse_rgbds_constants,
    parse_trainer_class_indexes,
    parse_trainer_constants,
)


PARTY_SIZE = 404
RECORD_SIZE = 406
HEADER_SIZE = 11
ARCHIVE_BANK = 1

APPEARANCE_STRIDE = 8  # overworld sprite, front pic, back pic, name (dw each)
BEAUTY_APPEARANCE_INDEX = 26


class FinalAITest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.trainer_classes = parse_trainer_class_indexes(
            REPO_ROOT / "constants/trainer_constants.asm"
        )
        # inject_fight2_spec's trainer_class parameter writes wCurOpponent
        # (an OPP_* value, see engine/debug/debug_fight2.asm .buildInjected),
        # a separate id space from the raw class wTrainerClass holds.
        self.trainer_opp_ids = parse_trainer_constants(
            REPO_ROOT / "constants/trainer_constants.asm"
        )
        self.ram_constants = parse_rgbds_constants(
            REPO_ROOT / "constants/ram_constants.asm"
        )
        self.type_constants = parse_rgbds_constants(
            REPO_ROOT / "constants/type_constants.asm"
        )
        # pokemon_constants.asm's values ARE the internal (scrambled) species
        # id that wPartyMonSpecies/wEnemyMonSpecies2 hold - NOT the Pokedex
        # number. RATTATA is Normal/Normal, so its header type is never FIRE.
        self.species = parse_rgbds_constants(
            REPO_ROOT / "constants/pokemon_constants.asm"
        )

    def _read_rom_bytes(self, bank: int, addr: int, length: int) -> list[int]:
        h = self.harness
        assert h is not None
        saved_bank = h.read8("hLoadedROMBank")
        h.pyboy.memory[0x2000] = bank
        data = list(h.pyboy.memory[addr : addr + length])
        h.pyboy.memory[0x2000] = saved_bank
        return data

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

    def test_tier_per_difficulty(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        final_ai = self.trainer_classes["FINAL_AI"]
        difficulty_mask = self.ram_constants["DIFFICULTY_MASK"]
        final_trainer_bit = self.ram_constants["BIT_ROGUE_FINAL_TRAINER"]
        # NORMAL, EASY, VERY_EASY, HARD, VERY_HARD = Expert, Skilled,
        # Competent, Expert, Expert (AITierCeiling, ai_core.asm).
        expected = [3, 2, 1, 3, 3]
        for difficulty, expected_tier in enumerate(expected):
            h.write8("wAIDebugTierOverride", 0)
            h.write8("wAITier", 0)
            h.write8("wBattleCount", 0)
            h.write8("wGymLeaderNo", 0)
            flags = h.read8("wRogueFlagsBitfield") & ~(1 << final_trainer_bit)
            h.write8("wRogueFlagsBitfield", flags)
            options2 = h.read8("wOptions2")
            options2 = (options2 & ~difficulty_mask) | difficulty
            h.write8("wOptions2", options2)
            h.write8("wTrainerClass", final_ai)
            h.park_before_hijack()
            h.call_routine("AIResolveTier")
            with self.subTest(difficulty=difficulty):
                self.assertEqual(h.read8("wAITier") - 1, expected_tier)

        # Control: a normal trainer class on NORMAL, battle count 0, gets tier 0.
        h.write8("wAIDebugTierOverride", 0)
        h.write8("wAITier", 0)
        h.write8("wBattleCount", 0)
        h.write8("wGymLeaderNo", 0)
        flags = h.read8("wRogueFlagsBitfield") & ~(1 << final_trainer_bit)
        h.write8("wRogueFlagsBitfield", flags)
        options2 = h.read8("wOptions2") & ~difficulty_mask
        h.write8("wOptions2", options2)
        h.write8("wTrainerClass", self.trainer_classes["COOLTRAINER_M"])
        h.park_before_hijack()
        h.call_routine("AIResolveTier")
        self.assertEqual(h.read8("wAITier") - 1, 0)

    def _mon(self, name: str, move_names: list[str]) -> dict[str, object]:
        moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        return {
            "species": self.species[name],
            "level": 50,
            "moves": [moves[m] for m in move_names],
        }

    def test_forced_omniscience_ignores_tier(self) -> None:
        # boot_fight2 is not reentrant (drives the debug menu from a fresh
        # boot), so this and the control below are separate test methods,
        # each with its own single boot - mirrors test_ai_fairplay.py.
        h = self.harness
        assert h is not None
        moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        h.inject_fight2_spec(
            [self._mon("SNORLAX", ["TACKLE", "GROWL", "SPLASH"])],
            [self._mon("RATTATA", ["TACKLE"])],
            trainer_class=self.trainer_opp_ids["FINAL_AI"], ai_tier=1,
        )
        h.boot_fight2(seed=1)
        # The FIGHT2 debug fixture only writes wCurOpponent (see
        # .buildInjected above); it never sets wTrainerClass, which the
        # production FINAL_AI override actually keys off. Set it directly.
        h.write8("wTrainerClass", self.trainer_classes["FINAL_AI"])
        growl = moves["GROWL"]
        base = h.address("wAISeenPlayerMoves")
        for index, move_id in enumerate([0, growl, 0, 0]):
            h.pyboy.memory[base + index] = move_id

        tackle = moves["TACKLE"]
        splash = moves["SPLASH"]
        self.assertEqual(call_a_preserving(h, "AIGetPlayerMoveN", 0), tackle)
        self.assertEqual(call_a_preserving(h, "AIGetPlayerMoveN", 2), splash)

    def test_forced_omniscience_control_is_class_gated(self) -> None:
        # Same fair-play tier, ordinary class: must stay fair-play (slot 0
        # unrevealed -> 0), proving the override above is class-gated.
        h = self.harness
        assert h is not None
        moves = parse_rgbds_constants(REPO_ROOT / "constants/move_constants.asm")
        h.inject_fight2_spec(
            [self._mon("SNORLAX", ["TACKLE", "GROWL", "SPLASH"])],
            [self._mon("RATTATA", ["TACKLE"])],
            trainer_class=self.trainer_opp_ids["COOLTRAINER_M"], ai_tier=1,
        )
        h.boot_fight2(seed=1)
        h.write8("wTrainerClass", self.trainer_classes["COOLTRAINER_M"])
        growl = moves["GROWL"]
        base = h.address("wAISeenPlayerMoves")
        for index, move_id in enumerate([0, growl, 0, 0]):
            h.pyboy.memory[base + index] = move_id
        self.assertEqual(call_a_preserving(h, "AIGetPlayerMoveN", 0), 0)

    def test_read_trainer_loads_archive_and_portrait(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=7)
        self._empty_archive()
        self._party(self.species["RATTATA"])
        h.write8("wPartyMon1Level", 42)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)

        h.write8("wPlayerAppearance", BEAUTY_APPEARANCE_INDEX)
        h.write8("wTrainerClass", self.trainer_classes["FINAL_AI"])
        h.write8("wTrainerNo", 1)
        h.park_before_hijack()
        h.call_routine("ReadTrainer", limit=4000)

        self.assertEqual(h.read8("wEnemyPartyCount"), 1)
        self.assertEqual(h.read8("wEnemyMon1Species"), self.species["RATTATA"])
        max_hp = h.read_bytes("wEnemyMon1MaxHP", 2)
        self.assertEqual(h.read_bytes("wEnemyMon1HP", 2), max_hp)
        self.assertEqual(h.read8("wCurEnemyLevel"), 42)

        appearance_bank, appearance_addr = h.symbols.get("PlayerAppearanceTable")
        row = self._read_rom_bytes(
            appearance_bank,
            appearance_addr + BEAUTY_APPEARANCE_INDEX * APPEARANCE_STRIDE + 2,
            2,
        )
        self.assertEqual(h.read_bytes("wTrainerPicPointer", 2), row)
        self.assertEqual(h.read8("wTrainerPicBank"), h.symbols.bank("RedPicFront"))

    def test_link_style_enemy_load_preserves_fusion_type(self) -> None:
        h = self.harness
        assert h is not None
        fire = self.type_constants["FIRE"]
        h.boot_fight2(seed=7)
        self._empty_archive()
        self._party(self.species["RATTATA"])
        h.write8("wPartyMon1Level", 42)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)

        h.write8("wPlayerAppearance", 0)
        h.write8("wTrainerClass", self.trainer_classes["FINAL_AI"])
        h.write8("wTrainerNo", 1)
        h.park_before_hijack()
        h.call_routine("ReadTrainer", limit=4000)

        # 321 does not fit a byte; write it as a real little-endian word
        # (65, 1) so a species-recompute regression (max ~255) can't pass by
        # accident.
        foreign_max_hp = 321
        h.write8("wEnemyMon1Type2", fire)
        h.write8("wEnemyMon1MaxHP", foreign_max_hp & 0xFF)
        h.write8("wEnemyMon1MaxHP", foreign_max_hp >> 8, offset=1)
        h.write8("wEnemyMon1HP", foreign_max_hp & 0xFF)
        h.write8("wEnemyMon1HP", foreign_max_hp >> 8, offset=1)
        h.write8("hIsInBattle", 2)
        h.write8("hWhichPokemon", 0)
        h.write8("wEnemyMonSpecies2", self.species["RATTATA"])
        h.park_before_hijack()
        h.call_routine("LoadEnemyMonData")

        self.assertEqual(h.read8("wEnemyMonType2"), fire)
        self.assertEqual(
            h.read_bytes("wEnemyMonMaxHP", 2),
            [foreign_max_hp & 0xFF, foreign_max_hp >> 8],
        )

    def test_wild_battle_after_final_ai_does_not_load_link_style(self) -> None:
        h = self.harness
        assert h is not None
        fire = self.type_constants["FIRE"]
        h.boot_fight2(seed=7)
        self._empty_archive()
        self._party(self.species["RATTATA"])
        h.write8("wPartyMon1Level", 42)
        h.park_before_hijack()
        h.call_routine("FinalTeamArchiveCapture")
        self.assertEqual(h.read8("wActionResultOrTookBattleTurn"), 1)

        h.write8("wPlayerAppearance", 0)
        h.write8("wTrainerClass", self.trainer_classes["FINAL_AI"])
        h.write8("wTrainerNo", 1)
        h.park_before_hijack()
        h.call_routine("ReadTrainer", limit=4000)

        h.write8("hIsInBattle", 1)  # wild: InitWildBattle has not zeroed wTrainerClass yet
        h.write8("hWhichPokemon", 0)
        h.write8("wEnemyMonSpecies2", self.species["RATTATA"])
        h.park_before_hijack()
        h.call_routine("LoadEnemyMonData")

        self.assertNotEqual(h.read8("wEnemyMonType2"), fire)

    def test_no_exp_awarded(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.write8("wLinkState", 0)
        h.write8("wTrainerClass", self.trainer_classes["FINAL_AI"])
        h.write8("wPartyGainExpFlags", 0x01)
        h.write8("wEnemyMonBaseExp", 100)
        exp_before = h.read_bytes("wPartyMon1Exp", 3)
        h.park_before_hijack()
        h.call_routine("GainExperience")
        self.assertEqual(h.read_bytes("wPartyMon1Exp", 3), exp_before)

    def test_final_battle_music_source_contract(self) -> None:
        text = (REPO_ROOT / "audio/play_battle_music.asm").read_text(encoding="utf-8")
        lines = [line.strip() for line in text.splitlines()]
        for index, line in enumerate(lines):
            if line.startswith("cp OPP_FINAL_AI"):
                self.assertEqual(lines[index + 1], "jr z, .finalBattle")
                return
        self.fail("cp OPP_FINAL_AI not found in audio/play_battle_music.asm")
