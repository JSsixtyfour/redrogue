"""Checks for the Phase 4a trainer-card slot system.

Two halves, for two different failure modes.

The static half decodes `CardLeaderClasses` out of the built ROMs. That table is
a hand-written 17-row index space that is NOT derivable from the trainer class
ids, and nothing in the build can see a transposed row: `ASSERT` proves only
that it has NUM_CARD_LEADERS entries, which is this repo's documented
"table whose count assert passes while its rows are misaligned" failure mode.
The specific trap is SABRINA before BLAINE - the sheet is in wObtainedBadges BIT
order (Marsh is bit 5, Volcano bit 6) while their class ids run the other way,
so a row order copied from constants/trainer_constants.asm assembles cleanly and
silently swaps two badges on the card.

The runtime half drives RogueSyncBadgeSlots in the real ROM. wBadgeSlotOrder is
what the whole phase renders from, and the routine has to be order-preserving,
idempotent and self-resetting at once; none of that is visible from source.
"""
import re
import unittest

from source_constants import parse_rgbds_constants, parse_trainer_class_indexes
from test_party_spec_coverage import Image, ROMS
from test_smoke import HarnessTestCase, REPO_ROOT

TRAINER_CONSTANTS = REPO_ROOT / "constants" / "trainer_constants.asm"
NUM_BADGES = 8

# gfx/trainer_card/badges.png block order, per tools/make_placeholder_badges.py.
# Blocks 0-7 are the Kanto eight in BADGE BIT order, which is where Sabrina and
# Blaine cross over relative to their class ids.
EXPECTED_BLOCKS = [
    "BROCK",      # 0  Boulder, bit 0
    "MISTY",      # 1  Cascade, bit 1
    "LT_SURGE",   # 2  Thunder, bit 2
    "ERIKA",      # 3  Rainbow, bit 3
    "KOGA",       # 4  Soul,    bit 4
    "SABRINA",    # 5  Marsh,   bit 5  <- class id $28, after BLAINE's $27
    "BLAINE",     # 6  Volcano, bit 6  <- class id $27, before SABRINA's $28
    "GIOVANNI",   # 7  Earth,   bit 7
    "FALKNER", "BUGSY", "WHITNEY", "MORTY",
    "CHUCK", "JASMINE", "PRYCE", "CLAIR",
    "JANINE",     # 16 badge half is Koga's Soul Badge, deliberately duplicated
]


class TrainerCardBlockMapTest(unittest.TestCase):
    def _classes(self):
        return parse_trainer_class_indexes(TRAINER_CONSTANTS)

    def test_block_table_matches_the_sheet_in_every_rom(self) -> None:
        classes = self._classes()
        expected = [classes[name] for name in EXPECTED_BLOCKS]
        for name in ROMS:
            with self.subTest(rom=name):
                image = Image(name)
                start = image.offset("CardLeaderClasses")
                end = image.offset("CardLeaderClassesEnd")
                self.assertEqual(
                    list(image.rom[start:end]),
                    expected,
                    "CardLeaderClasses does not match the badges.png block map",
                )

    def test_table_length_tracks_the_art_sheet(self) -> None:
        constants = parse_rgbds_constants(TRAINER_CONSTANTS)
        image = Image("pokered")
        length = image.offset("CardLeaderClassesEnd") - image.offset(
            "CardLeaderClasses"
        )
        self.assertEqual(length, constants["NUM_CARD_LEADERS"])
        self.assertEqual(length, len(EXPECTED_BLOCKS))
        art = (REPO_ROOT / "gfx" / "trainer_card" / "badges.2bpp").stat().st_size
        self.assertEqual(
            art,
            constants["NUM_CARD_LEADERS"] * constants["CARD_TILES_PER_LEADER"] * 16,
            "the art sheet and the block table disagree on the leader count",
        )

    def test_kanto_blocks_are_in_badge_bit_order(self) -> None:
        """The half of the table that vanilla code still assumes positionally.

        RogueCardBlockForSlot and RogueCardLeaderForBadgeBit both fall back to
        "block index == badge bit index" when no lineup has been rolled, so this
        ordering is load-bearing until Phase 7, not merely cosmetic.
        """
        constants = parse_rgbds_constants(REPO_ROOT / "constants" / "ram_constants.asm")
        for bit_name, block in (
            ("BIT_BOULDERBADGE", 0), ("BIT_CASCADEBADGE", 1),
            ("BIT_THUNDERBADGE", 2), ("BIT_RAINBOWBADGE", 3),
            ("BIT_SOULBADGE", 4), ("BIT_MARSHBADGE", 5),
            ("BIT_VOLCANOBADGE", 6), ("BIT_EARTHBADGE", 7),
        ):
            with self.subTest(badge=bit_name):
                self.assertEqual(constants[bit_name], block)


