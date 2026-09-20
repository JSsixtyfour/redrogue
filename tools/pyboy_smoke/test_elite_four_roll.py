"""Runtime checks for Phase 7's Elite Four and Champion rollers.

`RollElite4AndChampion` (custom_functions/final_sequence.asm) replaced the old
24-row `Elite4OrderTable` plus a 0-23 `wElite4Order` index. Nothing about the
replacement is visible from the build: the pool is gated at runtime on the
active species-group mask, the draw is rejection sampling against a used-slot
bitmask, and the Champion depends on what the Elite Four draw happened to take.
A clean link proves none of it (feedback_build_success_not_correctness), and the
predecessor of this code shipped a silent routing bug for weeks.

Group control. RogueGetActiveGroupMask short-circuits to "every group" when
BIT_DEBUG2_MODE is set in wStatusFlags6, and otherwise derives unlocks from
the persistent activation events and ANDs in the player's SRAM toggle byte.
That gives two clean levers that do not interfere: the debug bit selects the
POOL, and the activation/defeat events independently drive the forced
first-clear Champion.

Roll budget. call_routine corrupts the machine after roughly ten invocations on
one boot (project_call_routine_harness_limits), so no method below rolls more
than six times, and each method gets a fresh harness from HarnessTestCase.setUp.
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
EVENT_CONSTANTS = REPO_ROOT / "constants" / "event_constants.asm"

E4_ROOMS = [
    "LORELEIS_ROOM", "BRUNOS_ROOM", "AGATHAS_ROOM", "LANCES_ROOM",
    "KOGAS_ROOM", "WILLS_ROOM", "KARENS_ROOM",
]

NUM_E4 = 4
NUM_GYM_SLOTS = 8

KANTO_POOL = ["LORELEI", "BRUNO", "AGATHA", "LANCE"]
# KOGA_E4, not KOGA. The Elite Four Koga is a separate trainer class from the
# Fuchsia Gym one so that the two roles can carry different party grids; sharing
# a class made an E4 Koga field his gym rounds 1-4.
JOHTO_POOL = ["KOGA_E4", "WILL", "KAREN"]
CHAMPION_POOL = ["RIVAL3", "LANCE", "PROF_OAK"]


class Elite4RollTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.classes = parse_trainer_class_indexes(TRAINER_CONSTANTS)
        ram = parse_rgbds_constants(RAM_CONSTANTS)
        self.events = parse_rgbds_constants(EVENT_CONSTANTS)
        self.debug2_bit = ram["BIT_DEBUG2_MODE"]
        self.by_id = {self.classes[name]: name for name in self.classes}
        self.map_ids = parse_map_constants(MAP_CONSTANTS)
        self.e4_room_maps = {self.map_ids[name] for name in E4_ROOMS}

    # -- helpers ----------------------------------------------------------

    def _boot(
        self, *, johto: bool, unlock_stage: int = 0, defeat_stage: int = 0
    ) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        flags = h.read8("wStatusFlags6")
        if johto:
            flags |= 1 << self.debug2_bit
        else:
            flags &= ~(1 << self.debug2_bit) & 0xFF
        h.write8("wStatusFlags6", flags)
        if unlock_stage >= 1:
            h.set_event(self.events["EVENT_JOHTO_ACTIVATED"])
        if unlock_stage >= 2:
            h.set_event(self.events["EVENT_KANTO_TIMEWARP_ACTIVATED"])
        if defeat_stage >= 1:
            h.set_event(self.events["EVENT_LANCE_CHAMPION_DEFEATED"])
        if defeat_stage >= 2:
            h.set_event(self.events["EVENT_OAK_CHAMPION_DEFEATED"])
        self._set_lineup({})

    def _set_lineup(self, lineup: dict[int, int]) -> None:
        h = self.harness
        assert h is not None
        for index in range(NUM_GYM_SLOTS):
            h.write8("wRunGymLineup", lineup.get(index, 0), offset=index)

    def _roll(self) -> tuple[list[str], str]:
        """One roll. Returns (the four members by name, the champion by name)."""
        h = self.harness
        assert h is not None
        h.park_before_hijack()
        h.call_routine("RollElite4AndChampion")
        members = h.read_bytes("wRunElite4", NUM_E4)
        champion = h.read8("wRunChampion")
        unknown = [value for value in list(members) + [champion] if value not in self.by_id]
        self.assertEqual(
            unknown, [], f"roller wrote byte(s) that are not trainer class ids: {unknown}"
        )
        return [self.by_id[value] for value in members], self.by_id[champion]

    # -- the Elite Four draw ----------------------------------------------

    def test_kanto_only_draws_exactly_the_shipped_four(self) -> None:
        """The property that makes a Kanto-only regression attributable.

        Koga, Will and Karen are Johto-gated, so without Johto the pool is 4
        candidates for 4 slots: the result must be a permutation of today's
        Elite Four and never anything else.
        """
        self._boot(johto=False)
        for _ in range(5):
            members, _ = self._roll()
            self.assertCountEqual(members, KANTO_POOL)

    def test_johto_draws_four_distinct_from_the_seven(self) -> None:
        self._boot(johto=True)
        saw = set()
        for _ in range(6):
            members, _ = self._roll()
            self.assertEqual(
                len(set(members)), NUM_E4, f"a member was drawn twice: {members}"
            )
            for name in members:
                self.assertIn(name, KANTO_POOL + JOHTO_POOL)
            saw.update(members)
        self.assertTrue(
            saw & set(JOHTO_POOL),
            "six Johto-enabled rolls drew no Johto member; the gate is probably inverted",
        )

    def test_koga_is_dropped_when_he_stood_in_a_gym(self) -> None:
        """The one exclusion that is not expressible as a pool size."""
        self._boot(johto=True)
        self._set_lineup({3: self.classes["KOGA"]})
        for _ in range(5):
            members, _ = self._roll()
            self.assertNotIn("KOGA_E4", members)

    def test_janine_in_the_lineup_also_drops_koga(self) -> None:
        """Janine fills the same single Koga/Janine lineup entry."""
        self._boot(johto=True)
        self._set_lineup({0: self.classes["JANINE"]})
        for _ in range(5):
            members, _ = self._roll()
            self.assertNotIn("KOGA_E4", members)

    # -- the Champion ------------------------------------------------------

    def test_kanto_only_champion_is_always_the_rival(self) -> None:
        self._boot(johto=False)
        for _ in range(5):
            _, champion = self._roll()
            self.assertEqual(champion, "RIVAL3")

    def test_champion_is_never_also_an_elite_four_member(self) -> None:
        """Lance is in both pools; drawing him twice would make one room wrong."""
        self._boot(johto=True, unlock_stage=5, defeat_stage=2)
        for _ in range(6):
            members, champion = self._roll()
            self.assertNotIn(
                champion, members, f"{champion} is both Champion and an E4 member"
            )
            self.assertIn(champion, CHAMPION_POOL)

    def test_first_johto_clear_forces_lance_unless_he_is_in_the_four(self) -> None:
        """Johto active with Lance's first-clear event still unset."""
        self._boot(johto=True, unlock_stage=1)
        for _ in range(6):
            members, champion = self._roll()
            if "LANCE" in members:
                self.assertNotEqual(champion, "LANCE")
            else:
                self.assertEqual(
                    champion,
                    "LANCE",
                    "Lance was available and unforced on the first Johto clear",
                )

    def test_first_warp_clear_forces_oak(self) -> None:
        """Time Warp active with Oak's first-clear event still unset.

        Oak is never an Elite Four candidate, so unlike Lance he has no
        escape branch: this one is unconditional.
        """
        self._boot(johto=True, unlock_stage=2, defeat_stage=1)
        for _ in range(5):
            _, champion = self._roll()
            self.assertEqual(champion, "PROF_OAK")

    # -- the unrolled-lineup dead end --------------------------------------

    def test_lobby_doors_self_heal_an_unrolled_lineup(self) -> None:
        """ForceElite4Doors must never point a lobby door at the lobby.

        Its result becomes BOTH wLobbyDoor*StageMap, so a fallback here strands
        the player in the lobby with nowhere to walk. Rolling instead makes the
        unrolled state impossible at the doors rather than something a fallback
        has to survive. wRunElite4 IS zeroed on a Hall of Fame run reset, so
        zero is a state the doors can genuinely meet.
        """
        h = self.harness
        assert h is not None
        self._boot(johto=False)
        for index in range(NUM_E4):
            h.write8("wRunElite4", 0, offset=index)
        h.park_before_hijack()
        h.call_routine("ForceElite4Doors")

        lobby = self.map_ids["INDIGO_PLATEAU_LOBBY"]
        for label in ("wLobbyDoor1StageMap", "wLobbyDoor2StageMap"):
            door = h.read8(label)
            self.assertNotEqual(
                door, lobby, f"{label} points at the lobby itself: that is a dead end"
            )
            self.assertIn(
                door,
                self.e4_room_maps,
                f"{label} is not an Elite Four room map (got {door:#04x})",
            )
        self.assertNotEqual(
            h.read_bytes("wRunElite4", NUM_E4), bytes(NUM_E4),
            "the doors were armed without rolling a lineup",
        )


