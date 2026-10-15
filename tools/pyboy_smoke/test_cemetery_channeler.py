"""The Cemetery's possessed Channeler (PROCEDURAL_SUBROOMS_PLAN Phase 4).

He stands on one random floor per Cemetery (object 4 of every floor map; his
flag shown on that floor only, his picture installed there only), offers a
fight, battles as a route trainer at MONEY_MATCH_STEP with no bet, heals the
party Mom's way after a win, and then says his after line.

The test generates Cemeteries until his floor is floor 1 (where the player
arrives), so the real roll, flags, picture and placement are what it checks;
then it walks to him and plays the whole exchange.
"""

from __future__ import annotations

import io
import re
import unittest
from collections import deque
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
ATTEMPTS = 40
W, H, STRIDE, BASE = 10, 9, 16, 51     # CEMAP_*
QUADRANT = (4, 6, 12, 14)              # bottom-left tile of TL, TR, BL, BR
CONST = parse_rgbds_constants(ROOT / "constants/cemetery_channeler_constants.asm")
RAM = parse_rgbds_constants(ROOT / "constants/ram_constants.asm",
                            parse_rgbds_constants(ROOT / "constants/round_constants.asm"))


def walkable_tiles() -> set[int]:
    text = (ROOT / "data/tilesets/collision_tile_ids.asm").read_text(encoding="utf-8")
    m = re.search(r"^Cemetery_Coll::\s*\n\s*coll_tiles\s+([^\n;]+)", text, re.M)
    return {int(t.strip().lstrip("$"), 16) for t in m.group(1).split(",")}


def from_bcd(values) -> int:
    return int("".join(f"{v:02x}" for v in values))


class CemeteryChannelerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        self.sprites = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
        self.h = RedRogueHarness(ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.h.close()

    def hidden(self, name: str) -> bool:
        i = self.toggles[name]
        return bool(self.h.read8("wToggleableObjectFlags", offset=i // 8) & 1 << i % 8)

    def press_until(self, button: str, done, description: str) -> None:
        h = self.h
        h.pyboy.button_press(button)
        try:
            h.wait_until(done, description, 600)
        finally:
            h.pyboy.button_release(button)
        h.tick(60)

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

    def walk_to(self, goal: tuple[int, int], blocked: set) -> None:
        h = self.h
        blockset = (ROOT / "gfx/blocksets/cemetery.bst").read_bytes()
        walk = walkable_tiles()
        origin = h.address("wOverworldMap") + BASE
        cells = set()
        for by in range(H):
            for bx in range(W):
                block = h.pyboy.memory[origin + by * STRIDE + bx]
                for q, i in enumerate(QUADRANT):
                    if blockset[block * 16 + i] in walk:
                        cells.add((2 * bx + q % 2, 2 * by + q // 2))
        cells -= blocked
        start = (h.read8("wXCoord"), h.read8("wYCoord"))
        came = {start: None}
        todo = deque([start])
        moves = (("up", 0, -1), ("down", 0, 1), ("left", -1, 0), ("right", 1, 0))
        while todo and goal not in came:
            here = todo.popleft()
            for button, dx, dy in moves:
                there = (here[0] + dx, here[1] + dy)
                if there in cells and there not in came:
                    came[there] = (here, button)
                    todo.append(there)
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

    def talk_up(self) -> None:
        h = self.h
        h.move_tile("up")
        h.tick(10)
        h.tap("a", frames=8)
        h.tick(30)

    def test_floor_one_channeler_fights_and_heals(self) -> None:
        h = self.h
        floor1 = self.maps["PROCEDURAL_CEMETERY_1"]
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        lobby = io.BytesIO()
        h.save_state(lobby)
        for offset in range(ATTEMPTS):
            h.load_state(lobby)
            h.tick(offset * 7)
            h.preload_and_enter_wild_area(floor1, "cemetery")
            got = h.read_sram_bytes("sProcCemeteryItemGot", 1, bank=0)[0]
            if got & CONST["CEM_CHANNELER_FLOOR_MASK"] == 0:
                break
        else:
            self.fail(f"his floor was never floor 1 in {ATTEMPTS} Cemeteries")
        self.assertFalse(got & 1 << CONST["BIT_CEM_CHANNELER_WON"], "a fresh Cemetery starts him beaten")
        for n in range(1, 5):
            self.assertEqual(self.hidden(f"TOGGLE_CEMETERY_{n}_CHANNELER"), n != 1,
                             f"floor {n}'s Channeler flag is wrong")
        self.assertEqual(h.read8("wSprite04StateData1"), self.sprites["SPRITE_CHANNELER"],
                         "no picture on his floor")
        cy, cx = h.sprite_positions(4)[3]                 # step coords (y, x)
        self.assertEqual((cx % 2, cy % 2), (0, 0), "not on a block's top-left step")
        ball = tuple(h.sprite_positions(1)[0])
        self.assertNotEqual((cy, cx), ball, "standing on the ball")

        # Walk to the step below him and talk; decline once.
        blocked = {(x, y) for y, x in h.sprite_positions(4)}
        self.walk_to((cx, cy + 1), blocked)
        self.talk_up()
        for _ in range(16):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("hIsInBattle"), 0, "declining started a battle")

        # Accept and win; his lead's HP is 1 so the heal shows.
        h.write8("wPartyMon1HP", 0)
        h.write8("wPartyMon1HP", 1, offset=1)
        battle_count = h.read8("wBattleCount")
        seen = {"step": [], "payout": [], "themed": 0}

        def ko(_c):
            h.write8("wEnemyMonHP", 0)
            h.write8("wEnemyMonHP", 0, offset=1)

        def no_exp(_c):
            h.write8("wPartyGainExpFlags", 0)

        def step(_c):
            seen["step"].append(h.pyboy.register_file.A)

        def payout(_c):
            seen["payout"].append(h.read8("wMoneyMatchState"))

        def themed(_c):
            seen["themed"] += 1

        hooks = (("MainInBattleLoop", ko), ("GainExperience", no_exp), ("GetRandRoster.stepReady", step),
                 ("MoneyMatchApplyPayout", payout), ("AIMoveChoiceModification5", themed))
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
            for _ in range(30):                           # the heal and its boxes
                h.tap("b", frames=8)
                h.tick(20)
            h.tick(180)
        finally:
            for label, cb in reversed(hooks):
                h.unregister_hook(label, cb)
        self.assertEqual(h.read8("hCurMap"), floor1)
        self.assertEqual(seen["step"], [RAM["MONEY_MATCH_STEP"]], "party not rolled as route step 3")
        self.assertEqual(seen["themed"], 0, "Gambler's Paradise AI ran")
        self.assertEqual([s & 0xC0 for s in seen["payout"]], [0xC0], "not a no-bet fight")
        self.assertEqual(h.read8("wBattleCount"), battle_count, "he advanced the run")
        got = h.read_sram_bytes("sProcCemeteryItemGot", 1, bank=0)[0]
        self.assertTrue(got & 1 << CONST["BIT_CEM_CHANNELER_WON"], "the win was not recorded")
        hp = (h.read8("wPartyMon1HP") << 8) | h.read8("wPartyMon1HP", offset=1)
        max_hp = (h.read8("wPartyMon1MaxHP") << 8) | h.read8("wPartyMon1MaxHP", offset=1)
        self.assertEqual(hp, max_hp, "he did not heal the party")
        self.assertFalse(self.hidden("TOGGLE_CEMETERY_1_CHANNELER"), "he left after the fight")

        # Talking again: his after line, no battle.
        self.talk_up()
        self.assertIn("peace", self.screen_text(), "not the after line")
        for _ in range(6):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("hIsInBattle"), 0)


if __name__ == "__main__":
    unittest.main()
