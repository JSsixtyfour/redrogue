"""The Cemetery resurrection NPC's presence and placement (spec D2, D5).

Object 5 on every floor map, no toggle: on his floor his picture and a cell,
elsewhere picture 0 and an off-grid park. The roll is forced at
CemResurrectorRoll.store; the Cemetery, its layout and the Channeler are real.
"""

from __future__ import annotations

import io
import re
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
W, H, STRIDE, BASE = 10, 9, 16, 51     # CEMAP_*
QUADRANT = (4, 6, 12, 14)              # bottom-left tile of TL, TR, BL, BR
SLOT = 5                               # CEMETERY_RESURRECTOR
ARRIVAL_BLOCK = (2, 4)                 # PCEM_ARRIVAL_BLOCK_X/Y
LAYOUTS = 8
ABSENT = 0xFF


def walkable_tiles() -> set[int]:
    text = (ROOT / "data/tilesets/collision_tile_ids.asm").read_text(encoding="utf-8")
    m = re.search(r"^Cemetery_Coll::\s*\n\s*coll_tiles\s+([^\n;]+)", text, re.M)
    return {int(t.strip().lstrip("$"), 16) for t in m.group(1).split(",")}


class CemeteryResurrectorPlacementTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.sprites = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
        self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.h.boot_to_lobby(battle_count=11, encounter_kind=4)
        self.h.write8("wStageEvent", 0)
        self.lobby = io.BytesIO()
        self.h.save_state(self.lobby)

    def tearDown(self) -> None:
        self.h.close()

    def enter(self, ordinal: int, offset: int = 0) -> None:
        h = self.h
        h.load_state(self.lobby)
        h.tick(offset * 7)

        def force(_context) -> None:
            h.pyboy.register_file.A = ordinal

        h.register_hook("CemResurrectorRoll.store", force)
        try:
            h.preload_and_enter_wild_area(self.maps["PROCEDURAL_CEMETERY_1"], "cemetery")
        finally:
            h.unregister_hook("CemResurrectorRoll.store", force)
        stored = h.read_sram_bytes("sProcCaveStagingBuffer", 6, bank=0)[5]  # CEM_DEEP_RES_ORD
        self.assertEqual(stored, ordinal)

    def picture(self, slot: int) -> int:
        return self.h.read8(f"wSprite{slot:02d}StateData1PictureID")

    def block(self, slot: int) -> tuple[int, int]:
        h = self.h
        x = h.read8(f"wSprite{slot:02d}StateData2MapX")
        y = h.read8(f"wSprite{slot:02d}StateData2MapY")
        return (x - 4) // 2, (y - 4) // 2

    def assert_parked(self) -> None:
        h = self.h
        self.assertEqual(self.picture(SLOT), 0)
        self.assertEqual(h.read8(f"wSprite{SLOT:02d}StateData2MapX"), 0)
        self.assertEqual(h.read8(f"wSprite{SLOT:02d}StateData2MapY"), 0)

    def test_on_floor_one_he_stands_on_a_clear_floor_cell(self) -> None:
        h = self.h
        blockset = (ROOT / "gfx/blocksets/cemetery.bst").read_bytes()
        walk = walkable_tiles()
        cells = set()
        for offset in range(LAYOUTS):
            self.enter(0, offset)
            self.assertEqual(self.picture(SLOT), self.sprites["SPRITE_GRANNY"])
            bx, by = self.block(SLOT)
            self.assertTrue(0 <= bx < W and 0 <= by < H, (bx, by))
            cells.add((bx, by))
            # The quadrant he stands on is walkable ground.
            block = h.pyboy.memory[h.address("wOverworldMap") + BASE + by * STRIDE + bx]
            self.assertIn(blockset[block * 16 + QUADRANT[0]], walk, f"layout {offset}")
            # Not on the ball; clear of the Channeler and the arrival block.
            self.assertNotEqual(self.block(1), (bx, by), f"layout {offset}: on the ball")
            others = [ARRIVAL_BLOCK]
            if self.picture(4):
                others.append(self.block(4))
            for ox, oy in others:
                self.assertFalse(abs(ox - bx) <= 1 and abs(oy - by) <= 1,
                                 f"layout {offset}: next to {(ox, oy)}")
            # His sheet has a walking base of its own (3-10), not another NPC's.
            base = h.read8(f"wSprite{SLOT:02d}StateData2ImageBaseOffset")
            self.assertTrue(3 <= base <= 10, base)
            for slot in range(1, 5):
                if self.picture(slot) and self.picture(slot) != self.picture(SLOT):
                    self.assertNotEqual(
                        h.read8(f"wSprite{slot:02d}StateData2ImageBaseOffset"), base, slot)
        self.assertGreater(len(cells), 1, "every layout gave the same cell")

    def test_absent_he_is_parked_without_a_picture(self) -> None:
        self.enter(ABSENT)
        self.assert_parked()

    def test_on_another_floor_he_is_parked_here(self) -> None:
        self.enter(1)   # floor 2
        self.assert_parked()
        self.enter(5)   # floor 4 (ordinal 5)
        self.assert_parked()

    def test_the_same_cell_on_every_load(self) -> None:
        h = self.h
        self.enter(0, 3)
        first = self.block(SLOT)
        self.assertNotEqual(first, (-2, -2))
        # The cell is not stored: the placement re-derives it from saved state
        # on every load. Move him away and run it again.
        h.write8(f"wSprite{SLOT:02d}StateData2MapX", 0)
        h.write8(f"wSprite{SLOT:02d}StateData2MapY", 0)
        h.park_before_hijack()
        h.call_routine("CemResurrectorPlace", limit=400000)
        self.assertEqual(self.block(SLOT), first)

    def test_odds_knob_is_sixty_percent(self) -> None:
        consts = parse_rgbds_constants(ROOT / "constants/cemetery_deep_constants.asm")
        self.assertEqual(round(consts["RESURRECT_ODDS"] / 256, 2), 0.6)


if __name__ == "__main__":
    unittest.main()
