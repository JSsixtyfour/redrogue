"""The wandering Psychic Psyduck in the way: spinner slides, corridors and warps.

A slide only checks for collision on its last step, so these put the sprite on each
kind of tile in the real Facility and ride the real slide. Whatever it blocks, the
fight must start from the tile beside it and the player must get control back.
"""
from __future__ import annotations

import io
import unittest
from collections import deque

from audit_facility_pad_sites import FIRST_PAD_WARP, PAD_NONE
from test_facility_spinner_room import spin
from test_optional_facility import DOWN, FIRST, LEFT, RANGE, RIGHT, SLOT, UP, FacilityTripBase

FACING = {"down": DOWN, "up": UP, "left": LEFT, "right": RIGHT}
STEP = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}
OPPOSITE = {"up": "down", "down": "up", "left": "right", "right": "left"}
BIT_SPINNING = 0x80
WANDER, ANY_DIR = 0xFE, 0


def seeds(count):
    for i in range(count):
        yield (23 + i * 7 & 255, 201 - i * 11 & 255, 77 + i * 3 & 255, 9 + i * 5 & 255 | 1)


class WanderRiskBase(FacilityTripBase):
    def put_mon(self, tile, facing):
        """Frozen on `tile`. Collision reads pixels, and the engine only re-seats a sprite
        from its map tile when it is on screen and the player is still."""
        h = self.h
        h.write8(f"wSprite{SLOT}StateData1YPixels", ((tile[1] - h.read8("wYCoord") + 4) * 16 - 4) & 255)
        h.write8(f"wSprite{SLOT}StateData1XPixels", ((tile[0] - h.read8("wXCoord") + 4) * 16) & 255)
        h.write8(f"wSprite{SLOT}StateData2MapX", tile[0] + 4)
        h.write8(f"wSprite{SLOT}StateData2MapY", tile[1] + 4)
        h.write8(f"wSprite{SLOT}StateData2YDisplacement", 8)
        h.write8(f"wSprite{SLOT}StateData2XDisplacement", 8)
        h.write8(f"wSprite{SLOT}StateData2MovementByte1", 0xFF)
        h.write8("wMapSpriteData", RANGE[facing], offset=(SLOT - 1) * 2)
        h.write8(f"wSprite{SLOT}StateData1FacingDirection", facing)
        h.write8(f"wSprite{SLOT}StateData1MovementStatus", 1)
        h.tick(2)

    def release_mon(self):
        h = self.h
        h.write8(f"wSprite{SLOT}StateData2MovementByte1", WANDER)
        h.write8("wMapSpriteData", ANY_DIR, offset=(SLOT - 1) * 2)

    def mon_tile(self):
        h = self.h
        return (h.read8(f"wSprite{SLOT}StateData2MapX") - 4, h.read8(f"wSprite{SLOT}StateData2MapY") - 4)

    def enter_spinner_facility(self, index=None):
        """index: only this piece. A test whose setup needs open floor around a
        slide asks for the 5x5: the 3x3 has no such slide."""
        h = self.h
        for seed in seeds(80):
            self.enter(force=True, seed=seed, hold=DOWN)
            ox, oy, key = h.read_sram_bytes("sProcFacilityGenScratch", 5)[2:5]
            if key & 0x80 and (index is None or key & 0x7F == index) \
                    and h.read8("wOptionalEncounterMap") == self.maps["PROCEDURAL_FACILITY"]:
                h.write8("wOptionalEncounterPackage", FIRST)
                pieces, errors = spin.load()
                self.assertFalse(errors, errors)
                piece = pieces[key & 0x7F]
                origin = (2 * ox, 2 * oy)
                self.slides = {(origin[0] + a[0], origin[1] + a[1]):
                               ((origin[0] + e[0], origin[1] + e[1]), moves)
                               for a, (e, moves) in piece.slides.items()}
                return
        self.fail("no spinner Facility in 80 seeds")

    def walkable(self):
        """Floor the player can use, as test_facility_spinner_room counts it."""
        h = self.h
        cells = self.cells()
        ex, ey, ew, eh = h.read_sram_bytes("sProcFacilityGenScratch", 72)[66:70]
        cells -= {(x, y) for y in range(2 * (ey - 1), 2 * (ey + eh + 1)) for x in range(2 * (ex - 1), 2 * (ex + ew + 1))}
        warps = h.warp_entries()
        return cells - {(w[1], w[0]) for w in warps[FIRST_PAD_WARP:] if w[0] != PAD_NONE}

    def reached(self, cells, avoid):
        """BFS over walks and slides from the player, never landing on `avoid`.
        Out: {tile: (previous tile, button)}."""
        start = self.here()
        prev = {start: None}
        todo = deque([start])
        while todo:
            cur = todo.popleft()
            for button, (dx, dy) in STEP.items():
                nxt = (cur[0] + dx, cur[1] + dy)
                if nxt not in cells or nxt == avoid:
                    continue
                land = self.slides[nxt][0] if nxt in self.slides else nxt
                # A landing counts too: callers drop the tiles beside the sprite
                # from `cells`, and sliding onto one starts the battle.
                if land in cells and land != avoid and land not in prev:
                    prev[land] = (cur, button)
                    todo.append(land)
        return prev

    def walk_route(self, prev, goal):
        h = self.h
        path = []
        node = goal
        while prev[node]:
            cur, button = prev[node]
            path.append((button, node))
            node = cur
        for button, land in reversed(path):
            before = self.here()
            h.pyboy.button_press(button)
            try:
                h.wait_until(lambda: self.here() != before, f"step {button} from {before}", 90)
            finally:
                h.pyboy.button_release(button)
            # A slide starts a frame after its arrow's step ends: wait for where it lands.
            h.wait_until(lambda: self.here() == land, f"landing on {land}", 240)
            self.settle()
        self.assertEqual(self.here(), goal)

    def settle(self, frames=600):
        h = self.h
        h.wait_until(lambda: h.read8("hSimulatedJoypadStatesIndex") == 0 and h.read8("hJoyIgnore") == 0
                     and not h.read8("wMovementFlags") & BIT_SPINNING and h.read8("wWalkCounter") == 0,
                     "the slide hands control back", frames)
        h.tick(2)

    def slide_onto(self, arrow, moves, mon_tile):
        """Walk to a tile beside `arrow` that does not come off another arrow into
        it, with the sprite already on `mon_tile`. Out: the button that steps on."""
        cells = self.walkable() | set(self.slides)
        # Coming beside it starts the battle, so the way there keeps clear.
        cells -= {(mon_tile[0] + dx, mon_tile[1] + dy) for dx, dy in STEP.values()}
        prev = self.reached(cells, mon_tile)
        for button, (dx, dy) in STEP.items():
            beside = (arrow[0] - dx, arrow[1] - dy)
            if beside in prev and beside not in self.slides and beside != mon_tile:
                self.walk_route(prev, beside)
                return button
        return None

    def pick(self, want):
        """The first arrow `want(arrow, end, moves)` accepts and the route reaches.
        Out: (arrow, end, moves, the button that steps on), with the player beside it."""
        h = self.h
        base = io.BytesIO()
        h.save_state(base)
        for arrow, (end, moves) in self.slides.items():
            spot = want(arrow, end, moves)
            if spot is None:
                continue
            mon_tile, facing = spot
            self.put_mon(mon_tile, facing)
            button = self.slide_onto(arrow, moves, mon_tile)
            if button:
                return arrow, end, moves, button
            h.load_state(base)
        return None

    def step_on(self, button):
        h = self.h
        h.pyboy.button_press(button)
        try:
            for _ in range(40):
                h.tick(1)
                if h.read8("wWalkCounter"):
                    break
        finally:
            h.pyboy.button_release(button)


