"""Facility warp pads carry the player both ways (PROCEDURAL_SUBROOMS_PLAN Phase 2).

PFacPlacePads stores the pair in sProcFacilityGenScratch bytes 0-1 and stamps
block $2F at both sites; PFacArmPads points each end's warp at the other.
tools/pyboy_smoke/audit_facility_pad_sites.py --runtime checks placement over a
corpus. This rides the pads in the real engine: the entrance warp is
retargeted at pad A's warp so the player arrives standing on it, steps off
and back on, and must come out on pad B; then the same from B back to A.
Stepping off is always possible: the placement rule keeps all 8 quadrants
around a pad walkable.
"""

from __future__ import annotations

import io
import unittest
from pathlib import Path

from harness import RedRogueHarness
from source_constants import parse_map_constants
from audit_facility_pad_sites import FIRST_PAD_WARP, PAD_BLOCK, PAD_NONE, PAD_SITES

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "tools/pyboy_smoke/artifacts"
ENTRY_ATTEMPTS = 8


class FacilityWarpPadTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        self.h = RedRogueHarness(ROOT, ARTIFACTS)

    def tearDown(self) -> None:
        self.h.close()

    def pad_tile(self, site: int) -> tuple[int, int]:
        x, y = PAD_SITES[site]
        return 2 * y + 1, 2 * x + 1  # (wYCoord, wXCoord)

    def enter_with_pads(self) -> tuple[int, int]:
        """Enter a Facility whose layout got a pad pair; return (a, b)."""
        h = self.h
        facility = self.maps["PROCEDURAL_FACILITY"]
        h.boot_to_lobby(battle_count=11, encounter_kind=4)
        h.write8("wStageEvent", 0)
        lobby = io.BytesIO()
        h.save_state(lobby)
        for offset in range(ENTRY_ATTEMPTS):
            h.load_state(lobby)
            h.tick(offset * 7)  # a different RNG state at generation
            h.preload_and_enter_wild_area(facility, "facility")
            a, b = h.read_sram_bytes("sProcFacilityGenScratch", 2)
            if a != PAD_NONE:
                return a, b
        self.fail(f"no layout with warp pads in {ENTRY_ATTEMPTS} entries")

    def ride(self, start: int, end: int) -> None:
        """Standing on pad `start`: step off west, step back on, land on `end`."""
        h = self.h
        facility = self.maps["PROCEDURAL_FACILITY"]
        y, x = self.pad_tile(start)
        h.move_tile("left")
        self.assertEqual((h.read8("wYCoord"), h.read8("wXCoord")), (y, x - 1),
                         f"could not step off pad {start}")
        h.pyboy.button_press("right")
        try:
            h.wait_until(
                lambda: (h.read8("wYCoord"), h.read8("wXCoord")) == self.pad_tile(end)
                and h.read8("hCurMap") == facility,
                f"pad {start} -> pad {end}",
                900,
            )
        finally:
            h.pyboy.button_release("right")
        h.tick(120)
        self.assertEqual((h.read8("wYCoord"), h.read8("wXCoord")), self.pad_tile(end),
                         "the player moved after landing (a re-warp or a slide)")

    def test_pads_carry_the_player_both_ways(self) -> None:
        h = self.h
        facility = self.maps["PROCEDURAL_FACILITY"]
        a, b = self.enter_with_pads()
        h.write8("wProcFacilityWildBudget", 0)  # no encounter mid-walk
        layout = h.read_bytes("wOverworldMap", 601)
        for site in (a, b):
            x, y = PAD_SITES[site]
            self.assertEqual(layout[81 + y * 26 + x], PAD_BLOCK, f"site {site} is not a pad")
        battle_count = h.read8("wBattleCount")

        # Arrive standing on pad A through the retargeted entrance warp.
        h.wait_until(lambda: h.read8("wYCoord") == 39, "back on the entrance", 600)
        h.write8("wWarpEntries", FIRST_PAD_WARP + a, offset=2)
        h.write8("wWarpEntries", facility, offset=3)
        h.pyboy.button_press("down")
        try:
            h.wait_until(lambda: (h.read8("wYCoord"), h.read8("wXCoord")) == self.pad_tile(a),
                         f"arrive on pad {a}", 900)
        finally:
            h.pyboy.button_release("down")
        h.tick(120)

        self.ride(a, b)
        self.ride(b, a)

        self.assertEqual(h.read_bytes("wOverworldMap", 601), layout, "a pad warp changed the map")
        self.assertEqual(h.read8("wBattleCount"), battle_count)
        self.assertEqual(h.read8("wWarpedFromWhichMap"), facility)


if __name__ == "__main__":
    unittest.main()
