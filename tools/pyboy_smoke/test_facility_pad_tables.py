"""Static guards for the Facility warp-pad tables (PROCEDURAL_SUBROOMS_PLAN Phase 2).

PFacPadSiteValid proves a pad cannot strand anything from the per-block
walkable-quadrant table, so a stale table is a softlock risk the build would
never notice. The site list is read by the ROM and by the audit from one
constants file; these checks keep the two readings and the warp budget in step.
"""

from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

from audit_facility_pad_sites import FIRST_PAD_WARP, PAD_SITES

ROOT = Path(__file__).resolve().parents[2]
MAX_WARP_EVENTS = 32


class FacilityPadTableTest(unittest.TestCase):
    def test_quad_mask_table_is_fresh(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/gen_facility_quad_masks.py"), "--check"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_spinner_rooms_are_proven_and_fresh(self) -> None:
        """Every .spin room passes tools/facility_spinners.py's proofs (slides
        end, the ball is reachable from the baseboard, no trap) and the generated
        asm/constants match the rooms (Phase 3)."""
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/facility_spinners.py"), "--check"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @staticmethod
    def _piece(w, h, walk, arrows, ball):
        """A synthetic spinner piece straight in the tool's tile model (no art),
        so each test pins one proof rule."""
        sys.path.insert(0, str(ROOT / "tools"))
        import facility_spinners as spin
        piece = spin.Piece.__new__(spin.Piece)
        piece.name, piece.w, piece.h, piece.debug = "probe", w, h, False
        piece.walk, piece.arrows, piece.stoppers, piece.ball = set(walk), dict(arrows), set(), ball
        piece.masks = spin.quad_masks()
        piece.slides = {a: piece._slide(a) for a in piece.arrows}
        return spin, piece

    @staticmethod
    def _pocket_tiles(sealed: bool):
        # 3x3 blocks = 6x6 tiles: a walkable outer ring, solid walls at x/y 1
        # and 4, and a 2x2 pocket (2..3, 2..3) entered only by a DOWN arrow at
        # (2, 1). Unsealed, (4, 3) is opened so the pocket has a way out.
        ring = {(x, y) for x in range(6) for y in range(6) if x in (0, 5) or y in (0, 5)}
        pocket = {(2, 2), (3, 2), (2, 3), (3, 3)}
        walk = ring | pocket | {(2, 1)}
        if not sealed:
            walk.add((4, 3))
        return walk

    def test_spinner_prover_rejects_a_trap(self) -> None:
        _spin, piece = self._piece(3, 3, self._pocket_tiles(sealed=True), {(2, 1): "down"}, (0, 0))
        self.assertIn("trap", piece.prove(3, 3) or "")

    def test_spinner_prover_passes_the_same_pocket_with_an_exit(self) -> None:
        # Control for the trap test: one opened tile and the proof holds, so
        # the trap verdict above is about the trap, not about the fixture.
        _spin, piece = self._piece(3, 3, self._pocket_tiles(sealed=False), {(2, 1): "down"}, (0, 0))
        self.assertIsNone(piece.prove(3, 3))

    def test_spinner_prover_rejects_an_arrow_into_a_wall(self) -> None:
        sys.path.insert(0, str(ROOT / "tools"))
        import facility_spinners as spin
        walk = self._pocket_tiles(sealed=False)
        with self.assertRaises(spin.RoomError) as caught:
            self._piece(3, 3, walk, {(2, 1): "left"}, (0, 0))  # (1, 1) is solid
        self.assertIn("into a wall", str(caught.exception))

    def test_site_list_parses_and_fits_the_warp_budget(self) -> None:
        self.assertEqual(len(PAD_SITES), 27, "audit parsed a different site count than expected")
        self.assertEqual(len(set(PAD_SITES)), len(PAD_SITES), "duplicate pad site")
        self.assertLessEqual(FIRST_PAD_WARP + len(PAD_SITES), MAX_WARP_EVENTS)
        for x, y in PAD_SITES:
            self.assertTrue(1 <= x <= 18 and 3 <= y <= 18, (x, y))


if __name__ == "__main__":
    unittest.main()
