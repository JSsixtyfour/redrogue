"""The cave's deep floor (FOLLOWUPS #73, PROCEDURAL_DEEP_FLOOR_PLAN.md).

Phase 1: the flip, alone, forced by the harness before any warp uses it.
Floor 2 is PROCEDURAL_CAVE_1 with the cave's SRAM state exchanged for a shadow
copy in the Facility's bank-1 section (custom_functions/cave_deep_floor.asm).
Two real caves are generated (A, then B over it) so the two floors differ in
every way a flip could get wrong; A is planted as the shadow.

  - the cave's lobby preload resets both floor bits and invalidates the control
  - a flip and a flip back restore every byte, and swap ball 1's toggle with
    its off-floor copy; a flip to the floor already live changes nothing; a
    cave that is not deep never flips
  - a load reconciles the live buffer with the saved floor bit, without
    touching WRAM, and the reconciled cave battles and saves normally
  - a reset without saving after a flip heals on Continue, both ways, with the
    toggles of the save point
"""

from __future__ import annotations

import io
import unittest
from pathlib import Path

import save_reload
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
CAVE = MAPS["PROCEDURAL_CAVE_1"]
assert MAPS.get("PROCEDURAL_CAVE_SUBROOM")
TOGGLES = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
BALL1 = TOGGLES["TOGGLE_WILD_AREA_POKEBALL_1"]
BALL2 = TOGGLES["TOGGLE_WILD_AREA_POKEBALL_2"]
EVENTS = parse_rgbds_constants(ROOT / "constants/event_constants.asm")
SAVED_EVENTS = ("EVENT_BEAT_PC_BOSS", "EVENT_BEAT_STAGE_EVENT_NPC_1", "EVENT_BEAT_STAGE_EVENT_NPC_2",
                "EVENT_BEAT_FACILITY_STAGE_NPC_1", "EVENT_BEAT_FACILITY_STAGE_NPC_2",
                "EVENT_PC_BOSS_OFFERED", "EVENT_PC_BUDGET_ENDED", "EVENT_PC_CALMED_SHOWN")
TAIL = 81 + 19 * 26 + 20
DYN_1, DYN_2 = 0xFD, 0xFC
NERD_BIT, MANIAC_BIT = 0x04, 0x08      # CAVESUB_STATE resident bits
STATE_SIZE = 23
MAP_SIZE = 600
MAGIC = 0xA0
SETTLED = 0x10
PLANTED = MAGIC | 0x02 | SETTLED  # a made, settled floor 2 in the shadow
UNDECIDED = 0x50
BIT_LIVE_2 = 0x01
BIT_MADE = 0x02
RESIDENT_MASK = 0x0C
FLOOR_BIT = 0x80      # wRogueFlagsBitfield2 bit 7
OFF_BALL_BIT = 0x40   # wStatusFlags2 bit 6
OFF_BALL2_BIT = 0x80  # wStatusFlags2 bit 7: ball 2's (D1)
FLAGS_OFFSET = STATE_SIZE + 2 + 18 + 10  # CAVE_DEEP_FLAGS in sProcFacilityGenScratch


def blocks(raw) -> list[int]:
    """The 20x20 block area of a 26-stride cave buffer."""
    return [raw[81 + y * 26 + x] for y in range(20) for x in range(20)]


class CaveDeepFloorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.allow_deep_cave_floor = True

    def tearDown(self) -> None:
        import os
        if os.environ.get("DEEP_DEBUG"):
            print(f"\n[{self._testMethodName}] frames={self.h.pyboy.frame_count}")
        self.h.close()

    # --- reading the three places floor state lives ---------------------
    def live(self) -> tuple[bytes, bytes]:
        h = self.h
        return (bytes(h.read_sram_bytes("sProcCaveStagingBuffer", MAP_SIZE, bank=0)),
                bytes(h.read_sram_bytes("sProcCaveStagingEntranceY", STATE_SIZE, bank=0)))

    def shadow(self) -> tuple[bytes, bytes]:
        h = self.h
        return (bytes(h.read_sram_bytes("sProcFacilityStagingBuffer", MAP_SIZE, bank=1)),
                bytes(h.read_sram_bytes("sProcFacilityGenScratch", STATE_SIZE, bank=1)))

    def ctrl(self) -> list[int]:
        return self.h.read_sram_bytes("sProcFacilityGenScratch", STATE_SIZE + 2, bank=1)[STATE_SIZE:]

    def set_ctrl(self, value: int) -> None:
        h = self.h
        raw = h.read_sram_bytes("sProcFacilityGenScratch", STATE_SIZE + 2, bank=1)
        raw[STATE_SIZE:] = [value, value ^ 0xFF]
        h.write_sram_bytes("sProcFacilityGenScratch", raw, bank=1)

    def balls2(self) -> bool:
        """Floor 2 keeps ball 2 too (CAVE_DEEP_FLAGS bit 0, D1)."""
        raw = self.h.read_sram_bytes("sProcFacilityGenScratch", FLAGS_OFFSET + 1, bank=1)
        return bool(raw[FLAGS_OFFSET] & 1)

    def force_balls2(self, on: bool) -> None:
        """The decision rolls the second ball from the deep roll's bit 0 (d)."""
        h = self.h

        def at_decide(_context) -> None:
            d = h.pyboy.register_file.D
            h.pyboy.register_file.D = (d | 1) if on else (d & 0xFE)
        h.register_hook("CaveDeepAfterFinalize.decide", at_decide)

    def ball1_byte(self) -> int:
        return self.h.read8("wToggleableObjectFlags", offset=BALL1 // 8)

    def wram_bits(self) -> tuple[int, int, int]:
        h = self.h
        return (h.read8("wRogueFlagsBitfield2") & FLOOR_BIT, h.read8("wStatusFlags2") & OFF_BALL_BIT,
                self.ball1_byte() & 1 << BALL1 % 8)

    def set_bit(self, label: str, mask: int, on: bool, offset: int = 0) -> None:
        h = self.h
        value = h.read8(label, offset=offset)
        h.write8(label, value | mask if on else value & ~mask & 0xFF, offset=offset)

    def flip_to(self, floor: int) -> None:
        # call_routine enters through Bankswitch, which leaves the callee's bank
        # in a; the argument is set at the routine's own entry instead.
        h = self.h

        def argument(_context) -> None:
            h.pyboy.register_file.A = floor

        h.register_hook("CaveDeepFlipTo", argument)
        try:
            h.park_before_hijack()
            h.call_routine("CaveDeepFlipTo")
        finally:
            h.unregister_hook("CaveDeepFlipTo", argument)

    def hop(self) -> None:
        """A same-map warp onto the cave entrance: a real map load."""
        h = self.h
        h.write8("wWarpEntries", 39, offset=0)     # entry maps disarm their entrance on load
        h.write8("wWarpEntries", 0, offset=2)
        h.write8("wWarpEntries", CAVE, offset=3)
        seen = h.hook_flag("WarpFound2")
        h.pyboy.button_press("down")
        try:
            h.wait_until(lambda: seen["count"] > 0, "the hop", 300)
            h.tick(30)
        finally:
            h.pyboy.button_release("down")
        h.tick(200)
        self.assertEqual(h.read8("hCurMap"), CAVE)
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (18, 39))

    def timed(self, trigger) -> int:
        """Run trigger (which starts a warp) and return the frames from
        WarpFound2 to the first JoypadOverworld after it (the visible load)."""
        h = self.h
        marks = {}

        def found(_context) -> None:
            marks.setdefault("found", h.pyboy.frame_count)

        def polled(_context) -> None:
            if "found" in marks:
                marks.setdefault("polled", h.pyboy.frame_count)

        h.register_hook("WarpFound2", found)
        h.register_hook("JoypadOverworld", polled)
        try:
            trigger(lambda: "found" in marks)
            h.wait_until(lambda: "polled" in marks, "the warp to settle", 900)
        finally:
            h.unregister_hook("WarpFound2", found)
            h.unregister_hook("JoypadOverworld", polled)
        h.tick(120)
        return marks["polled"] - marks["found"]

    def edge_warp(self, dest: int) -> int:
        """From the entrance tile: re-arm warp entry 0 at cave warp dest, press down."""
        h = self.h
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (18, 39), "not on the entrance")
        h.write8("wWarpEntries", 39, offset=0)
        h.write8("wWarpEntries", dest, offset=2)
        h.write8("wWarpEntries", CAVE, offset=3)
        # An edge warp fires on the collision only while BIT_STANDING_ON_WARP is
        # set (home/overworld.asm:269), which walking onto the tile sets. A ladder
        # arrival leaves it clear; floor 2's real way up is S4's entrance ladder.
        self.set_bit("wMovementFlags", 1 << 2, True)
        return self.timed(lambda started: self.press_until("down", started, "the edge warp"))

    def ladder_warp(self, slot: int, dest: int) -> int:
        """Standing on the ladder armed in warp entry slot: step off west, aim it at
        cave warp dest (as CaveDeepAfterFinalize will), step back on."""
        h = self.h
        y, x = h.warp_entries()[slot][:2]
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (x, y), "not on that ladder")
        self.press_until("left", lambda: h.read8("wXCoord") == x - 1, "off the ladder")
        h.tick(30)
        self.assertEqual(h.read8("wXCoord"), x - 1, "could not step off the ladder")
        h.write8("wWarpEntries", dest, offset=4 * slot + 2)
        h.write8("wWarpEntries", CAVE, offset=4 * slot + 3)
        return self.timed(lambda started: self.press_until("right", started, "back onto the ladder"))

    def press_until(self, button: str, done, description: str) -> None:
        h = self.h
        h.pyboy.button_press(button)
        try:
            h.wait_until(done, description, 600)
        finally:
            h.pyboy.button_release(button)

    def shown_blocks(self) -> list[int]:
        return blocks(self.h.read_bytes("wOverworldMap", MAP_SIZE + 1))

    # --- fixture: two real caves, A in the shadow, B live ---------------
    def two_caves(self) -> None:
        h = self.h
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        # The lobby reset must clear bits a previous cave left set.
        self.set_bit("wRogueFlagsBitfield2", FLOOR_BIT, True)
        self.set_bit("wStatusFlags2", OFF_BALL_BIT, True)
        self.set_ctrl(MAGIC | BIT_LIVE_2)
        seen = {}

        def at_decision(_context) -> None:
            seen.setdefault("ctrl", self.ctrl())

        h.register_hook("CaveDeepAfterFinalize", at_decision)
        try:
            h.preload_and_enter_wild_area(CAVE, "cave")
        finally:
            h.unregister_hook("CaveDeepAfterFinalize", at_decision)
        h.write8("wProcCaveWildBudget", 0)
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the cave entrance", 600)
        self.reset_ctrl = seen.get("ctrl")
        self.decided_ctrl = self.ctrl()
        self.reset_bits = self.wram_bits()[:2]
        # An ordinary cave from here: the hop below must not take a way down.
        self.set_ctrl(0)
        self.cave_a = self.live()
        self.assertEqual(self.shown_blocks(), blocks(self.cave_a[0]), "cave A is not what is shown")
        # Cave B: generate again in place, then a hop takes the fresh path.
        h.park_before_hijack()
        h.call_routine("PCPreloadCave", limit=60000)
        self.hop()
        h.write8("wProcCaveWildBudget", 0)
        self.cave_b = self.live()
        self.assertNotEqual(blocks(self.cave_a[0]), blocks(self.cave_b[0]), "the two caves match")
        self.assertEqual(self.shown_blocks(), blocks(self.cave_b[0]))
        # Plant A as floor 2, make the cave deep (B live, floor 1).
        h.write_sram_bytes("sProcFacilityStagingBuffer", self.cave_a[0], bank=1)
        raw = h.read_sram_bytes("sProcFacilityGenScratch", STATE_SIZE + 2, bank=1)
        raw[:STATE_SIZE] = self.cave_a[1]
        h.write_sram_bytes("sProcFacilityGenScratch", raw, bank=1)
        self.set_ctrl(PLANTED)

    # --- tests -----------------------------------------------------------
    def test_lobby_preload_resets_the_floor(self) -> None:
        self.two_caves()
        self.assertEqual(self.reset_ctrl, [UNDECIDED, UNDECIDED ^ 0xFF],
                         "the lobby preload did not leave the cave undecided")
        self.assertIn(self.decided_ctrl, ([0, 0xFF], [MAGIC, MAGIC ^ 0xFF]), "the first load did not decide")
        self.assertEqual(self.reset_bits, (0, 0), "a floor bit survived the lobby preload")

    def test_flip_and_back_restore_every_byte(self) -> None:
        h = self.h
        self.two_caves()
        # Distinguishable ball-1 states: this floor's hidden, the off-floor's shown.
        self.set_bit("wToggleableObjectFlags", 1 << BALL1 % 8, True, offset=BALL1 // 8)
        self.set_bit("wStatusFlags2", OFF_BALL_BIT, False)
        before = (self.live(), self.shadow(), self.ctrl(), h.read8("wRogueFlagsBitfield2"),
                  h.read8("wStatusFlags2"), self.ball1_byte())

        self.flip_to(1)
        self.assertEqual(self.live(), self.cave_a, "floor 2 is not live after the flip")
        self.assertEqual(self.shadow(), self.cave_b, "floor 1 is not in the shadow")
        self.assertEqual(self.ctrl(), [PLANTED | BIT_LIVE_2, (PLANTED | BIT_LIVE_2) ^ 0xFF])
        self.assertEqual(self.wram_bits(), (FLOOR_BIT, OFF_BALL_BIT, 0),
                         "floor bit or ball 1 not exchanged")
        self.assertEqual(h.read8("wRogueFlagsBitfield2") & 0x7F, before[3] & 0x7F, "other bits moved")
        self.assertEqual(h.read8("wStatusFlags2") & 0xBF, before[4] & 0xBF, "other bits moved")

        snapshot = (self.live(), self.shadow(), self.ctrl(), self.wram_bits())
        self.flip_to(1)
        self.assertEqual((self.live(), self.shadow(), self.ctrl(), self.wram_bits()), snapshot,
                         "a flip to the floor already live changed something")

        self.flip_to(0)
        after = (self.live(), self.shadow(), self.ctrl(), h.read8("wRogueFlagsBitfield2"),
                 h.read8("wStatusFlags2"), self.ball1_byte())
        self.assertEqual(after, before, "flip and back did not restore every byte")

    def test_a_cave_that_is_not_deep_never_flips(self) -> None:
        h = self.h
        self.two_caves()
        for ctrl in ([0, 0], [MAGIC, MAGIC], [0x50, 0xAF], [MAGIC | 2, 0x00]):
            with self.subTest(ctrl=ctrl):
                raw = h.read_sram_bytes("sProcFacilityGenScratch", STATE_SIZE + 2, bank=1)
                raw[STATE_SIZE:] = ctrl
                h.write_sram_bytes("sProcFacilityGenScratch", raw, bank=1)
                before = (self.live(), self.shadow(), self.wram_bits())
                self.flip_to(1)
                self.assertEqual((self.live(), self.shadow(), self.wram_bits()), before)

    def test_load_reconciles_and_the_cave_battles_and_saves(self) -> None:
        h = self.h
        self.two_caves()
        toggles = h.read_bytes("wToggleableObjectFlags", 32)
        status = h.read8("wStatusFlags2")
        # As if the save said floor 2: the next load must put A in the live buffer.
        self.set_bit("wRogueFlagsBitfield2", FLOOR_BIT, True)
        self.hop()
        self.assertEqual(self.live(), self.cave_a, "the load did not reconcile")
        self.assertEqual(self.shadow(), self.cave_b)
        self.assertEqual(self.shown_blocks(), blocks(self.cave_a[0]), "floor 2's map is not shown")
        self.assertEqual(h.read_bytes("wToggleableObjectFlags", 32), toggles, "reconcile touched toggles")
        self.assertEqual(h.read8("wStatusFlags2"), status, "reconcile touched the off-floor ball")

        # A wild battle on the reconciled floor, won, and back.
        h.write8("wProcCaveWildBudget", 5)
        h.write8("wGrassRate", 255)
        for step in ("right", "left") * 8:
            h.move_tile(step)
            if h.read8("hIsInBattle"):
                break
        self.assertTrue(h.read8("hIsInBattle"), "no wild battle started")
        back = h.hook_flag("JoypadOverworld")
        for _ in range(300):
            if h.read8("hIsInBattle"):
                h.write8("wEnemyMonHP", 0)
                h.write8("wEnemyMonHP", 0, offset=1)
            h.tap("a", 4)
            h.tick(6)
            if not h.read8("hIsInBattle") and back["count"]:
                break
        h.tick(60)
        self.assertEqual(h.read8("hIsInBattle"), 0, "the battle did not end")
        self.assertEqual(h.read8("hCurMap"), CAVE)
        self.assertEqual(self.live(), self.cave_a, "the battle moved the floors")
        self.assertEqual(self.shown_blocks(), blocks(self.cave_a[0]))

        # Save there, and Continue into the same floor.
        h.write8("wGrassRate", 0)
        self.assertTrue(save_reload.settle(h))
        h.park_before_hijack()
        h.call_routine("SaveGameData")
        reboot = save_reload.Reboot(save_reload.sram_image(h))
        try:
            reboot.load()
            self.assertTrue(reboot.overworld, "Continue did not reach the overworld")
            r = reboot.h
            self.assertEqual(r.read8("hCurMap"), CAVE)
            self.assertEqual(r.read8("wRogueFlagsBitfield2") & FLOOR_BIT, FLOOR_BIT)
            self.assertEqual(bytes(r.read_sram_bytes("sProcCaveStagingBuffer", MAP_SIZE, bank=0)),
                             self.cave_a[0], "Continue changed the live floor")
            self.assertEqual(blocks(r.read_bytes("wOverworldMap", MAP_SIZE + 1)), blocks(self.cave_a[0]))
        finally:
            reboot.close()

    def reset_without_saving(self, saved_floor: int) -> None:
        """Save on saved_floor, flip to the other floor, cut the power."""
        h = self.h
        self.two_caves()
        if saved_floor:
            self.flip_to(1)
        self.set_bit("wToggleableObjectFlags", 1 << BALL1 % 8, True, offset=BALL1 // 8)
        self.set_bit("wStatusFlags2", OFF_BALL_BIT, False)
        saved_bits = self.wram_bits()
        saved_toggles = h.read_bytes("wToggleableObjectFlags", 32)
        saved_live = self.live()
        self.assertTrue(save_reload.settle(h))
        h.park_before_hijack()
        h.call_routine("SaveGameData")
        self.flip_to(1 - saved_floor)
        self.assertNotEqual(self.live(), saved_live)
        reboot = save_reload.Reboot(save_reload.sram_image(h))
        try:
            reboot.load()
            self.assertTrue(reboot.overworld, "Continue did not reach the overworld")
            r = reboot.h
            self.assertEqual(r.read8("hCurMap"), CAVE)
            self.assertEqual(
                (r.read8("wRogueFlagsBitfield2") & FLOOR_BIT, r.read8("wStatusFlags2") & OFF_BALL_BIT,
                 r.read8("wToggleableObjectFlags", offset=BALL1 // 8) & 1 << BALL1 % 8),
                saved_bits, "the floor bits are not the save's")
            self.assertEqual(r.read_bytes("wToggleableObjectFlags", 32), saved_toggles)
            live = (bytes(r.read_sram_bytes("sProcCaveStagingBuffer", MAP_SIZE, bank=0)),
                    bytes(r.read_sram_bytes("sProcCaveStagingEntranceY", STATE_SIZE, bank=0)))
            self.assertEqual(live, saved_live, "Continue did not heal the live floor")
            self.assertEqual(blocks(r.read_bytes("wOverworldMap", MAP_SIZE + 1)), blocks(saved_live[0]))
            ctrl = r.read_sram_bytes("sProcFacilityGenScratch", STATE_SIZE + 2, bank=1)[STATE_SIZE:]
            want = PLANTED | (BIT_LIVE_2 if saved_floor else 0)
            self.assertEqual(ctrl, [want, want ^ 0xFF])
        finally:
            reboot.close()

    def test_reset_without_saving_heals_from_floor_2(self) -> None:
        self.reset_without_saving(0)

    def test_reset_without_saving_heals_from_floor_1(self) -> None:
        self.reset_without_saving(1)

    # --- Phase 2 S1-S3: the decision, the seam, floor 2's generation ------
    def deep_cave(self, before_preload=None) -> None:
        """A fresh cave with two dynamic ladders, forced deep, player on its
        entrance; then onto ladder A through the entrance (a same-map warp to
        cave warp 2, which is no way down and so must change nothing)."""
        h = self.h
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        if before_preload:
            before_preload()
        lobby = io.BytesIO()
        h.save_state(lobby)
        for seed in (None, 17, 53, 91, 137, 203, 251, 7):
            h.load_state(lobby)
            if seed is not None:
                h.seed_rng((seed, seed ^ 0xA5, 0, 1))
            h.preload_and_enter_wild_area(CAVE, "cave")
            tail = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 2, bank=0)
            if (tail[TAIL], tail[TAIL + 1]) == (DYN_1, DYN_2):
                break
        else:
            self.fail("no two-ladder cave")
        h.write8("wProcCaveWildBudget", 0)
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the cave entrance", 600)
        self.set_ctrl(MAGIC)
        if h.read8("wOptionalEncounterMap") == MAPS["PROCEDURAL_CAVE_SUBROOM"]:
            h.write8("wOptionalEncounterMap", CAVE)          # S1's move (switched off in the ROM)
        self.floor1 = self.live()
        self.edge_warp(2)
        self.ladder_a = h.warp_entries()[2][:2]           # (Y, X) of ladder A's tile
        self.assertEqual((h.read8("wYCoord"), h.read8("wXCoord")), tuple(self.ladder_a),
                         "the entrance to warp 2 did not land on ladder A")
        self.assertEqual(self.live(), self.floor1, "a way that is not down changed the floors")
        self.assertEqual(self.wram_bits()[0], 0)

    def externals(self) -> tuple:
        """What floor 2's generation must not change for the cave as a whole."""
        h = self.h
        return (h.read8("wRoguePokemon1"), h.read8("wRoguePokemonForm1"),
                h.read_bytes("wOptionalEncounterSpecies", 7),
                [h.event_is_set(EVENTS[name]) for name in SAVED_EVENTS],
                h.read_sram_bytes("sProcCavePalette", 10, bank=0), h.read8("wStageEvent"))

    def mark_externals(self) -> None:
        """Values the floor-2 preload would certainly replace."""
        h = self.h
        for name in SAVED_EVENTS:
            h.set_event(EVENTS[name])
        h.write8("wOptionalEncounterLevel", 0x37)
        h.write8("wOptionalEncounterMap", 0xEE)          # no map: never current
        tail = h.read_sram_bytes("sProcCavePalette", 10, bank=0)
        tail[0] = 2                                      # a palette the roll never makes
        tail[3:7] = [0x11, 0x12, 0x13, 0x14]             # the hideout
        h.write_sram_bytes("sProcCavePalette", tail, bank=0)

    def test_first_descent_generates_floor_2_and_climbs_back(self) -> None:
        h = self.h
        self.deep_cave()
        self.mark_externals()
        before = self.externals()
        toggles = h.read_bytes("wToggleableObjectFlags", 32)
        self.set_bit("wToggleableObjectFlags", 1 << BALL1 % 8, True, offset=BALL1 // 8)
        self.set_bit("wStatusFlags2", OFF_BALL_BIT, False)
        self.set_bit("wStatusFlags2", OFF_BALL2_BIT, False)
        # Floor 1's balls 2-4 taken: floor 2's first entry must not show them again
        # (ball 2 is exchanged with floor 2's own, which starts shown).
        for n in (2, 3, 4):
            t = TOGGLES[f"TOGGLE_WILD_AREA_POKEBALL_{n}"]
            self.set_bit("wToggleableObjectFlags", 1 << t % 8, True, offset=t // 8)
        toggles = h.read_bytes("wToggleableObjectFlags", 32)
        preloads = h.hook_flag("PCPreloadCave")
        # Floor 2 must not refill it. 0, not 3: a budget lets a wild battle start on
        # the step back onto the ladder (measured 2026-11-20 on CGB after an RNG
        # shift: hIsInBattle 1 there), and a refill would still show as non-zero.
        h.write8("wProcCaveWildBudget", 0)
        self.assertEqual(h.warp_entries()[2][2:], [0, CAVE], "floor 1's ladder A does not lead down")
        self.assertEqual(h.warp_entries()[3][2:], [1, CAVE], "floor 1's ladder B does not lead down")

        frames = self.ladder_warp(2, 0)
        self.first_descent_frames = frames
        self.assertEqual(h.read8("hCurMap"), CAVE)
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (18, 39), "not on floor 2's entrance")
        self.assertEqual(preloads["count"], 1, "floor 2 was not generated exactly once")
        ctrl = self.ctrl()
        self.assertEqual(ctrl[1], ctrl[0] ^ 0xFF)
        self.assertEqual(ctrl[0] & ~RESIDENT_MASK, MAGIC | BIT_MADE | BIT_LIVE_2 | SETTLED, f"control {ctrl}")
        self.assertLess((ctrl[0] & RESIDENT_MASK) >> 2, 3, "no resident rolled")
        self.assertEqual(self.shadow(), self.floor1, "floor 1 is not safe in the shadow")
        floor2 = self.live()
        self.assertNotEqual(blocks(floor2[0]), blocks(self.floor1[0]), "floor 2 is floor 1")
        self.assertEqual(self.shown_blocks(), blocks(floor2[0]), "floor 2 is not what is shown")
        self.assertEqual(h.read_sram_bytes("sProcCaveBaked", 1, bank=0), [1], "floor 2 was not baked")
        self.assertEqual(self.externals(), before, "floor 2's generation changed the cave's own state")
        after = h.read_bytes("wToggleableObjectFlags", 32)
        flip = 1 << BALL1 % 8 | 1 << BALL2 % 8
        assert BALL1 // 8 == BALL2 // 8
        self.assertEqual(after[BALL1 // 8] ^ toggles[BALL1 // 8], flip, "balls 1 and 2 were not exchanged")
        after[BALL1 // 8] ^= flip
        ignore = {TOGGLES["TOGGLE_CAVESUB_GAMBLER"], TOGGLES["TOGGLE_CAVESUB_SUPER_NERD"],
                  TOGGLES["TOGGLE_CAVESUB_BALL"], TOGGLES["TOGGLE_CAVE_GAMBLER"],
                  TOGGLES["TOGGLE_CAVE_SUPER_NERD"]}
        for i in range(256):
            if i in ignore:
                continue
            self.assertEqual(after[i // 8] >> i % 8 & 1, toggles[i // 8] >> i % 8 & 1,
                             f"floor 2's first entry changed toggle ${i:02x}")
        self.assertEqual(self.wram_bits()[:2], (FLOOR_BIT, OFF_BALL_BIT))
        self.assertEqual(h.read8("wProcCaveWildBudget"), 0, "floor 2 refilled the wild budget")
        h.write8("wProcCaveWildBudget", 0)              # no wild battle from here on
        self.assert_floor2_layout()

        # Up: floor 2's entrance ladder (the entrance block's bottom-right tile).
        self.timed(lambda started: self.press_until("right", started, "onto the entrance ladder"))
        self.assertEqual((h.read8("wYCoord"), h.read8("wXCoord")), tuple(self.ladder_a),
                         "did not climb out onto ladder A")
        self.assertEqual(self.live(), self.floor1, "floor 1 did not come back byte for byte")
        self.assertEqual(self.shadow(), floor2, "floor 2 was not kept")
        self.assertEqual(self.shown_blocks(), blocks(self.floor1[0]))
        self.assertEqual(self.wram_bits()[:2], (0, 0))
        back = h.read_bytes("wToggleableObjectFlags", 32)
        for i in range(256):
            if i not in ignore:
                self.assertEqual(back[i // 8] >> i % 8 & 1, toggles[i // 8] >> i % 8 & 1,
                                 f"the round trip changed toggle ${i:02x}")
        self.assertEqual(self.externals(), before)

        # Down again: no second generation, the same floor 2.
        again = self.ladder_warp(2, 0)
        self.assertEqual(preloads["count"], 1, "floor 2 was generated twice")
        self.assertEqual(self.live(), floor2, "floor 2 changed between visits")
        self.assertEqual(self.shown_blocks(), blocks(floor2[0]))
        self.assert_floor2_layout()
        print(f"\n[{type(self).__name__}] first descent {frames} frames, second {again}")
        if self.h.hardware_mode == "DMG":
            self.assertLessEqual(frames, 120, "the first descent is over the plan's 120-frame line")

    def assert_floor2_layout(self) -> None:
        """S4/S5 on every floor-2 load: warps, removed objects, the entrance ladder."""
        h = self.h
        warps = h.warp_entries()
        self.assertEqual(warps[0][0], 0xFF, "floor 2's entrance warp is armed")
        self.assertEqual(warps[1][2:], [3, CAVE], "floor 2's exit ladder does not climb to B")
        self.assertEqual(warps[2], [39, 19, 2, CAVE], "floor 2's entrance ladder does not climb to A")
        for n in range(3, 32):
            self.assertEqual(warps[n][0], 0xFF, f"floor 2 warp {n} armed")
        layout = h.read_bytes("wOverworldMap", MAP_SIZE + 1)
        self.assertEqual(layout[81 + 19 * 26 + 9], 40, "no entrance ladder drawn")
        exit_y, exit_x = h.read_sram_bytes("sProcCaveStagingExitY", 2, bank=0)
        ladders = [(x, y) for y in range(1, 19) for x in range(1, 19)
                   if layout[81 + y * 26 + x] == 40 and (x, y) != (exit_x, exit_y)]
        self.assertEqual(ladders, [], "floor 2 still has ladders down")
        removed = (1, 4, 5, 6, 7) if self.balls2() else (1, 3, 4, 5, 6, 7)
        for slot in removed:
            self.assertEqual(h.read8(f"wSprite{slot:02d}StateData1"), 0, f"slot {slot} still has a picture")
            self.assertEqual((h.read8(f"wSprite{slot:02d}StateData2MapY"),
                              h.read8(f"wSprite{slot:02d}StateData2MapX")), (0, 0), f"slot {slot} not parked")
        if self.balls2():
            pos = lambda s: (h.read8(f"wSprite{s:02d}StateData2MapY"), h.read8(f"wSprite{s:02d}StateData2MapX"))
            self.assertNotEqual(h.read8("wSprite03StateData1"), 0, "floor 2's second ball has no picture")
            self.assertNotEqual(pos(3), (0, 0), "floor 2's second ball is parked")
            others = {pos(s) for s in (2, 8, 9, 10) if h.read8(f"wSprite{s:02d}StateData1")}
            self.assertNotIn(pos(3), others, "floor 2's second ball shares a cell")

    def test_second_ball_is_per_floor(self) -> None:
        """D1: a two-ball floor 2 shows ball 2 on its own cell; taking it there
        leaves floor 1's ball 2 as it was, and it stays taken on the next visit."""
        h = self.h
        self.force_balls2(True)
        self.deep_cave()
        self.set_bit("wToggleableObjectFlags", 1 << BALL2 % 8, False, offset=BALL2 // 8)  # floor 1's: there
        h.write8("wProcCaveWildBudget", 0)
        self.ladder_warp(2, 0)
        self.assertTrue(self.balls2(), "the forced second ball was not recorded")
        self.assert_floor2_layout()
        hidden = lambda: bool(h.read8("wToggleableObjectFlags", offset=BALL2 // 8) & 1 << BALL2 % 8)
        self.assertFalse(hidden(), "floor 2's second ball starts taken")
        self.set_bit("wToggleableObjectFlags", 1 << BALL2 % 8, True, offset=BALL2 // 8)  # taken on floor 2
        self.timed(lambda started: self.press_until("right", started, "onto the entrance ladder"))
        self.assertEqual(h.read8("wRogueFlagsBitfield2") & FLOOR_BIT, 0, "not back on floor 1")
        self.assertFalse(hidden(), "floor 1's ball 2 took floor 2's")
        self.assertTrue(h.read8("wStatusFlags2") & OFF_BALL2_BIT, "floor 2's taken ball 2 was not kept")
        self.ladder_warp(2, 0)
        self.assertTrue(hidden(), "floor 2's ball 2 came back")

    def test_one_ball_floor_removes_ball_2(self) -> None:
        h = self.h
        self.force_balls2(False)
        self.deep_cave()
        h.write8("wProcCaveWildBudget", 0)
        self.ladder_warp(2, 0)
        self.assertFalse(self.balls2())
        self.assert_floor2_layout()

    def step_off_and_back(self, description: str) -> int:
        """Standing on a warp tile: step off whichever way is open, then back on."""
        h = self.h
        here = (h.read8("wXCoord"), h.read8("wYCoord"))
        back = {"left": "right", "right": "left", "up": "down", "down": "up"}
        for way in ("left", "up", "right", "down"):
            h.pyboy.button_press(way)
            for _ in range(40):
                h.tick(1)
                if (h.read8("wXCoord"), h.read8("wYCoord")) != here:
                    break
            h.pyboy.button_release(way)
            h.tick(30)
            if (h.read8("wXCoord"), h.read8("wYCoord")) != here:
                return self.timed(lambda started: self.press_until(back[way], started, description))
        self.fail(f"boxed in on {here}")

    def walk_to(self, goal, avoid_warps: bool = False) -> None:
        """Walk on the live 20x20 cave to tile goal, around every sprite with a
        picture (test_cave_subroom's room flood, fed this floor's blocks), and
        around every armed warp tile when avoid_warps is set."""
        import test_cave_subroom as cave
        h = self.h
        live = h.read_bytes("wOverworldMap", MAP_SIZE + 1)
        room = {"blocks": bytes(blocks(live)), "w": 20, "h": 20}
        blocked = set()
        if avoid_warps:
            blocked = {(x, y) for y, x, _dest, _map in h.warp_entries()
                       if y != 0xFF and (x, y) != goal}
        # A taken ball keeps its picture byte, but it is hidden and the player
        # walks through it (measured 2026-11-20 on 192f9284: from below the
        # taken ball, two steps up). The cave's toggles are the plain list:
        # (sprite slot, toggle index) pairs, $FF-terminated.
        hidden = set()
        pairs = h.read_bytes("wToggleableObjectList", 33)
        for i in range(0, 32, 2):
            if pairs[i] == 0xFF:
                break
            toggle = pairs[i + 1]
            if h.read8("wToggleableObjectFlags", offset=toggle // 8) & 1 << toggle % 8:
                hidden.add(pairs[i])
        for slot in range(1, 16):
            if h.read8(f"wSprite{slot:02d}StateData1") and slot not in hidden:
                tile = (h.read8(f"wSprite{slot:02d}StateData2MapX") - 4,
                        h.read8(f"wSprite{slot:02d}StateData2MapY") - 4)
                if tile != goal:
                    blocked.add(tile)
        start = (h.read8("wXCoord"), h.read8("wYCoord"))
        came = cave.room_reach(room, start, blocked)
        self.assertIn(goal, came, f"no path from {start} to {goal}")
        path = []
        at = goal
        while came[at]:
            at, button = came[at]
            path.append(button)
        for button in reversed(path):
            x, y = h.read8("wXCoord"), h.read8("wYCoord")
            dx, dy = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}[button]
            self.press_until(button, lambda x=x, y=y, dx=dx, dy=dy:
                             (h.read8("wXCoord"), h.read8("wYCoord")) == (x + dx, y + dy), "a step")
        h.tick(20)

    def test_floor_2_hosts_the_b1f_resident_and_cold_encounter(self) -> None:
        import test_optional_encounter as encounter
        from test_optional_cold_moves import SPECIES
        h = self.h

        def cold_onix() -> None:
            h.register_hook("OptionalCaveAssignEncounter",
                            lambda _: h.pyboy.memory.__setitem__(h.address("sProcCavePalette"), 1))

            def force(_context) -> None:
                h.write8("wOptionalEncounterSpecies", SPECIES["ONIX"])
                h.write8("wOptionalEncounterLevel", 30)

            h.register_hook("OptionalRollColdPackage", force)

        self.deep_cave(cold_onix)
        self.assertEqual(h.read8("wOptionalEncounterSpecies"), SPECIES["ONIX"], "no cold encounter rolled")
        self.assertEqual(h.read8("wOptionalEncounterMap"), CAVE)
        slot = "wSprite10StateData1"
        self.assertEqual(h.read8(slot), 0, "the encounter is on floor 1")
        self.ladder_warp(2, 0)
        # The resident: on floor 2's first ladder spot, as the cave's fallback pair.
        tail = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 5, bank=0)
        a, b, state, ex, ey = tail[TAIL:TAIL + 5]
        resident = (self.ctrl()[0] & RESIDENT_MASK) >> 2
        self.assertTrue(a & 0x80 and b & 0x40, f"no resident fallback pair: {a:02x} {b:02x}")
        rx, ry = a & 0x3F, b & 0x3F
        nerd = resident in (1, 2)
        self.assertEqual(bool(state & NERD_BIT), nerd)
        self.assertEqual(bool(state & MANIAC_BIT), resident == 2)
        rslot = 9 if nerd else 8
        self.assertTrue(h.read8(f"wSprite{rslot:02d}StateData1"), "the resident has no picture")
        self.assertEqual((h.read8(f"wSprite{rslot:02d}StateData2MapX"), h.read8(f"wSprite{rslot:02d}StateData2MapY")),
                         (2 * rx + 5, 2 * ry + 5), "the resident is not on its spot")
        toggle = TOGGLES["TOGGLE_CAVE_SUPER_NERD" if nerd else "TOGGLE_CAVE_GAMBLER"]
        self.assertFalse(h.read8("wToggleableObjectFlags", offset=toggle // 8) & 1 << toggle % 8,
                         "the resident is hidden")
        # The encounter: the second spot, its own sheet, at least 10 blocks from the resident.
        self.assertLess(max(ex, ey), 19, "no encounter spot")
        self.assertGreaterEqual(abs(ex - rx) + abs(ey - ry), 10)
        self.assertEqual(h.read8(slot), encounter.optional_sprite(h), "the encounter has no picture")
        self.assertEqual((h.read8("wSprite10StateData2MapX"), h.read8("wSprite10StateData2MapY")),
                         (2 * ex + 5, 2 * ey + 5))
        # Talk to it from any open side: the B1F's cold battle. Not always from
        # below: measured 2026-11-20, a spot on the floor's bottom corridor has
        # the border's raised rock under it (an elevation step, no path), and
        # the three other sides open.
        count = h.read8("wBattleCount")
        self.face_and_press_a((2 * ex + 1, 2 * ey + 1))
        self.mash_until(lambda: h.read8("hIsInBattle") == 1 and h.read8("wOptionalEncounterBattle") == 0
                        and h.read8("wEnemyMonCatchRate") & 8, "the cold battle starts")
        self.assertEqual(h.read8("wEnemyMonSpecies"), SPECIES["ONIX"])
        self.assertEqual(h.read8("wEnemyMonLevel"), 30)
        h.write8("wEnemyMonHP", 0)
        h.write8("wEnemyMonHP", 1, offset=1)
        self.mash_until(lambda: h.read8("hIsInBattle") == 0 and h.read8("wOptionalEncounterState") & 4,
                        "the battle, then the gift", 3000)
        h.tap("b")
        h.tick(60)
        self.assertEqual(h.read8("wBattleCount"), count, "the encounter counted as a stage battle")
        gift = [h.read8("wPartyMon1", offset=i * 44) for i in range(h.read8("wPartyCount"))]
        boxed = h.read8("wBoxMon1") if h.read8("wBoxCount") else None
        self.assertIn(SPECIES["ONIX"], gift + [boxed], "no Onix was given")
        self.assertEqual(h.read8(slot), 0, "the resolved encounter still shows")
        self.assertEqual(h.read8("wRogueFlagsBitfield2") & FLOOR_BIT, FLOOR_BIT)

    def test_generic_trainer_on_floor_2_only(self) -> None:
        """GENERIC_TRAINER_ALL_AREAS_SPEC.md A2: rolled onto floor 2 (row 1, the
        Hiker), the cave's generic trainer (object 11) is absent from floor 1,
        stands on floor 2's own candidate dead end, and is absent again above."""
        h = self.h
        hooks = []

        def setup() -> None:
            for label, value in (("CaveGenericRoll.store", 1), ("CaveGenericRoll.floor", 1)):
                def force(_context, value=value) -> None:
                    h.pyboy.register_file.A = value
                h.register_hook(label, force)
                hooks.append((label, force))

        try:
            self.deep_cave(setup)
        finally:
            for label, force in hooks:
                h.unregister_hook(label, force)
        self.assertEqual(h.read8("wSprite11StateData1"), 0, "he is on floor 1 too")
        self.assertEqual((h.read8("wSprite11StateData2MapY"), h.read8("wSprite11StateData2MapX")), (0, 0))
        self.ladder_warp(2, 0)
        h.write8("wProcCaveWildBudget", 0)       # floor 2 refills it
        cell = h.read_sram_bytes("sWildGenericCell", 1, bank=0)[0]
        picture = h.read8("wSprite11StateData1")
        here = (h.read8("wSprite11StateData2MapY"), h.read8("wSprite11StateData2MapX"))
        if cell == 0xFE:
            self.assertEqual(picture, 0, "absent but drawn")
        else:
            self.assertNotEqual(picture, 0, "no generic trainer on floor 2")
            self.assertNotEqual(here, (0, 0))
            ax, ay = h.read_sram_bytes("sStageEventHideoutAltX", 2, bank=0)
            hx, hy = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
            block = ((here[1] - 4) // 2, (here[0] - 4) // 2)
            self.assertIn(block, ((ax, ay), (hx, hy)), "not floor 2's candidate dead end")
        # Up by floor 2's entrance ladder, then down again: the same tile.
        self.timed(lambda started: self.press_until("right", started, "onto the entrance ladder"))
        self.assertEqual(self.wram_bits()[0], 0, "not back on floor 1")
        self.assertEqual(h.read8("wSprite11StateData1"), 0, "he followed the player up")
        self.ladder_warp(2, 0)
        h.write8("wProcCaveWildBudget", 0)
        self.assertEqual(h.read8("wSprite11StateData1"), picture)
        self.assertEqual((h.read8("wSprite11StateData2MapY"), h.read8("wSprite11StateData2MapX")), here,
                         "floor 2's second visit moved him")

    def face_and_press_a(self, target, avoid_warps: bool = False) -> None:
        """From a walkable tile next to target, face it and press A."""
        h = self.h
        x, y = target
        for side, face in (((x, y + 1), "up"), ((x - 1, y), "right"), ((x + 1, y), "left"), ((x, y - 1), "down")):
            try:
                self.walk_to(side, avoid_warps)
            except AssertionError:
                continue
            h.tap(face, 4)
            h.tick(10)
            h.tap("a", 4)
            h.tick(60)
            return
        self.fail(f"cannot stand next to {target}")

    def test_floor_2_ball_cannot_be_duplicated_by_a_reset(self) -> None:
        """The design note's dupe: take floor 2's ball, climb, save, descend, cut the
        power. Continue must keep the ball taken (the save holds the item)."""
        h = self.h
        self.deep_cave()
        self.ladder_warp(2, 0)
        bx, by = h.read8("wSprite02StateData2MapX") - 4, h.read8("wSprite02StateData2MapY") - 4
        self.assertTrue(h.read8("wSprite02StateData1"), "floor 2 has no ball")
        hidden = lambda r: r.read8("wToggleableObjectFlags", offset=BALL1 // 8) & 1 << BALL1 % 8
        self.assertFalse(hidden(h), "floor 2's ball starts hidden")
        self.face_and_press_a((bx, by))
        self.mash_until(lambda: hidden(h), "the ball is picked up", 600)
        for _ in range(10):
            h.tap("b", 4)
        h.tick(30)
        # Climb by the entrance ladder, save on floor 1, descend again. Around
        # the ladder: a path from the east crossed it (192f9284's layout).
        self.walk_to((18, 39), avoid_warps=True)
        self.timed(lambda started: self.press_until("right", started, "onto the entrance ladder"))
        self.assertEqual(self.wram_bits()[0], 0)
        self.assertTrue(save_reload.settle(h))
        h.park_before_hijack()
        h.call_routine("SaveGameData")
        self.ladder_warp(2, 0)
        self.assertTrue(hidden(h), "the ball came back on the second visit")
        reboot = save_reload.Reboot(save_reload.sram_image(h))
        try:
            reboot.load()
            self.assertTrue(reboot.overworld, "Continue did not reach the overworld")
            r = reboot.h
            self.assertEqual(r.read8("wRogueFlagsBitfield2") & FLOOR_BIT, 0, "not the save's floor")
            # The off-floor copy (floor 2's ball, as saved) must say taken.
            self.assertTrue(r.read8("wStatusFlags2") & OFF_BALL_BIT, "floor 2's ball is back after Continue")
            ctrl = r.read_sram_bytes("sProcFacilityGenScratch", STATE_SIZE + 2, bank=1)[STATE_SIZE]
            self.assertFalse(ctrl & BIT_LIVE_2, "Continue left floor 2 live on floor 1")
        finally:
            reboot.close()

    def test_save_and_continue_on_floor_2(self) -> None:
        h = self.h
        self.deep_cave()
        self.ladder_warp(2, 0)
        floor2 = self.live()
        self.assertTrue(save_reload.settle(h))
        h.park_before_hijack()
        h.call_routine("SaveGameData")
        reboot = save_reload.Reboot(save_reload.sram_image(h))
        mine = self.h
        try:
            reboot.load()
            self.assertTrue(reboot.overworld, "Continue did not reach the overworld")
            self.h = reboot.h
            self.assertEqual(self.h.read8("hCurMap"), CAVE)
            self.assertEqual(self.wram_bits()[0], FLOOR_BIT)
            self.assertEqual(self.live(), floor2, "Continue changed floor 2")
            self.assertEqual(self.shown_blocks(), blocks(floor2[0]))
            self.assert_floor2_layout()
        finally:
            self.h = mine
            reboot.close()

    def test_floor_2_boss_is_gone(self) -> None:
        """Floor 2 has no boss: facing its exit ladder (where floor 1's boss stands)
        and pressing A starts nothing, and the player can still move."""
        h = self.h
        self.deep_cave()
        self.ladder_warp(2, 0)
        h.write8("wProcCaveWildBudget", 0)
        # Take the floor's ball first, as a player would: measured 2026-11-20 on
        # 192f9284's layout, it stood in the one-tile corridor that is the only
        # way to the exit, and a taken ball no longer blocks.
        bx, by = h.read8("wSprite02StateData2MapX") - 4, h.read8("wSprite02StateData2MapY") - 4
        if h.read8("wSprite02StateData1"):
            hidden = lambda: h.read8("wToggleableObjectFlags", offset=BALL1 // 8) & 1 << BALL1 % 8
            self.face_and_press_a((bx, by), avoid_warps=True)
            self.mash_until(hidden, "the ball is picked up", 600)
            for _ in range(10):
                h.tap("b", 4)
            h.tick(30)
        y, x = h.warp_entries()[1][:2]
        self.face_and_press_a((x, y), avoid_warps=True)  # never across the exit itself
        self.assertEqual(h.read8("hIsInBattle"), 0, "something on the exit tile started a battle")
        here = (h.read8("wXCoord"), h.read8("wYCoord"))
        for way in ("left", "right", "up", "down"):
            h.pyboy.button_press(way)
            h.tick(24)
            h.pyboy.button_release(way)
            h.tick(8)
            if (h.read8("wXCoord"), h.read8("wYCoord")) != here:
                break
        self.assertNotEqual((h.read8("wXCoord"), h.read8("wYCoord")), here, "a text box holds the player")
        self.assertEqual(h.read8("hCurMap"), CAVE)

    def screen_text(self) -> str:
        out = []
        for tile in self.h.read_bytes("wTileMap", 360):
            if 0x80 <= tile <= 0x99:
                out.append(chr(ord("A") + tile - 0x80))
            elif 0xA0 <= tile <= 0xB9:
                out.append(chr(ord("a") + tile - 0xA0))
            else:
                out.append(" ")
        return "".join(out)

    def read_sign(self) -> str:
        """Press A at the entrance sign (bg_event 19,35) and return the text box,
        without crossing a ladder on the way (that would read the other floor)."""
        h = self.h
        floor = self.wram_bits()[0]
        h.write8("wProcCaveWildBudget", 0)
        self.face_and_press_a((19, 35), avoid_warps=True)
        self.assertEqual(self.wram_bits()[0], floor, "the walk to the sign changed floors")
        text = self.screen_text()
        for _ in range(6):
            h.tap("b", 4)
            h.tick(10)
        return text

    def test_sign_reads_true_on_both_floors(self) -> None:
        """The sign speaks for the whole cave: floor 2 has one ball and no boss, so
        a per-floor line ("four items", "guards the exit") was false there. Each
        floor keeps its own rolled variant; both lines now say "this cave"."""
        h = self.h
        lines = {0: "in this cave", 1: "this cave"}
        self.deep_cave()
        self.ladder_warp(2, 0)                 # ladder_warp starts on the ladder
        for floor in (2, 1):
            if floor == 1:                     # climb by floor 2's entrance ladder
                self.walk_to((18, 39), avoid_warps=True)
                self.timed(lambda started: self.press_until("right", started, "onto the entrance ladder"))
                self.assertEqual(self.wram_bits()[0], 0, "still on floor 2")
            self.assertEqual(self.wram_bits()[0], FLOOR_BIT if floor == 2 else 0)
            variant = h.read_sram_bytes("sProcCaveSignVariant", 1, bank=0)[0]
            self.assertIn(variant, lines, f"floor {floor} sign variant {variant}")
            text = self.read_sign()
            self.assertIn(lines[variant], text, f"floor {floor} sign: {text.split()!r}")
            self.assertIn("Four ITEMS lie" if variant == 0 else "guards", text)

    def test_exit_credits_once_and_the_next_facility_is_fresh(self) -> None:
        """Plan Phase 4: the boss beaten, a descent and climb, then floor 1's exit to
        the lobby credits WILD_AREA_EXIT_BATTLES exactly once (every hop rewrites
        wWarpedFromWhichMap to the cave, which the credit keys on). Then a Facility
        straight after: floor 2 was parked in the Facility's own SRAM, so the
        Facility must generate fresh, with its boss and balls shown."""
        h = self.h
        lobby = MAPS["INDIGO_PLATEAU_LOBBY"]
        facility = MAPS["PROCEDURAL_FACILITY"]
        rounds = parse_rgbds_constants(ROOT / "constants/round_constants.asm")
        exit_battles = parse_rgbds_constants(ROOT / "constants/balance_constants.asm",
                                             rounds)["WILD_AREA_EXIT_BATTLES"]
        boss = TOGGLES["TOGGLE_WILD_AREA_BOSS"]
        hidden = lambda index: h.read8("wToggleableObjectFlags", offset=index // 8) & 1 << index % 8

        self.deep_cave()
        # As if the boss were beaten and its join offer shown (as test_facility_self_warp).
        h.write8("wToggleableObjectFlags", h.read8("wToggleableObjectFlags", offset=boss // 8)
                 | 1 << boss % 8, offset=boss // 8)
        h.set_event(EVENTS["EVENT_BEAT_PC_BOSS"])
        h.set_event(EVENTS["EVENT_PC_BOSS_OFFERED"])
        h.write8("wLastMap", lobby)       # the harness door skips the write real play does
        battles = h.read8("wBattleCount")

        self.ladder_warp(2, 0)
        self.assertEqual(self.wram_bits()[0], FLOOR_BIT)
        self.walk_to((18, 39), avoid_warps=True)
        self.timed(lambda started: self.press_until("right", started, "onto the entrance ladder"))
        self.assertEqual(self.wram_bits()[0], 0, "still on floor 2")
        self.assertTrue(hidden(boss), "the beaten boss came back after a descent")
        self.assertEqual(h.read8("wBattleCount"), battles, "a floor hop credited battles")
        floor2_map = self.shadow()[0]

        y, x = h.warp_entries()[1][:2]
        self.assertNotEqual(y, 0xFF, "floor 1's exit is not armed")
        self.assertEqual(h.warp_entries()[1][3], 0xFF, "floor 1's exit is not the LAST_MAP warp")
        h.write8("wProcCaveWildBudget", 0)
        try:
            self.walk_to((x, y), avoid_warps=True)
        except AssertionError:
            pass                                      # the last step warps: judged below
        h.wait_until(lambda: h.read8("hCurMap") == lobby, "the exit to the lobby", 900)
        h.tick(180)
        self.assertEqual(h.read8("wBattleCount"), battles + exit_battles,
                         "the exit after a descent was not credited exactly once")
        self.assertEqual(h.read8("wRogueFlagsBitfield2") & FLOOR_BIT, 0)

        h.write8("wStageEvent", 0)                    # no arrival text box
        h.preload_and_enter_wild_area(facility, "facility")
        self.assertEqual(h.read8("hCurMap"), facility)
        fac_map = bytes(h.read_sram_bytes("sProcFacilityStagingBuffer", MAP_SIZE, bank=1))
        self.assertTrue(fac_map != floor2_map, "the Facility loaded the parked cave floor")
        self.assertFalse(hidden(boss), "the Facility's boss is hidden by the cave's")
        for ball in (1, 2, 3, 4):
            self.assertFalse(hidden(TOGGLES[f"TOGGLE_WILD_AREA_POKEBALL_{ball}"]),
                             f"the Facility's ball {ball} is hidden")
        self.assertEqual(h.read8("wRogueFlagsBitfield2") & FLOOR_BIT, 0)

    def mash_until(self, predicate, description: str, limit: int = 1800) -> None:
        for _ in range(limit):
            if predicate():
                return
            self.h.tap("a")
            self.h.tick(2)
        self.fail(f"timed out: {description}")

    def test_ladder_b_reaches_floor_2_exit_and_back(self) -> None:
        h = self.h
        self.deep_cave()
        floor1 = self.live()
        # Over to ladder B: ladder A aimed at cave warp 3 (no way down) lands on B.
        self.ladder_warp(2, 3)
        ladder_b = h.warp_entries()[3][:2]
        self.assertEqual([h.read8("wYCoord"), h.read8("wXCoord")], ladder_b, "not on ladder B")
        self.assertEqual(self.live(), floor1)
        # Down B: the first descent, onto floor 2's generated exit ladder.
        self.ladder_warp(3, 1)
        self.assertEqual(self.wram_bits()[0], FLOOR_BIT)
        exit_tile = h.warp_entries()[1][:2]                 # (Y, X), armed by finalize
        self.assertEqual([h.read8("wYCoord"), h.read8("wXCoord")], exit_tile,
                         "did not land on floor 2's exit ladder")
        y, x = exit_tile
        self.assertEqual((h.read8("wXBlockCoord"), h.read8("wYBlockCoord")), (x % 2, y % 2), "arrival parity")
        ptr = h.address("wOverworldMap") + 27 + (y // 2) * 26 + x // 2
        self.assertEqual(h.read_bytes("wCurrentTileBlockMapViewPointer", 2), [ptr & 255, ptr >> 8],
                         "arrival view pointer")
        self.assert_floor2_layout()
        # Up the exit ladder: floor 1's ladder B.
        self.step_off_and_back("back onto the exit ladder")
        self.assertEqual(self.wram_bits()[0], 0)
        self.assertEqual([h.read8("wYCoord"), h.read8("wXCoord")], ladder_b, "did not climb out onto B")
        self.assertEqual(self.live(), floor1, "floor 1 did not come back")


if __name__ == "__main__":
    unittest.main()