class KogaE4PartyGridTest(unittest.TestCase):
    """KOGA_E4 must carry the four-tier Elite Four grid, not the gym round grid.

    This is the bug the separate class exists to fix. On one shared class both
    the spec path (KogaSpecs, 24 records indexed by ROUND) and the authored
    fallback (KogaData, an authored 24-round ladder) are indexed as gym rounds,
    while InitElite4Battle hands out wTrainerNo 1-12 - so an Elite Four Koga
    fielded his gym rounds 1 through 4, roughly level 15 against a level 55
    party. Source-level, because the failure is a table SHAPE.
    """

    def test_koga_e4_is_a_distinct_class_from_the_gym_koga(self) -> None:
        classes = parse_trainer_class_indexes(TRAINER_CONSTANTS)
        self.assertIn("KOGA_E4", classes)
        self.assertNotEqual(classes["KOGA_E4"], classes["KOGA"])

    def test_koga_e4_uses_the_e4_record_macro_not_the_gym_one(self) -> None:
        specs = (REPO_ROOT / "data" / "trainers" / "party_specs.asm").read_text()
        self.assertIn("e4_member_records  KogaE4", specs)
        self.assertNotIn("gym_leader_records  KogaE4", specs)

    def test_the_gym_koga_still_uses_the_gym_grid(self) -> None:
        """The fix must not have moved the Fuchsia Gym Koga onto the E4 grid."""
        specs = (REPO_ROOT / "data" / "trainers" / "party_specs.asm").read_text()
        self.assertIn("gym_leader_records  Koga,", specs)

    def test_the_elite_four_room_uses_the_e4_class(self) -> None:
        """The room object and both script sites must all agree on KOGA_E4."""
        objects = (REPO_ROOT / "data" / "maps" / "objects" / "KogasRoom.asm").read_text()
        script = (REPO_ROOT / "scripts" / "KogasRoom.asm").read_text()
        for name, text in (("objects", objects), ("script", script)):
            self.assertIn("OPP_KOGA_E4", text, f"{name} does not use OPP_KOGA_E4")
            self.assertNotRegex(
                text,
                r"OPP_KOGA\b(?!_E4)",
                f"{name} still references the gym OPP_KOGA",
            )


if __name__ == "__main__":
    unittest.main()
