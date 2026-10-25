"""The Facility subroom stamps its rolled room piece (PROCEDURAL_SUBROOMS_PLAN Phase 4).

PROCEDURAL_FACILITY_SUBROOM's .blk is black void. Each Facility rolls a piece
at generation (sProcFacilityGenScratch byte 6) and FacSubroomLoad stamps it at
every load, centred, puts the pad on the piece's landing spot, disarms the other
landing warps and stands the Super Nerd on the tile tools/facility_subroom.py
proved.

The way in is one of the Facility's pad sites (scratch byte 7), armed by
PFacArmPads at the piece's landing; the landing leads back onto that same pad.
This test rides it both ways with real engine warps, for the rolled piece and
then forced ones, and compares the live wOverworldMap with the tool's own
placement.
"""

from __future__ import annotations

import importlib.util
import io
import re
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
SCRATCH_PIECE = 6   # FACSUB_SCRATCH_PIECE
SCRATCH_PAD = 7     # FACSUB_SCRATCH_PAD = PFAC_SUBROOM_PAD
ENTRY_ATTEMPTS = 8
TOGGLES = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
FALLBACK_ATTEMPTS = 80   # about 1 Facility in 10 has no subroom pad
RAM = parse_rgbds_constants(
    ROOT / "constants/ram_constants.asm",
    parse_rgbds_constants(ROOT / "constants/round_constants.asm"))
RAM_STEP = RAM["MONEY_MATCH_STEP"]
_SITES = (ROOT / "constants/facility_pad_site_constants.asm").read_text(encoding="utf-8")
PAD_SITES = [(int(x), int(y)) for x, y in re.findall(r"^\tpad_site\s+(\d+),\s*(\d+)", _SITES, re.M)]
FIRST_PAD_WARP = int(re.search(r"FACILITY_FIRST_PAD_WARP EQU (\d+)", _SITES).group(1))

_spec = importlib.util.spec_from_file_location("facility_subroom", ROOT / "tools/facility_subroom.py")
subroom = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(subroom)


class FacilitySubroomTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        blockset = subroom.premades.BLOCKSET.read_bytes()
        self.pieces, self.landings, _ = subroom.solve_all(blockset)
        self.h = RedRogueHarness(ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.h.close()

    def piece_index(self) -> int:
        return self.h.read_sram_bytes("sProcFacilityGenScratch", SCRATCH_PIECE + 1)[SCRATCH_PIECE]

    def toggle_hidden(self, name: str) -> bool:
        index = TOGGLES[name]
        return bool(self.h.read8("wToggleableObjectFlags", offset=index // 8) & 1 << index % 8)

    def subroom_pad(self) -> int:
        return self.h.read_sram_bytes("sProcFacilityGenScratch", SCRATCH_PAD + 1)[SCRATCH_PAD]

    def enter_with_subroom_pad(self) -> int:
        """Enter a Facility whose layout got a subroom pad; return its site."""
        h = self.h
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        # As if an earlier Facility had shown the Super Nerd's fallback: this
        # one, with a subroom pad, must hide him again.
        index = TOGGLES["TOGGLE_FACILITY_SUPER_NERD"]
        byte = h.read8("wToggleableObjectFlags", offset=index // 8)
        h.write8("wToggleableObjectFlags", byte & ~(1 << index % 8), offset=index // 8)
        # ... and an earlier stage's subroom ball was picked up: it must come back.
        index = TOGGLES["TOGGLE_FACSUBROOM_BALL"]
        byte = h.read8("wToggleableObjectFlags", offset=index // 8)
        h.write8("wToggleableObjectFlags", byte | 1 << index % 8, offset=index // 8)
        lobby = io.BytesIO()
        h.save_state(lobby)
        for offset in range(ENTRY_ATTEMPTS):
            h.load_state(lobby)
            h.tick(offset * 7)  # a different RNG state at generation
            h.preload_and_enter_wild_area(self.maps["PROCEDURAL_FACILITY"], "facility")
            site = self.subroom_pad()
            if site < len(PAD_SITES):
                return site
        self.fail(f"no layout with a subroom pad in {ENTRY_ATTEMPTS} entries")

    def facility_pad_tile(self, site: int) -> tuple[int, int]:
        x, y = PAD_SITES[site]
        return 2 * x + 1, 2 * y + 1

    def force_piece(self, index: int) -> None:
        raw = self.h.read_sram_bytes("sProcFacilityGenScratch", SCRATCH_PIECE + 1)
        raw[SCRATCH_PIECE] = index
        self.h.write_sram_bytes("sProcFacilityGenScratch", raw)

    def press_until(self, button: str, done, description: str) -> None:
        h = self.h
        h.pyboy.button_press(button)
        try:
            h.wait_until(done, description, 600)
        finally:
            h.pyboy.button_release(button)
        h.tick(120)

    def check_room(self, piece: dict) -> None:
        h = self.h
        stride = subroom.MAP_W + 6
        live = h.read_bytes("wOverworldMap", (subroom.MAP_H + 6) * stride)
        expected = [row[:] for row in piece["grid"]]
        bx, by = self.landings[piece["landing"]]
        expected[by][bx] = subroom.PAD_BLOCK
        for y in range(subroom.MAP_H):
            row = live[(y + 3) * stride + 3:(y + 3) * stride + 3 + subroom.MAP_W]
            self.assertEqual(row, expected[y], f"{piece['file']}: block row {y}")
        armed = [i for i, warp in enumerate(h.warp_entries()[:len(self.landings)]) if warp[0] != 0xFF]
        self.assertEqual(armed, [piece["landing"]], f"{piece['file']}: armed landings")
        nx, ny = piece["nerd"]
        self.assertEqual(h.read8("wSprite01StateData2MapX"), nx + 4, f"{piece['file']}: nerd x")
        self.assertEqual(h.read8("wSprite01StateData2MapY"), ny + 4, f"{piece['file']}: nerd y")
        bx, by = piece["ball"]
        self.assertEqual(h.read8("wSprite02StateData2MapX"), bx + 4, f"{piece['file']}: ball x")
        self.assertEqual(h.read8("wSprite02StateData2MapY"), by + 4, f"{piece['file']}: ball y")
        self.assertFalse(self.toggle_hidden("TOGGLE_FACSUBROOM_BALL"), "the ball is not shown")
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), piece["pad"],
                         "the player did not arrive on the pad")

    def test_generated_files_are_current(self) -> None:
        # The ROM trusts the tables, so they must describe today's pieces.
        for path, text in ((subroom.OUT_ASM, subroom.generate_table(self.pieces)),
                           (subroom.OUT_CONST, subroom.generate_constants(self.landings))):
            self.assertEqual(path.read_text(encoding="utf-8"), text,
                             f"{path.name} is stale: rerun tools/facility_subroom.py")

    def leave_by_pad(self, piece: dict, facility: int) -> None:
        h = self.h
        px, py = piece["pad"]
        for button, back, (dx, dy) in (("up", "down", (0, -1)), ("down", "up", (0, 1)),
                                       ("left", "right", (-1, 0)), ("right", "left", (1, 0))):
            spot = (px + dx, py + dy)
            if spot in piece["walk"] and spot not in (piece["nerd"], piece["ball"]):
                break
        else:
            self.fail(f"{piece['file']}: no free tile beside the pad")
        self.press_until(button, lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == spot, "off the pad")
        self.press_until(back, lambda: h.read8("hCurMap") == facility, "back to the Facility")

    def test_pad_leads_to_the_room_and_back(self) -> None:
        h = self.h
        facility = self.maps["PROCEDURAL_FACILITY"]
        room = self.maps["PROCEDURAL_FACILITY_SUBROOM"]
        site = self.enter_with_subroom_pad()
        h.write8("wProcFacilityWildBudget", 0)  # no encounter mid-walk
        rolled = self.piece_index()
        self.assertLess(rolled, len(self.pieces), "generation rolled no valid piece")
        x, y = PAD_SITES[site]
        layout = h.read_bytes("wOverworldMap", 601)
        self.assertEqual(layout[81 + y * 26 + x], subroom.PAD_BLOCK, "the subroom pad is not drawn")
        pair = h.read_sram_bytes("sProcFacilityGenScratch", 2)
        self.assertNotIn(site, pair, "the subroom pad took a pad pair's site")
        px, py = self.facility_pad_tile(site)
        self.assertEqual(h.warp_entries()[FIRST_PAD_WARP + site],
                         [py, px, self.pieces[rolled]["landing"], room],
                         "the subroom pad is not armed at the piece's landing")
        index = TOGGLES["TOGGLE_FACILITY_SUPER_NERD"]
        self.assertTrue(h.read8("wToggleableObjectFlags", offset=index // 8) & 1 << index % 8,
                        "the Facility's fallback Super Nerd was left shown")
        battle_count = h.read8("wBattleCount")

        # Stand on the pad: arrive on it through the retargeted entrance warp.
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the entrance", 600)
        h.write8("wWarpEntries", 39, offset=0)  # re-arm: entry maps disarm their entrance on load
        h.write8("wWarpEntries", FIRST_PAD_WARP + site, offset=2)
        h.write8("wWarpEntries", facility, offset=3)
        self.press_until("down", lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == (px, py),
                         "onto the subroom pad")

        largest = max(range(len(self.pieces)),
                      key=lambda i: self.pieces[i]["w"] * self.pieces[i]["h"])
        smallest = min(range(len(self.pieces)),
                       key=lambda i: self.pieces[i]["w"] * self.pieces[i]["h"])
        for index in (rolled, largest, smallest):
            piece = self.pieces[index]
            with self.subTest(piece=piece["file"]):
                self.force_piece(index)
                # What PFacArmPads computes on the Facility's next load.
                h.write8("wWarpEntries", piece["landing"], offset=4 * (FIRST_PAD_WARP + site) + 2)
                # Off the pad (west is always walkable: PFacPadSiteValid) and on again.
                self.press_until("left", lambda: h.read8("wXCoord") == px - 1, "off the Facility pad")
                self.press_until("right", lambda: h.read8("hCurMap") == room, "into the subroom")
                self.check_room(piece)
                self.assertEqual(h.warp_entries()[piece["landing"]][2:],
                                 [FIRST_PAD_WARP + site, facility], "the way back is not that pad")
                self.leave_by_pad(piece, facility)
                self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (px, py),
                                 "did not come back onto the subroom pad")
        self.assertEqual(self.piece_index(), smallest, "a load rerolled the piece")
        self.assertEqual(h.read_bytes("wOverworldMap", 601), layout, "the trips changed the Facility")
        self.assertEqual(h.read8("wBattleCount"), battle_count)


def from_bcd(values) -> int:
    return int("".join(f"{v:02x}" for v in values))


class FacilitySuperNerdTest(FacilitySubroomTest):
    """Offer, decline, battle, prize and after line, through the real pad."""

    # Reuses the subroom test's helpers, not its tests (unittest skips a
    # non-callable name).
    test_generated_files_are_current = None
    test_pad_leads_to_the_room_and_back = None

    taken: set = set()

    def step(self, button: str, to: tuple[int, int]) -> None:
        h = self.h
        self.press_until(button, lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == to, f"step to {to}")

    def walk_to(self, piece: dict, goal: tuple[int, int]) -> None:
        """BFS over the tool's walk area, around the Super Nerd."""
        h = self.h
        start = (h.read8("wXCoord"), h.read8("wYCoord"))
        free = piece["walk"] - {piece["nerd"], piece["ball"]} - self.taken
        moves = (("up", 0, -1), ("down", 0, 1), ("left", -1, 0), ("right", 1, 0))
        came = {start: None}
        todo = [start]
        while todo and goal not in came:
            here = todo.pop(0)
            for button, dx, dy in moves:
                there = (here[0] + dx, here[1] + dy)
                if there in free and there not in came:
                    came[there] = (here, button)
                    todo.append(there)
        self.assertIn(goal, came, f"{piece['file']}: no path to {goal}")
        path = []
        at = goal
        while came[at]:
            here, button = came[at]
            path.append((button, at))
            at = here
        for button, to in reversed(path):
            self.step(button, to)

    def talk_up(self) -> None:
        h = self.h
        h.move_tile("up")               # only turns: he is in the way
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

    def enter_subroom(self) -> dict:
        """Ride a real Facility's subroom pad in; return the room piece."""
        h = self.h
        facility = self.maps["PROCEDURAL_FACILITY"]
        room = self.maps["PROCEDURAL_FACILITY_SUBROOM"]
        site = self.enter_with_subroom_pad()
        h.write8("wProcFacilityWildBudget", 0)
        piece = self.pieces[self.piece_index()]
        px, py = self.facility_pad_tile(site)
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the entrance", 600)
        h.write8("wWarpEntries", 39, offset=0)  # re-arm: entry maps disarm their entrance on load
        h.write8("wWarpEntries", FIRST_PAD_WARP + site, offset=2)
        h.write8("wWarpEntries", facility, offset=3)
        self.press_until("down", lambda: (h.read8("wXCoord"), h.read8("wYCoord")) == (px, py),
                         "onto the subroom pad")
        self.press_until("left", lambda: h.read8("wXCoord") == px - 1, "off the Facility pad")
        self.press_until("right", lambda: h.read8("hCurMap") == room, "into the subroom")
        return piece

    def test_ball_gives_an_item_and_stays_picked_up(self) -> None:
        h = self.h
        piece = self.enter_subroom()
        self.assertFalse(self.toggle_hidden("TOGGLE_FACSUBROOM_BALL"), "the ball was not put back")
        bx, by = piece["ball"]
        for button, (dx, dy) in (("down", (0, -1)), ("up", (0, 1)), ("right", (-1, 0)), ("left", (1, 0))):
            spot = (bx + dx, by + dy)        # stand here, face the ball with `button`
            if spot in piece["walk"] and spot != piece["nerd"]:
                break
        else:
            self.fail(f"{piece['file']}: nowhere to stand beside the ball")
        self.walk_to(piece, spot)
        h.move_tile(button)                  # only turns: the ball is in the way
        h.tick(10)
        h.tap("a", frames=8)
        h.tick(60)
        self.assertIn("found", self.screen_text(), "no pickup message")
        for _ in range(8):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertTrue(self.toggle_hidden("TOGGLE_FACSUBROOM_BALL"), "the ball was not hidden")
        self.assertNotEqual(h.read8("wRogueItem"), 0, "no item was rolled")

    def test_decline_then_win_then_prize_and_after_line(self) -> None:
        h = self.h
        room = self.maps["PROCEDURAL_FACILITY_SUBROOM"]
        piece = self.enter_subroom()
        # One Facility in five rolls the PokeManiac in his place (BIT_PFAC_MANIAC),
        # who fights at FINAL_ROUTE_STEP with his own lines; this is the Super
        # Nerd's test (test_cave_subroom covers the PokeManiac).
        flags = h.read_sram_bytes("sProcFacilityItemGot", 1)
        flags[0] &= ~0x08
        h.write_sram_bytes("sProcFacilityItemGot", flags)
        nx, ny = piece["nerd"]
        self.walk_to(piece, (nx, ny + 1))

        for _ in range(2):              # NO twice: B answers every prompt
            self.talk_up()
            for _ in range(16):
                h.tap("b", frames=8)
                h.tick(20)
            self.assertEqual(h.read8("hIsInBattle"), 0, "declining started a battle")
            self.assertEqual(h.read8("wMoneyMatchState"), 0)

        battle_count = h.read8("wBattleCount")
        money_before = from_bcd(h.read_bytes("wPlayerMoney", 3))
        seen = {"themed": 0, "step": [], "payout": []}

        def ko(_context) -> None:
            h.write8("wEnemyMonHP", 0)
            h.write8("wEnemyMonHP", 0, offset=1)

        def no_exp(_context) -> None:
            h.write8("wPartyGainExpFlags", 0)

        def step(_context) -> None:
            seen["step"].append(h.pyboy.register_file.A)

        def themed(_context) -> None:
            seen["themed"] += 1

        def payout(_context) -> None:
            seen["payout"].append((from_bcd(h.read_bytes("wAmountMoneyWon", 3)),
                                   h.read8("wMoneyMatchState")))

        hooks = (("MainInBattleLoop", ko), ("GainExperience", no_exp),
                 ("GetRandRoster.stepReady", step),
                 ("AIMoveChoiceModification5", themed), ("MoneyMatchApplyPayout", payout))
        for label, callback in hooks:
            h.register_hook(label, callback)
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
            for _ in range(20):         # the prize box
                h.tap("b", frames=8)
                h.tick(20)
            h.tick(120)
        finally:
            for label, callback in reversed(hooks):
                h.unregister_hook(label, callback)

        self.assertEqual(h.read8("hIsInBattle"), 0, f"battle never ended; payout={seen['payout']}")
        self.assertEqual(h.read8("hCurMap"), room)
        self.assertEqual(seen["step"], [RAM_STEP], "party not rolled as route step 3")
        self.assertEqual(seen["themed"], 0, "Gambler's Paradise AI ran")
        self.assertEqual(len(seen["payout"]), 1)
        prize, state = seen["payout"][0]
        self.assertEqual(state & 0xC0, 0xC0, "not armed as a no-payout fight")
        self.assertEqual(from_bcd(h.read_bytes("wPlayerMoney", 3)) - money_before, prize,
                         "the prize money was changed: he is no bet")
        self.assertEqual(h.read8("wMoneyMatchState"), 0, "state byte leaked past the battle")
        self.assertEqual(h.read8("wBattleCount"), battle_count, "the Super Nerd advanced the run")
        flags = h.read_sram_bytes("sProcFacilityItemGot", 1)[0]
        self.assertTrue(flags & 1, "the win was not recorded")
        self.assertTrue(flags & 2, "the prize was not handed over")

        # Talking again: his after line, no offer, no battle.
        self.talk_up()
        self.assertIn("earned", self.screen_text(), "not the after line")
        for _ in range(6):
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("hIsInBattle"), 0)
        self.assertEqual(h.read8("wMoneyMatchState"), 0)



class FacilitySuperNerdFallbackTest(FacilitySubroomTest):
    """No subroom pad: the Super Nerd stands in the Facility itself."""

    test_generated_files_are_current = None
    test_pad_leads_to_the_room_and_back = None

    def test_he_stands_in_the_facility_and_pays_out(self) -> None:
        h = self.h
        toggles = parse_rgbds_constants(ROOT / "constants/toggle_constants.asm")
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        lobby = io.BytesIO()
        h.save_state(lobby)
        for offset in range(FALLBACK_ATTEMPTS):
            h.load_state(lobby)
            h.tick(offset * 7)
            h.preload_and_enter_wild_area(self.maps["PROCEDURAL_FACILITY"], "facility")
            scratch = h.read_sram_bytes("sProcFacilityGenScratch", SCRATCH_PAD + 1)
            if scratch[SCRATCH_PAD] >= len(PAD_SITES):
                break
        else:
            self.fail(f"every one of {FALLBACK_ATTEMPTS} Facilities had a subroom pad")
        x_byte, y_byte = scratch[SCRATCH_PIECE], scratch[SCRATCH_PAD]
        self.assertEqual((x_byte & 0x80, y_byte & 0xC0), (0x80, 0x40),
                         f"no fallback spot stored: {x_byte:#x}/{y_byte:#x}")
        bx, by = x_byte & 0x7F, y_byte & 0x3F
        layout = h.read_bytes("wOverworldMap", 601)
        self.assertEqual(layout[81 + by * 26 + bx], 0x0E, "his block is not plain floor")
        self.assertEqual(h.read8("wSprite12StateData2MapX"), 2 * bx + 1 + 4)
        self.assertEqual(h.read8("wSprite12StateData2MapY"), 2 * by + 1 + 4)
        index = toggles["TOGGLE_FACILITY_SUPER_NERD"]
        hidden = h.read8("wToggleableObjectFlags", offset=index // 8) & 1 << index % 8
        self.assertFalse(hidden, "he was not shown")
        armed = [w for w in h.warp_entries()[FIRST_PAD_WARP:] if w[0] != 0xFF]
        self.assertNotIn(self.maps["PROCEDURAL_FACILITY_SUBROOM"], [w[3] for w in armed],
                         "a pad leads to the subroom anyway")

        # The Facility script settles his battle: as if one was just won.
        h.write8("wSafariZoneGateCurScript", RAM["SCRIPT_SUPER_NERD_AFTER_BATTLE"])
        h.write8("wCurOpponent", 0)
        h.tick(30)
        for _ in range(20):         # the prize box
            h.tap("b", frames=8)
            h.tick(20)
        self.assertEqual(h.read8("wSafariZoneGateCurScript"), 0, "the battle was not settled")
        flags = h.read_sram_bytes("sProcFacilityItemGot", 1)[0]
        self.assertTrue(flags & 1, "the win was not recorded")
        self.assertTrue(flags & 2, "the prize was not handed over")


if __name__ == "__main__":
    unittest.main()
