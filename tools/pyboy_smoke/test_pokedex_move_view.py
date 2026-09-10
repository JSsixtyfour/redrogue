from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class PokedexMoveViewContractTest(unittest.TestCase):
    def test_area_is_replaced_by_banked_move_viewer(self) -> None:
        source = (REPO_ROOT / "engine" / "menus" / "pokedex.asm").read_text()

        self.assertIn('next "MOVE"', source)
        self.assertNotIn('next "AREA"', source)
        self.assertIn("farcall PokedexMoveViewer", source)
        self.assertNotIn("predef LoadTownMap_Nest ; display pokemon areas", source)

    def test_viewer_is_species_only_and_has_three_learnset_views(self) -> None:
        source = (REPO_ROOT / "engine" / "pokemon" / "status_view.asm").read_text()
        start = source.index("PokedexMoveViewer::")
        end = source.index("\n.HelpText:", start)
        viewer = source[start:end]

        self.assertIn("ld [wMonHIndex], a", viewer)
        self.assertIn("ld [wLoadedMonCatchRate], a", viewer)
        self.assertIn("ld [wFormContextSpecies], a", viewer)
        self.assertIn("ld [wFormContextForm], a", viewer)
        self.assertIn("ld [wMonHForm], a", viewer)
        self.assertIn("ld [wMonHFormSpecies], a", viewer)
        self.assertIn("MOVES_BOX_LEVELUP", viewer)
        self.assertIn("MOVES_BOX_TMHM", viewer)
        self.assertNotIn("MOVES_BOX_CURRENT", viewer)
        self.assertIn("MOVES_BOX_TUTOR", viewer)
        self.assertIn("call LoadHpBarAndStatusTilePatterns", viewer)
        self.assertIn("call StatusScreen2MoveCursor", viewer)
        self.assertIn("ldh [hTileAnimations], a", viewer)


if __name__ == "__main__":
    unittest.main()
