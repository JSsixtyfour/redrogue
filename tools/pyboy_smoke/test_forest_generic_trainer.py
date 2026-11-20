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
_EVENTS = parse_rgbds_constants(ROOT / "constants/event_constants.asm")
EVENT_BIT = _EVENTS["EVENT_BEAT_FOREST_GENERIC_TRAINER"]
EVENT_BEAT_BOSS = _EVENTS["EVENT_BEAT_PC_BOSS"]
SCRIPT_END_BATTLE = 2          # ProceduralForest_ScriptPointers: default, start battle, end battle
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

    def test_stands_clear_of_joy_jenny_and_the_burglar(self) -> None:
        for name in ("STAGE_EVENT_JOY", "STAGE_EVENT_JENNY", "STAGE_EVENT_BURGLAR"):
            with self.subTest(event=name):
                self.enter(4, self.ram[name], 2)   # Hiker: never the event's sprite
                tx, ty = self.assert_placed(3, name)
                for slot in (6, 7):
                    if self.picture(slot):
                        self.assertNotEqual(self.pos(slot), (tx, ty), f"{name}: on slot {slot}")

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

    # ---- the battle (D4, D5) -------------------------------------------------

    def engage_at(self, distance: int) -> int:
        """TrainerEngage with him `distance` tiles in front of the player, his
        screen pixels set the way the live scan sees them. Out: wTrainerSpriteOffset
        (0xff = engaged)."""
        h = self.h
        dx, dy = FACING[h.read8(f"wSprite{SLOT:02d}StateData1FacingDirection")]
        h.park_before_hijack()
        h.write8("hActiveSpriteIndex", SLOT)
        h.write8("wTrainerSpriteOffset", SLOT * 16)
        h.write8(f"wSprite{SLOT:02d}StateData1", 0, offset=2)
        h.write8(f"wSprite{SLOT:02d}StateData1", (0x3c - dy * distance * 16) & 0xff, offset=4)
        h.write8(f"wSprite{SLOT:02d}StateData1", (0x40 - dx * distance * 16) & 0xff, offset=6)
        h.write8("wTrainerEngageDistance", 64)
        # Read at the callee's return: an engagement keeps running in the frame
        # that call_routine resumes (the engine rewrites the offset).
        return h.call_routine("TrainerEngage", capture=lambda hh: hh.read8("wTrainerSpriteOffset"))

    def test_sees_one_tile_and_no_further(self) -> None:
        self.enter(4, 0, 2)
        self.assert_placed(3, "sight")
        self.assertEqual(self.engage_at(1), 0xFF, "adjacent: engages")
        self.enter(4, 0, 2)
        self.assertEqual(self.engage_at(2), 0, "two tiles: does not")

    def talk(self, frames: int = 4000, until_battle: bool = True) -> list[int]:
        """An A press facing him: DisplayTextID with his slot, then A through the
        text (until the battle is on, or for `frames`). Out: every PrintText hl."""
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

    def flag(self) -> int:
        return self.h.read8("wEventFlags", offset=EVENT_BIT // 8) >> (EVENT_BIT % 8) & 1

    def test_battle_is_a_roster_team_and_the_win_is_normal(self) -> None:
        h = self.h
        for row in (3, 5):                       # Hiker, Jr. Trainer F
            with self.subTest(row=row):
                self.enter(row + 1, 0, 2)
                self.assert_placed(row, "battle")
                count_before = h.read8("wBattleCount")
                self.assertEqual(self.flag(), 0, "a new Forest finds him unbeaten")
                intro = self.talk()
                self.assertIn(h.symbols.get("PFGenericIntroText")[1], intro)
                self.assertEqual(h.read8("hIsInBattle"), 2, "talking starts a trainer battle")
                self.assertEqual(h.read8("wTrainerHeaderFlagBit"), SLOT)
                self.assertEqual(h.read8("wCurOpponent"), self.opp(TABLE_CLASS[row]))
                party = h.read8("wEnemyPartyCount")
                self.assertTrue(1 <= party <= 6, party)
                self.assertTrue(all(h.read8("wEnemyPartySpecies", offset=i) for i in range(party)))
                self.assertEqual(h.read8("wBattleCount"), count_before)

    def test_a_win_sets_his_flag_and_keeps_him(self) -> None:
        h = self.h
        self.enter(4, 0, 2)
        picture = self.picture(SLOT)
        self.talk()
        self.assertEqual(h.read8("hIsInBattle"), 2)
        # The battle's end, through the map's own script: the header pick must
        # hand EndTrainerBattle HIS header (bit 9), not the boss's or the pair's.
        h.park_before_hijack()
        h.write8("hIsInBattle", 0)
        h.write8("hActiveSpriteIndex", SLOT)
        h.write8("wProceduralForestCurScript", SCRIPT_END_BATTLE)
        h.call_routine("ProceduralForest_Script", limit=200000)
        self.assertEqual(self.flag(), 1, "his flag, no other, is set")
        self.assertEqual(h.read8("wEventFlags", offset=EVENT_BEAT_BOSS // 8) >> (EVENT_BEAT_BOSS % 8) & 1, 0)
        self.assertEqual(self.picture(SLOT), picture, "the sprite stays")

    def test_once_beaten_he_gives_the_after_line_not_a_battle(self) -> None:
        h = self.h
        self.enter(4, 0, 2)
        h.write8("wEventFlags", h.read8("wEventFlags", offset=EVENT_BIT // 8) | 1 << (EVENT_BIT % 8),
                 offset=EVENT_BIT // 8)
        printed = self.talk(frames=900, until_battle=False)
        self.assertIn(h.symbols.get("PFGenericAfterText")[1], printed)
        self.assertNotIn(h.symbols.get("PFGenericIntroText")[1], printed)
        self.assertEqual(h.read8("hIsInBattle"), 0)

    def test_a_new_forest_finds_him_unbeaten(self) -> None:
        h = self.h
        self.enter(4, 0, 2)
        h.write8("wEventFlags", h.read8("wEventFlags", offset=EVENT_BIT // 8) | 1 << (EVENT_BIT % 8),
                 offset=EVENT_BIT // 8)
        self.assertEqual(self.flag(), 1)
        self.enter(4, 0, 3)                      # the next Forest's preload
        self.assertEqual(self.flag(), 0)


if __name__ == "__main__":
    unittest.main()