class SpinnerSlideTest(WanderRiskBase):
    def test_on_a_slide_s_last_tile_it_stops_the_player_short_and_the_fight_starts(self):
        h = self.h
        self.enter_spinner_facility(index=0)

        def last_tile(arrow, end, moves):
            if len(moves) < 2:
                return None
            short = (end[0] - STEP[moves[-1]][0], end[1] - STEP[moves[-1]][1])
            return None if short in self.slides else (end, FACING[moves[-1]])  # facing away

        picked = self.pick(last_tile)
        self.assertTrue(picked, "no arrow with a free run-up")
        arrow, end, moves, button = picked
        self.step_on(button)
        short = (end[0] - STEP[moves[-1]][0], end[1] - STEP[moves[-1]][1])
        h.wait_until(lambda: h.read8("wOptionalEncounterScript"), "it starts the battle", 240)
        self.assertEqual(self.here(), short, "the last step should be blocked")
        self.fight("PSYDUCK", FIRST, True)
        self.settle()
        self.assertEqual(h.read8(f"wSprite{SLOT}StateData1"), 0)
        self.step(moves[-1])
        self.assertEqual(self.here(), end)

    def test_on_a_slide_s_lane_the_player_passes_through_to_the_proven_end(self):
        h = self.h
        self.enter_spinner_facility()

        def lane(arrow, end, moves):
            # Two tiles along: not beside the arrow, nor beside the end.
            first = STEP[moves[0]]
            second = STEP[moves[1]] if len(moves) > 1 else first
            tile = (arrow[0] + first[0] + second[0], arrow[1] + first[1] + second[1])
            apart = abs(arrow[0] - tile[0]) + abs(arrow[1] - tile[1]) > 1 and abs(end[0] - tile[0]) + abs(end[1] - tile[1]) > 1
            return (tile, UP) if len(moves) >= 3 and apart and tile not in self.slides else None

        picked = self.pick(lane)
        self.assertTrue(picked, "no long slide with a free run-up")
        arrow, end, moves, button = picked
        here = self.mon_tile()
        self.step_on(button)
        h.wait_until(lambda: self.here() == end, "the slide reaches its end", 240)
        self.settle()
        self.assertEqual(self.mon_tile(), here)
        self.assertEqual(h.read8("hIsInBattle"), 0)

    def test_on_an_arrow_it_is_fought_from_beside_and_the_arrow_then_works(self):
        h = self.h
        self.enter_spinner_facility()
        base = io.BytesIO()
        h.save_state(base)
        for arrow, (end, moves) in self.slides.items():
            h.load_state(base)
            cells = self.walkable() | set(self.slides)
            prev = self.reached(cells, arrow)
            for button, (dx, dy) in STEP.items():
                beside = (arrow[0] - dx, arrow[1] - dy)
                if beside in prev and beside not in self.slides:
                    around = {(arrow[0] + ax, arrow[1] + ay) for ax, ay in STEP.values()} - {beside}
                    route = self.reached(cells - around, arrow)
                    if beside not in route:
                        continue
                    self.put_mon(arrow, FACING[button])  # facing away from the player
                    self.walk_route(route, beside)
                    self.fight("PSYDUCK", FIRST, True)
                    self.settle()
                    self.step_on(button)
                    h.wait_until(lambda: self.here() == end, "the arrow slides after it left", 240)
                    self.settle()
                    return
        self.fail("no arrow with a free run-up")

    def assert_battle_then_offer_then_slide(self, arrow, end, button):
        """The order that keeps the buttons live: the offer before the arrow's slide."""
        h = self.h
        self.step_on(button)
        h.wait_until(lambda: h.read8("wOptionalEncounterScript"), "it starts the battle", 240)
        self.assertEqual(self.here(), arrow, f"the battle starts from the arrow; it is on {self.mon_tile()}")
        self.fight("PSYDUCK", FIRST, True)
        self.assertEqual(h.read8(f"wSprite{SLOT}StateData1"), 0)
        h.wait_until(lambda: self.here() == end, "the slide finishes after the offer", 240)
        self.settle()

    def test_a_slide_of_one_step_into_it_starts_the_battle_and_then_finishes(self):
        self.enter_spinner_facility()
        picked = self.pick(lambda arrow, end, moves: (end, FACING[moves[0]]) if len(moves) == 1 else None)
        self.assertTrue(picked, "no one-step arrow with a free run-up")
        arrow, end, _, button = picked
        self.assert_battle_then_offer_then_slide(arrow, end, button)

    def test_beside_it_on_an_arrow_the_offer_comes_before_the_slide(self):
        self.enter_spinner_facility()

        def beside(arrow, end, moves):
            # Off the slide's line, looking at the arrow.
            for side, (dx, dy) in STEP.items():
                tile = (arrow[0] + dx, arrow[1] + dy)
                if side not in (moves[0], OPPOSITE[moves[0]]) and tile in self.walkable():
                    return tile, FACING[OPPOSITE[side]]
            return None

        picked = self.pick(beside)
        self.assertTrue(picked, "no arrow with a free side")
        arrow, end, _, button = picked
        self.assert_battle_then_offer_then_slide(arrow, end, button)


