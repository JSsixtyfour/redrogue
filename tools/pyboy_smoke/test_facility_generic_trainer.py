"""The Facility's generic route trainer (GENERIC_TRAINER_ALL_AREAS_SPEC.md, Phase 3).

Object FACILITY_GENERIC (14) of PROCEDURAL_FACILITY, one per Facility on one floor.
The roll is forced at FacilityGenericRoll.store (row + 1) and .floor; the
Facility, its generator, balls, boss and stage event are real. His cell is a
room's plain-floor block by PFacHideoutFindFloor's rule (which never seals a
door), more than two blocks from the hideout and on no ball (PFacGenericPick).
"""

from __future__ import annotations

import io
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
from test_forest_generic_trainer import trainer_ids, FACING

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
SLOT = 14                      # FACILITY_GENERIC
BEATEN_BIT = SLOT % 8          # wWildGenericBeaten
SCRIPT_END_BATTLE = 2          # ProceduralFacility_ScriptPointers: default, start, end battle
CELL_NONE = 0xFE
PFAC_STRIDE, PFAC_BASE, PFAC_FLOOR = 26, 81, 14
# WGTFacilityPool, in order: (class, its sprite).
POOL = [("SCIENTIST", "SPRITE_SCIENTIST"), ("ROCKET", "SPRITE_ROCKET"),
        ("BURGLAR", "SPRITE_SUPER_NERD"), ("SUPER_NERD", "SPRITE_SUPER_NERD"),
        ("ENGINEER", "SPRITE_SUPER_NERD"), ("JUGGLER", "SPRITE_ROCKER")]
STEMS = {"SCIENTIST": "Scientist", "ROCKET": "Rocket", "BURGLAR": "Burglar",
         "SUPER_NERD": "SuperNerd", "ENGINEER": "Engineer", "JUGGLER": "Juggler"}
LAYOUTS = 8


