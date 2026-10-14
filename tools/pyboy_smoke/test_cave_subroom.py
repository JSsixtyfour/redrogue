"""The cave subroom (PROCEDURAL_SUBROOMS_PLAN Phase 4, cave).

PROCEDURAL_CAVE_SUBROOM is a drawn room (a placeholder cut from Mt. Moon B1F's
two-ladder chamber) with two ladders up, one per cave ladder down. Step 1
checks the map itself through real engine warps: the cave's entrance warp is
retargeted at each ladder in turn, the room's blocks load, the player lands on
that ladder, and stepping off and back on climbs out to the cave.
"""

from __future__ import annotations

import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
MAP_W, MAP_H = 8, 4                     # blocks
LADDERS = ((13, 3), (5, 5))             # warp tiles, in warp order


class CaveSubroomTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.blocks = (ROOT / "maps/ProceduralCaveSubroom.blk").read_bytes()
        self.h = RedRogueHarness(ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.h.close()

    def press_until(self, button: str, done, description: str) -> None:
        h = self.h
        h.pyboy.button_press(button)
        try:
            h.wait_until(done, description, 600)
        finally:
            h.pyboy.button_release(button)
        h.tick(120)

    def test_both_ladders_land_and_climb_out(self) -> None:
        h = self.h
        cave = self.maps["PROCEDURAL_CAVE_1"]
        room = self.maps["PROCEDURAL_CAVE_SUBROOM"]
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(cave, "cave")
        h.write8("wProcCaveWildBudget", 0)
        stride = MAP_W + 6
        for ladder, (lx, ly) in enumerate(LADDERS):
            with self.subTest(ladder=ladder):
                h.wait_until(lambda: h.read8("hCurMap") == cave and h.read8("wYCoord") == 39,
                             "on the cave entrance", 600)
                if ladder:
                    # Back by ladder onto the entrance: step off before the
                    # south edge will warp again.
                    self.press_until("up", lambda: h.read8("wYCoord") == 38, "off the entrance")
                h.write8("wWarpEntries", ladder, offset=2)
                h.write8("wWarpEntries", room, offset=3)
                self.press_until("down", lambda: h.read8("hCurMap") == room, "into the subroom")
                live = h.read_bytes("wOverworldMap", (MAP_H + 6) * stride)
                for y in range(MAP_H):
                    self.assertEqual(live[(y + 3) * stride + 3:(y + 3) * stride + 3 + MAP_W],
                                     list(self.blocks[y * MAP_W:(y + 1) * MAP_W]), f"block row {y}")
                self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (lx, ly),
                                 "not standing on the ladder")
                # Off the ladder (west: open floor beside both) and back on.
                self.press_until("left", lambda: h.read8("wXCoord") == lx - 1, "off the ladder")
                self.press_until("right", lambda: h.read8("hCurMap") == cave, "climb out")


if __name__ == "__main__":
    unittest.main()
