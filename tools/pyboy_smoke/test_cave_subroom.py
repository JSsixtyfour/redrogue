"""The cave subroom (PROCEDURAL_SUBROOMS_PLAN Phase 4, cave).

PROCEDURAL_CAVE_SUBROOM is a drawn room (a placeholder cut from Mt. Moon B1F's
two-ladder chamber) with two ladders up, one per cave ladder down. The cave
draws two ladders down on fixed sites (state in the staging
buffer's tail), arms only their warps, and the subroom's ladder N climbs back
onto ladder N. Ridden both ways for both ladders; a collected ball must stay
hidden when the player climbs back into the cave (the once-per-cave show gate).
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
MAP_W, MAP_H = 8, 4                     # blocks
LADDERS = ((13, 3), (5, 5))             # warp tiles, in warp order
_SITES = (ROOT / "constants/cave_ladder_site_constants.asm").read_text(encoding="utf-8")
SITES = [(int(x), int(y)) for x, y in re.findall(r"^\tladder_site\s+(\d+),\s*(\d+)", _SITES, re.M)]
FIRST_LADDER_WARP = int(re.search(r"CAVE_FIRST_LADDER_WARP EQU (\d+)", _SITES).group(1))
LADDER_BLOCK = int(re.search(r"CAVE_LADDER_BLOCK EQU (\d+)", _SITES).group(1))
TAIL = 81 + 19 * 26 + 20                # CAVESUB_TAIL: ladder A, ladder B, state
_RAM = parse_rgbds_constants(ROOT / "constants/ram_constants.asm",
                             parse_rgbds_constants(ROOT / "constants/round_constants.asm"))
STEP = _RAM["MONEY_MATCH_STEP"]
RAM_SUPER_NERD_AFTER_BATTLE = _RAM["SCRIPT_SUPER_NERD_AFTER_BATTLE"]


class CaveSubroomTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.blocks = (ROOT / "maps/ProceduralCaveSubroom.blk").read_bytes()
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

    def test_cave_ladders_lead_in_and_back(self) -> None:
        h = self.h
        cave = self.maps["PROCEDURAL_CAVE_1"]
        room = self.maps["PROCEDURAL_CAVE_SUBROOM"]
        toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(cave, "cave")
        h.write8("wProcCaveWildBudget", 0)
        tail = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 3, bank=0)[TAIL:]
        a, b = tail[0], tail[1]
        self.assertLess(a, len(SITES), "no ladder this cave")
        self.assertLess(b, len(SITES), "only one ladder this cave (rare: rerun or pick another seed)")
        self.assertTrue(tail[2] & 0x80, "the cave's objects were not marked shown")
        # The coin flip: exactly the rolled resident is shown.
        nerd = bool(tail[2] & 0x04)
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
        warps = h.warp_entries()
        for n, (x, y) in enumerate(SITES):
            entry = warps[FIRST_LADDER_WARP + n]
            if n in (a, b):
                self.assertEqual(entry, [2 * y + 1, 2 * x + 1, 0 if n == a else 1, room],
                                 f"ladder site {n} armed wrong")
            else:
                self.assertEqual(entry[0], 0xFF, f"site {n} not disarmed")
        # As if ball 1 had been collected: it must stay hidden on the way back.
        index = toggles["TOGGLE_WILD_AREA_POKEBALL_1"]
        byte = h.read8("wToggleableObjectFlags", offset=index // 8)
        h.write8("wToggleableObjectFlags", byte | 1 << index % 8, offset=index // 8)

        # Onto ladder A: arrive on it through the retargeted entrance warp.
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the cave entrance", 600)
        h.write8("wWarpEntries", FIRST_LADDER_WARP + a, offset=2)
        h.write8("wWarpEntries", cave, offset=3)
        self.press_until("down", lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == (2 * ax + 1, 2 * ay + 1),
                         "onto ladder A")
        for site, ladder, (sx, sy) in ((a, 0, (ax, ay)), (b, 1, (bx, by))):
            with self.subTest(ladder=ladder):
                lx, ly = LADDERS[ladder]
                tile = (2 * sx + 1, 2 * sy + 1)
                self.press_until("left", lambda: h.read8("wXCoord") == tile[0] - 1, "off the cave ladder")
                self.press_until("right", lambda: h.read8("hCurMap") == room, "down into the subroom")
                self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (lx, ly),
                                 "not on the matching subroom ladder")
                stride = MAP_W + 6
                live = h.read_bytes("wOverworldMap", (MAP_H + 6) * stride)
                for y in range(MAP_H):
                    self.assertEqual(live[(y + 3) * stride + 3:(y + 3) * stride + 3 + MAP_W],
                                     list(self.blocks[y * MAP_W:(y + 1) * MAP_W]), f"block row {y}")
                self.assertEqual(h.warp_entries()[ladder][2:], [FIRST_LADDER_WARP + site, cave])
                self.press_until("left", lambda: h.read8("wXCoord") == lx - 1, "off the subroom ladder")
                self.press_until("right", lambda: h.read8("hCurMap") == cave, "climb back up")
                self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), tile,
                                 "did not climb out onto the same ladder")
                byte = h.read8("wToggleableObjectFlags", offset=index // 8)
                self.assertTrue(byte & 1 << index % 8, "a collected ball came back")
                if ladder == 0:
                    # Over to ladder B: retarget ladder A's warp at it, as a pad pair would.
                    h.write8("wWarpEntries", FIRST_LADDER_WARP + b, offset=4 * (FIRST_LADDER_WARP + a) + 2)
                    h.write8("wWarpEntries", cave, offset=4 * (FIRST_LADDER_WARP + a) + 3)
                    self.press_until("left", lambda: h.read8("wXCoord") == tile[0] - 1, "off ladder A")
                    self.press_until("right", lambda: (h.read8("wXCoord"), h.read8("wYCoord"))
                                     == (2 * bx + 1, 2 * by + 1), "onto ladder B")
        self.assertEqual(h.read_bytes("wOverworldMap", 601), layout, "the trips changed the cave")



def from_bcd(values) -> int:
    return int("".join(f"{v:02x}" for v in values))


class CaveSubroomResidentTest(CaveSubroomTest):
    """The coin-flip resident: the Gambler or the Super Nerd, both ways."""

    test_cave_ladders_lead_in_and_back = None   # the parent's, not repeated
    RESIDENT_TILE = (9, 2)

    def enter_subroom_as(self, nerd: bool) -> None:
        h = self.h
        cave = self.maps["PROCEDURAL_CAVE_1"]
        room = self.maps["PROCEDURAL_CAVE_SUBROOM"]
        toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        h.preload_and_enter_wild_area(cave, "cave")
        h.write8("wProcCaveWildBudget", 0)
        raw = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 3, bank=0)
        a = raw[TAIL]
        self.assertLess(a, len(SITES), "no ladder this cave")
        # Force the coin flip both ways: the state bit and the two flags.
        raw[TAIL + 2] = (raw[TAIL + 2] & ~0x07) | (0x04 if nerd else 0)
        h.write_sram_bytes("sProcCaveStagingBuffer", raw, bank=0)
        for name, shown in (("TOGGLE_CAVESUB_GAMBLER", not nerd), ("TOGGLE_CAVESUB_SUPER_NERD", nerd)):
            index = toggles[name]
            byte = h.read8("wToggleableObjectFlags", offset=index // 8)
            byte = byte & ~(1 << index % 8) if shown else byte | 1 << index % 8
            h.write8("wToggleableObjectFlags", byte, offset=index // 8)
        ax, ay = SITES[a]
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the cave entrance", 600)
        h.write8("wWarpEntries", FIRST_LADDER_WARP + a, offset=2)
        h.write8("wWarpEntries", cave, offset=3)
        self.press_until("down", lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == (2 * ax + 1, 2 * ay + 1),
                         "onto ladder A")
        self.press_until("left", lambda: h.read8("wXCoord") == 2 * ax, "off the cave ladder")
        self.press_until("right", lambda: h.read8("hCurMap") == room, "down into the subroom")
        # From ladder 0 (13,3) along row 3 to the tile below the resident.
        rx, ry = self.RESIDENT_TILE
        self.press_until("left", lambda: h.read8("wXCoord") == rx, "to the resident")

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

    def fight_and_win(self, nerd: bool) -> None:
        h = self.h
        room = self.maps["PROCEDURAL_CAVE_SUBROOM"]
        self.talk_up()                          # NO once: B answers every prompt
        for _ in range(16):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("hIsInBattle"), 0, "declining started a battle")
        battle_count = h.read8("wBattleCount")
        money_before = from_bcd(h.read_bytes("wPlayerMoney", 3))
        seen = {"themed": 0, "step": [], "payout": []}

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
        self.assertEqual(h.read8("hCurMap"), room)
        self.assertEqual(seen["step"], [STEP], "party not rolled as route step 3")
        self.assertEqual(seen["themed"], 0, "Gambler's Paradise AI ran")
        self.assertEqual(len(seen["payout"]), 1)
        prize, state = seen["payout"][0]
        self.assertEqual(state & 0xC0, 0xC0 if nerd else 0x80, "armed as the wrong kind of fight")
        gained = from_bcd(h.read_bytes("wPlayerMoney", 3)) - money_before
        if nerd:
            self.assertEqual(gained, prize, "the Super Nerd's prize money was changed")
        else:
            self.assertNotEqual(gained, prize, "the Gambler's bet did not change the payout")
        self.assertEqual(h.read8("wBattleCount"), battle_count, "the resident advanced the run")
        flags = h.read_sram_bytes("sProcCaveStagingBuffer", TAIL + 3, bank=0)[TAIL + 2]
        self.assertTrue(flags & 1, "the win was not recorded in the cave's state")
        if nerd:
            self.assertTrue(flags & 2, "the prize was not handed over")
        self.talk_up()
        self.assertIn("earned" if nerd else "worth", self.screen_text(), "not the after line")
        for _ in range(6):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("hIsInBattle"), 0)

    def test_ball_gives_an_item(self) -> None:
        h = self.h
        toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        self.enter_subroom_as(nerd=True)
        # From below the resident (9,3) along row 3 to below the ball (2,3).
        self.press_until("left", lambda: h.read8("wXCoord") == 2, "below the ball")
        self.talk_up()
        self.assertIn("found", self.screen_text(), "no pickup message")
        for _ in range(8):
            h.tap("b", frames=8)
            h.tick(20)
        i = toggles["TOGGLE_CAVESUB_BALL"]
        self.assertTrue(h.read8("wToggleableObjectFlags", offset=i // 8) & 1 << i % 8,
                        "the ball was not hidden")

    def test_gambler(self) -> None:
        self.enter_subroom_as(nerd=False)
        self.fight_and_win(nerd=False)

    def test_super_nerd(self) -> None:
        self.enter_subroom_as(nerd=True)
        self.fight_and_win(nerd=True)



class CaveResidentFallbackTest(CaveSubroomTest):
    """No ladder fits: the rolled resident stands in the cave itself.

    About 1 cave in 300, so the test forces it: a block the ladder rule accepts
    (the audit's own model) is stored as the fallback spot, and the cave is
    reloaded through a real warp so the picture patch, the arming and the
    once-per-cave show all run as they do in play.
    """

    test_cave_ladders_lead_in_and_back = None

    def test_super_nerd_stands_in_the_cave_and_pays_out(self) -> None:
        import sys
        sys.path.insert(0, str(ROOT / "tools/pyboy_smoke"))
        import audit_cave_ladder_sites as model
        h = self.h
        cave = self.maps["PROCEDURAL_CAVE_1"]
        sprites = parse_rgbds_constants(ROOT / "constants/sprite_constants.asm")
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
        raw[TAIL + 2] = 0x04                       # the Super Nerd; not shown yet; not beaten
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
        self.assertEqual(h.read8("wSprite09StateData1"), sprites["SPRITE_SUPER_NERD"],
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
