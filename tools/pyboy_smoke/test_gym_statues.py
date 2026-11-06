"""Johto gym statues read, and Whitney's exit opens to a walkable path."""
from collections import deque
import re
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
import save_reload

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).parent / "artifacts" / "gym_statues"
MAPS = parse_map_constants(ROOT / "constants/map_constants.asm")
EVENTS = parse_rgbds_constants(ROOT / "constants/event_constants.asm")
SPRITE_FACING_UP = 0x04
BADGE_MASK = 0x01

GYMS = ("VIOLET", "AZALEA", "GOLDENROD", "ECRUTEAK", "CIANWOOD", "OLIVINE", "MAHOGANY", "BLACKTHORN")
EXPECTED_STATUES = {
    "VIOLET": 2, "AZALEA": 2, "GOLDENROD": 2, "ECRUTEAK": 4,
    "CIANWOOD": 4, "OLIVINE": 2, "MAHOGANY": 2, "BLACKTHORN": 6,
}

GOLDENROD_WIDTH = 10
GOLDENROD_OPEN_BLOCK = 0x33
# Trees and door as drawn before Whitney is beaten, then the blocks that replace them.
GOLDENROD_EXIT_BLOCKS = ((0, 4, 0x7A), (1, 4, 0x3A))
GYM_PASSABLE = {0x11, 0x16, 0x19, 0x2B, 0x3C, 0x3D, 0x3F, 0x4A, 0x4C, 0x4D, 0x03}
DIRECTIONS = {(0, -1): "up", (0, 1): "down", (-1, 0): "left", (1, 0): "right"}


def statue_cells(gym: str) -> list[tuple[int, int]]:
    text = (ROOT / "data/events/hidden_events.asm").read_text(encoding="utf-8")
    block = re.search(rf"hidden_events_for {gym}_GYM\n(.*?)db -1", text, re.S)
    return [(int(x), int(y)) for x, y in re.findall(r"hidden_event\s+(\d+),\s*(\d+), GymStatues", block[1])]


