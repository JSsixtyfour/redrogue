"""Runtime checks for Phase 7a's gym-leader lineup roller.

`RogueRollGymLineup` (custom_functions/random_stage_selection.asm) decides which
eight gyms a run visits. Three properties matter and none is visible from the
build:

  * eight DISTINCT leaders, gated on the Johto species group;
  * `wGymsUsedMask` carries across runs, so run 2 draws the eight run 1 did not,
    and the mask self-clears when a cycle is spent rather than spinning in a
    draw loop it can never satisfy;
  * exactly one of Koga and Janine occupies the single Fuchsia Gym slot.

The mask is the sharp edge. It lives inside `wGameProgressFlags`, which
`RogueResetRunState` blanket-clears at the end of every run, so it only survives
because that routine explicitly carries it across the wipe in `de`. That is a
save/restore nobody would notice losing, and losing it silently degrades the
whole feature to "every run re-rolls from all sixteen".

Group control is the same two levers test_elite_four_roll.py uses:
BIT_DEBUG2_MODE in wStatusFlags6 selects the pool, wNumHoFTeams is independent.
"""
import unittest

from source_constants import (
    parse_map_constants,
    parse_rgbds_constants,
    parse_trainer_class_indexes,
)
from test_smoke import HarnessTestCase, REPO_ROOT

TRAINER_CONSTANTS = REPO_ROOT / "constants" / "trainer_constants.asm"
RAM_CONSTANTS = REPO_ROOT / "constants" / "ram_constants.asm"
MAP_CONSTANTS = REPO_ROOT / "constants" / "map_constants.asm"

NUM_BADGES = 8

KANTO_LEADERS = ["BROCK", "MISTY", "LT_SURGE", "ERIKA", "KOGA",
                 "SABRINA", "BLAINE", "GIOVANNI"]
JOHTO_LEADERS = ["FALKNER", "BUGSY", "WHITNEY", "MORTY",
                 "CHUCK", "JASMINE", "PRYCE", "CLAIR"]
# Janine is NOT a ninth Johto leader: she is the alternate occupant of the
# single Fuchsia Gym pool slot, so she can appear in a lineup without being a
# pool entry of her own.
FUCHSIA_OCCUPANTS = {"KOGA", "JANINE"}


class GymLineupRollTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.classes = parse_trainer_class_indexes(TRAINER_CONSTANTS)
        self.by_id = {self.classes[name]: name for name in self.classes}
        self.debug2_bit = parse_rgbds_constants(RAM_CONSTANTS)["BIT_DEBUG2_MODE"]
        self.map_ids = parse_map_constants(MAP_CONSTANTS)

    def _boot(self, *, johto: bool) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        flags = h.read8("wStatusFlags6")
        if johto:
            flags |= 1 << self.debug2_bit
        else:
            flags &= ~(1 << self.debug2_bit) & 0xFF
        h.write8("wStatusFlags6", flags)
        self._clear_mask()
        self._clear_lineup()

    def _clear_mask(self) -> None:
        h = self.harness
        assert h is not None
        h.write8("wGymsUsedMask", 0)
        h.write8("wGymsUsedMask", 0, offset=1)

    def _clear_lineup(self) -> None:
        h = self.harness
        assert h is not None
        for index in range(NUM_BADGES):
            h.write8("wRunGymLineup", 0, offset=index)

    def _mask(self) -> int:
        h = self.harness
        assert h is not None
        return h.read8("wGymsUsedMask") | (h.read8("wGymsUsedMask", offset=1) << 8)

    def _roll(self) -> list[str]:
        h = self.harness
        assert h is not None
        h.park_before_hijack()
        h.call_routine("RogueRollGymLineup")
        drawn = h.read_bytes("wRunGymLineup", NUM_BADGES)
        unknown = [value for value in drawn if value not in self.by_id]
        self.assertEqual(
            unknown, [], f"roller wrote byte(s) that are not trainer class ids: {unknown}"
        )
        return [self.by_id[value] for value in drawn]

    # -- the draw ---------------------------------------------------------

    def test_kanto_only_draws_all_eight_kanto_leaders(self) -> None:
        """Eight candidates for eight slots, so the set is forced."""
        self._boot(johto=False)
        for _ in range(4):
            self._clear_mask()
            self.assertCountEqual(self._roll(), KANTO_LEADERS)

    def test_johto_draws_eight_distinct_from_the_sixteen(self) -> None:
        self._boot(johto=True)
        saw = set()
        for _ in range(4):
            self._clear_mask()
            drawn = self._roll()
            self.assertEqual(
                len(set(drawn)), NUM_BADGES, f"a leader was drawn twice: {drawn}"
            )
            for name in drawn:
                self.assertIn(name, KANTO_LEADERS + JOHTO_LEADERS + ["JANINE"])
            saw.update(drawn)
        self.assertTrue(
            saw & set(JOHTO_LEADERS),
            "four Johto-enabled rolls drew no Johto leader; the gate is probably inverted",
        )

    def test_exactly_one_fuchsia_occupant_per_run(self) -> None:
        """Koga and Janine share one gym, so both in one lineup is two Fuchsias."""
        self._boot(johto=True)
        for _ in range(5):
            self._clear_mask()
            drawn = self._roll()
            occupants = [name for name in drawn if name in FUCHSIA_OCCUPANTS]
            self.assertLessEqual(
                len(occupants), 1, f"both Fuchsia occupants in one lineup: {drawn}"
            )

    def test_kanto_only_never_draws_janine(self) -> None:
        """Janine is a Johto leader; a Kanto-only run sees the Koga it always saw."""
        self._boot(johto=False)
        for _ in range(4):
            self._clear_mask()
            self.assertNotIn("JANINE", self._roll())

    # -- wGymsUsedMask ----------------------------------------------------

    def test_the_second_run_draws_the_other_eight(self) -> None:
        """The property the mask exists for, and the one nothing else covers."""
        self._boot(johto=True)
        first = set(self._roll())
        self._clear_lineup()
        second = set(self._roll())
        overlap = first & second
        # Koga/Janine are one pool slot under two names, so the flip can make
        # them look like an overlap when the mask is behaving correctly.
        overlap -= FUCHSIA_OCCUPANTS
        self.assertEqual(
            overlap, set(), f"run 2 repeated leaders from run 1: {sorted(overlap)}"
        )

    def test_a_spent_cycle_clears_the_mask_instead_of_spinning(self) -> None:
        """With too few candidates left the draw loop could never terminate.

        A fully-set mask is the worst case: zero candidates for eight slots.
        The roller must notice and start a fresh cycle.
        """
        h = self.harness
        assert h is not None
        self._boot(johto=True)
        h.write8("wGymsUsedMask", 0xFF)
        h.write8("wGymsUsedMask", 0xFF, offset=1)
        drawn = self._roll()
        self.assertEqual(len(set(drawn)), NUM_BADGES)
        self.assertNotEqual(self._mask(), 0xFFFF, "the spent cycle was not cleared")

    def test_the_roll_marks_what_it_drew(self) -> None:
        self._boot(johto=True)
        self._roll()
        self.assertEqual(
            bin(self._mask()).count("1"),
            NUM_BADGES,
            "the mask should carry exactly the eight slots just drawn",
        )


class GymLineupResetTest(HarnessTestCase):
    """RogueResetRunState must clear the run block but SPARE wGymsUsedMask.

    The mask sits inside wGameProgressFlags, which that routine blanket-clears,
    so it survives only because of an explicit save/restore around the
    FillMemory. Without it every run re-rolls from all sixteen leaders and the
    across-run no-repeat guarantee is silently gone - nothing crashes, nothing
    looks wrong, the feature just does not work.
    """

    def setUp(self) -> None:
        super().setUp()
        self.classes = parse_trainer_class_indexes(TRAINER_CONSTANTS)

    def test_run_reset_spares_the_used_mask_but_clears_the_lineup(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        h.write8("wGymsUsedMask", 0b10110001)
        h.write8("wGymsUsedMask", 0b01001010, offset=1)
        for index in range(NUM_BADGES):
            h.write8("wRunGymLineup", self.classes["CLAIR"], offset=index)

        h.park_before_hijack()
        h.call_routine("RogueResetRunState")

        self.assertEqual(
            h.read8("wGymsUsedMask"), 0b10110001,
            "RogueResetRunState wiped wGymsUsedMask's low byte",
        )
        self.assertEqual(
            h.read8("wGymsUsedMask", offset=1), 0b01001010,
            "RogueResetRunState wiped wGymsUsedMask's high byte",
        )
        self.assertEqual(
            list(h.read_bytes("wRunGymLineup", NUM_BADGES)), [0] * NUM_BADGES,
            "the lineup must NOT survive a run reset",
        )


if __name__ == "__main__":
    unittest.main()
