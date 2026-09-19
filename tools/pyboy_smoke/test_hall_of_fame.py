"""Regression contracts for the Hall of Fame player-summary transition."""

import unittest

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT


EVENT_CONSTANTS = REPO_ROOT / "constants" / "event_constants.asm"
HALL_OF_FAME_SOURCE = REPO_ROOT / "engine" / "movie" / "hall_of_fame.asm"
DEBUG_PARTY_SOURCE = REPO_ROOT / "engine" / "debug" / "debug_party.asm"


class HallOfFameSourceContractTest(unittest.TestCase):
    def test_cgb_updates_the_background_palette_it_just_wrote(self) -> None:
        source = HALL_OF_FAME_SOURCE.read_text()
        seam = "ldh [rBGP], a\n\tcall UpdateGBCPal_BGP"
        self.assertIn(seam, source)
        self.assertNotIn("ldh [rBGP], a\n\tcall UpdateGBCPal_OBP0", source)

    def test_debug_dex_fill_is_derived_from_num_pokemon(self) -> None:
        source = DEBUG_PARTY_SOURCE.read_text()
        self.assertIn("ld b, NUM_POKEMON / 8", source)
        self.assertIn("ld [hl], (1 << (NUM_POKEMON % 8)) - 1", source)


class HallOfFameDexRatingTest(HarnessTestCase):
    def test_legacy_255_entry_debug_save_is_clamped_and_returns(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)

        # The old debug initializer filled 31 complete bytes plus seven bits,
        # reporting 255 owned/seen entries even though the dex has only 252.
        invalid_debug_dex = [0xFF] * 31 + [0x7F]
        owned = h.address("wPokedexOwned")
        seen = h.address("wPokedexSeen")
        for offset, value in enumerate(invalid_debug_dex):
            h.pyboy.memory[owned + offset] = value
            h.pyboy.memory[seen + offset] = value

        events = parse_rgbds_constants(EVENT_CONSTANTS)
        event = events["EVENT_HALL_OF_FAME_DEX_RATING"]
        flags = h.address("wEventFlags") + event // 8
        h.pyboy.memory[flags] |= 1 << (event % 8)

        h.park_before_hijack()
        h.call_routine("DisplayDexRating")

        self.assertEqual(h.read8("hDexRatingNumMonsSeen"), 252)
        self.assertEqual(h.read8("hDexRatingNumMonsOwned"), 252)
        self.assertEqual(h.pyboy.memory[flags] & (1 << (event % 8)), 0)
