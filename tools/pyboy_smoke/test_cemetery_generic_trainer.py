"""The Cemetery's generic route trainer (GENERIC_TRAINER_ALL_AREAS_SPEC.md, Phase 3).

Object CEMETERY_GENERIC (6) on all four floor maps, one per Cemetery on one floor
(an ordinal, as the resurrection NPC's). The rolls are forced: his row and floor
at CemGenericRoll.store / .floor, and the resurrector onto the same floor at
CemResurrectorRoll.store, so the two must keep apart. The Cemetery, its layout
and the Channeler are real. His cell is re-derived on every load (not stored).
"""

from __future__ import annotations

import io
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
from test_cemetery_resurrector_place import W, H, STRIDE, BASE, QUADRANT, ARRIVAL_BLOCK, walkable_tiles
from test_forest_generic_trainer import trainer_ids, FACING

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
SLOT = 6                       # CEMETERY_GENERIC
RESURRECTOR = 5
BEATEN_BIT = SLOT % 8          # wWildGenericBeaten
SCRIPT_END_BATTLE = 2          # PCemStageScriptPointers: default, start, end battle
POOL = [("CHANNELER", "SPRITE_CHANNELER"), ("GENTLEMAN", "SPRITE_GENTLEMAN")]
STEMS = {"CHANNELER": "Channeler", "GENTLEMAN": "Gentleman"}
LAYOUTS = 8


