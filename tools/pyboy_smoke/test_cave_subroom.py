"""The cave subroom (PROCEDURAL_SUBROOMS_PLAN Phase 4, cave).

PROCEDURAL_CAVE_SUBROOM shows one of the user's drawn rooms, rolled per cave
(CaveSubRooms in custom_functions/cave_subroom.asm), each with two ladders up,
one per cave ladder down. The cave draws two ladders down on fixed sites (state
in the staging buffer's tail), arms only their warps at the rolled room's two
ladders, and the subroom's ladder N climbs back onto ladder N. Every room is
ridden both ways for both ladders, its blocks, warps and its lake and mountain
Pokemon checked; a collected ball must stay hidden when the player climbs back
into the cave (the once-per-cave show gate). The residents (Gambler, Super
Nerd, PokeManiac) are fought in the rooms.
"""

from __future__ import annotations

import re
import unittest
from collections import deque
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
_MAPS = (ROOT / "constants/map_constants.asm").read_text(encoding="utf-8")
MAP_W, MAP_H = (int(v) for v in re.search(
    r"map_const PROCEDURAL_CAVE_SUBROOM,\s*(\d+),\s*(\d+)", _MAPS).groups())
FILL_BLOCK = 0x03
_SITES = (ROOT / "constants/cave_ladder_site_constants.asm").read_text(encoding="utf-8")
SITES = [(int(x), int(y)) for x, y in re.findall(r"^\tladder_site\s+(\d+),\s*(\d+)", _SITES, re.M)]
FIRST_LADDER_WARP = int(re.search(r"CAVE_FIRST_LADDER_WARP EQU (\d+)", _SITES).group(1))
LADDER_BLOCK = int(re.search(r"CAVE_LADDER_BLOCK EQU (\d+)", _SITES).group(1))
TAIL = 81 + 19 * 26 + 20                # CAVESUB_TAIL: ladder A, ladder B, state, room
_RAM = parse_rgbds_constants(ROOT / "constants/ram_constants.asm",
                             parse_rgbds_constants(ROOT / "constants/round_constants.asm"))
STEP = _RAM["MONEY_MATCH_STEP"]
FINAL_STEP = parse_rgbds_constants(ROOT / "constants/round_constants.asm")["ROUTE_BATTLES"]  # = FINAL_ROUTE_STEP
RAM_SUPER_NERD_AFTER_BATTLE = _RAM["SCRIPT_SUPER_NERD_AFTER_BATTLE"]
NERD, MANIAC = 0x04, 0x08               # CAVESUB_STATE resident bits

_OBJECTS = (ROOT / "data/maps/objects/ProceduralCaveSubroom.asm").read_text(encoding="utf-8")
WARPS = [(int(x), int(y)) for x, y in re.findall(r"warp_event\s+(\d+),\s*(\d+)", _OBJECTS)]
_CODE = (ROOT / "custom_functions/cave_subroom.asm").read_text(encoding="utf-8")
_FILES = dict(re.findall(r'^(\w+):\s*INCBIN "([^"]+)"', _CODE, re.M))
ROOMS = []
for _label, _nums in re.findall(r"^\tcave_subroom_room (\w+),((?:\s*\d+,){11}\s*\d+)", _CODE, re.M):
    _n = [int(v) for v in _nums.split(",")]
    ROOMS.append({
        "name": _label, "blocks": (ROOT / _FILES[_label]).read_bytes(), "w": _n[0], "h": _n[1],
        "warps": (_n[2], _n[3]), "ladders": (WARPS[_n[2]], WARPS[_n[3]]), "resident": (_n[4], _n[5]),
        "ball": (_n[6], _n[7]), "water": (_n[8], _n[9]), "land": (_n[10], _n[11])})
WATER_SPRITES = ("", "SPRITE_LAPRAS", "SPRITE_SEEL")
LAND_SPRITES = ("", "SPRITE_CLEFAIRY", "SPRITE_MACHOP", "SPRITE_MACHOKE", "SPRITE_CUBONE")
_COLL = (ROOT / "data/tilesets/collision_tile_ids.asm").read_text(encoding="utf-8")
WALKABLE = {int(t.strip().lstrip("$"), 16) for t in
            re.search(r"^Cavern_Coll::\s*\n\s*coll_tiles\s+([^\n;]+)", _COLL, re.M).group(1).split(",")}
