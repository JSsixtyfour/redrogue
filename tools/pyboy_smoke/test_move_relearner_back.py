"""Move Relearner: B on the move list goes back to the party, B there leaves, and
the forget-move box hides the player it covers (LearnMoveOverMap)."""

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"
RAM = parse_rgbds_constants(ROOT / "constants" / "ram_constants.asm")
MOVES = parse_rgbds_constants(ROOT / "constants" / "move_constants.asm")
MOVESLISTMENU = 2  # constants/list_constants.asm


def relearner_slot():
    names = [line.split()[1] for line in
             (ROOT / "data/maps/objects/IndigoPlateauLobby.asm").read_text().splitlines()
             if line.strip().startswith("const_export")]
    return names.index("PC_MOVERELEARNER") + 1


class MoveRelearnerTest(unittest.TestCase):
    def press(self, button, settle=30):
        self.h.tap(button, 4)
        self.h.tick(settle)

    def row(self, row, col, length):
        return self.h.read_bytes("wTileMap", length, row * 20 + col)

    def until(self, hook, buttons="a", limit=40):
        before = hook["count"]
        for _ in range(limit):
            if hook["count"] > before:
                return
            self.press(buttons)
        self.fail("menu was not reached")

    def test_back_out_and_forget_box(self):
        h = self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        for offset, value in enumerate((0x99, 0x99, 0x99)):
            h.write8("wPlayerMoney", value, offset=offset)
        h.write8("wPartyMon1Level", 100)
        for offset, name in enumerate(("TACKLE", "POUND", "SCRATCH", "CUT")):
            h.write8("wPartyMon1Moves", MOVES[name], offset=offset)
        slot = relearner_slot()
        # Stand the Relearner in front of the player.
        h.write8(f"wSprite{slot:02d}StateData2MapY", h.read8("wYCoord") + 4 - 1)
        h.write8(f"wSprite{slot:02d}StateData2MapX", h.read8("wXCoord") + 4)
        h.tick(20)
        party = h.hook_flag("DisplayPartyMenu")
        moves = h.hook_flag("PrepareRelearnableMoveList")
        bye = h.hook_flag("MoveRelearnerText1.exit")
        forget = h.hook_flag("TryingToLearn")
        self.press("up")
        self.until(party)
        h.tick(60)
        self.until(moves)
        h.tick(120)
        self.assertEqual(h.read8("wListMenuID"), MOVESLISTMENU)
        self.press("b", 60)
        self.until(party)                     # one stage back, not out of the shop
        self.assertEqual(bye["count"], 0)
        h.tick(90)
        self.until(moves)                     # and forward again
        h.tick(120)
        self.until(forget)                    # teach: all four slots are full
        for _ in range(30):
            if self.row(7, 4, 2) == [0x79, 0x7A] and self.row(8, 5, 1) == [0xED]:
                break
            self.press("a")
        self.assertEqual(self.row(8, 5, 1), [0xED], "the forget-move box did not open")
        h.tick(20, render=True)
        ARTIFACTS.mkdir(exist_ok=True)
        h.pyboy.screen.image.save(ARTIFACTS / "move_relearner_forget.png")
        self.assertEqual(h.read8("hUpdateSpritesEnabled"), 1, "vacuous: sprites are off here")
        self.assertEqual(h.read8("wSpritePlayerStateData1ImageIndex"), 0xFF,
                         "the player is drawn over the forget-move box")
        flag = 1 << RAM["BIT_LEARN_MOVE_HIDES_SPRITES"]
        self.assertTrue(h.read8("wStatusFlags7") & flag)
        for _ in range(60):                   # give up the move; the flag goes with it
            if not h.read8("wStatusFlags7") & flag:
                break
            self.press("b", 20)
            self.press("a", 20)
        self.assertFalse(h.read8("wStatusFlags7") & flag)

    def test_b_at_the_party_menu_leaves(self):
        h = self.h = RedRogueHarness(ROOT, ARTIFACTS)
        self.addCleanup(h.close)
        h.boot_to_lobby()
        for offset in range(3):
            h.write8("wPlayerMoney", 0x99, offset=offset)
        slot = relearner_slot()
        h.write8(f"wSprite{slot:02d}StateData2MapY", h.read8("wYCoord") + 4 - 1)
        h.write8(f"wSprite{slot:02d}StateData2MapX", h.read8("wXCoord") + 4)
        h.tick(20)
        party = h.hook_flag("DisplayPartyMenu")
        bye = h.hook_flag("MoveRelearnerText1.exit")
        self.press("up")
        self.until(party)
        h.tick(90)
        self.press("b", 60)
        self.assertEqual(bye["count"], 1)


if __name__ == "__main__":
    unittest.main()
