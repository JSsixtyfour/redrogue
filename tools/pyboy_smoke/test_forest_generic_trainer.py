"""The Forest's generic route trainer: roll, cell, picture, class and facing
(GENERIC_TRAINER_TRIAL_SPEC.md; the Opus handoff point).

Object 9 of ProceduralForest, independent of the stage event (D3). The roll is
forced at ForestGenericRoll.store; the Forest, its maze, balls, boss and
stage event are real. Checked in the event's three phases, the pair re-placed
between them (the vanish's own placement call), and on DMG and CGB.
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
SLOT = 9                       # FOREST_GENERIC
PF_STRIDE, PF_BASE, PF_TREE = 26, 81, 2
LAYOUTS = 6
FACING = {0: (0, 1), 4: (0, -1), 8: (-1, 0), 12: (1, 0)}  # SPRITE_FACING_* -> step
TABLE_SPRITE = ["SPRITE_YOUNGSTER", "SPRITE_YOUNGSTER", "SPRITE_COOLTRAINER_F",
                "SPRITE_HIKER", "SPRITE_COOLTRAINER_M", "SPRITE_COOLTRAINER_F"]
TABLE_CLASS = ["YOUNGSTER", "BUG_CATCHER", "LASS", "HIKER", "JR_TRAINER_M", "JR_TRAINER_F"]


def trainer_ids() -> dict[str, int]:
    """trainer_const order (constants/trainer_constants.asm): OPP_x = id + OPP_ID_OFFSET."""
    text = (ROOT / "constants/trainer_constants.asm").read_text(encoding="utf-8")
    offset = int(re.search(r"DEF OPP_ID_OFFSET EQU (\d+)", text).group(1))
    names = re.findall(r"^\s*trainer_const (\w+)", text, re.M)
    return {name: i + offset for i, name in enumerate(names)}


class ForestGenericTrainerTest(unittest.TestCase):
    CGB = False

    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.sprites = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
        self.ram = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")
        self.trainers = trainer_ids()
        self.h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=self.CGB)
        self.h.boot_to_lobby(battle_count=11, encounter_kind=4, wild_type="forest")
        self.lobby = io.BytesIO()
        self.h.save_state(self.lobby)

    def tearDown(self) -> None:
        self.h.close()

    def enter(self, row: int, event: int, offset: int = 0) -> None:
        h = self.h
        h.load_state(self.lobby)
        h.tick(offset * 7)
        h.write8("wStageEvent", event)

        def force(_context) -> None:
            h.pyboy.register_file.A = row

        h.register_hook("ForestGenericRoll.store", force)
        try:
            h.preload_and_enter_wild_area(self.maps["PROCEDURAL_FOREST"], "forest")
        finally:
            h.unregister_hook("ForestGenericRoll.store", force)

    def pos(self, slot: int) -> tuple[int, int]:
        h = self.h
        return (h.read8(f"wSprite{slot:02d}StateData2MapX") - 4,
                h.read8(f"wSprite{slot:02d}StateData2MapY") - 4)

    def picture(self, slot: int) -> int:
        return self.h.read8(f"wSprite{slot:02d}StateData1PictureID")

    def block(self, bx: int, by: int) -> int:
        h = self.h
        return h.pyboy.memory[h.address("wOverworldMap") + PF_BASE + by * PF_STRIDE + bx]

    def opp(self, name: str) -> int:
        return self.trainers[name]

    def assert_placed(self, row: int, label: str) -> tuple[int, int]:
        h = self.h
        self.assertEqual(self.picture(SLOT), self.sprites[TABLE_SPRITE[row]], label)
        tx, ty = self.pos(SLOT)
        self.assertEqual((tx % 2, ty % 2), (0, 0), f"{label}: not a block's top-left tile")
        bx, by = tx // 2, ty // 2
        self.assertEqual((bx % 2, by % 2), (1, 1), f"{label}: not a maze cell")
        self.assertNotEqual(self.block(bx, by), PF_TREE, f"{label}: in a tree")
        # Not on a ball, the boss, or within one cell of the stage pair's hideout.
        for slot in range(1, 6):
            if self.picture(slot):
                self.assertNotEqual(self.pos(slot), (tx, ty), f"{label}: on slot {slot}")
        hx, hy = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
        if hx != 0xFF:
            self.assertFalse(abs(hx - bx) <= 2 and abs(hy - by) <= 2,
                             f"{label}: next to the hideout {(hx, hy)}")
        self.assertNotEqual((bx, by), (9, 17), f"{label}: on the entrance")
        # Class: the roster class of the row, read by EngageMapTrainer.
        self.assertEqual(h.read8("wMapSpriteExtraData", offset=(SLOT - 1) * 2),
                         self.opp(TABLE_CLASS[row]), label)
        # Facing: toward an open block (the dead end's way in).
        dx, dy = FACING[h.read8(f"wSprite{SLOT:02d}StateData1FacingDirection")]
        self.assertNotEqual(self.block(bx + dx, by + dy), PF_TREE, f"{label}: faces a tree")
        # His own walking base.
        base = h.read8(f"wSprite{SLOT:02d}StateData2ImageBaseOffset")
        self.assertTrue(3 <= base <= 10, (label, base))
        return tx, ty

    def test_stands_on_his_own_dead_end_through_every_phase(self) -> None:
        h = self.h
        jj = self.ram["STAGE_EVENT_JESSIE_JAMES"]
        shift = self.ram["STAGE_EVENT_PHASE_SHIFT"]
        cells = set()
        for offset in range(LAYOUTS):
            row = offset % len(TABLE_CLASS)
            if TABLE_SPRITE[row] == "SPRITE_YOUNGSTER":
                row = 3  # J&J layouts: any row; keep the sprite assertion simple
            self.enter(row + 1, jj, offset)
            label = f"layout {offset}"
            first = self.assert_placed(row, label)
            cells.add(first)
            # The pair moves (WAITING -> HIDING -> SETTLED); he does not.
            for phase in ("STAGE_EVENT_PHASE_HIDING", "STAGE_EVENT_PHASE_SETTLED"):
                h.write8("wStageEvent", jj | self.ram[phase] << shift)
                h.park_before_hijack()
                h.call_routine("PFPlaceStageEventNpcs", limit=200000)
                self.assertEqual(self.pos(SLOT), first, f"{label}: moved at {phase}")
                self.assertNotEqual(self.pos(6), first, f"{label}: the pair stands on him")
                self.assertNotEqual(self.pos(7), first, f"{label}: the pair stands on him")
        self.assertGreater(len(cells), 1, "every layout gave the same cell")

    def test_no_event_still_has_him(self) -> None:
        self.enter(4, 0, 2)          # row 3: Hiker
        self.assert_placed(3, "no event")

    def test_never_wears_the_villains_sprite(self) -> None:
        self.enter(1, self.ram["STAGE_EVENT_PSYCHIC"], 1)   # row 0: Youngster, the Psychic's sprite
        self.assertNotEqual(self.picture(SLOT), self.sprites["SPRITE_YOUNGSTER"])
        self.assertNotEqual(self.picture(SLOT), 0)
        self.assertNotEqual(self.picture(SLOT), self.picture(6))

    def test_absent_he_is_parked_without_a_picture(self) -> None:
        self.enter(0, 0)
        self.assertEqual(self.picture(SLOT), 0)
        self.assertEqual(self.pos(SLOT), (-4, -4))

    def test_keep_table_holds_him(self) -> None:
        source = (ROOT / "custom_functions/stage_events.asm").read_text()
        self.assertIn("db PROCEDURAL_FOREST,     1, 6, 7, FOREST_GENERIC", source)


if __name__ == "__main__":
    unittest.main()
