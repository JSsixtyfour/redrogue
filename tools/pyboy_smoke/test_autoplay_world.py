"""Pure unit tests for the autoplay agent's overworld model (autoplay_world.py).

No ROM: synthetic grids, plus the block-to-step decoding on hand-built
wOverworldMap and blockset bytes.
"""
import unittest
from types import SimpleNamespace

import autoplay_world as world


class BagErrandRecoveryTest(unittest.TestCase):
    def test_battle_takes_control_from_bag_errand_but_keeps_battle_errand(self):
        import autoplay
        for kind in ("bag", "battle"):
            with self.subTest(kind=kind):
                agent = object.__new__(autoplay.AutoplayAgent)
                agent.h = SimpleNamespace(pyboy=SimpleNamespace(frame_count=100),
                    read8=lambda name: {"hIsInBattle": 1, "wIsTrainerBattle": 1,
                                        "wCurOpponent": 42}[name])
                agent.in_battle = False
                agent.errand = {"kind": kind, "presses": 123, "start": 0}
                agent.trainer_names = {42: "TEST_TRAINER"}
                agent.ai_telemetry = None
                events = []
                agent.event = lambda *args, **kwargs: events.append((args, kwargs))
                agent.track_battles()
                self.assertTrue(agent.in_battle)
                if kind == "bag":
                    self.assertIsNone(agent.errand)
                    self.assertEqual(events[0][1]["why"], "battle started")
                else:
                    self.assertEqual(agent.errand["kind"], "battle")

    def test_exhausted_bag_errand_keeps_cancelling_until_overworld(self):
        import autoplay
        agent = object.__new__(autoplay.AutoplayAgent)
        agent.errand = {"kind": "bag", "presses": autoplay.ERRAND_GIVE_UP, "opened": True}
        original = agent.errand
        buttons, events = [], []
        agent.press = buttons.append
        agent.event = lambda *args, **kwargs: events.append((args, kwargs))
        # Several nested menus may each require B. Returning control to the
        # default A policy between them would re-enter the selected item.
        for _ in range(4):
            agent.errand_step()
            self.assertIs(agent.errand, original)
        self.assertEqual(buttons, ["b"] * 4)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0][0], ("errand_recovery",))

    def test_learning_cancel_goal_waits_for_the_new_confirmation(self):
        import autoplay
        agent = object.__new__(autoplay.AutoplayAgent)
        agent.h = SimpleNamespace(pyboy=SimpleNamespace(frame_count=100), read8=lambda _: 1)
        agent.errand = {"kind": "bag", "presses": autoplay.ERRAND_GIVE_UP}
        agent.menu_frame = 99
        agent.last_menu_caller = "DisplayTwoOptionMenu.notNoYesMenu"
        agent._on_abandon_learning(None)
        self.assertFalse(agent.menu_goal.waiting())
        agent.menu_frame = 101
        self.assertTrue(agent.menu_goal.waiting())
        self.assertEqual(agent.menu_goal.next_button(), "up")
        self.assertEqual(agent.menu_goal.button, "a")
        agent.errand = {"kind": "battle", "presses": 999}
        agent.menu_goal = None
        agent._on_abandon_learning(None)
        self.assertIsNone(agent.menu_goal)


class SpinnerCacheLifecycleTest(unittest.TestCase):
    def test_warp_retires_layout_and_same_map_id_accepts_new_table(self):
        import autoplay
        agent = object.__new__(autoplay.AutoplayAgent)
        agent.h = SimpleNamespace(
            read8=lambda name: {"hCurMap": 243, "hLoadedROMBank": 47}[name],
            pyboy=SimpleNamespace(register_file=SimpleNamespace(HL=0x7bec, B=3, C=4)))
        agent.position = lambda: (30, 29)
        agent.warps_taken = set()
        agent.arrow_table = (243, 47, 0x7000, 2, 2)
        agent._arrows = (agent.arrow_table, {(30, 28): (33, 28)})
        agent._on_warp(None)
        self.assertIsNone(agent.arrow_table)
        self.assertEqual(agent._arrows, (None, {}))
        self.assertIn((243, 30, 29), agent.warps_taken)
        agent._on_arrow_table(None)
        self.assertEqual(agent.arrow_table, (243, 47, 0x7bec, 26, 26))
        # Recursive decoder hooks must still retain the first complete table.
        agent.h.pyboy.register_file.HL += 6
        agent._on_arrow_table(None)
        self.assertEqual(agent.arrow_table[2], 0x7bec)

WALL, FLOOR, LEDGE, STAND, COUNTER = 0x01, 0x02, 0x37, 0x2C, 0x03


def grid_from_rows(rows, **kwargs):
    """'#' wall, '.' floor, 'v' ledge, 's' floor that can jump the ledge
    below, 'c' counter."""
    tiles = {"#": WALL, ".": FLOOR, "v": LEDGE, "s": STAND, "c": COUNTER}
    return world.WalkGrid(
        width=len(rows[0]),
        height=len(rows),
        tiles=[[tiles[ch] for ch in row] for row in rows],
        passable=frozenset({FLOOR, STAND}),
        **kwargs,
    )


def walk(grid, start, path):
    position = start
    for direction in path:
        position = dict(grid.moves(*position))[direction]
    return position