class TrainerCardSourceContractTest(unittest.TestCase):
    """The two call sites that make the defeat order exact rather than approximate.

    A sync only at card-open time would still render, but would collapse two
    badges earned between card views into badge-bit order. The lobby call is
    what guarantees at most one new badge per sync.
    """

    def test_lobby_exit_syncs_the_slot_array(self) -> None:
        source = (
            REPO_ROOT / "custom_functions" / "random_stage_selection.asm"
        ).read_text(encoding="utf-8")
        body = source.split("SelectAndPatchLobbyExit::", 1)[1]
        self.assertRegex(body.split("\n\n", 1)[0], r"call\s+RogueSyncBadgeSlots")

    def test_trainer_info_blits_per_slot(self) -> None:
        source = (
            REPO_ROOT / "engine" / "menus" / "start_sub_menus.asm"
        ).read_text(encoding="utf-8")
        body = source.split("DrawTrainerInfo:", 1)[1]
        self.assertRegex(body, r"farcall\s+RogueBlitCardBadges")
        self.assertNotRegex(
            body,
            r"ld\s+bc,\s*8\s*\*\s*8\s*tiles",
            "the single 64-tile badge blit is back; it can only draw the Kanto "
            "eight in badge-bit order",
        )

    def test_draw_badges_asks_for_a_slot_mask(self) -> None:
        source = (
            REPO_ROOT / "engine" / "menus" / "draw_badges.asm"
        ).read_text(encoding="utf-8")
        self.assertRegex(source, r"farcall\s+RogueCardEarnedSlotMask")
        self.assertNotRegex(
            re.sub(r";.*", "", source),
            r"ld\s+a,\s*\[wObtainedBadges\]",
            "DrawBadges is reading the badge bitfield again; slots fill in "
            "defeat order and badge bits are set in scattered order",
        )


class TrainerCardSlotSyncSmokeTest(HarnessTestCase):
    """RogueSyncBadgeSlots against the real ROM.

    Each method gets its own boot, so the harness's repeated-invocation ceiling
    (see test_party_specs.py) is not a factor: no method calls more than three
    times.
    """

    def setUp(self) -> None:
        super().setUp()
        self.classes = parse_trainer_class_indexes(TRAINER_CONSTANTS)

    def _sync(self) -> list[int]:
        h = self.harness
        assert h is not None
        h.park_before_hijack()
        h.call_routine("RogueSyncBadgeSlots")
        return h.read_bytes("wBadgeSlotOrder", NUM_BADGES)

    def _seed(self, badges: int, lineup=None) -> None:
        h = self.harness
        assert h is not None
        h.write8("wObtainedBadges", badges)
        for index in range(NUM_BADGES):
            h.write8("wRunGymLineup", 0, offset=index)
        for index, value in (lineup or {}).items():
            h.write8("wRunGymLineup", value, offset=index)

    def test_no_badges_clears_a_previous_runs_array(self) -> None:
        """There is no run-start hook; a zero badge byte is what resets this."""
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        for index in range(NUM_BADGES):
            h.write8("wBadgeSlotOrder", self.classes["CLAIR"], offset=index)
        self._seed(0)
        self.assertEqual(self._sync(), [0] * NUM_BADGES)

    def test_slots_fill_in_defeat_order_not_badge_bit_order(self) -> None:
        """The property the whole phase exists for.

        Marsh (bit 5) is earned first and Cascade (bit 1) second, so Sabrina
        must hold slot 0 even though her badge bit is the higher one.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self._seed(0)
        self._sync()

        self._seed(1 << 5)
        first = self._sync()
        self.assertEqual(first[0], self.classes["SABRINA"])
        self.assertEqual(first[1:], [0] * (NUM_BADGES - 1))

        self._seed((1 << 5) | (1 << 1))
        second = self._sync()
        self.assertEqual(
            second[:2], [self.classes["SABRINA"], self.classes["MISTY"]]
        )
        self.assertEqual(second[2:], [0] * (NUM_BADGES - 2))

    def test_sync_is_idempotent(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self._seed(0)
        self._sync()
        self._seed((1 << 0) | (1 << 3))
        once = self._sync()
        twice = self._sync()
        self.assertEqual(once, twice)
        self.assertEqual(
            once[:2], [self.classes["BROCK"], self.classes["ERIKA"]]
        )
        self.assertEqual(once[2:], [0] * (NUM_BADGES - 2))

    def test_a_rolled_lineup_overrides_the_kanto_default(self) -> None:
        """Phase 7's contract, proven now so Phase 7 only has to roll the array.

        _PickNextGym picks a random unset BADGE BIT and Phase 7 maps that bit
        through wRunGymLineup, so badge bit 3 must resolve to whoever the lineup
        put at index 3 - here Morty, not Erika.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self._seed(0)
        self._sync()
        self._seed(1 << 3, lineup={3: self.classes["MORTY"]})
        slots = self._sync()
        self.assertEqual(slots[0], self.classes["MORTY"])
        self.assertEqual(slots[1:], [0] * (NUM_BADGES - 1))


if __name__ == "__main__":
    unittest.main(verbosity=2)
