"""The cave's generic route trainer (GENERIC_TRAINER_ALL_AREAS_SPEC.md, Phase 2).

Object CAVE_GENERIC (11) of PROCEDURAL_CAVE_1, one per cave on one floor. The
roll is forced at CaveGenericRoll.store (row + 1) and .floor; the cave, its
generator, balls, boss and stage event are real. His cell is the hideout's
second candidate target (sStageEventHideoutAltX/Y), a carved dead end, unless the
hideout took it, it is the exit's, or a ball's: then he is absent.
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
SLOT = 11                      # CAVE_GENERIC
BEATEN_BIT = SLOT % 8          # wWildGenericBeaten
SCRIPT_END_BATTLE = 2          # ProceduralCave1_ScriptPointers: default, start battle, end battle
CELL_NONE = 0xFE
# WGTCavePool, in order: (class, its sprite).
POOL = [("HIKER", "SPRITE_HIKER"), ("SUPER_NERD", "SPRITE_SUPER_NERD"),
        ("POKEMANIAC", "SPRITE_SUPER_NERD"), ("BLACKBELT", "SPRITE_HIKER"),
        ("JR_TRAINER_F", "SPRITE_COOLTRAINER_F"), ("COOLTRAINER_F", "SPRITE_COOLTRAINER_F")]
STEMS = {"HIKER": "Hiker", "SUPER_NERD": "SuperNerd", "POKEMANIAC": "Pokemaniac",
         "BLACKBELT": "Blackbelt", "JR_TRAINER_F": "JrF", "COOLTRAINER_F": "CooltrainerF"}
LAYOUTS = 8


class CaveGenericTrainerTest(unittest.TestCase):
    CGB = False

    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.sprites = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
        self.ram = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")
        self.trainers = trainer_ids()
        self.h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=self.CGB)
        self.h.boot_to_lobby(battle_count=11, encounter_kind=4, wild_type="cave")
        self.lobby = io.BytesIO()
        self.h.save_state(self.lobby)

    def tearDown(self) -> None:
        self.h.close()

    def enter(self, row: int, offset: int = 0, event: int = 0) -> None:
        """A fresh cave, his row forced (row + 1 at .store), floor 1."""
        h = self.h
        h.load_state(self.lobby)
        if offset:
            # A few frames' delay does not move the cave preload's RNG (measured:
            # offsets 0-3 gave one cave), so seed it per layout.
            seed = offset * 37 + 11
            h.seed_rng((seed & 0xFF, (seed ^ 0xA5) & 0xFF, 0, 1))
        h.write8("wStageEvent", event)

        def force_row(_context) -> None:
            h.pyboy.register_file.A = row

        def force_floor(_context) -> None:
            h.pyboy.register_file.A = 0

        h.register_hook("CaveGenericRoll.store", force_row)
        h.register_hook("CaveGenericRoll.floor", force_floor)
        try:
            h.preload_and_enter_wild_area(self.maps["PROCEDURAL_CAVE_1"], "cave")
        finally:
            h.unregister_hook("CaveGenericRoll.store", force_row)
            h.unregister_hook("CaveGenericRoll.floor", force_floor)
        h.write8("wProcCaveWildBudget", 0)

    def pos(self, slot: int) -> tuple[int, int]:
        h = self.h
        return (h.read8(f"wSprite{slot:02d}StateData2MapX") - 4,
                h.read8(f"wSprite{slot:02d}StateData2MapY") - 4)

    def picture(self, slot: int) -> int:
        return self.h.read8(f"wSprite{slot:02d}StateData1PictureID")

    def cell(self) -> int:
        return self.h.read_sram_bytes("sWildGenericCell", 1, bank=0)[0]

    def present(self, row: int, need: int = 1) -> list[int]:
        """Offsets (layouts) whose cave holds him, up to `need`."""
        found = []
        for offset in range(LAYOUTS * 3):
            self.enter(row + 1, offset)
            if self.picture(SLOT):
                found.append(offset)
                if len(found) == need:
                    break
        self.assertEqual(len(found), need, "too few caves hold him")
        return found

    def reachable(self) -> set[tuple[int, int]]:
        """Tiles the player can reach on the live cave, every other sprite solid but
        the balls (slots 2-5) and the stage pair (6-7). A ball is picked up and
        walked through (measured 2026-11-20, audit seed 55: a ball in a one-tile
        corridor gated his room). The pair stands in front of the arrival until
        its text sends it to the hideout, its own dead end (audit, Jessie & James:
        5 of 120 starts boxed in by it)."""
        import test_cave_subroom as cave
        from test_cave_deep_floor import blocks, MAP_SIZE
        h = self.h
        live = h.read_bytes("wOverworldMap", MAP_SIZE + 1)
        room = {"blocks": bytes(blocks(live)), "w": 20, "h": 20}
        solid = {self.pos(s) for s in range(1, 16)
                 if s != SLOT and not 2 <= s <= 7 and h.read8(f"wSprite{s:02d}StateData1")}
        solid.add(self.pos(SLOT))
        start = (h.read8("wXCoord"), h.read8("wYCoord"))
        return set(cave.room_reach(room, start, solid))

    def assert_placed(self, row: int, label: str) -> tuple[int, int]:
        h = self.h
        name, sprite = POOL[row]
        self.assertEqual(self.picture(SLOT), self.sprites[sprite], label)
        tx, ty = self.pos(SLOT)
        bx, by = tx // 2, ty // 2
        ax, ay = h.read_sram_bytes("sStageEventHideoutAltX", 2, bank=0)
        hx, hy = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
        armed = h.read8("wStageEvent") & self.ram["STAGE_EVENT_TYPE_MASK"]
        candidates = [(ax, ay)] if armed else [(ax, ay), (hx, hy)]
        if (bx, by) not in candidates:
            # The last resort (WGTCaveDeadEndOk): only when every candidate was
            # taken, and then clear of the pair, every object and every warp.
            for cell in candidates:
                self.assertTrue(self.taken(cell, hideout=armed),
                                f"{label}: a fallback cell {(bx, by)} though {cell} was free")
            if hx < 20:
                self.assertFalse(abs(hx - bx) <= 1 and abs(hy - by) <= 1,
                                 f"{label}: next to the hideout {(hx, hy)}")
            for slot in range(1, SLOT):
                x, y = self.pos(slot)
                self.assertNotEqual((x // 2, y // 2), (bx, by), f"{label}: on slot {slot}'s block")
            for y, x, *_ in h.warp_entries():
                self.assertNotEqual((x // 2, y // 2), (bx, by), f"{label}: on a warp's block")
        for slot in range(1, 8):
            if self.picture(slot):
                self.assertNotEqual(self.pos(slot), (tx, ty), f"{label}: on slot {slot}")
        self.assertEqual(h.read8("wMapSpriteExtraData", offset=(SLOT - 1) * 2),
                         self.trainers[name], label)
        # Talkable: a neighbouring tile the player can reach.
        reach = self.reachable()
        sides = {(tx + dx, ty + dy) for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))}
        self.assertTrue(sides & reach, f"{label}: nobody can reach him at {(tx, ty)}")
        # His sight square, the step he faces: the player must be able to stand
        # there, or he can never start the battle himself (2026-11-21: seed 12
        # faced a wall at (0,1) and seed 37 one at (38,9), as the facing read
        # the neighbouring block's mask, not the exact adjacent step).
        dx, dy = FACING[h.read8(f"wSprite{SLOT:02d}StateData1FacingDirection")]
        self.assertIn((tx + dx, ty + dy), reach,
                      f"{label}: he at {(tx, ty)} faces {(tx + dx, ty + dy)}, which nobody can reach")
        base = h.read8(f"wSprite{SLOT:02d}StateData2ImageBaseOffset")
        self.assertTrue(3 <= base <= 10, (label, base))
        return tx, ty

    def taken(self, cell, hideout: bool = False) -> bool:
        """A candidate WGTCaveCellOk refuses: the exit's, a ball's, unset, or
        (with an event armed) the hideout's own block."""
        h = self.h
        ey, ex = h.read8("wWarpEntries", offset=4) // 2, h.read8("wWarpEntries", offset=5) // 2
        balls = {(x // 2, y // 2) for x, y in (self.pos(s) for s in range(2, 6))}
        hx, hy = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
        return (cell == (ex, ey) or cell in balls or cell[0] >= 20
                or (hideout and cell == (hx, hy)))

    def test_always_stands_on_a_reachable_dead_end(self) -> None:
        cells = set()
        for offset in range(LAYOUTS):
            for event in (0, self.ram["STAGE_EVENT_JESSIE_JAMES"]):
                with self.subTest(offset=offset, event=event):
                    self.enter(1, offset, event)     # row 0: Hiker
                    self.assertTrue(self.picture(SLOT), "absent")
                    self.assertNotEqual(self.cell(), CELL_NONE)
                    cells.add(self.assert_placed(0, f"layout {offset}, event {event}"))
        self.assertGreater(len(cells), 1, "every layout gave the same cell")

    def test_every_pool_class_is_placed_as_itself(self) -> None:
        offset = self.present(0)[0]
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
        self.assertIn("db PROCEDURAL_CAVE_1,     1, 6, 7, CAVE_GENERIC", source)

    # ---- sight and battle ----------------------------------------------------

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

    def test_sees_one_tile_and_no_further(self) -> None:
        offset = self.present(0)[0]
        self.enter(1, offset)
        self.assertEqual(self.engage_at(1), 0xFF, "adjacent: engages")
        self.enter(1, offset)
        self.assertEqual(self.engage_at(2), 0, "two tiles: does not")

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

    def flag(self) -> int:
        return self.h.read8("wWildGenericBeaten") >> BEATEN_BIT & 1

    def test_battle_win_and_his_own_flag(self) -> None:
        h = self.h
        offset = self.present(0)[0]
        for row in (1, 5):                       # Super Nerd, Cooltrainer F
            with self.subTest(row=row):
                self.enter(row + 1, offset)
                self.assertEqual(self.flag(), 0, "a new cave finds him unbeaten")
                count_before = h.read8("wBattleCount")
                lines = []

                def done(_context) -> None:
                    lines.append(h.pyboy.register_file.HL)

                h.register_hook("FGTLine.done", done)
                try:
                    intro = self.talk()
                finally:
                    h.unregister_hook("FGTLine.done", done)
                self.assertIn(h.symbols.get("PCGenericIntroText")[1], intro)
                stem = STEMS[POOL[row][0]]
                self.assertEqual(lines[:1], [h.symbols.get(f"FGT{stem}Intro")[1]], "not his class's line")
                self.assertEqual(h.read8("hIsInBattle"), 2, "talking starts a trainer battle")
                self.assertEqual(h.read8("wTrainerHeaderFlagBit"), SLOT)
                self.assertEqual(h.read8("wCurOpponent"), self.trainers[POOL[row][0]])
                party = h.read8("wEnemyPartyCount")
                self.assertTrue(1 <= party <= 6, party)
                self.assertEqual(h.read8("wBattleCount"), count_before)
        # The battle's end through the map's own script: the header pick must hand
        # EndTrainerBattle HIS header (bit 11 from wWildGenericBeaten - 1).
        picture = self.picture(SLOT)
        events = h.read_bytes("wEventFlags", 64)
        h.park_before_hijack()
        h.write8("hIsInBattle", 0)
        h.write8("hActiveSpriteIndex", SLOT)
        h.write8("wProceduralCave1CurScript", SCRIPT_END_BATTLE)
        h.call_routine("ProceduralCave1_Script", limit=200000)
        self.assertEqual(h.read8("wWildGenericBeaten"), 1 << BEATEN_BIT, "his bit, and only his")
        self.assertEqual(h.read_bytes("wEventFlags", 64), events, "an event flag changed")
        self.assertEqual(self.picture(SLOT), picture, "the sprite stays")

    def test_once_beaten_the_after_line_and_a_new_cave_resets(self) -> None:
        h = self.h
        offset = self.present(0)[0]
        self.enter(1, offset)
        h.write8("wWildGenericBeaten", 1 << BEATEN_BIT)
        printed = self.talk(frames=900, until_battle=False)
        self.assertIn(h.symbols.get("PCGenericAfterText")[1], printed)
        self.assertNotIn(h.symbols.get("PCGenericIntroText")[1], printed)
        self.assertEqual(h.read8("hIsInBattle"), 0)
        self.enter(1, offset + 1)                # the next cave's preload
        self.assertEqual(self.flag(), 0)


if __name__ == "__main__":
    unittest.main()