class FacilityGenericTrainerTest(unittest.TestCase):
    CGB = False

    def engage_at(self, distance: int) -> int:
        h = self.h
        dx, dy = FACING[h.read8(f"wSprite{SLOT:02d}StateData1FacingDirection")]
        h.park_before_hijack()
        h.write8("hActiveSpriteIndex", SLOT)
        h.write8("wTrainerSpriteOffset", SLOT * 16)
        h.write8(f"wSprite{SLOT:02d}StateData1", 0, offset=2)
        h.write8(f"wSprite{SLOT:02d}StateData1", (0x3c - dy * distance * 16) & 0xff, offset=4)
        h.write8(f"wSprite{SLOT:02d}StateData1", (0x40 - dx * distance * 16) & 0xff, offset=6)
        h.write8("wTrainerEngageDistance", 64)
        return h.call_routine("TrainerEngage", capture=lambda hh: hh.read8("wTrainerSpriteOffset"))

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

    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.sprites = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
        self.trainers = trainer_ids()
        self.h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=self.CGB)
        self.h.boot_to_lobby(battle_count=11, encounter_kind=4, wild_type="facility")
        self.lobby = io.BytesIO()
        self.h.save_state(self.lobby)

    def tearDown(self) -> None:
        self.h.close()

    def enter(self, row: int, offset: int = 0, event: int = 0) -> None:
        """A fresh Facility, his row forced (row + 1 at .store), floor 1."""
        h = self.h
        h.load_state(self.lobby)
        if offset:
            seed = offset * 37 + 11
            h.seed_rng((seed & 0xFF, (seed ^ 0xA5) & 0xFF, 0, 1))
        h.write8("wStageEvent", event)

        def force_row(_context) -> None:
            h.pyboy.register_file.A = row

        def force_floor(_context) -> None:
            h.pyboy.register_file.A = 0

        h.register_hook("FacilityGenericRoll.store", force_row)
        h.register_hook("FacilityGenericRoll.floor", force_floor)
        try:
            h.preload_and_enter_wild_area(self.maps["PROCEDURAL_FACILITY"], "facility")
        finally:
            h.unregister_hook("FacilityGenericRoll.store", force_row)
            h.unregister_hook("FacilityGenericRoll.floor", force_floor)

    def pos(self, slot: int) -> tuple[int, int]:
        h = self.h
        return (h.read8(f"wSprite{slot:02d}StateData2MapX") - 4,
                h.read8(f"wSprite{slot:02d}StateData2MapY") - 4)

    def picture(self, slot: int) -> int:
        return self.h.read8(f"wSprite{slot:02d}StateData1PictureID")

    def block(self, bx: int, by: int) -> int:
        h = self.h
        return h.pyboy.memory[h.address("wOverworldMap") + PFAC_BASE + by * PFAC_STRIDE + bx]

    def cell(self) -> int:
        return self.h.read_sram_bytes("sWildGenericCell", 1, bank=0)[0]

    def present(self, row: int) -> int:
        for offset in range(LAYOUTS * 3):
            self.enter(row + 1, offset)
            if self.picture(SLOT):
                return offset
        self.fail("no Facility holds him")

    def assert_placed(self, row: int, label: str) -> tuple[int, int]:
        h = self.h
        name, sprite = POOL[row]
        self.assertEqual(self.picture(SLOT), self.sprites[sprite], label)
        tx, ty = self.pos(SLOT)
        self.assertEqual((tx % 2, ty % 2), (0, 0), f"{label}: not a block's top-left step")
        bx, by = tx // 2, ty // 2
        self.assertEqual(self.block(bx, by), PFAC_FLOOR, f"{label}: not plain floor")
        hx, hy = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
        if hx != 0xFF:
            self.assertFalse(abs(hx - bx) <= 2 and abs(hy - by) <= 2,
                             f"{label}: next to the hideout {(hx, hy)}")
        for slot in range(1, 14):
            if self.picture(slot):
                self.assertNotEqual(self.pos(slot), (tx, ty), f"{label}: on slot {slot}")
        self.assertEqual(h.read8("wMapSpriteExtraData", offset=(SLOT - 1) * 2),
                         self.trainers[name], label)
        base = h.read8(f"wSprite{SLOT:02d}StateData2ImageBaseOffset")
        self.assertTrue(3 <= base <= 10, (label, base))
        return tx, ty

    def test_stands_on_plain_floor_clear_of_everything(self) -> None:
        placed, cells = 0, set()
        for offset in range(LAYOUTS):
            with self.subTest(offset=offset):
                self.enter(1, offset)
                if self.picture(SLOT):
                    cells.add(self.assert_placed(0, f"layout {offset}"))
                    placed += 1
                else:
                    self.assertEqual(self.cell(), CELL_NONE, "absent without a reason")
        self.assertGreaterEqual(placed, LAYOUTS - 1, "he is absent too often")
        self.assertGreater(len(cells), 1, "every layout gave the same cell")

    def test_every_pool_class_is_placed_as_itself(self) -> None:
        offset = self.present(0)
        for row in range(len(POOL)):
            with self.subTest(row=row):
                self.enter(row + 1, offset)
                self.assert_placed(row, POOL[row][0])

    def test_absent_he_is_parked_without_a_picture(self) -> None:
        self.enter(0)
        self.assertEqual(self.picture(SLOT), 0)
        self.assertEqual(self.pos(SLOT), (-4, -4))

    def test_keep_table_holds_him(self) -> None:
        source = (ROOT / "custom_functions/stage_events.asm").read_text()
        self.assertIn("db PROCEDURAL_FACILITY,   1, 10, 11, FACILITY_GENERIC", source)

    def test_sees_one_tile_and_no_further(self) -> None:
        offset = self.present(0)
        self.enter(1, offset)
        self.assertEqual(self.engage_at(1), 0xFF, "adjacent: engages")
        self.enter(1, offset)
        self.assertEqual(self.engage_at(2), 0, "two tiles: does not")

    def test_battle_win_and_his_own_flag(self) -> None:
        h = self.h
        offset = self.present(0)
        for row in (1, 5):                       # Rocket, Juggler
            with self.subTest(row=row):
                self.enter(row + 1, offset)
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
                self.assertIn(h.symbols.get("PFacGenericIntroText")[1], intro)
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
        h.write8("wProceduralCave1CurScript", SCRIPT_END_BATTLE)   # the Facility shares it
        h.call_routine("ProceduralFacility_Script", limit=200000)
        self.assertEqual(h.read8("wWildGenericBeaten"), 1 << BEATEN_BIT, "his bit, and only his")
        self.assertEqual(h.read_bytes("wEventFlags", 64), events, "an event flag changed")
        self.assertEqual(self.picture(SLOT), picture, "the sprite stays")

    def test_once_beaten_the_after_line_and_a_new_facility_resets(self) -> None:
        h = self.h
        offset = self.present(0)
        self.enter(1, offset)
        h.write8("wWildGenericBeaten", 1 << BEATEN_BIT)
        printed = self.talk(frames=900, until_battle=False)
        self.assertIn(h.symbols.get("PFacGenericAfterText")[1], printed)
        self.assertNotIn(h.symbols.get("PFacGenericIntroText")[1], printed)
        self.enter(1, offset + 1)
        self.assertEqual(h.read8("wWildGenericBeaten") >> BEATEN_BIT & 1, 0)


if __name__ == "__main__":
    unittest.main()