class GymStatueTest(unittest.TestCase):
    def boot(self, map_name: str) -> RedRogueHarness:
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.register_hook("DebugMenu.startDebugGame",
                        lambda _: setattr(h.pyboy.register_file, "A", MAPS[map_name]))
        h.boot_debug1(MAPS[map_name])
        self.assertTrue(save_reload.settle(h))
        return h

    def beat_gym_trainers(self, h: RedRogueHarness, gym: str) -> None:
        for index in range(3):
            h.set_event(EVENTS[f"EVENT_BEAT_{gym}_GYM_TRAINER_{index}"])

    def test_every_statue_answers(self) -> None:
        for gym in GYMS:
            with self.subTest(gym=gym):
                cells = statue_cells(gym)
                self.assertEqual(len(cells), EXPECTED_STATUES[gym])
                h = self.boot(f"{gym}_GYM")
                self.beat_gym_trainers(h, gym)
                h.write8("wRogueCurGymBadgeMask", BADGE_MASK)
                statue = h.hook_flag("GymStatues")
                text = h.hook_flag("PrintPredefTextID")
                for x, y in cells:
                    before = statue["count"], text["count"]
                    h.write8("wXCoord", x)
                    h.write8("wYCoord", y + 1)
                    h.write8("wSpritePlayerStateData1FacingDirection", SPRITE_FACING_UP)
                    h.tap("a")
                    h.tick(10)
                    self.assertGreater(statue["count"], before[0], f"statue at {(x, y)} did not answer")
                    self.assertGreater(text["count"], before[1], f"statue at {(x, y)} printed nothing")
                    for _ in range(30):
                        h.tap("b", 6)
                self.assertFalse(h.hook_errors)
                h.close()

    def overworld_block(self, h: RedRogueHarness, row: int, column: int) -> int:
        stride = GOLDENROD_WIDTH + 6
        return h.read8("wOverworldMap", (row + 3) * stride + column + 3)

    def test_whitney_exit_stays_closed_until_she_is_beaten(self) -> None:
        h = self.boot("GOLDENROD_GYM")
        for row, column, closed in GOLDENROD_EXIT_BLOCKS:
            self.assertEqual(self.overworld_block(h, row, column), closed)
        self.assertEqual(h.read8("wCurMapWidth"), GOLDENROD_WIDTH)
        self.assertFalse(h.event_is_set(EVENTS["EVENT_BEAT_WHITNEY"]))

    def test_a_cell_without_a_statue_stays_silent(self) -> None:
        h = self.boot("GOLDENROD_GYM")
        self.beat_gym_trainers(h, "GOLDENROD")
        h.write8("wRogueCurGymBadgeMask", BADGE_MASK)
        statue = h.hook_flag("GymStatues")
        h.write8("wXCoord", 10)
        h.write8("wYCoord", 10)
        h.write8("wSpritePlayerStateData1FacingDirection", SPRITE_FACING_UP)
        h.tap("a")
        h.tick(10)
        self.assertEqual(statue["count"], 0)

    def test_whitney_exit_is_walkable_after_she_is_beaten(self) -> None:
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        h.enter_stage_door1(MAPS["GOLDENROD_GYM"], description="GOLDENROD_GYM (WHITNEY)")
        self.assertTrue(save_reload.settle(h))
        self.assertIn((h.read8("wXCoord"), h.read8("wYCoord")), {(2, 17), (3, 17)})
        self.beat_gym_trainers(h, "GOLDENROD")
        h.set_event(EVENTS["EVENT_BEAT_WHITNEY"])
        flags = parse_rgbds_constants(ROOT / "constants/ram_constants.asm")
        h.write8("wCurrentMapScriptFlags",
                 h.read8("wCurrentMapScriptFlags") | (1 << flags["BIT_CUR_MAP_LOADED_1"]))
        h.tick(40)
        for row, column, _closed in GOLDENROD_EXIT_BLOCKS:
            self.assertEqual(self.overworld_block(h, row, column), GOLDENROD_OPEN_BLOCK)

        bst = (ROOT / "gfx/blocksets/gym.bst").read_bytes()
        blocks = bytearray((ROOT / "maps/GoldenrodGym.blk").read_bytes())
        for row, column, _closed in GOLDENROD_EXIT_BLOCKS:
            blocks[row * GOLDENROD_WIDTH + column] = GOLDENROD_OPEN_BLOCK
        sprites = {(8, 3), (17, 4), (13, 12), (9, 6), (5, 15)}

        def walkable(x: int, y: int) -> bool:
            if not (0 <= x < 20 and 0 <= y < 18) or (x, y) in sprites:
                return False
            block = blocks[(y // 2) * GOLDENROD_WIDTH + x // 2]
            return bst[block * 16 + (1 + 2 * (y % 2)) * 4 + 2 * (x % 2)] in GYM_PASSABLE

        start = (h.read8("wXCoord"), h.read8("wYCoord"))
        came_from = {start: None}
        queue = deque([start])
        while queue:
            cell = queue.popleft()
            for dx, dy in DIRECTIONS:
                step = (cell[0] + dx, cell[1] + dy)
                if step not in came_from and walkable(*step):
                    came_from[step] = cell
                    queue.append(step)
        self.assertIn((8, 0), came_from)
        path = [(8, 0)]
        while came_from[path[-1]] is not None:
            path.append(came_from[path[-1]])
        path.reverse()

        for cell, step in zip(path, path[1:]):
            h.tap(DIRECTIONS[(step[0] - cell[0], step[1] - cell[1])], 4)
            h.tick(24)
            self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), step, f"blocked stepping {cell}->{step}")

        h.pyboy.button_press("up")
        h.tick(60)
        h.pyboy.button_release("up")
        h.tick(120)
        self.assertEqual(h.read8("hCurMap"), MAPS["INDIGO_PLATEAU_LOBBY"])
        self.assertFalse(h.hook_errors)


if __name__ == "__main__":
    unittest.main()
