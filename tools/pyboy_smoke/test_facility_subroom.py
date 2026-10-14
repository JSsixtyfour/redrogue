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
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
SCRATCH_PIECE = 6   # FACSUB_SCRATCH_PIECE
SCRATCH_PAD = 7     # FACSUB_SCRATCH_PAD = PFAC_SUBROOM_PAD
PAD_NONE = 0xFF
ENTRY_ATTEMPTS = 8
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

    def subroom_pad(self) -> int:
        return self.h.read_sram_bytes("sProcFacilityGenScratch", SCRATCH_PAD + 1)[SCRATCH_PAD]

    def enter_with_subroom_pad(self) -> int:
        """Enter a Facility whose layout got a subroom pad; return its site."""
        h = self.h
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        lobby = io.BytesIO()
        h.save_state(lobby)
        for offset in range(ENTRY_ATTEMPTS):
            h.load_state(lobby)
            h.tick(offset * 7)  # a different RNG state at generation
            h.preload_and_enter_wild_area(self.maps["PROCEDURAL_FACILITY"], "facility")
            site = self.subroom_pad()
            if site != PAD_NONE:
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
        battle_count = h.read8("wBattleCount")

        # Stand on the pad: arrive on it through the retargeted entrance warp.
        h.wait_until(lambda: h.read8("wYCoord") == 39, "on the entrance", 600)
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

if __name__ == "__main__":
    unittest.main()
