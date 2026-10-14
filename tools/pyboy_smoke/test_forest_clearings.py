"""Static guards for the Procedural Forest clearings (PROCEDURAL_SUBROOMS_PLAN Phase F).

PFPlaceClearing stamps pieces anywhere in the maze because tools/forest_clearings.py
proves each one keeps every maze path connected; these checks keep that proof
and the generated table honest. audit_forest_clearings.py (audits.json) checks
real generated forests.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import forest_clearings as fc  # noqa: E402


class ForestClearingTableTest(unittest.TestCase):
    def test_pieces_are_proven_and_the_table_is_fresh(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools/forest_clearings.py"), "--check"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_all_six_drop_pieces_are_wired_in(self) -> None:
        pieces, errors = fc.load()
        self.assertFalse(errors, errors)
        self.assertEqual(
            sorted(p.name for p in pieces),
            ["cut_trees", "double_tree", "hill", "medium_pond", "small_pond", "tree_pond"],
        )

    def test_prover_rejects_a_piece_with_no_way_through(self) -> None:
        # A 2x2 block of the maze's own wall: nothing on its edge is walkable,
        # so a path reaching it would dead-end and a subtree behind it would be
        # stranded. The prover must refuse it.
        blockset, walk = fc.BLOCKSET.read_bytes(), fc.walkable_tiles()
        with tempfile.TemporaryDirectory() as tmp:
            blk = Path(tmp) / "solid.blk"
            blk.write_bytes(bytes([0x00] * 4))
            spec = Path(tmp) / "solid.clear"
            spec.write_text(f"blk {blk}\nsize 2 2\n", encoding="utf-8")
            with self.assertRaises(fc.PieceError):
                fc.Piece(spec, blockset, walk)


if __name__ == "__main__":
    unittest.main()