ELEVATION_PAIRS = {(0x20, 0x05), (0x05, 0x20), (0x41, 0x05), (0x05, 0x41)}   # CAVERN's
WATER_TILE = 0x14


def room_tiles(room) -> dict:
    """Tile (x, y) -> its collision tile (a quadrant's bottom-left)."""
    blockset = (ROOT / "gfx/blocksets/cavern.bst").read_bytes()
    tiles = {}
    for by in range(room["h"]):
        for bx in range(room["w"]):
            block = room["blocks"][by * room["w"] + bx]
            for q, i in enumerate((4, 6, 12, 14)):
                tiles[(2 * bx + q % 2, 2 * by + q // 2)] = blockset[block * 16 + i]
    return tiles


def room_reach(room, start, blocked=frozenset()) -> dict:
    """BFS from start over walkable tiles (elevation pairs respected).
    Returns tile -> (previous tile, button), start -> None."""
    tiles = room_tiles(room)
    came = {start: None}
    todo = deque([start])
    moves = (("up", 0, -1), ("down", 0, 1), ("left", -1, 0), ("right", 1, 0))
    while todo:
        here = todo.popleft()
        for button, dx, dy in moves:
            there = (here[0] + dx, here[1] + dy)
            if (there in tiles and there not in came and there not in blocked and tiles[there] in WALKABLE
                    and (tiles[here], tiles[there]) not in ELEVATION_PAIRS):
                came[there] = (here, button)
                todo.append(there)
    return came


def room_map_rows(room) -> list:
    rows = []
    for y in range(MAP_H):
        if y < room["h"]:
            row = list(room["blocks"][y * room["w"]:(y + 1) * room["w"]]) + [FILL_BLOCK] * (MAP_W - room["w"])
        else:
            row = [FILL_BLOCK] * MAP_W
        rows.append(row)
    return rows


def room_byte(room: int, water: int, land: int) -> int:
    return room | water << 2 | land << 4


def from_bcd(values) -> int:
    return int("".join(f"{v:02x}" for v in values))


class CaveSubroomRoomTableTest(unittest.TestCase):
    """The room table against the drawn rooms, without the ROM."""

    def test_every_room_works(self) -> None:
        self.assertEqual(len(ROOMS), int(re.search(r"CAVESUB_NUM_ROOMS\s+EQU (\d+)", _SITES).group(1)))
        for room in ROOMS:
            with self.subTest(room=room["name"]):
                self.assertEqual(len(room["blocks"]), room["w"] * room["h"])
                self.assertLessEqual(room["w"], MAP_W)
                self.assertLessEqual(room["h"], MAP_H)
                tiles = room_tiles(room)
                for lx, ly in room["ladders"]:
                    self.assertIn((lx, ly), tiles, "a ladder off the room")
                reach = room_reach(room, room["ladders"][0], {room["resident"], room["ball"]})
                rx, ry = room["resident"]
                bx, by = room["ball"]
                self.assertIn(room["ladders"][1], reach, "the ladders are not connected")
                self.assertIn((rx, ry + 1), reach, "the resident cannot be talked to")
                self.assertIn((bx, by + 1), reach, "the ball cannot be picked up")
                for lx, ly in room["ladders"]:
                    self.assertIn((lx - 1, ly), reach, "no floor west of a ladder")
                for kind in ("water", "land"):
                    self.assertNotIn(room[kind], reach, f"the {kind} Pokemon can be reached")
                self.assertEqual(tiles[room["water"]], WATER_TILE, "the lake Pokemon is not on water")
                # Neither the resident nor the ball cuts the room in two.
                open_reach = room_reach(room, room["ladders"][0])
                self.assertEqual(set(reach) | {room["resident"], room["ball"]} >= set(open_reach) - {
                    room["resident"], room["ball"]}, True, "the resident or the ball cuts a path")


class CaveSubroomTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.sprites = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
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

    def ride(self, index: int, water: int, land: int) -> None:
        h = self.h
        room = ROOMS[index]
        cave = self.maps["PROCEDURAL_CAVE_1"]
        subroom = self.maps["PROCEDURAL_CAVE_SUBROOM"]
        toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(cave, "cave")
        h.write8("wProcCaveWildBudget", 0)
        raw = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 4, bank=0)
        a, b, state = raw[TAIL], raw[TAIL + 1], raw[TAIL + 2]
        self.assertLess(a, len(SITES), "no ladder this cave")
        self.assertLess(b, len(SITES), "only one ladder this cave (rare: rerun or pick another seed)")
        self.assertTrue(state & 0x80, "the cave's objects were not marked shown")
        self.assertLess(raw[TAIL + 3] & 3, len(ROOMS), "rolled a room past the table")
        # Exactly the rolled resident is shown (the PokeManiac uses the Super Nerd's object).
        nerd = bool(state & NERD)
        if state & MANIAC:
            self.assertTrue(nerd, "the PokeManiac bit without the Super Nerd's")
        for name, shown in (("TOGGLE_CAVESUB_GAMBLER", not nerd), ("TOGGLE_CAVESUB_SUPER_NERD", nerd)):
            i = toggles[name]
            hidden = bool(h.read8("wToggleableObjectFlags", offset=i // 8) & 1 << i % 8)
            self.assertEqual(hidden, not shown, f"{name} shown={not hidden}, the roll says {shown}")
        i = toggles["TOGGLE_CAVESUB_BALL"]
        self.assertFalse(h.read8("wToggleableObjectFlags", offset=i // 8) & 1 << i % 8,
                         "the subroom's ball was not put back for the new cave")
        (ax, ay), (bx, by) = SITES[a], SITES[b]
        self.assertGreaterEqual(abs(ax - bx) + abs(ay - by), 8, "the ladders are too close")
        layout = h.read_bytes("wOverworldMap", 601)
        for x, y in (SITES[a], SITES[b]):
            self.assertEqual(layout[81 + y * 26 + x], LADDER_BLOCK, f"no ladder drawn at {(x, y)}")
        # This test's room and Pokemon; the reload onto ladder A arms for them.
        raw[TAIL + 3] = room_byte(index, water, land)
        h.write_sram_bytes("sProcCaveStagingBuffer", raw, bank=0)
        # As if ball 1 had been collected: it must stay hidden on the way back.
        ball = toggles["TOGGLE_WILD_AREA_POKEBALL_1"]
        byte = h.read8("wToggleableObjectFlags", offset=ball // 8)
        h.write8("wToggleableObjectFlags", byte | 1 << ball % 8, offset=ball // 8)

        # Onto ladder A: arrive on it through the retargeted entrance warp.
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the cave entrance", 600)
        h.write8("wWarpEntries", FIRST_LADDER_WARP + a, offset=2)
        h.write8("wWarpEntries", cave, offset=3)
        self.press_until("down", lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == (2 * ax + 1, 2 * ay + 1),
                         "onto ladder A")
        warps = h.warp_entries()
        for n, (x, y) in enumerate(SITES):
            entry = warps[FIRST_LADDER_WARP + n]
            if n in (a, b):
                self.assertEqual(entry, [2 * y + 1, 2 * x + 1, room["warps"][0 if n == a else 1], subroom],
                                 f"ladder site {n} armed wrong")
            else:
                self.assertEqual(entry[0], 0xFF, f"site {n} not disarmed")
        for site, ladder, (sx, sy) in ((a, 0, (ax, ay)), (b, 1, (bx, by))):
            with self.subTest(ladder=ladder):
                lx, ly = room["ladders"][ladder]
                tile = (2 * sx + 1, 2 * sy + 1)
                self.press_until("left", lambda: h.read8("wXCoord") == tile[0] - 1, "off the cave ladder")
                self.press_until("right", lambda: h.read8("hCurMap") == subroom, "down into the subroom")
                self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (lx, ly),
                                 "not on the matching subroom ladder")
                stride = MAP_W + 6
                live = h.read_bytes("wOverworldMap", (MAP_H + 6) * stride)
                for y, row in enumerate(room_map_rows(room)):
                    self.assertEqual(live[(y + 3) * stride + 3:(y + 3) * stride + 3 + MAP_W], row,
                                     f"block row {y}")
                for n, entry in enumerate(h.warp_entries()[:len(WARPS)]):
                    if n == room["warps"][0]:
                        self.assertEqual(entry[2:], [FIRST_LADDER_WARP + a, cave], "ladder 0's way back")
                    elif n == room["warps"][1]:
                        self.assertEqual(entry[2:], [FIRST_LADDER_WARP + b, cave], "ladder 1's way back")
                    else:
                        self.assertEqual(entry[0], 0xFF, f"subroom warp {n} not disarmed")
                for slot, kind, table, value in ((4, "water", WATER_SPRITES, water),
                                                 (5, "land", LAND_SPRITES, land)):
                    picture = self.sprites[table[value]] if value else 0
                    self.assertEqual(h.read8(f"wSprite0{slot}StateData1"), picture, f"the {kind} Pokemon's picture")
                    px, py = room[kind]
                    self.assertEqual((h.read8(f"wSprite0{slot}StateData2MapX"),
                                      h.read8(f"wSprite0{slot}StateData2MapY")),
                                     (px + 4, py + 4), f"the {kind} Pokemon's spot")
                rx, ry = room["resident"]
                self.assertEqual((h.read8("wSprite01StateData2MapX"), h.read8("wSprite01StateData2MapY")),
                                 (rx + 4, ry + 4), "the resident's spot")
                self.press_until("left", lambda: h.read8("wXCoord") == lx - 1, "off the subroom ladder")
                self.press_until("right", lambda: h.read8("hCurMap") == cave, "climb back up")
                self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), tile,
                                 "did not climb out onto the same ladder")
                byte = h.read8("wToggleableObjectFlags", offset=ball // 8)
                self.assertTrue(byte & 1 << ball % 8, "a collected ball came back")
                if ladder == 0:
                    # Over to ladder B: retarget ladder A's warp at it, as a pad pair would.
                    h.write8("wWarpEntries", FIRST_LADDER_WARP + b, offset=4 * (FIRST_LADDER_WARP + a) + 2)
                    h.write8("wWarpEntries", cave, offset=4 * (FIRST_LADDER_WARP + a) + 3)
                    self.press_until("left", lambda: h.read8("wXCoord") == tile[0] - 1, "off ladder A")
                    self.press_until("right", lambda: (h.read8("wXCoord"), h.read8("wYCoord"))
                                     == (2 * bx + 1, 2 * by + 1), "onto ladder B")
        self.assertEqual(h.read_bytes("wOverworldMap", 601), layout, "the trips changed the cave")

    def test_lake_room(self) -> None:
        self.ride(0, water=1, land=1)

    def test_lake2_room(self) -> None:
        self.ride(1, water=2, land=4)

    def test_mountains1_room(self) -> None:
        self.ride(2, water=0, land=3)


class CaveSubroomResidentTest(CaveSubroomTest):
    """The rolled resident: the Gambler, the Super Nerd or the PokeManiac."""

    test_lake_room = test_lake2_room = test_mountains1_room = None   # the parent's, not repeated

    def walk_in_room(self, goal) -> None:
        h = self.h
        start = (h.read8("wXCoord"), h.read8("wYCoord"))
        came = room_reach(self.room, start, {self.room["resident"], self.room["ball"]})
        self.assertIn(goal, came, f"no path from {start} to {goal}")
        path = []
        at = goal
        while came[at]:
            here, button = came[at]
            path.append((button, at))
            at = here
        for button, to in reversed(path):
            self.press_until(button, lambda to=to: (h.read8("wXCoord"), h.read8("wYCoord")) == to,
                             f"step to {to}")

    def enter_subroom_as(self, kind: str, index: int) -> None:
        h = self.h
        self.room = ROOMS[index]
        cave = self.maps["PROCEDURAL_CAVE_1"]
        subroom = self.maps["PROCEDURAL_CAVE_SUBROOM"]
        toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(cave, "cave")
        h.write8("wProcCaveWildBudget", 0)
        raw = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 4, bank=0)
        a = raw[TAIL]
        self.assertLess(a, len(SITES), "no ladder this cave")
        # Force the resident and the room: the state bits and the two flags.
        nerd = kind != "gambler"
        raw[TAIL + 2] = (raw[TAIL + 2] & ~0x0F) | {"gambler": 0, "nerd": NERD, "maniac": NERD | MANIAC}[kind]
        raw[TAIL + 3] = room_byte(index, 1, 1)
        h.write_sram_bytes("sProcCaveStagingBuffer", raw, bank=0)
        for name, shown in (("TOGGLE_CAVESUB_GAMBLER", not nerd), ("TOGGLE_CAVESUB_SUPER_NERD", nerd)):
            i = toggles[name]
            byte = h.read8("wToggleableObjectFlags", offset=i // 8)
            byte = byte & ~(1 << i % 8) if shown else byte | 1 << i % 8
            h.write8("wToggleableObjectFlags", byte, offset=i // 8)
        ax, ay = SITES[a]
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the cave entrance", 600)
        h.write8("wWarpEntries", FIRST_LADDER_WARP + a, offset=2)
        h.write8("wWarpEntries", cave, offset=3)
        self.press_until("down", lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == (2 * ax + 1, 2 * ay + 1),
                         "onto ladder A")
        self.press_until("left", lambda: h.read8("wXCoord") == 2 * ax, "off the cave ladder")
        self.press_until("right", lambda: h.read8("hCurMap") == subroom, "down into the subroom")
        rx, ry = self.room["resident"]
        self.walk_in_room((rx, ry + 1))

    def talk_up(self) -> None:
        h = self.h
        h.move_tile("up")
        h.tick(10)
        h.tap("a", frames=8)
        h.tick(30)

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

    def fight_and_win(self, kind: str) -> dict:
        h = self.h
        subroom = self.maps["PROCEDURAL_CAVE_SUBROOM"]
        self.talk_up()                          # NO once: B answers every prompt
        for _ in range(16):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("hIsInBattle"), 0, "declining started a battle")
        battle_count = h.read8("wBattleCount")
        money_before = from_bcd(h.read_bytes("wPlayerMoney", 3))
        seen = {"themed": 0, "step": [], "payout": [], "party": None}

        def ko(_c):
            h.write8("wEnemyMonHP", 0)
            h.write8("wEnemyMonHP", 0, offset=1)

        def no_exp(_c):
            h.write8("wPartyGainExpFlags", 0)

        def step(_c):
            seen["step"].append(h.pyboy.register_file.A)

        def themed(_c):
            seen["themed"] += 1

        def payout(_c):
            seen["payout"].append((from_bcd(h.read_bytes("wAmountMoneyWon", 3)), h.read8("wMoneyMatchState")))
            count = h.read8("wEnemyPartyCount")
            mons = h.read_bytes("wEnemyMons", 44 * count)
            seen["party"] = [mons[44 * i:44 * (i + 1)] for i in range(count)]

        hooks = (("MainInBattleLoop", ko), ("GainExperience", no_exp), ("GetRandRoster.stepReady", step),
                 ("AIMoveChoiceModification5", themed), ("MoneyMatchApplyPayout", payout))
        for label, cb in hooks:
            h.register_hook(label, cb)
        try:
            self.talk_up()
            for _ in range(40):
                if h.read8("hIsInBattle"):
                    break
                h.tap("a", frames=8)
                h.tick(20)
            self.assertTrue(h.read8("hIsInBattle"), "YES did not start the battle")
            for _ in range(200):
                if not h.read8("hIsInBattle") and seen["payout"] and h.read8("wSafariZoneGateCurScript") == 0:
                    break
                h.tap("b", frames=8)
                h.tick(20)
            for _ in range(20):
                h.tap("b", frames=8)
                h.tick(20)
            h.tick(120)
        finally:
            for label, cb in reversed(hooks):
                h.unregister_hook(label, cb)
        self.assertEqual(h.read8("hCurMap"), subroom)
        self.assertEqual(seen["step"], [FINAL_STEP if kind == "maniac" else STEP], "party rolled at the wrong step")
        self.assertEqual(seen["themed"], 0, "Gambler's Paradise AI ran")
        self.assertEqual(len(seen["payout"]), 1)
        prize, state = seen["payout"][0]
        self.assertEqual(state & 0xC0, 0x80 if kind == "gambler" else 0xC0, "armed as the wrong kind of fight")
        gained = from_bcd(h.read_bytes("wPlayerMoney", 3)) - money_before
        if kind == "gambler":
            self.assertNotEqual(gained, prize, "the Gambler's bet did not change the payout")
        else:
            self.assertEqual(gained, prize, "a no-bet resident's prize money was changed")
        self.assertEqual(h.read8("wBattleCount"), battle_count, "the resident advanced the run")
        flags = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 3, bank=0)[TAIL + 2]
        self.assertTrue(flags & 1, "the win was not recorded in the cave's state")
        if kind != "gambler":
            self.assertTrue(flags & 2, "the prize was not handed over")
        self.talk_up()
        after = {"gambler": "worth", "nerd": "earned", "maniac": "care"}[kind]
        self.assertIn(after, self.screen_text(), "not the after line")
        for _ in range(6):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("hIsInBattle"), 0)
        return seen

    def test_ball_gives_an_item(self) -> None:
        h = self.h
        toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        self.enter_subroom_as("nerd", 2)
        bx, by = self.room["ball"]
        self.walk_in_room((bx, by + 1))
        self.talk_up()
        self.assertIn("found", self.screen_text(), "no pickup message")
        for _ in range(8):
            h.tap("b", frames=8)
            h.tick(20)
        i = toggles["TOGGLE_CAVESUB_BALL"]
        self.assertTrue(h.read8("wToggleableObjectFlags", offset=i // 8) & 1 << i % 8,
                        "the ball was not hidden")

    def test_gambler(self) -> None:
        self.enter_subroom_as("gambler", 0)
        self.fight_and_win("gambler")

    def test_super_nerd(self) -> None:
        self.enter_subroom_as("nerd", 2)
        self.fight_and_win("nerd")

    def test_pokemaniac_gives_one_of_his_pokemon(self) -> None:
        h = self.h
        self.enter_subroom_as("maniac", 1)
        h.write8("wPartyCount", 5)                 # room for one
        h.write8("wPartySpecies", 0xFF, offset=5)
        player_id = h.read_bytes("wPlayerID", 2)
        seen = self.fight_and_win("maniac")
        self.assertEqual(h.read8("wPartyCount"), 6, "no Pokemon was given")
        got = h.read_bytes("wPartyMons", 44 * 6)[44 * 5:]
        self.assertEqual(h.read8("wPartySpecies", offset=5), got[0])
        # One of his, as it was: species, level, catch-rate flags (form, shiny...;
        # never fusion), moves, stat experience and DVs, stats.
        def same(mon):
            return (mon[0], mon[33], mon[7] & ~0x02, list(mon[8:12]), list(mon[17:29]), list(mon[34:44]))
        self.assertIn(same(got), [same(mon) for mon in seen["party"]], "not one of his Pokemon")
        self.assertEqual(got[1:3], got[34:36], "not healed")
        self.assertEqual(got[4], 0, "still has a status")
        self.assertEqual(got[12:14], player_id, "the player is not its OT")
        ot = h.read_bytes("wPartyMonOT", 11 * 6)[11 * 5:]
        self.assertEqual(ot, h.read_bytes("wPlayerName", 11), "OT name")
        nick = h.read_bytes("wPartyMonNicks", 11 * 6)[11 * 5:]
        self.assertIn(0x50, nick[1:], "the name is not terminated")
        self.assertNotEqual(nick[0], 0x50, "no name")

    def test_pokemaniac_with_a_full_party_sends_it_to_the_box(self) -> None:
        h = self.h
        self.enter_subroom_as("maniac", 0)
        self.assertEqual(h.read8("wPartyCount"), 6)
        boxed = h.read8("wBoxCount")
        seen = self.fight_and_win("maniac")
        self.assertEqual(h.read8("wPartyCount"), 6)
        self.assertEqual(h.read8("wBoxCount"), boxed + 1, "nothing sent to the box")
        species = h.read_bytes("wBoxSpecies", boxed + 1)
        self.assertTrue(set(species) & {mon[0] for mon in seen["party"]}, "not one of his species in the box")


class CaveResidentFallbackTest(CaveSubroomTest):
    """No ladder fits: the rolled resident stands in the cave itself.

    About 1 cave in 300, so the test forces it: a block the ladder rule accepts
    (the audit's own model) is stored as the fallback spot, and the cave is
    reloaded through a real warp so the picture patch, the arming and the
    once-per-cave show all run as they do in play.
    """

    test_lake_room = test_lake2_room = test_mountains1_room = None

    def test_super_nerd_stands_in_the_cave_and_pays_out(self) -> None:
        import sys
        sys.path.insert(0, str(ROOT / "tools/pyboy_smoke"))
        import audit_cave_ladder_sites as model
        h = self.h
        cave = self.maps["PROCEDURAL_CAVE_1"]
        toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(cave, "cave")
        h.write8("wProcCaveWildBudget", 0)

        origin = h.address("wOverworldMap") + 81
        grid = [[h.pyboy.memory[origin + y * 26 + x] for x in range(20)] for y in range(20)]
        player = (h.read8("wXCoord"), h.read8("wYCoord"))
        balls = [(x, y) for y, x in h.sprite_positions(5)]
        exit_yx = h.read_sram_bytes("sProcCaveStagingExitY", 2, bank=0)
        hideout = h.read_sram_bytes("sStageEventHideoutX", 2, bank=0)
        valid, _ = model.valid_sites(grid, player, balls, (exit_yx[1], exit_yx[0]), hideout,
                                     (ROOT / "gfx/blocksets/cavern.bst").read_bytes(), model.passable_tiles())
        bx, by = sorted(valid)[0]

        raw = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 3, bank=0)
        raw[TAIL], raw[TAIL + 1] = 0x80 | bx, 0x40 | by
        raw[TAIL + 2] = NERD                       # the Super Nerd; not shown yet; not beaten
        h.write_sram_bytes("sProcCaveStagingBuffer", raw, bank=0)

        # Reload the cave through a real warp: its entrance, retargeted at itself.
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the cave entrance", 600)
        h.write8("wWarpEntries", 0, offset=2)
        h.write8("wWarpEntries", cave, offset=3)
        frame = h.pyboy.frame_count
        self.press_until("down", lambda: h.read8("hCurMap") == cave and h.pyboy.frame_count - frame > 60
                         and h.read8("wYCoord") == 39, "back into the cave")
        h.tick(120)

        self.assertEqual(h.read8("wSprite08StateData1"), 0, "the Gambler's picture was not zeroed")
        self.assertEqual(h.read8("wSprite09StateData1"), self.sprites["SPRITE_SUPER_NERD"],
                         "the Super Nerd's picture was not installed")
        self.assertEqual((h.read8("wSprite09StateData2MapX"), h.read8("wSprite09StateData2MapY")),
                         (2 * bx + 1 + 4, 2 * by + 1 + 4), "he is not on his block")
        for name, shown in (("TOGGLE_CAVE_GAMBLER", False), ("TOGGLE_CAVE_SUPER_NERD", True)):
            i = toggles[name]
            hidden = bool(h.read8("wToggleableObjectFlags", offset=i // 8) & 1 << i % 8)
            self.assertEqual(hidden, not shown, f"{name}")
        armed = [w for w in h.warp_entries()[FIRST_LADDER_WARP:] if w[0] != 0xFF]
        self.assertEqual(armed, [], "a ladder warp is armed in a cave without ladders")

        # The cave script settles his battle: as if one was just won.
        h.write8("wSafariZoneGateCurScript", RAM_SUPER_NERD_AFTER_BATTLE)
        h.write8("wCurOpponent", 0)
        h.tick(30)
        for _ in range(20):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("wSafariZoneGateCurScript"), 0, "the battle was not settled")
        state = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 3, bank=0)[TAIL + 2]
        self.assertTrue(state & 1, "the win was not recorded")
        self.assertTrue(state & 2, "the prize was not handed over")


if __name__ == "__main__":
    unittest.main()
