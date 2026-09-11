"""Checks for the Phase 4a/4b trainer-card slot system.

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

4b's resolver, RogueCardBlockForSlot, takes its slot in `a` and so cannot be
driven by call_routine at all: the Bankswitch trampoline destroys `a` before the
callee sees it (project_farcall_home_clobbers_a). Per the documented workaround
in project_call_routine_harness_limits, the tests below drive the caller,
RogueBlitCardBadges, which takes no arguments, and read the decision off hooks
on the resolver own .found/.unknown exits. Those runs blit into VRAM
with the LCD on, which is not how the routine is used in game; that is harmless
here because nothing asserts on VRAM and each test method boots its own machine.
"""
import re
import unittest

from source_constants import (
    parse_map_constants,
    parse_rgbds_constants,
    parse_trainer_class_indexes,
)
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
            constants["NUM_CARD_BLOCKS"] * constants["CARD_TILES_PER_LEADER"] * 16,
            "the art sheet and the block table disagree on the block count; the "
            "sheet carries the leader blocks PLUS CARD_BLOCK_UNKNOWN",
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

    def _foresight(self) -> bool:
        h = self.harness
        assert h is not None
        return bool(h.read8("wRogueFlagsBitfield2") & 0x80)

    def test_beating_the_revealed_gym_spends_foresight(self) -> None:
        """Foresight is bought per gym, not once per run.

        The whole point: without this, one purchase would name every remaining
        leader for the rest of the run.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self._seed(0)
        self._sync()

        # Buy foresight, then beat the gym it was bought for.
        h.write8("wRogueFlagsBitfield2", 0x80)
        self._seed(1 << 5)
        self.assertEqual(self._sync()[0], self.classes["SABRINA"])
        self.assertFalse(
            self._foresight(), "foresight survived the gym it was bought for"
        )

        # Buying again covers exactly one more gym.
        h.write8("wRogueFlagsBitfield2", 0x80)
        self._seed((1 << 5) | (1 << 1))
        self._sync()
        self.assertFalse(self._foresight())

    def test_foresight_survives_until_a_gym_is_actually_beaten(self) -> None:
        """Syncing without a new badge must not silently eat the purchase.

        The lobby sync runs on every return, including after routes, so an
        unconditional clear would consume foresight before it revealed anything.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self._seed(1 << 5)
        self._sync()
        h.write8("wRogueFlagsBitfield2", 0x80)
        for _ in range(3):
            self._sync()
            self.assertTrue(
                self._foresight(), "a sync with no new badge spent foresight"
            )

    def test_a_new_run_drops_unspent_foresight(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.write8("wRogueFlagsBitfield2", 0x80)
        self._seed(0)
        self._sync()
        self.assertFalse(self._foresight())

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


class UnknownBlockContractTest(unittest.TestCase):
    """CARD_BLOCK_UNKNOWN is a block of its own, holding real "?" art.

    It used to be GIOVANNI's block, which worked for free because his vanilla
    face IS the "?" glyph. The next-gym reveal separated the two: a queued
    Giovanni would otherwise draw the same thing as an unknown slot.
    """

    def test_unknown_block_is_not_any_leaders_block(self) -> None:
        """The whole point of the split; folding it back in is the regression."""
        constants = parse_rgbds_constants(TRAINER_CONSTANTS)
        unknown = constants["CARD_BLOCK_UNKNOWN"]
        self.assertGreaterEqual(unknown, constants["NUM_CARD_LEADERS"])
        self.assertLess(unknown, constants["NUM_CARD_BLOCKS"])

        # The resolver's scan is bounded by NUM_CARD_LEADERS, so no class may
        # resolve to the "?" block by landing at that index in the table.
        image = Image("pokered")
        start = image.offset("CardLeaderClasses")
        end = image.offset("CardLeaderClassesEnd")
        self.assertEqual(end - start, constants["NUM_CARD_LEADERS"])
        self.assertLess(
            constants["NUM_CARD_LEADERS"],
            constants["NUM_CARD_BLOCKS"],
            "the sheet must carry one more block than there are leaders",
        )

    def test_giovanni_keeps_a_leader_block_of_his_own(self) -> None:
        """So real portrait art has somewhere to go without touching the '?'."""
        classes = parse_trainer_class_indexes(TRAINER_CONSTANTS)
        constants = parse_rgbds_constants(TRAINER_CONSTANTS)
        image = Image("pokered")
        start = image.offset("CardLeaderClasses")
        end = image.offset("CardLeaderClassesEnd")
        blocks = list(image.rom[start:end])
        self.assertIn(classes["GIOVANNI"], blocks)
        self.assertNotEqual(
            blocks.index(classes["GIOVANNI"]), constants["CARD_BLOCK_UNKNOWN"]
        )

    def test_unknown_blocks_art_is_the_glyph_in_both_halves(self) -> None:
        """Guard against pointing the '?' at a blank or half-built block.

        Both halves, deliberately: the badge half is reachable when a recorded
        class is missing from CardLeaderClasses, and that slot is earned, so
        DrawBadges draws the badge. A "?" there beats a spurious Earth Badge.
        """
        constants = parse_rgbds_constants(TRAINER_CONSTANTS)
        block = constants["CARD_BLOCK_UNKNOWN"]
        stride = constants["CARD_TILES_PER_LEADER"] * 16
        art = (REPO_ROOT / "gfx" / "trainer_card" / "badges.2bpp").read_bytes()
        self.assertEqual(art, art[:constants["NUM_CARD_BLOCKS"] * stride])
        base = block * stride
        face = art[base:base + stride // 2]
        badge = art[base + stride // 2:base + stride]
        self.assertGreater(
            len(set(face)), 1, "the '?' block's face half is blank"
        )
        self.assertEqual(face, badge)


class TrainerCardBlockChoiceSmokeTest(HarnessTestCase):
    """Which block RogueCardBlockForSlot picks for each of the eight slots.

    Read off hooks rather than returned values; see the module docstring.
    """

    def setUp(self) -> None:
        super().setUp()
        self.classes = parse_trainer_class_indexes(TRAINER_CONSTANTS)
        self.constants = parse_rgbds_constants(TRAINER_CONSTANTS)
        self.maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")

    def _blocks(
        self, badges: int, predict: bool, queued_map: int = 0, lineup=None
    ) -> list[int]:
        """Drive the real blit and return the block chosen for slots 0-7."""
        h = self.harness
        assert h is not None
        unknown = self.constants["CARD_BLOCK_UNKNOWN"]
        chosen: list[int] = []

        # Written whole rather than bit-set: bits 2-6 are the Shin Red VRAM/DMA
        # flags and a stray one would change how the blit behaves.
        h.write8("wRogueFlagsBitfield2", 0x80 if predict else 0x00)
        h.write8("wObtainedBadges", badges)
        h.write8("wRogueMap", queued_map)
        for index in range(NUM_BADGES):
            h.write8("wRunGymLineup", 0, offset=index)
            h.write8("wBadgeSlotOrder", 0, offset=index)
        for index, value in (lineup or {}).items():
            h.write8("wRunGymLineup", value, offset=index)

        h.hook_flag(
            "RogueCardBlockForSlot.found",
            lambda: chosen.append(h.pyboy.register_file.C),
        )
        h.hook_flag(
            "RogueCardBlockForSlot.unknown", lambda: chosen.append(unknown)
        )
        h.park_before_hijack()
        h.call_routine("RogueBlitCardBadges")
        return chosen

    def test_every_unearned_slot_draws_the_question_mark(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        unknown = self.constants["CARD_BLOCK_UNKNOWN"]
        self.assertEqual(
            self._blocks(badges=0, predict=False), [unknown] * NUM_BADGES
        )

    def test_earned_slots_keep_their_leader_and_the_rest_stay_hidden(self) -> None:
        """Sabrina beaten first: her block in slot 0, seven question marks."""
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        unknown = self.constants["CARD_BLOCK_UNKNOWN"]
        sabrina_block = EXPECTED_BLOCKS.index("SABRINA")
        self.assertEqual(
            self._blocks(badges=1 << 5, predict=False),
            [sabrina_block] + [unknown] * (NUM_BADGES - 1),
        )

    def test_prediction_reveals_exactly_one_slot(self) -> None:
        """Foresight names the next opponent; it is not a run table of contents.

        Celadon queued with no badges: Erika's face in slot 0, and the other
        seven slots must STILL be question marks.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        unknown = self.constants["CARD_BLOCK_UNKNOWN"]
        self.assertEqual(
            self._blocks(badges=0, predict=True, queued_map=self.maps["CELADON_GYM"]),
            [EXPECTED_BLOCKS.index("ERIKA")] + [unknown] * (NUM_BADGES - 1),
        )

    def test_reveal_lands_on_the_next_slot_not_the_badge_bit(self) -> None:
        """The two indexes differ as soon as any badge is earned.

        Two badges earned, so the reveal belongs in slot 2. The queued gym is
        Fuchsia, badge bit 4 - if the reveal were keyed off the badge bit it
        would land in slot 4 instead, which is the bug this guards.

        Slots 0 and 1 come back in BADGE BIT order (Misty, Sabrina) rather than
        defeat order here, and that is correct: _blocks wipes wBadgeSlotOrder,
        so the sync inside the blit rebuilds it cold from wObtainedBadges and
        has no history to preserve. In play the lobby sync builds it one badge
        at a time, which is what keeps defeat order exact - see
        test_slots_fill_in_defeat_order_not_badge_bit_order, which syncs twice.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        unknown = self.constants["CARD_BLOCK_UNKNOWN"]
        blocks = self._blocks(
            badges=(1 << 5) | (1 << 1),
            predict=True,
            queued_map=self.maps["FUCHSIA_GYM"],
        )
        self.assertEqual(
            blocks[:3],
            [
                EXPECTED_BLOCKS.index("MISTY"),
                EXPECTED_BLOCKS.index("SABRINA"),
                EXPECTED_BLOCKS.index("KOGA"),
            ],
        )
        self.assertEqual(blocks[3:], [unknown] * (NUM_BADGES - 3))

    def test_nothing_is_revealed_while_a_route_is_queued(self) -> None:
        """Foresight is silent between gyms, which is most of the run."""
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        unknown = self.constants["CARD_BLOCK_UNKNOWN"]
        self.assertEqual(
            self._blocks(badges=0, predict=True, queued_map=self.maps["ROUTE_3"]),
            [unknown] * NUM_BADGES,
        )

    def test_reveal_follows_a_rolled_lineup(self) -> None:
        """Phase 7's contract on the reveal path, not just the earned path.

        Celadon is badge bit 3, so a lineup putting MORTY at index 3 must make
        Celadon Gym reveal Morty rather than Erika.
        """
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        blocks = self._blocks(
            badges=0,
            predict=True,
            queued_map=self.maps["CELADON_GYM"],
            lineup={3: self.classes["MORTY"]},
        )
        self.assertEqual(blocks[0], EXPECTED_BLOCKS.index("MORTY"))

    def test_a_queued_gym_reveals_nothing_without_foresight(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        unknown = self.constants["CARD_BLOCK_UNKNOWN"]
        self.assertEqual(
            self._blocks(badges=0, predict=False, queued_map=self.maps["CELADON_GYM"]),
            [unknown] * NUM_BADGES,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
