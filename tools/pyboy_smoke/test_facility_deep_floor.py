"""The Facility's deep floor (PROCEDURAL_DEEP_FLOOR_PLAN.md, Facility SPEC X1-X5).

X3's gate: the decision, the first descent generating floor 2 in the seam, the
climb and the second descent, with the exchange, each floor's arrival on its own
subroom pad, floor 2's closed exits and removed objects, the follower, and the
Facility-wide state the generation must give back. The trips use the engine's
scripted-warp path (BIT_WARP_FROM_CUR_SCRIPT -> WarpFound2) aimed at the live
floor's subroom pad, the warp the post-pass arms that pad with.
"""

from __future__ import annotations

import unittest
from pathlib import Path

import save_reload
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
from test_optional_cold_moves import SPECIES

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
FAC = MAPS["PROCEDURAL_FACILITY"]
SUBROOM = MAPS["PROCEDURAL_FACILITY_SUBROOM"]
PADS = parse_rgbds_constants(ROOT / "constants/facility_pad_site_constants.asm")
TOGGLES = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
FIRST_PAD = PADS["FACILITY_FIRST_PAD_WARP"]
# NUM_FACILITY_PAD_SITES is a REDEF count the parser cannot evaluate: count the sites.
NUM_PAD_SITES = sum(1 for line in (ROOT / "constants/facility_pad_site_constants.asm").read_text().splitlines()
                    if line.strip().startswith("pad_site "))
assert NUM_PAD_SITES > 0
MAP_SIZE, STATE_SIZE, BLOCK_SIZE = 600, 102, 21
MAGIC, MAGIC_MASK = 0xE0, 0xE0
LIVE_2, MADE, FAST_FADE, BALLS_2, ENC_2 = 0x01, 0x02, 0x04, 0x08, 0x10
FLOOR_BIT = 0x80
RAM = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")
PSYCHIC_PACKAGE = RAM["OPTIONAL_PACKAGE_PSYCHIC"]
ENC_STATE_BIT = 0x08                    # BIT_OPTIONAL_ON_FLOOR_2
NERD_SLOT, ENC_SLOT = 12, 13
GENERIC_SLOT = 14                       # FACILITY_GENERIC
WALL, EXIT_N, EXIT_E, EXIT_W = 46, 0x08, 0x04, 0x05


def ring_exits(buffer) -> list[int]:
    """The exit doorway blocks on a 26-stride Facility map's outer ring."""
    at = lambda x, y: buffer[81 + 26 * y + x]
    return ([at(x, 0) for x in range(20) if at(x, 0) == EXIT_N]
            + [at(0, y) for y in range(20) if at(0, y) == EXIT_W]
            + [at(19, y) for y in range(20) if at(19, y) == EXIT_E])


class FacilityDeepFloorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.allow_deep_facility_floor = True

    def tearDown(self) -> None:
        self.h.close()

    # --- state -----------------------------------------------------------
    def ctrl(self) -> list[int]:
        return self.h.read_sram_bytes("sProcForestStagingBuffer", 2, bank=0)

    def live(self) -> bytes:
        return bytes(self.h.read_sram_bytes("sProcFacilityStagingBuffer", MAP_SIZE + STATE_SIZE, bank=1))

    def shadow(self) -> bytes:
        h = self.h
        return (bytes(h.read_sram_bytes("sProcCaveStagingBuffer", MAP_SIZE, bank=0))
                + bytes(h.read_sram_bytes("sProcForestExitI", STATE_SIZE, bank=0)))

    def subroom_pad(self) -> int:
        return self.h.read_sram_bytes("sProcFacilityGenScratch", 8, bank=1)[7]

    def floor(self) -> int:
        return 2 if self.h.read8("wRogueFlagsBitfield2") & FLOOR_BIT else 1

    # --- fixtures --------------------------------------------------------
    def deep_facility(self, balls_2: bool | None = None, before_preload=None) -> None:
        h = self.h
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        if before_preload:
            before_preload()
        if balls_2 is not None:
            def coin(_context) -> None:
                b = h.pyboy.register_file.B
                h.pyboy.register_file.B = (b | BALLS_2) if balls_2 else (b & ~BALLS_2 & 0xFF)
            h.register_hook("FacilityDeepLobbyDecide.haveCtrl", coin)
        h.preload_and_enter_wild_area(FAC, "facility")
        h.wait_until(lambda: h.read8("hJoyIgnore") == 0, "settled", 900)
        h.tick(60)
        h.write8("wProcFacilityWildBudget", 0)

    def deep_facility_with_encounter(self, map_name: str) -> None:
        """A deep Facility whose lobby rolled a Psychic encounter for map_name."""
        h = self.h

        def force(_context) -> None:
            for i, value in enumerate((SPECIES["PSYDUCK"], PSYCHIC_PACKAGE, 20, 0, 0, 0, 0)):
                h.write8("wOptionalEncounterSpecies", value, offset=i)
            h.write8("wOptionalEncounterMap", MAPS[map_name])

        h.register_hook("FacilityDeepLobbyDecide", force)
        self.deep_facility()

    def spot(self, slot: int) -> tuple[int, int]:
        h = self.h
        return h.read8(f"wSprite{slot:02d}StateData2MapX"), h.read8(f"wSprite{slot:02d}StateData2MapY")

    def picture(self, slot: int) -> int:
        return self.h.read8(f"wSprite{slot:02d}StateData1")

    def trip(self, description: str, zero_budget: bool = True) -> None:
        """A same-map warp to the live floor's subroom pad (the post-pass's marker)."""
        h = self.h
        pad = self.subroom_pad()
        self.assertLess(pad, NUM_PAD_SITES, f"{description}: no subroom pad")
        self.assertEqual(h.warp_entries()[FIRST_PAD + pad][2:], [FIRST_PAD + pad, FAC],
                         f"{description}: the subroom pad is not armed at its own warp")
        # Issue the warp right after the map script has run (a quiet point of the
        # overworld loop), and wait for it to run again on the new floor. Issued
        # straight after the fixture's settle, the scripted warp left the map
        # script idle for the rest of the test on DMG, so floor 2's first entry
        # (the block X7 gates) never ran and its test passed vacuously (measured
        # 2026-11-19, probe_facility_deep_* in the plan's Facility status).
        script = h.hook_flag("ProceduralFacility_Script")
        h.wait_until(lambda: script["count"] > 0, f"{description}: the map script runs", 300)
        h.write8("hWarpDestinationMap", FAC)
        h.write8("wDestinationWarpID", FIRST_PAD + pad)
        h.write8("wStatusFlags3", h.read8("wStatusFlags3") | 1 << 3)   # BIT_WARP_FROM_CUR_SCRIPT
        seen = h.hook_flag("WarpFound2")
        h.wait_until(lambda: seen["count"] > 0, f"{description}: the warp", 300)
        h.wait_until(lambda: h.read8("hCurMap") == FAC and h.read8("hJoyIgnore") == 0,
                     f"{description}: settled", 1500)
        ran = script["count"]
        h.wait_until(lambda: script["count"] > ran, f"{description}: the map script runs on arrival", 600)
        h.tick(120)
        if zero_budget:
            h.write8("wProcFacilityWildBudget", 0)

    def pad_hop(self, description: str) -> None:
        """An ordinary pad warp (to another pad, not the subroom's): leaves the
        player standing on a pad, as every real trip starts."""
        h = self.h
        pad = self.subroom_pad()
        entries = h.warp_entries()
        pick = next(i for i in range(FIRST_PAD, FIRST_PAD + NUM_PAD_SITES)
                    if i != FIRST_PAD + pad and entries[i][3] == FAC and entries[i][0] != 0xFF)
        script = h.hook_flag("ProceduralFacility_Script")
        h.wait_until(lambda: script["count"] > 0, f"{description}: the map script runs", 300)
        h.write8("hWarpDestinationMap", FAC)
        h.write8("wDestinationWarpID", entries[pick][2])
        h.write8("wStatusFlags3", h.read8("wStatusFlags3") | 1 << 3)   # BIT_WARP_FROM_CUR_SCRIPT
        seen = h.hook_flag("WarpFound2")
        h.wait_until(lambda: seen["count"] > 0, f"{description}: the warp", 300)
        ran = script["count"]
        h.wait_until(lambda: script["count"] > ran and h.read8("hJoyIgnore") == 0,
                     f"{description}: arrived", 1500)
        h.tick(60)
        h.write8("wProcFacilityWildBudget", 0)

    def test_only_the_first_descent_fades_fast(self) -> None:
        """FACILITY_WARP_TIME_2026-11-19.md: the first descent's fades run fast
        to hide floor 2's generation; no other warp, and the transient control
        bit never outlives the warp."""
        h = self.h
        self.deep_facility()
        self.pad_hop("onto a pad")
        out = h.hook_flag("FastWarpFadeOutToWhite")
        back = h.hook_flag("FastWarpFadeInFromWhite")
        ordinary = h.hook_flag("GBCFadeOutToWhite")
        self.trip("down, first")
        self.assertEqual((out["count"], back["count"]), (1, 1), "the first descent did not fade fast")
        self.assertEqual(self.ctrl()[0] & FAST_FADE, 0, "the fast-fade bit outlived the warp")
        for description in ("up", "down again"):
            self.trip(description)
        self.pad_hop("an ordinary pad on floor 2")
        self.assertEqual((out["count"], back["count"]), (1, 1), "a later warp faded fast")
        self.assertEqual(self.ctrl()[0] & FAST_FADE, 0)
        if h.hardware_mode == "CGB":
            self.assertGreaterEqual(ordinary["count"], 3, "the later warps skipped the ordinary fade")

    def on_own_pad(self, description: str) -> None:
        h = self.h
        pad = self.subroom_pad()
        self.assertEqual([h.read8("wYCoord"), h.read8("wXCoord")], h.warp_entries()[FIRST_PAD + pad][:2],
                         f"{description}: not on this floor's subroom pad")

    # --- tests -----------------------------------------------------------
    def test_lobby_decides_and_the_default_is_ordinary(self) -> None:
        h = self.h
        self.deep_facility()
        ctrl = self.ctrl()
        self.assertEqual(ctrl[0] ^ ctrl[1], 0xFF, f"control pair {ctrl}")
        self.assertEqual(ctrl[0] & MAGIC_MASK, MAGIC, "not decided deep")
        self.assertEqual(ctrl[0] & (LIVE_2 | MADE), 0)
        self.assertEqual(self.floor(), 1)
        self.assertEqual(h.read8("wStatusFlags2") & 0xC0, 0, "floor 2's balls start taken")
        self.assertNotEqual(h.read8("wOptionalEncounterMap"), SUBROOM, "the subroom kept its encounter")
        ordinary = RedRogueHarness(ROOT, ARTIFACTS)
        try:
            ordinary.boot_to_lobby(battle_count=11, encounter_kind=4)
            ordinary.write8("wStageEvent", 0)
            ordinary.preload_and_enter_wild_area(FAC, "facility")
            self.assertEqual(ordinary.read_sram_bytes("sProcForestStagingBuffer", 2, bank=0), [0x00, 0xFF],
                             "the harness's default Facility is not ordinary")
        finally:
            ordinary.close()

    def test_first_descent_generates_floor_2_and_climbs_back(self) -> None:
        h = self.h
        self.deep_facility()
        floor1 = self.live()
        finalizes = h.hook_flag("PFacFinalize")
        # Facility-wide markers floor 2's generation must give back.
        h.write8("wProcFacilityWildBudget", 3)
        door = h.read8("wRogueDoorSelection")
        h.write8("wRogueDoorSelection", door ^ 0x40)
        # Floor 1's boss beaten and ball 3 taken: floor 2's first entry must not
        # show them again (X7's gate).
        for name in ("TOGGLE_WILD_AREA_BOSS", "TOGGLE_WILD_AREA_POKEBALL_3"):
            n = TOGGLES[name]
            h.write8("wToggleableObjectFlags", h.read8("wToggleableObjectFlags", offset=n // 8) | 1 << n % 8,
                     offset=n // 8)
        toggles = h.read_bytes("wToggleableObjectFlags", 32)

        self.trip("down", zero_budget=False)
        self.assertTrue(h.read_sram_bytes("sProcFacilityItemGot", 1, bank=1)[0] & 0x80,
                        "floor 2's first entry did not run, so its gate was not exercised")
        after = h.read_bytes("wToggleableObjectFlags", 32)
        nerd = TOGGLES["TOGGLE_FACILITY_SUPER_NERD"]
        self.assertEqual(after[nerd // 8] >> nerd % 8 & 1, 0, "the resident is hidden on floor 2")
        # His toggle is the one deliberate change: floor 1 hid him, floor 2 shows him.
        per_floor = {TOGGLES["TOGGLE_WILD_AREA_POKEBALL_1"], TOGGLES["TOGGLE_WILD_AREA_POKEBALL_2"], nerd}
        for i in range(32 * 8):
            if i not in per_floor:
                self.assertEqual(after[i // 8] >> i % 8 & 1, toggles[i // 8] >> i % 8 & 1,
                                 f"floor 2's first entry changed toggle ${i:02x}")
        self.assertEqual(self.floor(), 2)
        ctrl = self.ctrl()
        self.assertEqual(ctrl[0] ^ ctrl[1], 0xFF)
        self.assertEqual(ctrl[0] & (LIVE_2 | MADE), LIVE_2 | MADE, f"ctrl {ctrl[0]:02x}")
        self.assertEqual(self.shadow(), floor1, "floor 1 is not safe in the shadow")
        floor2 = self.live()
        self.assertNotEqual(floor2[:MAP_SIZE], floor1[:MAP_SIZE], "floor 2 is floor 1's map")
        self.assertEqual(floor2[MAP_SIZE + 3:MAP_SIZE + 5], floor1[MAP_SIZE + 3:MAP_SIZE + 5],
                         "floor 2 did not take floor 1's boss")
        self.assertEqual(h.read_sram_bytes("sProcFacilityBaked", 1, bank=1), [1], "floor 2 not baked")
        self.assertEqual(finalizes["count"], 2, "floor 2 was not generated once in the seam")
        self.on_own_pad("down")
        self.assertEqual(h.read8("wRogueDoorSelection"), door ^ 0x40, "the lobby's door choice changed")
        self.assertEqual(h.read_bytes("wRogueItem", 8)[::2],
                         h.read_sram_bytes("sProcFacilityBallItems", 4, bank=1),
                         "the balls' items are not floor 2's own")
        self.assertEqual(h.read8("wProcFacilityWildBudget"), 3, "floor 2 refilled the wild budget")
        h.write8("wProcFacilityWildBudget", 0)
        self.assertEqual(len(ring_exits(floor1)), 1, "floor 1's exit doorway is not on the ring (the scan is blind)")
        self.assertEqual(ring_exits(floor2), [], "floor 2's exit doorway is still open")
        warps = h.warp_entries()
        self.assertEqual((warps[1][0], warps[2][0]), (0xFF, 0xFF), "floor 2's exit warps are armed")
        removed = (1, 4, 5, 6, 7, 8, 9, 10, 11) if ctrl[0] & BALLS_2 else (1, 3, 4, 5, 6, 7, 8, 9, 10, 11)
        for slot in removed:
            self.assertEqual(h.read8(f"wSprite{slot:02d}StateData1"), 0, f"slot {slot} still has a picture")
            self.assertEqual((h.read8(f"wSprite{slot:02d}StateData2MapY"),
                              h.read8(f"wSprite{slot:02d}StateData2MapX")), (0, 0), f"slot {slot} not parked")
        self.assertNotEqual(h.read8("wSprite02StateData1"), 0, "floor 2's ball has no picture")
        self.assertNotEqual(h.read8("wSprite15StateData1PictureID"), 0, "no follower to check")
        self.assertEqual((h.read8("wSprite15StateData2MapY") - 4, h.read8("wSprite15StateData2MapX") - 4),
                         (h.read8("wYCoord"), h.read8("wXCoord")),
                         "the follower spawned away from the arrival")

        self.trip("up")
        self.assertEqual(self.floor(), 1)
        self.assertEqual(self.live()[:MAP_SIZE], floor1[:MAP_SIZE], "floor 1's map did not come back")
        self.assertEqual(self.shadow()[:MAP_SIZE], floor2[:MAP_SIZE], "floor 2 was not kept")
        self.assertEqual(self.ctrl()[0] & LIVE_2, 0)
        self.on_own_pad("up")

        self.trip("down again")
        self.assertEqual(self.floor(), 2)
        self.assertEqual(self.live()[:MAP_SIZE], floor2[:MAP_SIZE], "the second descent regenerated floor 2")
        self.on_own_pad("down again")

    def test_generic_trainer_on_floor_2_only(self) -> None:
        """GENERIC_TRAINER_ALL_AREAS_SPEC.md A2: rolled onto floor 2 (row 1, the
        Scientist), the generic trainer (object 14) is parked on floor 1, stands
        on a plain-floor block of floor 2, and keeps that tile after a climb and
        a second descent."""
        h = self.h
        hooks = []

        def setup() -> None:
            for label, value in (("FacilityGenericRoll.store", 1), ("FacilityGenericRoll.floor", 1)):
                def force(_context, value=value) -> None:
                    h.pyboy.register_file.A = value
                h.register_hook(label, force)
                hooks.append((label, force))

        try:
            self.deep_facility(before_preload=setup)
        finally:
            for label, force in hooks:
                h.unregister_hook(label, force)
        self.assertEqual(self.floor(), 1)
        self.assertEqual(self.picture(GENERIC_SLOT), 0, "he is on floor 1 too")
        self.trip("down")
        self.assertEqual(self.floor(), 2)
        picture, here = self.picture(GENERIC_SLOT), self.spot(GENERIC_SLOT)
        self.assertNotEqual(picture, 0, "no generic trainer on floor 2")
        self.assertNotEqual(h.read_sram_bytes("sWildGenericCell", 1, bank=0)[0], 0xFE, "no cell")
        bx, by = (here[0] - 4) // 2, (here[1] - 4) // 2
        block = h.pyboy.memory[h.address("wOverworldMap") + 81 + by * 26 + bx]
        self.assertEqual(block, 14, f"not plain floor at {(bx, by)}")          # PFAC_FLOOR
        self.trip("up")
        self.assertEqual(self.floor(), 1)
        self.assertEqual(self.picture(GENERIC_SLOT), 0, "he followed the player up")
        self.trip("down again")
        self.assertEqual((self.picture(GENERIC_SLOT), self.spot(GENERIC_SLOT)), (picture, here),
                         "floor 2's second visit moved him")

    def test_floor_2_hosts_the_resident_and_floor_1_does_not(self) -> None:
        h = self.h
        self.deep_facility()
        self.assertEqual(self.picture(NERD_SLOT), 0, "the resident stands on floor 1")
        nerd = TOGGLES["TOGGLE_FACILITY_SUPER_NERD"]
        self.trip("down")
        self.assertNotEqual(self.picture(NERD_SLOT), 0, "the resident has no picture on floor 2")
        self.assertEqual(h.read8("wToggleableObjectFlags", offset=nerd // 8) & 1 << nerd % 8, 0,
                         "the resident is hidden on floor 2")
        x, y = self.spot(NERD_SLOT)
        self.assertEqual((x % 2, y % 2), (1, 1), f"not on a block's bottom-right quadrant: {x},{y}")
        bx, by = (x - 5) // 2, (y - 5) // 2
        layout = h.read_bytes("wOverworldMap", 601)
        self.assertEqual(layout[81 + by * 26 + bx], 0x0E, "his block is not plain floor")
        for slot in range(1, 12):
            self.assertNotEqual(self.spot(slot), (x, y), f"slot {slot} stands on the resident")
        # The same spot every load: up and down again.
        self.trip("up")
        self.assertEqual(self.picture(NERD_SLOT), 0, "the resident stands on floor 1 after the climb")
        self.trip("down again")
        self.assertEqual(self.spot(NERD_SLOT), (x, y), "the resident moved between loads")
        # His fight is settled against floor 2's own state byte.
        h.write8("wSafariZoneGateCurScript", RAM["SCRIPT_SUPER_NERD_AFTER_BATTLE"])
        h.write8("wCurOpponent", 0)
        h.tick(30)
        for _ in range(20):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("wSafariZoneGateCurScript"), 0, "the battle was not settled")
        flags = h.read_sram_bytes("sProcFacilityItemGot", 1, bank=1)[0]
        self.assertEqual(flags & 3, 3, f"floor 2's WON/PAID not recorded: {flags:02x}")
        self.trip("up to floor 1")
        self.assertEqual(h.read_sram_bytes("sProcFacilityItemGot", 1, bank=1)[0] & 3, 0,
                         "floor 1's resident bits changed")

    def test_the_subroom_encounter_stands_on_floor_2(self) -> None:
        h = self.h
        self.deep_facility_with_encounter("PROCEDURAL_FACILITY_SUBROOM")
        self.assertEqual(h.read8("wOptionalEncounterMap"), FAC, "the decision did not move the encounter")
        self.assertTrue(h.read8("wOptionalEncounterState") & ENC_STATE_BIT, "floor-2 state bit not set")
        self.assertEqual(self.picture(ENC_SLOT), 0, "the encounter stands on floor 1")
        self.trip("down")
        self.assertNotEqual(self.picture(ENC_SLOT), 0, "the encounter is not on floor 2")
        mon = tuple(h.read_sram_bytes("sProcFacilityGenScratch", 10, bank=1)[8:10])
        nerd = self.spot(NERD_SLOT)
        self.assertNotEqual((2 * mon[0] + 5, 2 * mon[1] + 5), nerd, "the encounter's block is the resident's")
        self.assertLess(max(mon), 19, "no encounter spot stored")
        # It wanders, so its tile drifts; its stored spot is what every load starts from.
        self.trip("up")
        self.assertEqual(self.picture(ENC_SLOT), 0, "the encounter followed the player up")
        self.trip("down again")
        self.assertNotEqual(self.picture(ENC_SLOT), 0)
        self.assertEqual(tuple(h.read_sram_bytes("sProcFacilityGenScratch", 10, bank=1)[8:10]), mon)

    def test_floor_2_without_a_pad_leaves_an_ordinary_facility(self) -> None:
        """X3's .noWayUp, forced: floor 2's generation draws no subroom pad (its way
        back up), so the first descent flips floor 1 back in mid-seam and demotes the
        Facility. The player lands on floor 1's pad, the control word is ordinary,
        floor 1 is byte for byte itself, the encounter the decision moved goes back
        to the subroom (and loses its floor-2 bit), and the pad leads to the subroom
        again on the next load."""
        h = self.h
        self.deep_facility_with_encounter("PROCEDURAL_FACILITY_SUBROOM")
        self.assertTrue(h.read8("wOptionalEncounterState") & ENC_STATE_BIT)
        floor1 = self.live()
        pad1 = self.subroom_pad()

        def no_pad(_context) -> None:
            if h.read8("wRogueFlagsBitfield2") & FLOOR_BIT:      # floor 2's generation only
                h.pyboy.register_file.A = 0
        h.register_hook("PFacPlaceSubroomPad.counted", no_pad)
        self.trip("down")
        h.unregister_hook("PFacPlaceSubroomPad.counted", no_pad)
        self.assertEqual(self.floor(), 1, "stranded on a floor 2 with no way up")
        self.assertEqual(self.ctrl(), [0x00, 0xFF], "the Facility is still deep")
        self.assertEqual(self.live()[:MAP_SIZE], floor1[:MAP_SIZE], "floor 1 did not come back")
        self.assertEqual(self.subroom_pad(), pad1)
        self.on_own_pad("the demoted descent")
        self.assertEqual(h.read8("wOptionalEncounterMap"), SUBROOM, "the encounter did not go back to the subroom")
        self.assertFalse(h.read8("wOptionalEncounterState") & ENC_STATE_BIT, "the floor-2 bit survived the demotion")
        self.assertEqual(h.warp_entries()[FIRST_PAD + pad1][3], SUBROOM, "the pad does not lead to the subroom")

    def test_a_main_map_encounter_stays_on_floor_1(self) -> None:
        h = self.h
        self.deep_facility_with_encounter("PROCEDURAL_FACILITY")
        self.assertFalse(h.read8("wOptionalEncounterState") & ENC_STATE_BIT, "floor-2 state bit set")
        self.assertEqual(self.ctrl()[0] & ENC_2, 0)
        self.assertNotEqual(self.picture(ENC_SLOT), 0, "the encounter is not on floor 1")
        self.trip("down")
        self.assertEqual(self.picture(ENC_SLOT), 0, "a floor-1 encounter shows on floor 2")
        self.trip("up")
        self.assertNotEqual(self.picture(ENC_SLOT), 0, "the encounter is gone from floor 1")

    def toggle_bit(self, name: str) -> int:
        n = TOGGLES[name]
        return self.h.read8("wToggleableObjectFlags", offset=n // 8) >> n % 8 & 1

    def take(self, name: str) -> None:
        h = self.h
        n = TOGGLES[name]
        h.write8("wToggleableObjectFlags", h.read8("wToggleableObjectFlags", offset=n // 8) | 1 << n % 8,
                 offset=n // 8)

    def test_second_ball_is_per_floor(self) -> None:
        h = self.h
        self.deep_facility(balls_2=True)
        self.assertTrue(self.ctrl()[0] & BALLS_2)
        self.trip("down")
        self.assertNotEqual(self.picture(3), 0, "floor 2's second ball has no picture")
        x, y = self.spot(3)
        self.assertNotEqual((x, y), (0, 0), "floor 2's second ball is parked")
        for slot in (2, NERD_SLOT, ENC_SLOT):
            self.assertNotEqual(self.spot(slot), (x, y), f"ball 2 shares slot {slot}'s cell")
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_2"), 0, "floor 2's ball 2 starts taken")
        self.take("TOGGLE_WILD_AREA_POKEBALL_2")                      # taken on floor 2
        self.trip("up")
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_2"), 0, "floor 1's ball 2 took floor 2's")
        self.assertTrue(h.read8("wStatusFlags2") & 0x80, "floor 2's taken ball 2 was not kept")
        self.trip("down again")
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_2"), 1, "floor 2's ball 2 came back")

    def test_one_ball_floor_removes_ball_2(self) -> None:
        h = self.h
        self.deep_facility(balls_2=False)
        self.assertEqual(self.ctrl()[0] & BALLS_2, 0)
        self.trip("down")
        self.assertEqual(self.picture(3), 0, "a one-ball floor 2 shows ball 2")
        self.assertEqual(self.spot(3), (0, 0))
        self.assertNotEqual(self.picture(2), 0, "floor 2's one ball has no picture")

    def test_floor_2_ball_cannot_be_duplicated_by_a_reset(self) -> None:
        """Take floor 2's ball, climb, save, descend, cut the power: Continue must keep it taken."""
        h = self.h
        self.deep_facility()
        self.trip("down")
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_1"), 0, "floor 2's ball starts taken")
        self.take("TOGGLE_WILD_AREA_POKEBALL_1")
        self.trip("up")
        self.assertTrue(save_reload.settle(h))
        h.park_before_hijack()
        h.call_routine("SaveGameData")
        self.trip("down again")
        self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_1"), 1, "the ball came back on the second visit")
        reboot = save_reload.Reboot(save_reload.sram_image(h), cgb_mode=h.hardware_mode == "CGB")
        mine = self.h
        try:
            reboot.load()
            self.assertTrue(reboot.overworld, "Continue did not reach the overworld")
            r = reboot.h
            self.assertEqual(r.read8("wRogueFlagsBitfield2") & FLOOR_BIT, 0, "not the save's floor")
            self.assertTrue(r.read8("wStatusFlags2") & 0x40, "floor 2's ball is back after Continue")
            self.assertEqual(r.read_sram_bytes("sProcForestStagingBuffer", 1, bank=0)[0] & LIVE_2, 0,
                             "Continue left floor 2 live on floor 1")
            self.h = r
            self.trip("down after Continue")
            self.assertEqual(self.toggle_bit("TOGGLE_WILD_AREA_POKEBALL_1"), 1,
                             "floor 2's ball came back after Continue")
        finally:
            self.h = mine
            reboot.close()

    def test_save_and_continue_on_floor_2(self) -> None:
        h = self.h
        self.deep_facility()
        self.trip("down")
        floor2 = self.live()
        resident = self.spot(NERD_SLOT)
        self.assertTrue(save_reload.settle(h))
        h.park_before_hijack()
        h.call_routine("SaveGameData")
        reboot = save_reload.Reboot(save_reload.sram_image(h), cgb_mode=h.hardware_mode == "CGB")
        mine = self.h
        try:
            reboot.load()
            self.assertTrue(reboot.overworld, "Continue did not reach the overworld")
            self.h = reboot.h
            self.assertEqual(self.h.read8("hCurMap"), FAC)
            self.assertEqual(self.h.read8("wRogueFlagsBitfield2") & FLOOR_BIT, FLOOR_BIT)
            self.assertEqual(self.live(), floor2, "Continue changed floor 2")
            self.assertNotEqual(self.picture(NERD_SLOT), 0, "the resident is gone after Continue")
            self.assertEqual(self.spot(NERD_SLOT), resident, "the resident moved across Continue")
        finally:
            self.h = mine
            reboot.close()

    def test_stale_cave_and_forest_state_leaves_no_trace(self) -> None:
        """A Facility borrows the cave's map buffer and the Forest's state and map
        regions; whatever an earlier deep cave or Forest left there must not leak
        into its decision, its flip or either floor."""
        h = self.h

        def stale() -> None:
            h.write_sram_bytes("sProcCaveStagingBuffer", [0xA5] * MAP_SIZE, bank=0)
            h.write_sram_bytes("sProcForestExitI", [0x5A] * STATE_SIZE, bank=0)
            h.write_sram_bytes("sProcForestStagingBuffer", [0xC4, 0x3B] + [0xEE] * 40, bank=0)  # a Forest's valid control

        self.deep_facility(before_preload=stale)
        ctrl = self.ctrl()
        self.assertEqual(ctrl[0] ^ ctrl[1], 0xFF)
        self.assertEqual(ctrl[0] & MAGIC_MASK, MAGIC, "the Facility's decision did not rewrite the control")
        self.assertEqual(ctrl[0] & (LIVE_2 | MADE), 0, "a stale control marked floor 2 made or live")
        floor1 = self.live()
        self.trip("down")
        self.assertEqual(self.shadow(), floor1, "floor 1 is not safe in the shadow")
        self.trip("up")
        self.assertEqual(self.live(), floor1, "floor 1 did not come back intact")

    # --- one session across areas ------------------------------------------
    # The stale-state test above fakes what an earlier area leaves behind. These
    # two play it: a real deep Forest, both floors visited, left through its own
    # exit to the lobby, then a deep Facility in the same session (and the
    # reverse), so the lobby's real reset path runs between the two.
    FOREST = MAPS["PROCEDURAL_FOREST"]
    FOREST_OPENING_WARP, FOREST_ENTRANCE = 31, (18, 35)

    def forest_warp(self, warp: int, description: str) -> None:
        h = self.h
        entry = h.warp_entries()[warp]
        h.write8("hWarpDestinationMap", self.FOREST)
        h.write8("wDestinationWarpID", warp)
        h.write8("wStatusFlags3", h.read8("wStatusFlags3") | 1 << 3)   # BIT_WARP_FROM_CUR_SCRIPT
        seen = h.hook_flag("WarpFound2")
        h.wait_until(lambda: seen["count"] > 0, f"{description}: the warp", 300)
        h.wait_until(lambda: h.read8("hCurMap") == self.FOREST and h.read8("hJoyIgnore") == 0,
                     f"{description}: settled", 900)
        h.tick(120)
        h.write8("wProcForestWildBudget", 0)
        self.assertNotEqual(entry[0], 0xFF, f"{description}: warp {warp} is not armed")

    def leave_to_lobby(self, description: str) -> None:
        """Out through the area's own exit warp (LAST_MAP), as a cleared stage is left."""
        h = self.h
        here = h.read8("hCurMap")
        exit_warp = h.warp_entries()[1]
        self.assertNotEqual(exit_warp[0], 0xFF, f"{description}: the exit is closed")
        h.write8("hWarpDestinationMap", exit_warp[3])
        h.write8("wDestinationWarpID", exit_warp[2])
        h.write8("wStatusFlags3", h.read8("wStatusFlags3") | 1 << 3)
        h.wait_until(lambda: h.read8("hCurMap") == h.LOBBY_MAP and h.read8("hJoyIgnore") == 0,
                     f"{description}: back in the lobby from ${here:02x}", 1500)
        h.tick(120)
        self.assertEqual(self.floor(), 1, f"{description}: the lobby kept the floor-2 bit")

    def real_deep_forest_round_trip(self) -> None:
        h = self.h
        h.allow_deep_forest_floor = True
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(self.FOREST, "forest")
        h.write8("wProcForestWildBudget", 0)
        h.wait_until(lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == self.FOREST_ENTRANCE,
                     "forest: on the entrance", 600)
        h.tick(30)
        self.forest_warp(self.FOREST_OPENING_WARP, "forest down")
        self.assertEqual(self.floor(), 2, "the Forest's descent did not reach floor 2")
        self.forest_warp(self.FOREST_OPENING_WARP, "forest up")
        self.assertEqual(self.floor(), 1)
        self.leave_to_lobby("forest")

    def real_deep_facility_round_trip(self) -> bytes:
        h = self.h
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(FAC, "facility")
        h.wait_until(lambda: h.read8("hJoyIgnore") == 0, "facility: settled", 900)
        h.tick(60)
        h.write8("wProcFacilityWildBudget", 0)
        ctrl = self.ctrl()
        self.assertEqual(ctrl[0] ^ ctrl[1], 0xFF, f"facility control pair {ctrl}")
        self.assertEqual(ctrl[0] & (MAGIC_MASK | LIVE_2 | MADE), MAGIC, f"facility control {ctrl[0]:02x}")
        floor1 = self.live()
        self.trip("facility down")
        self.assertEqual(self.floor(), 2)
        self.assertEqual(self.shadow(), floor1, "floor 1 is not safe in the shadow")
        self.on_own_pad("facility down")
        floor2 = self.live()
        self.assertNotEqual(floor2[:MAP_SIZE], floor1[:MAP_SIZE], "floor 2 is floor 1's map")
        self.trip("facility up")
        self.assertEqual(self.floor(), 1)
        self.assertEqual(self.live(), floor1, "floor 1 did not come back intact")
        self.on_own_pad("facility up")
        return floor1

    def test_a_real_deep_forest_then_a_deep_facility(self) -> None:
        h = self.h
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        self.real_deep_forest_round_trip()
        self.real_deep_facility_round_trip()

    def test_a_real_deep_facility_then_a_deep_forest(self) -> None:
        h = self.h
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        self.real_deep_facility_round_trip()
        self.leave_to_lobby("facility")
        self.real_deep_forest_round_trip()

    def test_floor_2_script_gate_keeps_first_entry_objects_hidden(self) -> None:
        h = self.h
        self.deep_facility(balls_2=False)
        self.trip("down")
        for slot in (1, 3, 4, 5, 6, 7, 8, 9, 10, 11):
            self.assertEqual(self.picture(slot), 0, f"slot {slot} shows on floor 2")


if __name__ == "__main__":
    unittest.main()