class GridFromBlocksTest(unittest.TestCase):
    def test_each_step_stands_on_the_lower_left_tile_of_its_square(self):
        # One 1x1-block map inside the 3-block border: 7x7 blocks, block 1 in
        # the middle. Its 4x4 tiles are numbered row-major 0..15, so the four
        # steps stand on tiles 4 (row 1, col 0), 6, 12 and 14.
        overworld = [0] * 49
        overworld[3 * 7 + 3] = 1
        blockset = [0xFF] * 16 + list(range(16))
        grid = world.grid_from_blocks(1, 1, overworld, blockset, {4, 14})
        self.assertEqual(grid.tiles, [[4, 6], [12, 14]])
        self.assertTrue(grid.walkable(0, 0))
        self.assertFalse(grid.walkable(1, 0))
        self.assertTrue(grid.walkable(1, 1))
        self.assertFalse(grid.walkable(2, 1))  # out of bounds


class MovesTest(unittest.TestCase):
    def test_walls_and_bounds(self):
        grid = grid_from_rows(["..#", "..."])
        self.assertEqual(dict(grid.moves(1, 0)), {"down": (1, 1), "left": (0, 0)})

    def test_ledge_jumps_two_steps_one_way_only(self):
        grid = grid_from_rows(["s", "v", "."], ledges=(world.Ledge(world.FACING["down"], STAND, LEDGE),))
        self.assertEqual(dict(grid.moves(0, 0)), {"down": (0, 2)})
        self.assertEqual(dict(grid.moves(0, 2)), {})  # no climbing back up

    def test_ledge_needs_the_listed_standing_tile(self):
        grid = grid_from_rows([".", "v", "."], ledges=(world.Ledge(world.FACING["down"], STAND, LEDGE),))
        self.assertEqual(dict(grid.moves(0, 0)), {})

    def test_tile_pair_collision_blocks_both_directions_on_its_tileset(self):
        pairs = frozenset({(7, FLOOR, STAND)})
        same = grid_from_rows([".s"], tileset=7, pair_collisions=pairs)
        other = grid_from_rows([".s"], tileset=8, pair_collisions=pairs)
        self.assertEqual(dict(same.moves(0, 0)), {})
        self.assertEqual(dict(same.moves(1, 0)), {})
        self.assertEqual(dict(other.moves(0, 0)), {"right": (1, 0)})

    def test_teleport_lands_on_its_destination(self):
        grid = grid_from_rows(["....", "...."], teleports={(1, 0): (3, 1)})
        self.assertEqual(dict(grid.moves(0, 0))["right"], (3, 1))


class FindPathTest(unittest.TestCase):
    def test_shortest_path_around_a_wall(self):
        grid = grid_from_rows([
            "....",
            ".##.",
            "....",
        ])
        path = world.find_path(grid, (0, 1), {(3, 1)})
        self.assertEqual(len(path), 5)
        self.assertEqual(walk(grid, (0, 1), path), (3, 1))

    def test_already_there_and_unreachable(self):
        grid = grid_from_rows([".#."])
        self.assertEqual(world.find_path(grid, (0, 0), {(0, 0)}), [])
        self.assertIsNone(world.find_path(grid, (0, 0), {(2, 0)}))

    def test_blocked_steps_are_avoided_but_a_goal_is_not_blocked(self):
        grid = grid_from_rows(["...", "..."])
        path = world.find_path(grid, (0, 0), {(2, 0)}, blocked={(1, 0), (2, 0)})
        self.assertEqual(path, ["down", "right", "right", "up"])

    def test_impassable_goal_only_when_asked(self):
        # A warp drawn on a wall tile: reachable only by walking into it.
        grid = grid_from_rows(["..#"])
        self.assertIsNone(world.find_path(grid, (0, 0), {(2, 0)}))
        self.assertEqual(
            world.find_path(grid, (0, 0), {(2, 0)}, enter_impassable_goals=True),
            ["right", "right"],
        )

    def test_path_through_an_arrow_tile(self):
        # The only way to the right room is the arrow at (1, 0), which carries
        # the player to (3, 0).
        grid = grid_from_rows(["..#.."], teleports={(1, 0): (3, 0)})
        self.assertEqual(world.find_path(grid, (0, 0), {(4, 0)}), ["right", "right"])


class HelpersTest(unittest.TestCase):
    def test_arrow_destination_sums_its_movement_list(self):
        down, right = 0x80, 0x10
        self.assertEqual(world.arrow_destination((5, 5), [(down, 3), (right, 2)]), (7, 8))

    def test_adjacent_facing_includes_talking_across_a_counter(self):
        grid = grid_from_rows([
            "...",
            ".c.",
            "...",
        ])
        spots = world.adjacent_facing((1, 0), {COUNTER}, grid)
        self.assertEqual(spots[(1, 1)], "up")
        self.assertEqual(spots[(1, 2)], "up")  # across the counter
        self.assertEqual(spots[(0, 0)], "right")
        self.assertNotIn((0, 1), spots)

    def test_render_marks(self):
        grid = grid_from_rows([".#"])
        self.assertEqual(world.render(grid, {(0, 0): "@"}), "@#")


if __name__ == "__main__":
    unittest.main()
