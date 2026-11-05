"""The stage-event pair must never be placed where it seals part of the Facility.

The pair stays solid after defeat and fills the top row of its block. A room's center
can sit right under a door, and with server blocks (solid on both rows) beside the door
nothing leads around the pair: the exit was cut off in Endless campaign seed 6.

Each test drives PFacHideoutKeepsWayOpen directly. The flood is the independent check:
the routine answering yes on a real generated layout must mean nothing was cut off.
"""
from __future__ import annotations

import random
import re
import unittest
from pathlib import Path

from audit_stage_hideout_partner import GRID_BASE, GRID_SIZE, GRID_STRIDE, RNG_STATE_BYTES, passable_tiles, stage_const, walkable_grid
from audit_stage_pair_blocks_exit import PFAC_FLOOR, flood
from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
SOURCE = (ROOT / "custom_functions/procedural_facility_gen.asm").read_text(errors="replace")
CUR_X = int(re.search(r"DEF wPFacCurX\s+EQU\s+(\d+)", SOURCE).group(1))
CUR_Y = int(re.search(r"DEF wPFacCurY\s+EQU\s+(\d+)", SOURCE).group(1))
WALL_TOP, SERVER, WALL_LEFT, WALL_RIGHT, SOLID = 65, 97, 68, 70, 46
BX, BY = 10, 10  # shapes are written here, well inside the grid


class FacilityHideoutWayOpenTest(unittest.TestCase):
    def enter(self, seed: int) -> RedRogueHarness:
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        rng = random.Random(seed)
        for offset in range(RNG_STATE_BYTES):
            h.write8("wRandomTable", rng.randrange(1, 256), offset=offset)
        h.write8("wStageEvent", stage_const("STAGE_EVENT_JESSIE_JAMES") | (1 << stage_const("STAGE_EVENT_PHASE_SHIFT")))
        maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        h.preload_and_enter_wild_area(maps["PROCEDURAL_FACILITY"], "Procedural Facility")
        h.park_before_hijack()
        self.yes = h.hook_flag("PFacHideoutKeepsWayOpen.yes")
        self.no = h.hook_flag("PFacHideoutKeepsWayOpen.no")
        return h

    def allowed(self, h, bx: int, by: int) -> bool:
        h.write8("wBuffer", bx, offset=CUR_X)
        h.write8("wBuffer", by, offset=CUR_Y)
        yes, no = self.yes["count"], self.no["count"]
        h.call_routine("PFacHideoutKeepsWayOpen")
        answers = (self.yes["count"] - yes, self.no["count"] - no)
        self.assertIn(answers, ((1, 0), (0, 1)))
        return answers == (1, 0)

    def shape(self, h, north, west, east) -> bool:
        base = h.address("wOverworldMap") + GRID_BASE
        for row, blocks in ((BY - 1, north), (BY, (west, PFAC_FLOOR, east))):
            for column, block in enumerate(blocks):
                h.pyboy.memory[base + row * GRID_STRIDE + BX - 1 + column] = block
        return self.allowed(h, BX, BY)

    def test_block_shapes(self) -> None:
        h = self.enter(1)
        floor = PFAC_FLOOR
        # The sealed room: door above, servers beside it.
        self.assertFalse(self.shape(h, (SERVER, floor, SERVER), floor, floor))
        # The same door in plain wall: the walkable bottom row leads round the pair.
        self.assertTrue(self.shape(h, (WALL_TOP, floor, WALL_TOP), floor, floor))
        # A server on one side only still leaves the other way round.
        self.assertTrue(self.shape(h, (SERVER, floor, WALL_TOP), floor, floor))
        # A corridor between solid walls: nothing goes round.
        self.assertFalse(self.shape(h, (WALL_LEFT, floor, WALL_RIGHT), SOLID, SOLID))
        # Side walls 68 and 70 keep a walkable inner column, and that does go round.
        self.assertTrue(self.shape(h, (WALL_LEFT, floor, WALL_RIGHT), WALL_LEFT, WALL_RIGHT))
        # Solid above: nothing up there to cut off.
        self.assertTrue(self.shape(h, (SERVER, SERVER, SERVER), floor, floor))
        # The open middle of a room.
        self.assertTrue(self.shape(h, (floor, floor, floor), floor, floor))

    def test_allowed_blocks_cut_nothing_off_on_real_layouts(self) -> None:
        blockset = (ROOT / "gfx/blocksets/facility.bst").read_bytes()
        passable = passable_tiles("Facility_Coll")
        for seed in (2, 3, 4):
            h = self.enter(seed)
            base = h.address("wOverworldMap") + GRID_BASE
            grid = [[h.pyboy.memory[base + y * GRID_STRIDE + x] for x in range(GRID_SIZE)] for y in range(GRID_SIZE)]
            walkable = walkable_grid(grid, blockset, passable)
            player = (h.read8("wXCoord"), h.read8("wYCoord"))
            free = flood(walkable, player, {}, set())
            refused = allowed = 0
            for by in range(1, GRID_SIZE - 1):
                for bx in range(1, GRID_SIZE - 1):
                    solid = {(bx * 2, by * 2), (bx * 2 + 1, by * 2)}
                    if grid[by][bx] != PFAC_FLOOR or player in solid:
                        continue
                    if not self.allowed(h, bx, by):
                        refused += 1
                        continue
                    allowed += 1
                    seen = flood(walkable, player, {}, solid)
                    self.assertEqual(free - solid - seen, set(), f"seed {seed}: block ({bx},{by}) cut floor off")
            self.assertGreater(allowed, 0)
            self.assertGreater(refused, 0, "a routine that refuses nothing proves nothing")


if __name__ == "__main__":
    unittest.main()
