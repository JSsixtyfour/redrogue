"""The forest's rest house: placed, entered, left, and the forest unharmed.

PROCEDURAL_SUBROOMS_PLAN Phase 4. Every forest stands a two-block house over
trees on one of the door spots in constants/forest_house_site_constants.asm.
This drives the real engine:

  * the player walks the maze (a breadth-first path over walkable quadrants,
    collision decoded from the blockset) to the door and steps up onto it;
  * the way out is the house's own exit, which PFRestHouseLoad points at this
    forest's door: the player must land on the door and be stepped down;
  * then up onto the door again, and out again.

Throughout, the forest must keep its layout, a collected ball must stay
hidden (the re-entry dupe the Facility's Phase 1 fixed), and neither the
battle count nor wLastMap (which the forest's LAST_MAP exit reads) may move.
"""

from __future__ import annotations

import re
import sys
import unittest
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import forest_clearings as fc  # noqa: E402
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
SITE_MASK = 0x1F
HOUSE_LEFT, HOUSE_RIGHT = 0x19, 0x1C
PF_BASE, PF_STRIDE = 81, 26  # custom_functions/procedural_forest_gen.asm
STEPS = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}


def forest_collision(blocks: list[int]) -> dict[tuple[int, int], int]:
    """{tile: its collision tile} for every walkable quadrant, the same model
    tools/forest_clearings.py proves its pieces with."""
    blockset, walk = fc.BLOCKSET.read_bytes(), fc.walkable_tiles()
    out = {}
    for by in range(20):
        for bx in range(20):
            block = blocks[PF_BASE + bx + by * PF_STRIDE]
            for q, index in enumerate(fc.QUADRANT_TILES):
                tile = blockset[block * 16 + index]
                if tile in walk:
                    out[(2 * bx + q % 2, 2 * by + q // 2)] = tile
    return out


def house_sites() -> list[tuple[int, int]]:
    text = (ROOT / "constants/forest_house_site_constants.asm").read_text(encoding="utf-8")
    return [(int(x), int(y)) for x, y in re.findall(r"^\s*house_site\s+(\d+),\s*(\d+)", text, re.M)]


class ForestWalk:
    """Forest/house harness helpers, shared with test_money_match.py."""

    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        self.sites = house_sites()
        self.h = RedRogueHarness(ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.h.close()

    def hidden(self, toggle: str) -> bool:
        index = self.toggles[toggle]
        return bool(self.h.read8("wToggleableObjectFlags", offset=index // 8) & 1 << index % 8)

    def hide(self, toggle: str) -> None:
        index = self.toggles[toggle]
        byte = self.h.read8("wToggleableObjectFlags", offset=index // 8)
        self.h.write8("wToggleableObjectFlags", byte | 1 << index % 8, offset=index // 8)

    def block(self, x: int, y: int) -> int:
        return self.h.read8("wOverworldMap", offset=PF_BASE + x + y * PF_STRIDE)

    def press_until(self, button: str, arrive_map: int, description: str) -> None:
        h = self.h
        # Release on the map change: still holding the button after arriving
        # walks on past the door's own step-out.
        h.pyboy.button_press(button)
        try:
            h.wait_until(lambda: h.read8("hCurMap") == arrive_map, description, 900)
        finally:
            h.pyboy.button_release(button)
        h.tick(200)

    def objects(self) -> set[tuple[int, int]]:
        """Every object slot's tile, and the tiles beside the boss (its flank
        guard starts the fight)."""
        h = self.h
        out = set()
        for slot in range(1, 16):
            y = h.read8("wSprite01StateData2MapY", offset=16 * (slot - 1)) - 4
            x = h.read8("wSprite01StateData2MapX", offset=16 * (slot - 1)) - 4
            out.add((x, y))
            if slot == 1:
                out |= {(x + dx, y + dy) for dx, dy in STEPS.values()}
        return out

    def walk_to(self, goal: tuple[int, int]) -> None:
        h = self.h
        walkable = forest_collision(h.read_bytes("wOverworldMap", 601))
        start = (h.read8("wXCoord"), h.read8("wYCoord"))
        for tile in self.objects() - {start}:  # the follower stands on the player
            walkable.pop(tile, None)
        pairs = fc.forest_tile_pairs()
        came = {start: None}
        queue = deque([start])
        while queue and goal not in came:
            here = queue.popleft()
            for name, (dx, dy) in STEPS.items():
                there = (here[0] + dx, here[1] + dy)
                if (there in walkable and there not in came
                        and frozenset((walkable[here], walkable[there])) not in pairs):
                    came[there] = (here, name)
                    queue.append(there)
        self.assertIn(goal, came, f"no walkable path from {start} to {goal}")
        path = []
        node = goal
        while came[node]:
            node, name = came[node]
            path.append(name)
        for name in reversed(path):
            self.step(name)

    def step(self, name: str) -> None:
        h = self.h
        before = (h.read8("wXCoord"), h.read8("wYCoord"))
        want = (before[0] + STEPS[name][0], before[1] + STEPS[name][1])
        # Hold only until the coordinate moves: a fixed-length press can turn
        # without moving, or walk two tiles.
        h.pyboy.button_press(name)
        try:
            h.wait_until(lambda: (h.read8("wXCoord"), h.read8("wYCoord")) != before,
                         f"step {name} from {before}", 90)
        finally:
            h.pyboy.button_release(name)
        h.wait_until(lambda: h.read8("wWalkCounter") == 0, "step finished", 60)
        h.tick(2)
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), want, f"step {name} from {before}")

    def screen_text(self) -> str:
        """wTileMap decoded through the charmap's letters and space."""
        out = []
        for tile in self.h.read_bytes("wTileMap", 360):
            if 0x80 <= tile <= 0x99:
                out.append(chr(ord("A") + tile - 0x80))
            elif 0xA0 <= tile <= 0xB9:
                out.append(chr(ord("a") + tile - 0xA0))
            else:
                out.append(" ")
        return "".join(out)

    def talk(self, face: str, token: str, description: str) -> None:
        """Face the resident, press A, and wait for `token` on screen (tapping A
        through any leading text box). Then back out with B until the player
        walks again."""
        h = self.h
        h.move_tile(face)  # blocked by the NPC or a counter: only turns
        h.tick(10)
        h.tap("a")
        for attempt in range(8):
            found = False
            for _ in range(90):
                h.tick(1)
                if token in self.screen_text():
                    found = True
                    break
            if found:
                break
            h.tap("a")
        self.assertIn(token, self.screen_text(), f"{description}: never showed {token!r}")
        for _ in range(16):
            h.tap("b")
            h.tick(20)


class ForestRestHouseTest(ForestWalk, unittest.TestCase):
    def test_house_round_trip(self) -> None:
        h = self.h
        forest = self.maps["PROCEDURAL_FOREST"]
        house = self.maps["PROCEDURAL_FOREST_REST_HOUSE"]
        lobby = self.maps["INDIGO_PLATEAU_LOBBY"]
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)  # no arrival text box to block the walk
        h.preload_and_enter_wild_area(forest, "forest")
        h.write8("wLastMap", lobby)  # what a real ROGUE_MAP door writes (see the Facility test)

        got = h.read_sram_bytes("sProcForestItemGot", 1, bank=0)[0]
        site = (got & SITE_MASK) - 1
        self.assertGreaterEqual(site, 0, "no rest house placed in this forest")
        self.assertTrue(got & 0x80, "first entry did not record that the objects were shown")
        x, y = self.sites[site]
        self.assertEqual((self.block(x, y), self.block(x + 1, y)), (HOUSE_LEFT, HOUSE_RIGHT),
                         f"site {site} at block ({x},{y}) does not hold the house")
        warps = h.warp_entries()
        for n in range(len(self.sites)):
            entry = warps[3 + n]
            if n == site:
                self.assertEqual(entry[:2], [2 * y + 1, 2 * x + 1], "this forest's door is not armed")
                self.assertEqual(entry[3], house)
            else:
                self.assertEqual(entry[0], 0xFF, f"door warp {n} is armed but has no house")

        # Gambler always in; never both residents of the (6,6) spot.
        self.assertFalse(self.hidden("TOGGLE_PFRESTHOUSE_GAMBLER"))
        self.assertTrue(self.hidden("TOGGLE_PFRESTHOUSE_RENTAL_OFFICIAL")
                        or self.hidden("TOGGLE_PFRESTHOUSE_CLERK_HEALING"),
                        "the rental official and the healing clerk share one spot")

        self.hide("TOGGLE_WILD_AREA_POKEBALL_1")  # as if collected
        battle_count = h.read8("wBattleCount")
        layout = h.read_bytes("wOverworldMap", 601)

        # In: walk the maze to the cell below the door, then up onto the door.
        h.write8("wProcForestWildBudget", 0)  # no encounter mid-walk
        self.walk_to((2 * x + 1, 2 * y + 2))
        self.press_until("up", house, "into the rest house")
        # The room itself: its blocks are read through a bankless header
        # pointer, so a bank mismatch draws garbage (2026-10-13, seen in BGB).
        width = h.read8("wCurMapWidth")
        stride = width + 6
        loaded = [h.read8("wOverworldMap", offset=(3 + row) * stride + 3 + col)
                  for row in range(h.read8("wCurMapHeight")) for col in range(width)]
        self.assertEqual(loaded, list((ROOT / "maps/ProceduralForestRestHouse.blk").read_bytes()),
                         "the rest house did not load its own blocks")
        exit_warps = h.warp_entries()[:2]
        for entry in exit_warps:
            self.assertEqual(entry[2:], [3 + site, forest], "the house's way out is not this forest's door")

        for trip in range(2):
            with self.subTest(trip=trip):
                self.press_until("down", forest, f"out of the house ({trip})")
                self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (2 * x + 1, 2 * y + 2),
                                 "did not land on the door and step out below it")
                self.assertEqual(h.read_bytes("wOverworldMap", 601), layout, "the forest changed")
                self.assertTrue(self.hidden("TOGGLE_WILD_AREA_POKEBALL_1"), "collected ball re-shown")
                for ball in (2, 3, 4):
                    self.assertFalse(self.hidden(f"TOGGLE_WILD_AREA_POKEBALL_{ball}"))
                self.assertEqual(h.read8("wBattleCount"), battle_count)
                self.assertEqual(h.read8("wLastMap"), lobby)
                if trip == 0:
                    self.press_until("up", house, "back in through the door")

    def test_residents_serve(self) -> None:
        h = self.h
        events = parse_rgbds_constants(ROOT / "constants/event_constants.asm")
        bought = events["EVENT_BOUGHT_POKEMON"]

        # Offers were rolled with the forest: both mart lists, the salesman's
        # and the trader's species, and a fresh purchase/trade state.
        forest = self.maps["PROCEDURAL_FOREST"]
        house = self.maps["PROCEDURAL_FOREST_REST_HOUSE"]
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        h.set_event(bought)  # as if the lobby salesman had sold this visit
        h.preload_and_enter_wild_area(forest, "forest")
        scratch = h.read_sram_bytes("sProcForestGenScratch", 81, bank=0)
        for name, start in (("healing", 40), ("stock", 52)):
            mart = scratch[start:start + 12]
            self.assertEqual(mart[0], 10, f"{name} mart count")
            self.assertEqual(mart[11], 0xFF, f"{name} mart terminator")
            self.assertTrue(all(0 < item < 0xFF for item in mart[1:11]), f"{name} mart items {mart}")
        self.assertNotEqual(h.read8("wroguenpcsell"), 0, "no salesman offer")
        self.assertNotEqual(h.read8("wroguenpctradeget"), 0, "no trade offer")
        self.assertFalse(h.event_is_set(bought), "the house salesman inherited the lobby's sale")

        # Everyone home, the healing clerk on the shared spot, the wandering
        # salesman out of the way of the walk (his code is the lobby's own).
        for name in ("CLERK_HEALING", "CLERK_STOCK", "MOVE_TUTOR", "TRADER", "GAMBLER"):
            index = self.toggles[f"TOGGLE_PFRESTHOUSE_{name}"]
            byte = h.read8("wToggleableObjectFlags", offset=index // 8)
            h.write8("wToggleableObjectFlags", byte & ~(1 << index % 8), offset=index // 8)
        for name in ("RENTAL_OFFICIAL", "SALESMAN"):
            self.hide(f"TOGGLE_PFRESTHOUSE_{name}")

        site = (h.read_sram_bytes("sProcForestItemGot", 1, bank=0)[0] & SITE_MASK) - 1
        x, y = self.sites[site]
        h.write8("wProcForestWildBudget", 0)
        self.walk_to((2 * x + 1, 2 * y + 2))
        self.press_until("up", house, "into the rest house")
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (2, 7))
        budget = h.read8("wProcForestWildBudget")

        for move in ("up", "right", "right"):          # to (4,6), across the counter
            self.step(move)
        self.talk("right", "BUY", "healing clerk")
        self.step("up")                                 # (4,5)
        self.talk("right", "BUY", "stock clerk")
        self.step("left")                               # (3,5), below the tutor
        self.talk("up", "pathway", "move tutor")
        for move in ("left", "up", "up", "left", "left"):   # to (0,3), below the trader
            self.step(move)
        # Decoded the way screen_text decodes the tilemap (non-letters become
        # spaces): since the trader carries the offer's form (2026-10-13), the
        # name can be a form name with a dash, e.g. "A-VULPIX" -> "A VULPIX".
        trade_name = self.h.read_bytes("wroguenpctradename", 10)
        trade_name = trade_name[:trade_name.index(0x50)] if 0x50 in trade_name else trade_name
        name = "".join(chr(ord("A") + c - 0x80) if 0x80 <= c <= 0x99 else " " for c in trade_name)
        self.talk("up", name[:4], "trade guru")
        self.assertEqual(h.read8("wProcForestWildBudget"), budget, "a mart cost the forest its wild budget")



if __name__ == "__main__":
    unittest.main()