class CemeteryGenericTrainerTest(unittest.TestCase):
    CGB = False

    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.sprites = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
        self.trainers = trainer_ids()
        self.h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=self.CGB)
        self.h.boot_to_lobby(battle_count=11, encounter_kind=4, wild_type="cemetery")
        self.h.write8("wStageEvent", 0)
        self.lobby = io.BytesIO()
        self.h.save_state(self.lobby)

    def tearDown(self) -> None:
        self.h.close()

    def enter(self, row: int, ordinal: int = 0, offset: int = 0, resurrector: int = 0) -> None:
        h = self.h
        h.load_state(self.lobby)
        if offset:
            seed = offset * 37 + 11
            h.seed_rng((seed & 0xFF, (seed ^ 0xA5) & 0xFF, 0, 1))
        forces = (("CemGenericRoll.store", row), ("CemGenericRoll.floor", ordinal),
                  ("CemResurrectorRoll.store", resurrector))
        hooks = []
        for label, value in forces:
            def force(_context, value=value) -> None:
                h.pyboy.register_file.A = value
            h.register_hook(label, force)
            hooks.append((label, force))
        try:
            h.preload_and_enter_wild_area(self.maps["PROCEDURAL_CEMETERY_1"], "cemetery")
        finally:
            for label, force in hooks:
                h.unregister_hook(label, force)

    def picture(self, slot: int) -> int:
        return self.h.read8(f"wSprite{slot:02d}StateData1PictureID")

    def block(self, slot: int) -> tuple[int, int]:
        h = self.h
        return ((h.read8(f"wSprite{slot:02d}StateData2MapX") - 4) // 2,
                (h.read8(f"wSprite{slot:02d}StateData2MapY") - 4) // 2)

    def assert_parked(self) -> None:
        h = self.h
        self.assertEqual(self.picture(SLOT), 0)
        self.assertEqual(h.read8(f"wSprite{SLOT:02d}StateData2MapX"), 0)
        self.assertEqual(h.read8(f"wSprite{SLOT:02d}StateData2MapY"), 0)

    def assert_placed(self, row: int, label: str) -> tuple[int, int]:
        h = self.h
        name, sprite = POOL[row]
        self.assertEqual(self.picture(SLOT), self.sprites[sprite], label)
        bx, by = self.block(SLOT)
        self.assertTrue(0 <= bx < W and 0 <= by < H, (label, bx, by))
        blockset = (ROOT / "gfx/blocksets/cemetery.bst").read_bytes()
        block = h.pyboy.memory[h.address("wOverworldMap") + BASE + by * STRIDE + bx]
        self.assertIn(blockset[block * 16 + QUADRANT[0]], walkable_tiles(), f"{label}: not ground")
        self.assertNotEqual(self.block(1), (bx, by), f"{label}: on the ball")
        others = [ARRIVAL_BLOCK]
        for slot in (4, RESURRECTOR):            # the Channeler, the resurrector
            if self.picture(slot):
                others.append(self.block(slot))
        for ox, oy in others:
            self.assertFalse(abs(ox - bx) <= 1 and abs(oy - by) <= 1, f"{label}: next to {(ox, oy)}")
        self.assertEqual(h.read8("wMapSpriteExtraData", offset=(SLOT - 1) * 2), self.trainers[name], label)
        base = h.read8(f"wSprite{SLOT:02d}StateData2ImageBaseOffset")
        self.assertTrue(3 <= base <= 10, (label, base))
        return bx, by

    def test_floor_one_a_clear_ground_cell_apart_from_the_resurrector(self) -> None:
        cells = set()
        for offset in range(LAYOUTS):
            with self.subTest(offset=offset):
                self.enter(1, 0, offset)
                self.assertTrue(self.picture(RESURRECTOR), "the resurrector is not here")
                cells.add(self.assert_placed(0, f"layout {offset}"))
        self.assertGreater(len(cells), 1, "every layout gave the same cell")

    def test_both_classes_are_placed_as_themselves(self) -> None:
        for row in range(len(POOL)):
            with self.subTest(row=row):
                self.enter(row + 1, 0, 2)
                self.assert_placed(row, POOL[row][0])

    def test_absent_and_other_floors_park_him(self) -> None:
        self.enter(0)
        self.assert_parked()
        self.enter(1, 1)       # floor 2
        self.assert_parked()
        self.enter(1, 5)       # floor 4 (ordinal 5)
        self.assert_parked()

    def test_the_same_cell_on_every_load(self) -> None:
        h = self.h
        self.enter(1, 0, 3)
        first = self.block(SLOT)
        h.write8(f"wSprite{SLOT:02d}StateData2MapX", 0)
        h.write8(f"wSprite{SLOT:02d}StateData2MapY", 0)

        def floor_one(_context) -> None:
            h.pyboy.register_file.D = 0
            h.pyboy.register_file.E = 0

        h.register_hook("CemGenericPlace", floor_one)
        try:
            h.park_before_hijack()
            h.call_routine("CemGenericPlace", limit=400000)
        finally:
            h.unregister_hook("CemGenericPlace", floor_one)
        self.assertEqual(self.block(SLOT), first)

    def test_keep_table_holds_him(self) -> None:
        source = (ROOT / "custom_functions/stage_events.asm").read_text()
        for n in (1, 2, 3, 4):
            self.assertIn(f"db PROCEDURAL_CEMETERY_{n}, 0, 2, 3, CEMETERY_GENERIC", source)

    # ---- the battle ----------------------------------------------------------

    def talk(self, frames: int = 4000, until_battle: bool = True) -> list[int]:
        h = self.h
        state = {"opened": False}
        printed: list[int] = []

        def open_box(_context) -> None:
            if not state["opened"]:
                state["opened"] = True
                h.write8("hSpriteIndex", SLOT)
                h.pyboy.register_file.PC = h.symbols.get("DisplayTextID")[1]

        def printing(_context) -> None:
            printed.append(h.pyboy.register_file.HL)

        h.register_hook("JoypadOverworld", open_box)
        h.register_hook("PrintText", printing)
        try:
            for frame in range(frames):
                h.tick(1)
                if (until_battle and h.read8("hIsInBattle") == 2 and h.read8("wCurOpponent")
                        and h.read8("wEnemyPartyCount")):
                    break
                if state["opened"] and frame % 20 == 0:
                    h.tap("a", 2)
        finally:
            h.unregister_hook("JoypadOverworld", open_box)
            h.unregister_hook("PrintText", printing)
        return printed

    def test_battle_win_and_his_own_flag(self) -> None:
        h = self.h
        for row in (0, 1):
            with self.subTest(row=row):
                self.enter(row + 1, 0, 2)
                self.assertEqual(h.read8("wWildGenericBeaten") >> BEATEN_BIT & 1, 0)
                count_before = h.read8("wBattleCount")
                lines = []

                def done(_context) -> None:
                    lines.append(h.pyboy.register_file.HL)

                h.register_hook("FGTLine.done", done)
                try:
                    intro = self.talk()
                finally:
                    h.unregister_hook("FGTLine.done", done)
                self.assertIn(h.symbols.get("PCemGenericIntroText")[1], intro)
                stem = STEMS[POOL[row][0]]
                self.assertEqual(lines[:1], [h.symbols.get(f"FGT{stem}Intro")[1]], "not his class's line")
                self.assertEqual(h.read8("hIsInBattle"), 2, "talking starts a trainer battle")
                self.assertEqual(h.read8("wTrainerHeaderFlagBit"), SLOT)
                self.assertEqual(h.read8("wCurOpponent"), self.trainers[POOL[row][0]])
                self.assertTrue(1 <= h.read8("wEnemyPartyCount") <= 6)
                self.assertEqual(h.read8("wBattleCount"), count_before)
        picture = self.picture(SLOT)
        events = h.read_bytes("wEventFlags", 64)
        h.park_before_hijack()
        h.write8("hIsInBattle", 0)
        h.write8("hActiveSpriteIndex", SLOT)
        h.write8("wProceduralCemetery4CurScript", SCRIPT_END_BATTLE)   # shared by the four floors
        h.call_routine("ProceduralCemetery1_Script", limit=200000)
        self.assertEqual(h.read8("wWildGenericBeaten"), 1 << BEATEN_BIT, "his bit, and only his")
        self.assertEqual(h.read_bytes("wEventFlags", 64), events, "an event flag changed")
        self.assertEqual(self.picture(SLOT), picture, "the sprite stays")

    def test_once_beaten_the_after_line_and_a_new_cemetery_resets(self) -> None:
        h = self.h
        self.enter(1, 0, 2)
        h.write8("wWildGenericBeaten", 1 << BEATEN_BIT)
        printed = self.talk(frames=900, until_battle=False)
        self.assertIn(h.symbols.get("PCemGenericAfterText")[1], printed)
        self.assertNotIn(h.symbols.get("PCemGenericIntroText")[1], printed)
        self.enter(1, 0, 3)
        self.assertEqual(h.read8("wWildGenericBeaten") >> BEATEN_BIT & 1, 0)

    def test_sees_one_tile_and_no_further(self) -> None:
        h = self.h
        for distance, expected in ((1, 0xFF), (2, 0)):
            self.enter(1, 0, 2)
            dx, dy = FACING[h.read8(f"wSprite{SLOT:02d}StateData1FacingDirection")]
            h.park_before_hijack()
            h.write8("hActiveSpriteIndex", SLOT)
            h.write8("wTrainerSpriteOffset", SLOT * 16)
            h.write8(f"wSprite{SLOT:02d}StateData1", 0, offset=2)
            h.write8(f"wSprite{SLOT:02d}StateData1", (0x3c - dy * distance * 16) & 0xff, offset=4)
            h.write8(f"wSprite{SLOT:02d}StateData1", (0x40 - dx * distance * 16) & 0xff, offset=6)
            h.write8("wTrainerEngageDistance", 64)
            got = h.call_routine("TrainerEngage", capture=lambda hh: hh.read8("wTrainerSpriteOffset"))
            self.assertEqual(got, expected, f"distance {distance}")


if __name__ == "__main__":
    unittest.main()