class CorridorAndWarpTest(WanderRiskBase):
    def corridor(self):
        """Out: (tile, near neighbour, far neighbour, button) for a real one-wide choke
        whose far side holds floor the player can reach no other way."""
        cells = self.walkable()
        start = self.here()
        seen, todo = {start}, deque([start])
        while todo:
            cur = todo.popleft()
            for dx, dy in STEP.values():
                nxt = (cur[0] + dx, cur[1] + dy)
                if nxt in cells and nxt not in seen:
                    seen.add(nxt)
                    todo.append(nxt)
        for tile in sorted(seen - {start}, key=lambda t: abs(t[0] - start[0]) + abs(t[1] - start[1])):
            for button, (dx, dy) in STEP.items():
                near, far = (tile[0] - dx, tile[1] - dy), (tile[0] + dx, tile[1] + dy)
                if near not in cells or far not in cells:
                    continue
                side = {(tile[0] + dy, tile[1] + dx), (tile[0] - dy, tile[1] - dx)}
                if side & cells:
                    continue
                without = cells - {tile}
                got, todo = {start}, deque([start])
                while todo:
                    cur = todo.popleft()
                    for ddx, ddy in STEP.values():
                        nxt = (cur[0] + ddx, cur[1] + ddy)
                        if nxt in without and nxt not in got:
                            got.add(nxt)
                            todo.append(nxt)
                if near in got and far not in got:
                    return tile, near, far, button, len(seen) - len(got) - 1
        return None

    def test_it_can_block_a_corridor_only_until_the_player_reaches_it(self):
        h = self.h
        for seed in seeds(40):
            self.enter(force=True, seed=seed, hold=DOWN)
            if h.read8("wOptionalEncounterMap") != self.maps["PROCEDURAL_FACILITY"]:
                continue
            self.slides = {}
            choke = self.corridor()
            if choke:
                break
        else:
            self.fail("no corridor in 40 Facilities")
        tile, near, far, button, cut_off = choke
        print(f"\ncorridor: {tile}, {cut_off} tiles behind it")
        h.write8("wOptionalEncounterPackage", FIRST)
        self.put_mon(tile, FACING[button])  # its back to the player
        self.walk_route(self.reached(self.walkable(), tile), near)
        h.wait_until(lambda: h.read8("wOptionalEncounterScript"), "reaching it", 240)
        self.fight("PSYDUCK", FIRST, True)
        self.settle()
        self.step(button)
        self.step(button)
        self.assertEqual(self.here(), far)

    def test_on_a_warp_tile_it_waits_and_a_is_the_way_to_fight(self):
        """OptionalPlayerOnWarp. A pad a player has just come back to is such a tile,
        so an armed pad is moved under the player here."""
        h = self.h
        for seed in seeds(40):
            self.enter(force=True, seed=seed, hold=DOWN)
            if h.read8("wOptionalEncounterMap") != self.maps["PROCEDURAL_FACILITY"]:
                continue
            armed = [i for i, w in enumerate(h.warp_entries()) if i >= FIRST_PAD_WARP and w[0] != PAD_NONE]
            x, y = self.here()
            cells = self.walkable()
            way = [(b, d) for b, d in STEP.items() if (x + d[0], y + d[1]) in cells]
            if armed and way:
                break
        else:
            self.fail("no Facility with a pad")
        button, (dx, dy) = way[0]
        entry = h.address("wWarpEntries") + armed[0] * 4
        h.pyboy.memory[entry], h.pyboy.memory[entry + 1] = y, x
        h.write8("wOptionalEncounterPackage", FIRST)
        room = h.read8("hCurMap")
        self.put_mon((x + dx, y + dy), FACING[button])
        h.pyboy.button_press(button)
        h.tick(120)
        h.pyboy.button_release(button)
        h.tick(4)
        self.assertEqual((self.here(), h.read8("hCurMap")), ((x, y), room), "it moved the player")
        self.assertEqual(h.read8("wOptionalEncounterScript"), 0, "fought from a warp tile")
        self.assertEqual(h.read8("hJoyIgnore"), 0)
        h.write8("wSpritePlayerStateData1FacingDirection", FACING[button])
        h.tick(2)
        h.tap("a", frames=8)
        self.fight("PSYDUCK", FIRST, True)
        self.settle()
        self.assertEqual(h.read8(f"wSprite{SLOT}StateData1"), 0)
        print(f"after a fight on a pad: map {h.read8('hCurMap'):#x}, was {room:#x}, at {self.here()}")


if __name__ == "__main__":
    unittest.main()
