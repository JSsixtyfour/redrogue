"""Special Onix/Snorlax type pairs and Pink Butterfree accuracy."""
from __future__ import annotations

import io
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
SPECIES = parse_rgbds_constants(ROOT / "constants/pokemon_constants.asm")
TYPES = parse_rgbds_constants(ROOT / "constants/type_constants.asm")
PALETTES = parse_rgbds_constants(ROOT / "constants/palette_constants.asm")
MOVES = parse_rgbds_constants(ROOT / "constants/move_constants.asm")
SPECIAL = 8


class CrystalPinkFormsTest(unittest.TestCase):
    def setUp(self):
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.boot_to_lobby()
        self.baseline = io.BytesIO()
        self.h.save_state(self.baseline)

    def tearDown(self):
        self.h.close()

    def restore(self):
        self.h.load_state(self.baseline)

    def struct_argument(self, label):
        address = self.h.address(label)
        self.h.pyboy.register_file.D = address >> 8
        self.h.pyboy.register_file.E = address & 255

    def accuracy(self, species, flags, threshold, side=0, flat=False):
        h = self.h
        self.restore()
        for mon in ("wBattleMon", "wEnemyMon"):
            h.write8(mon, SPECIES[species])
            h.write8(mon, flags, offset=7)
        h.write8("hWhoseTurn", side)
        h.write8("wWitchPrizesEarned", 0)
        start = h.address("wBridgeGlobalEffects")
        h.pyboy.memory[start:start + 3] = [0, (1 << 2) if flat else 0, 0]
        h.pyboy.register_file.E = threshold
        h.call_routine("BridgeAdjustAccuracyThreshold", limit=1000)
        return h.last_call_registers["E"]

    def test_bonus_on_both_sides_with_integer_rounding_and_saturation(self):
        for side in (0, 1):
            for threshold in (0, 1, 16, 128, 190, 200, 255):
                with self.subTest(side=side, threshold=threshold):
                    expected = min(255, threshold + threshold // 4 + threshold // 16)
                    self.assertEqual(self.accuracy("BUTTERFREE", SPECIAL, threshold, side), expected)

    def test_bonus_requires_special_bit_and_butterfree_species(self):
        for species, flags in (("BUTTERFREE", 0), ("BUTTERFREE", 32),
                               ("ONIX", SPECIAL), ("STEELIX", SPECIAL)):
            for side in (0, 1):
                with self.subTest(species=species, flags=flags, side=side):
                    self.assertEqual(self.accuracy(species, flags, 128, side), 128)
        self.assertEqual(self.accuracy("BUTTERFREE", SPECIAL | 0x70, 128), 168)

    def test_player_flat_bonus_follows_intrinsic_bonus_and_stays_player_only(self):
        self.assertEqual(self.accuracy("BUTTERFREE", SPECIAL, 128, flat=True), 194)
        self.assertEqual(self.accuracy("BUTTERFREE", SPECIAL, 128, side=1, flat=True), 168)
        self.assertEqual(self.accuracy("BUTTERFREE", SPECIAL, 190, flat=True), 255)
        self.assertEqual(self.accuracy("BUTTERFREE", 0, 128, flat=True), 154)

    def test_accuracy_capability_is_species_keyed_and_bit_gated(self):
        h = self.h
        for species, flags, expected in (("BUTTERFREE", SPECIAL, 4),
                                         ("BUTTERFREE", 0, 0),
                                         ("BUTTERFREE", 32, 0),
                                         ("ONIX", SPECIAL, 0),
                                         ("HITMONCHAN", SPECIAL, 2)):
            with self.subTest(species=species, flags=flags):
                self.restore()
                h.write8("wPartyMon1", SPECIES[species])
                h.write8("wPartyMon1", flags, offset=7)
                self.struct_argument("wPartyMon1")
                h.call_routine("GetSpecialFormCaps2", limit=1000)
                self.assertEqual(h.last_call_registers["E"], expected)


    def test_apply_special_authors_type_pairs_without_losing_marker_bits(self):
        h = self.h
        cases = (("ONIX", "ICE", "GROUND", 0x5D),
                 ("SNORLAX", "ICE", "ICE", 0x5D),
                 ("BUTTERFREE", "ROCK", "WATER", 0x59),
                 ("STEELIX", "ROCK", "WATER", 0x59))
        for mon in ("wPartyMon1", "wBoxMon1"):
            for species, first, second, flags in cases:
                with self.subTest(mon=mon, species=species):
                    self.restore()
                    h.write8(mon, SPECIES[species])
                    h.write8(mon, TYPES["ROCK"], offset=5)
                    h.write8(mon, TYPES["WATER"], offset=6)
                    h.write8(mon, 0x51, offset=7)
                    self.struct_argument(mon)
                    pointer = h.address(mon)
                    h.call_routine("ApplySpecialForm", limit=1000)
                    self.assertEqual(h.read8(mon, offset=5), TYPES[first])
                    self.assertEqual(h.read8(mon, offset=6), TYPES[second])
                    self.assertEqual(h.read8(mon, offset=7), flags)
                    result = h.last_call_registers
                    self.assertEqual((result["D"] << 8) | result["E"], pointer)

    def test_only_pink_has_species_keyed_special_palette(self):
        h = self.h
        for species, flags, palette in (("BUTTERFREE", SPECIAL, 0x17),
                                         ("BUTTERFREE", 0, 0),
                                         ("BUTTERFREE", 32, 0),
                                         ("ONIX", SPECIAL | 4, 0),
                                         ("SNORLAX", SPECIAL | 4, 0)):
            with self.subTest(species=species, flags=flags):
                self.restore()
                h.write8("wPartyMon1", SPECIES[species])
                h.write8("wPartyMon1", flags, offset=7)
                self.struct_argument("wPartyMon1")
                h.call_routine("GetFormPaletteForStruct", limit=4000)
                self.assertEqual(h.last_call_registers["E"], palette)
        for species in ("ONIX", "BUTTERFREE", "SNORLAX"):
            self.restore()
            h.pyboy.register_file.D = SPECIES[species]
            h.pyboy.register_file.E = 1
            h.call_routine("GetFormPalette", limit=4000)
            self.assertEqual(h.last_call_registers["E"], 0)

    def palette_command(self, command, ready_label):
        """Read the completed packet before the resumed lobby can reuse it."""
        h = self.h
        captured = []
        bank, address = h.symbols.get(ready_label)
        h.pyboy.hook_register(
            bank, address,
            lambda _: captured.append(h.read_bytes("wPalPacket", 16)), None)
        try:
            h.call_routine(command, limit=4000)
        finally:
            h.pyboy.hook_deregister(bank, address)
        self.assertEqual(len(captured), 1)
        return captured[0]

    def test_status_palette_command_uses_stored_type_variant_colors(self):
        h = self.h
        cases = (("ONIX", 0, "GROUND", "PAL_GRAYMON"),
                 ("ONIX", SPECIAL | 4, "GROUND", "PAL_BLUEMON"),
                 ("SNORLAX", 0, "NORMAL", "PAL_PINKMON"),
                 ("SNORLAX", SPECIAL | 4, "ICE", "PAL_BLUEMON"),
                 ("BUTTERFREE", 0, "FLYING", "PAL_CYANMON"),
                 ("BUTTERFREE", SPECIAL, "FLYING", "PAL_PINKMON"),
                 ("BUTTERFREE", SPECIAL | 1, "GHOST", "PAL_PURPLEMON"),
                 ("BUTTERFREE", SPECIAL | 4, "ROCK", "PAL_GRAYMON"),
                 ("ONIX", SPECIAL | 4 | 1, "GROUND", "PAL_BLUEMON"),
                 ("SNORLAX", SPECIAL | 4 | 1, "ICE", "PAL_BLUEMON"))
        for species, flags, second, expected in cases:
            with self.subTest(species=species, flags=flags):
                self.restore()
                h.write8("wCurPartySpecies", SPECIES[species])
                h.write8("wLoadedMon", SPECIES[species])
                h.write8("wLoadedMon", flags, offset=7)
                if species in ("ONIX", "SNORLAX") and flags & 4:
                    h.write8("wLoadedMon", TYPES["ICE"], offset=5)
                h.write8("wLoadedMon", TYPES[second], offset=6)
                packet = self.palette_command(
                    "SetPal_StatusScreen", "SetPal_StatusScreen.notTypeVariant")
                self.assertEqual(packet[3], PALETTES[expected])

    def test_battle_palette_command_colors_both_sides(self):
        h = self.h
        cases = (("ONIX", 0, "GROUND", "PAL_GRAYMON"),
                 ("ONIX", SPECIAL | 4, "GROUND", "PAL_BLUEMON"),
                 ("SNORLAX", 0, "NORMAL", "PAL_PINKMON"),
                 ("SNORLAX", SPECIAL | 4, "ICE", "PAL_BLUEMON"),
                 ("BUTTERFREE", 0, "FLYING", "PAL_CYANMON"),
                 ("BUTTERFREE", SPECIAL, "FLYING", "PAL_PINKMON"),
                 ("BUTTERFREE", SPECIAL | 1, "GHOST", "PAL_PURPLEMON"),
                 ("BUTTERFREE", SPECIAL | 4, "ROCK", "PAL_GRAYMON"),
                 ("ONIX", SPECIAL | 4 | 1, "GROUND", "PAL_BLUEMON"))
        for species, flags, second, expected in cases:
            with self.subTest(species=species, flags=flags):
                self.restore()
                for mon in ("wBattleMon", "wEnemyMon"):
                    h.write8(mon, SPECIES[species])
                    h.write8(mon, flags, offset=7)
                    if species in ("ONIX", "SNORLAX") and flags & 4:
                        h.write8(mon, TYPES["ICE"], offset=5)
                    h.write8(mon, TYPES[second], offset=6)
                h.write8("wEnemyMonSpecies2", SPECIES[species])
                h.write8("wPlayerBattleStatus3", 0)
                h.write8("wEnemyBattleStatus3", 0)
                packet = self.palette_command("SetPal_Battle", "SetPal_Battle.enemyNotTypeVariant")
                self.assertEqual((packet[5], packet[7]), (PALETTES[expected],) * 2)

    def test_pink_palette_guard_still_excludes_transform_and_enemy_intro(self):
        h = self.h
        def packet(flags, transformed=False, displayed=None):
            self.restore()
            for mon in ("wBattleMon", "wEnemyMon"):
                h.write8(mon, SPECIES["BUTTERFREE"])
                h.write8(mon, flags, offset=7)
            h.write8("wEnemyMonSpecies2", SPECIES["BUTTERFREE"] if displayed is None else displayed)
            h.write8("wPlayerBattleStatus3", 8 if transformed else 0)
            h.write8("wEnemyBattleStatus3", 8 if transformed else 0)
            return self.palette_command("SetPal_Battle", "SetPal_Battle.enemyNotTypeVariant")
        transformed = packet(SPECIAL, transformed=True)
        self.assertEqual((transformed[5], transformed[7]), (PALETTES["PAL_GRAYMON"],) * 2)
        self.assertEqual(packet(SPECIAL, displayed=1)[7], packet(0, displayed=1)[7])

    def test_trainer_shiny_ditto_and_redraws(self):
        h = self.h
        # Transform changes the active struct species and keeps Ditto's flags.
        cases = (
            (0, "DITTO", "DITTO", False, "PAL_GRAYMON"),
            (16, "DITTO", "DITTO", False, "PAL_MEWMON"),
            (16, "ONIX", "DITTO", True, "PAL_MEWMON"),
            (17, "DITTO", "DITTO", False, "PAL_PURPLEMON"),
            (21, "DITTO", "DITTO", False, "PAL_BLUEMON"),
        )
        for flags, active, displayed, transformed, expected in cases:
            with self.subTest(flags=flags, transformed=transformed):
                self.restore()
                h.write8("wBattleMonSpecies", SPECIES["DITTO"])
                h.write8("wBattleMonCatchRate", 0)
                h.write8("wPlayerBattleStatus3", 0)
                h.write8("wEnemyMonSpecies", SPECIES[active])
                h.write8("wEnemyMonSpecies2", SPECIES[displayed])
                h.write8("wEnemyMonCatchRate", flags)
                h.write8("wEnemyMonType2", TYPES["WATER"])
                h.write8("wEnemyBattleStatus3", 8 if transformed else 0)
                packet = self.palette_command("SetPal_Battle", "SetPal_Battle.enemyNotTypeVariant")
                self.assertEqual(packet[5], PALETTES["PAL_GRAYMON"])
                self.assertEqual(packet[7], PALETTES[expected])
        h.write8("wEnemyMonSpecies2", 0)  # Trainer portrait with stale flags.
        stale = self.palette_command("SetPal_Battle", "SetPal_Battle.enemyNotTypeVariant")
        h.write8("wEnemyMonCatchRate", 0)
        clean = self.palette_command("SetPal_Battle", "SetPal_Battle.enemyNotTypeVariant")
        self.assertEqual(stale[7], clean[7])

    def test_type_variant_palette_retains_existing_secondary_type_mapping(self):
        h = self.h
        for first, second, expected in (("ICE", "GROUND", "PAL_BLUEMON"),
                                         ("ICE", "ICE", "PAL_BLUEMON"),
                                         ("ICE", "ROCK", "PAL_GRAYMON"),
                                         ("ICE", "DRAGON", "PAL_BLACK"),
                                         ("NORMAL", "ROCK", "PAL_GRAYMON"),
                                         ("FIRE", "DRAGON", "PAL_BLACK"),
                                         ("WATER", "PSYCHIC_TYPE", "PAL_PINKMON")):
            with self.subTest(first=first, second=second):
                self.restore()
                h.write8("wPartyMon1", SPECIES["ONIX"])
                h.write8("wPartyMon1", 4, offset=7)
                h.write8("wPartyMon1", TYPES[first], offset=5)
                h.write8("wPartyMon1", TYPES[second], offset=6)
                self.struct_argument("wPartyMon1")
                h.call_routine("GetTypeVariantPalette", limit=1000)
                self.assertEqual(h.last_call_registers["E"], PALETTES[expected])

    def test_banked_gift_finalizer_retains_kind_for_party_and_box_front(self):
        h = self.h
        cases = (("ONIX", 1, "ICE", "GROUND", 12, 0),
                 ("SNORLAX", 1, "ICE", "ICE", 12, 0),
                 ("CHARIZARD", 9, "FIRE", "DRAGON", 12, 0),
                 ("EKANS", 5, "NORMAL", "NORMAL", 8, MOVES["SUPER_FANG"]))
        for boxed in (False, True):
            for species, finalizer, first, second, flags, move in cases:
                with self.subTest(boxed=boxed, species=species, finalizer=finalizer):
                    self.restore()
                    h.write8("wAddedToParty", 0 if boxed else 1)
                    h.write8("wPartyCount", 1)
                    h.write8("wBoxCount", 2)
                    target = "wBoxMon1" if boxed else "wPartyMon1"
                    address = h.address(target)
                    h.pyboy.memory[address:address + 33] = [0] * 33
                    h.write8(target, SPECIES[species])
                    h.write8(target, TYPES["NORMAL"], offset=5)
                    h.write8(target, TYPES["NORMAL"], offset=6)
                    # A nonempty box must finalize its front-inserted gift,
                    # leaving the previous occupant in the second slot intact.
                    previous = h.address("wBoxMon2")
                    h.pyboy.memory[previous:previous + 33] = [0x43] * 33
                    h.pyboy.register_file.E = finalizer
                    h.call_routine("BridgeFinalizeGiftMonFar", limit=2000)
                    self.assertEqual(h.read8(target, offset=5), TYPES[first])
                    self.assertEqual(h.read8(target, offset=6), TYPES[second])
                    self.assertEqual(h.read8(target, offset=7), flags)
                    self.assertEqual(h.read8(target, offset=8), move)
                    self.assertEqual(h.read_bytes("wBoxMon2", 33), [0x43] * 33)
                    if move:
                        self.assertGreater(h.read8(target, offset=29), 0, "taught move receives PP")
