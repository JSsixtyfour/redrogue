"""Play the Facility spinner decor in the engine (PROCEDURAL_SUBROOMS_PLAN Phase 3).

audit_facility_spinner_rooms.py checks placement over a corpus; this plays the
shipped piece. A route is planned over the same graph tools/facility_spinners.py
proves with (stepping onto an arrow moves you to that slide's end), from the
entrance to the tile beside the pokeball, and walked for real: every slide must
stop exactly where the tool says. The ball is picked up, then a route back to
the entrance is planned and walked, which is the no-trap proof replayed.
"""

from __future__ import annotations

import io
import sys
import unittest
from collections import deque
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
from audit_facility_stranded_quadrants import BLOCKSET, ENTRANCE, passable

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import facility_spinners as spin  # noqa: E402

ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
ENTRY_ATTEMPTS = 40
STEP = {(0, -1): "up", (0, 1): "down", (-1, 0): "left", (1, 0): "right"}


class FacilitySpinnerRoomTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        pieces, errors = spin.load()
        self.assertFalse(errors, errors)
        self.pieces = pieces
        self.h = RedRogueHarness(ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.h.close()

    def enter_with_spinner(self):
        """Enter a Facility that got spinner decor; return (piece, origin tile, ball index)."""
        h = self.h
        facility = self.maps["PROCEDURAL_FACILITY"]
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        lobby = io.BytesIO()
        h.save_state(lobby)
        for offset in range(ENTRY_ATTEMPTS):
            h.load_state(lobby)
            h.tick(offset * 5)
            h.preload_and_enter_wild_area(facility, "facility")
            ox, oy, key, ball = h.read_sram_bytes("sProcFacilityGenScratch", 6)[2:6]
            if key & 0x80:
                return self.pieces[key & 0x7F], (2 * ox, 2 * oy), ball
        self.fail(f"no Facility with spinner decor in {ENTRY_ATTEMPTS} entries")

    def step(self, direction: str) -> None:
        """Exactly one tile: hold only until the position changes."""
        h = self.h
        cur = (h.read8("wXCoord"), h.read8("wYCoord"))
        h.pyboy.button_press(direction)
        try:
            h.wait_until(lambda: (h.read8("wXCoord"), h.read8("wYCoord")) != cur,
                         f"step {direction} from {cur}", 60)
        finally:
            h.pyboy.button_release(direction)
        h.wait_until(lambda: h.read8("wWalkCounter") == 0, "step settles", 60)
        h.tick(2)

    def rest_on(self, tile, description: str) -> None:
        """Wait until the player rests on `tile` with any slide finished. A slide
        of one tile is over before a poll could see it start, so arrival is
        what is checked: stepping onto an arrow alone stops ON the arrow."""
        h = self.h
        h.wait_until(lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == tile
                     and h.read8("hSimulatedJoypadStatesIndex") == 0
                     and not h.read8("wMovementFlags") & 0x80
                     and h.read8("wWalkCounter") == 0,
                     f"{description}: rest on {tile}", 600)
        h.tick(20)
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), tile,
                         f"{description}: moved on after landing")

    def travel(self, goal, piece, origin, ball_world, blocked, ball_gone=False) -> int:
        """Plan over walk + slide edges and play it. Returns the slides ridden."""
        h = self.h
        layout = h.read_bytes("wOverworldMap", 601)
        playable = tuple(layout[81 + r * 26 + c] for r in range(20) for c in range(20))
        cells = passable(BLOCKSET.read_bytes(), playable) - blocked
        if not ball_gone:
            cells.discard(ball_world)
        ends = {(origin[0] + x, origin[1] + y): (origin[0] + e[0], origin[1] + e[1])
                for (x, y), (e, _m) in piece.slides.items()}
        start = (h.read8("wXCoord"), h.read8("wYCoord"))
        prev = {start: None}
        todo = deque([start])
        while todo:
            cur = todo.popleft()
            if cur == goal:
                break
            for dx, dy in STEP:
                nxt = (cur[0] + dx, cur[1] + dy)
                if nxt not in cells:
                    continue
                land = ends.get(nxt, nxt)
                if land not in prev:
                    prev[land] = (cur, nxt)
                    todo.append(land)
        self.assertIn(goal, prev, f"no route from {start} to {goal}")
        plan = []
        node = goal
        while prev[node] is not None:
            cur, via = prev[node]
            plan.append((cur, via, node))
            node = cur
        rides = 0
        for cur, via, land in reversed(plan):
            here = (h.read8("wXCoord"), h.read8("wYCoord"))
            self.assertEqual(here, cur, "route desynchronised")
            self.step(STEP[(via[0] - cur[0], via[1] - cur[1])])
            if via in ends:
                rides += 1
                local = (via[0] - origin[0], via[1] - origin[1])
                self.rest_on(land, f"arrow {local}")
            else:
                self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), via,
                                 f"walk stalled at {cur} heading for {via}")
        return rides

    def test_spinner_decor_reaches_the_ball_and_lets_the_player_out(self) -> None:
        h = self.h
        piece, origin, ball = self.enter_with_spinner()
        h.write8("wProcFacilityWildBudget", 0)
        ball_world = (origin[0] + piece.ball[0], origin[1] + piece.ball[1])
        self.assertEqual(
            tuple(h.read_sram_bytes("sProcFacilityBallXY", 8)[2 * ball: 2 * ball + 2]),
            (ball_world[1] + 4, ball_world[0] + 4),
            "the ball is not on the piece's ball tile",
        )

        # Every object except the reward ball, and the boss room, are walls.
        blocked = {(x, y) for y, x in h.sprite_positions(9)} - {ball_world}
        ex, ey, ew, eh = h.read_sram_bytes("sProcFacilityGenScratch", 72)[66:70]
        blocked |= {(x, y) for y in range(2 * (ey - 1), 2 * (ey + eh + 1))
                    for x in range(2 * (ex - 1), 2 * (ex + ew + 1))}

        # Stand beside the ball: whichever neighbour the route reaches first.
        targets = [(ball_world[0] + dx, ball_world[1] + dy, face) for (dx, dy), face in
                   (((-1, 0), "right"), ((1, 0), "left"), ((0, -1), "down"), ((0, 1), "up"))]
        last_error = None
        for tx, ty, face in targets:
            try:
                rides = self.travel((tx, ty), piece, origin, ball_world, blocked)
                break
            except AssertionError as exc:
                last_error = exc
                if "no route" not in str(exc):
                    raise
        else:
            self.fail(f"no route to any tile beside the ball: {last_error}")
        self.assertGreater(rides, 0, "the ball was reachable without riding a single arrow")

        toggle = self.toggles[f"TOGGLE_WILD_AREA_POKEBALL_{ball + 1}"]
        h.tap(face, 4)
        h.tap("a", 4)
        for _ in range(6):
            h.tick(40)
            h.tap("a", 4)
        self.assertTrue(h.read8("wToggleableObjectFlags", offset=toggle // 8) & 1 << toggle % 8,
                        "the reward ball was not picked up")

        # And back out to the entrance, ball gone.
        self.travel(ENTRANCE, piece, origin, ball_world, blocked, ball_gone=True)
        self.assertFalse(h.read8("wMovementFlags") & 0x80, "BIT_SPINNING left set")
        self.assertEqual(h.read8("hJoyIgnore"), 0, "input left ignored")


if __name__ == "__main__":
    unittest.main()
