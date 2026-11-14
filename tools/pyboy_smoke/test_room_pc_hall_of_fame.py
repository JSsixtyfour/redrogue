"""The Dorm PC's RECORDS menu and Hall of Fame return must preserve graphics.

PKMNLeaguePC decompresses each record's front pic into vFrontPic (vChars2 tile
$00), over the overworld tileset. The generic PC follows it with ReloadMapData
(ReloadMainMenu, engine/menus/pc.asm); RoomPC once returned straight to its
menu, so after LOG OFF the room redrew from the pic's tiles. Reported after a
first Champion clear. RECORDS now exists even before the first clear.
"""

from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants
from test_eevee_form_gate import CHAR_TO_BYTE


ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = Path(__file__).resolve().parent / "artifacts"

TILESET_START = 0x9000          # vChars2 tile $00, also vFrontPic
TILESET_LEN = 0x60 * 16         # tiles $00-$5F; $60+ is the Dorm's glyph/box region
HOF_MON = 0x10
BULBASAUR = 0x99                # internal species id
ROOM_PC_HOF_ROW = 3


class RoomPCHallOfFameTest(unittest.TestCase):
    def setUp(self) -> None:
        self.harness = RedRogueHarness(ROOT, ARTIFACTS)
        self.maps = parse_map_constants(ROOT / "constants" / "map_constants.asm")

    def tearDown(self) -> None:
        self.harness.close()

    def tileset(self) -> bytes:
        mem = self.harness.pyboy.memory
        return bytes(mem[TILESET_START : TILESET_START + TILESET_LEN])

    def press(self, button: str, settle: int = 8) -> None:
        self.harness.tap(button, 4)
        self.harness.tick(settle)

    def step(self, direction: str) -> None:
        h = self.harness
        h.pyboy.button_press(direction)
        h.tick(3)
        h.pyboy.button_release(direction)
        h.tick(30)

    def test_hall_of_fame_row_restores_the_dorm_tileset(self) -> None:
        h = self.harness
        h.boot_debug1(self.maps["SILPH_CO_DORM"])
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (1, 7), "spawn moved; re-plan the walk")

        # One recorded team of one mon: the row exists and the viewer has a pic.
        record = [BULBASAUR, 50] + [0x50] * (HOF_MON - 2)
        h.write_sram_bytes("sHallOfFame", record + [0xFF] * HOF_MON, bank=0)
        h.write8("wNumHoFTeams", 0)  # RECORDS must exist before the first Champion clear
        h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [0x87], bank=1)  # JOHTO+WARP cheat

        for _ in range(10):
            if h.read8("wYCoord") <= 2:
                break
            self.step("up")
        self.step("left")
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (0, 2), "did not reach the PC's front")
        self.step("up")  # the desk blocks the step; this only turns to face it

        before = self.tileset()

        league = h.hook_flag("PKMNLeaguePC")
        show_mon = h.hook_flag("LeaguePCShowMon")
        self.press("a", 60)
        for _ in range(40):  # PC boot text, if any, then the RoomPC menu
            if h.read8("wMaxMenuItem") >= ROOM_PC_HOF_ROW + 1 and h.read8("wTopMenuItemY") == 2:
                break
            self.press("a", 20)
        for _ in range(ROOM_PC_HOF_ROW):
            self.press("down")
        self.press("a", 30)
        for row, label in ((2, "RUN TIMES"), (4, "FURTHEST RUNS"), (6, "SPECIAL FORMS"), (8, "CHALLENGES"), (10, "BACK")):
            self.assertEqual(h.read_bytes("wTileMap", len(label), row * 20 + 2),
                             [CHAR_TO_BYTE[c] for c in label])
        self.assertEqual(h.read8("wMaxMenuItem"), 4)
        self.assertEqual(league["count"], 0)
        self.press("a", 30)      # RECORDS -> RUN TIMES (empty before first record)
        h.tick(3, render=True)
        ARTIFACTS.mkdir(exist_ok=True)
        h.pyboy.screen.image.save(ARTIFACTS / "run_records_empty.png")
        self.assertEqual(h.read_bytes("wTileMap", 13, 5 * 20 + 2),
                         [0x8D, 0x8E, 0x7F, 0x93, 0x88, 0x8C, 0x84, 0x92, 0x7F, 0x98, 0x84, 0x93, 0xE8])
        self.press("b", 30)
        h.write8("wRunRecordCount", 5)
        for label, values in (("wRunRecordsFirst", [0, 12, 34, 0, 20, 0, 1, 2, 3]),
                              ("wRunRecordsLast", [10, 0, 0, 255, 59, 59])):
            start = h.address(label)
            h.pyboy.memory[start:start + len(values)] = values
        self.press("a", 30)
        h.tick(3, render=True)
        h.pyboy.screen.image.save(ARTIFACTS / "run_records_five.png")
        # The loaded standard font maps digits to $f6-$ff, colon $9c, dot $e8.
        digits = lambda text: [0xF6 + int(c) if c.isdigit() else {":": 0x9C, ".": 0xE8, " ": 0x7F}[c] for c in text]
        for row, value in zip((4, 6, 8, 10, 12), ("1. 000:12:34", "2. 000:20:00", "3. 001:02:03", "4. 010:00:00", "5. 255:59:59")):
            self.assertEqual(h.read_bytes("wTileMap", len(value), row * 20 + 2), digits(value))
        self.press("b", 30)

        # RECORDS -> FURTHEST RUNS: empty, then full plus the current run.
        text = lambda value: [CHAR_TO_BYTE[c] if not c.isdigit() else 0xF6 + int(c) for c in value]
        h.write8("wEndlessDepth", 0)
        h.write8("wBattleCount", 0)
        self.press("down")
        self.press("a", 30)
        self.assertEqual(h.read_bytes("wTileMap", 12, 6 * 20 + 2), text("NO RUNS YET."))
        self.assertEqual(h.read_bytes("wTileMap", 8, 11 * 20 + 2), [0x7F] * 8, "no THIS RUN between runs")
        self.press("b", 30)
        table = [255, 73, 2, 37, 0, 73, 0, 9, 0, 2]
        start = h.address("wFurthestRunsFirst")
        h.pyboy.memory[start:start + 8] = table[:8]
        start = h.address("wFurthestRunsLast")
        h.pyboy.memory[start:start + 2] = table[8:]
        h.write8("wEndlessDepth", 1)
        h.write8("wBattleCount", 12)
        self.press("down")       # every page returns to the top row
        self.press("a", 30)
        h.tick(3, render=True)
        h.pyboy.screen.image.save(ARTIFACTS / "furthest_runs_full.png")
        self.assertEqual(h.read_bytes("wTileMap", 17, 3 * 20 + 2), text("   CIRC RND  WINS"))
        for row, value in zip(range(4, 9), ("1.  256   9 18432", "2.    3   5   180", "3.    1   9    72",
                                            "4.    1   2     8", "5.    1   1     1")):
            self.assertEqual(h.read_bytes("wTileMap", len(value), row * 20 + 2), text(value), value)
        self.assertEqual(h.read_bytes("wTileMap", 8, 11 * 20 + 2), text("THIS RUN"))
        value = "   2   2    83"
        self.assertEqual(h.read_bytes("wTileMap", len(value), 12 * 20 + 5), text(value))
        self.press("b", 30)
        h.write8("wEndlessDepth", 0)
        h.write8("wBattleCount", 0)

        self.press("b", 30)      # leave RECORDS to redraw with a recorded team
        h.write8("wNumHoFTeams", 1)
        for _ in range(ROOM_PC_HOF_ROW):
            self.press("down")
        self.press("a", 30)
        self.assertEqual(h.read8("wMaxMenuItem"), 5)
        self.press("down")
        self.press("down")       # RECORDS -> HALL OF FAME
        self.press("a", 30)
        self.assertEqual(league["count"], 1, "HALL OF FAME did not open")
        for _ in range(20):  # "Accessed the HALL OF FAME" text, then the pic
            if show_mon["count"]:
                break
            self.press("a", 20)
        self.assertEqual(show_mon["count"], 1, "the viewer never showed a mon")
        h.tick(120, render=True)
        ARTIFACTS.mkdir(exist_ok=True)
        h.pyboy.screen.image.save(ARTIFACTS / "room_pc_hof_viewer.png")
        # Control: the pic really does overwrite the tileset, or this test proves nothing.
        self.assertNotEqual(self.tileset(), before, "the HoF pic did not touch vChars2; test is vacuous")

        # Leave the viewer (B is read from hJoyHeld) and then LOG OFF.
        h.pyboy.button_press("b")
        h.tick(20)
        h.pyboy.button_release("b")
        h.tick(90)
        self.press("b", 30)      # leave RECORDS
        self.press("b", 120)
        h.tick(60, render=True)
        h.pyboy.screen.image.save(ARTIFACTS / "room_pc_hof_after.png")

        after = self.tileset()
        bad = [t for t in range(0x60) if after[t * 16 : t * 16 + 16] != before[t * 16 : t * 16 + 16]]
        self.assertEqual(bad, [], "Dorm tileset tiles still differ after the HoF viewer: "
                         + " ".join(f"${t:02X}" for t in bad))


if __name__ == "__main__":
    unittest.main()
