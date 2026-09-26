"""Testing/debug updates (2026-09-25).

1. Debug 2 BATTLES row: the value always wrapped correctly, but PrintNumber
   leaves leading-zero cells untouched, so 99 -> 1 drew "91" and counting down
   from 10 drew 19, 18 ... 11. Debug2DrawBattles now blanks its cell first.
2. Debug 2 SEED row: a nonzero seed reseeds the CMWC state when the screen
   closes, so the first lobby's rolls no longer depend on how long the player
   took to get there.
3. Lobby NPC appearance: the Witch, Psychic, salesman, trader and move tutor
   roll to appear in a normal run and always appear with BIT_DEBUG_MODE set.
4. Dorm PC: furniture and decoration lists show only owned pieces (plus the
   free default), and a choice still writes the real option number.
"""
import unittest

from source_constants import parse_rgbds_constants, parse_map_constants
from test_smoke import HarnessTestCase, REPO_ROOT

TOGGLE_CONSTANTS = REPO_ROOT / "constants" / "toggle_constants.asm"
BIT_DEBUG_MODE = 1
TILE_ZERO = 0xF6
TILE_SPACE = 0x7F


def glyphs(values: list[int]) -> str:
    out = []
    for b in values:
        if TILE_ZERO <= b <= TILE_ZERO + 9:
            out.append(chr(ord("0") + b - TILE_ZERO))
        elif b == TILE_SPACE:
            out.append(" ")
        else:
            out.append("?")
    return "".join(out)


class Debug2BattlesDisplayTest(HarnessTestCase):
    def open_debug2_screen(self) -> None:
        h = self.harness
        assert h is not None
        debug_menu = h.hook_flag("DebugMenu")
        drawn = h.hook_flag("OptDrawCursor")
        h.tick(240)
        h.pyboy.button_press("select")
        for _ in range(300):
            h.tap("start", 1)
            if debug_menu["count"]:
                break
        h.pyboy.button_release("select")
        h.tick(30)
        for button in ("down", "down", "down", "a"):
            h.tap(button)
        h.wait_until(lambda: drawn["count"] >= 1, "the Debug 2 config screen", 600)
        h.tick(10)

    def step(self, button: str) -> tuple[int, str]:
        h = self.harness
        assert h is not None
        h.tap(button, 6)
        h.tick(10)
        # BATTLES: screen row 1, value column 17, two cells
        return h.read8("wBattleCount"), glyphs(h.read_bytes("wTileMap", 2, offset=1 * 20 + 17))

    def test_one_digit_values_do_not_keep_the_old_tens_digit(self) -> None:
        h = self.harness
        assert h is not None
        self.open_debug2_screen()
        h.write8("wBattleCount", 98)
        self.assertEqual(self.step("right"), (99, "99"))
        self.assertEqual(self.step("right"), (1, " 1"), "99 wraps to 1 and must not read 91")
        h.write8("wBattleCount", 11)
        self.assertEqual(self.step("left"), (10, "10"))
        self.assertEqual(self.step("left"), (9, " 9"), "10 -> 9 must not read 19")
        self.assertEqual(self.step("left"), (8, " 8"))
        h.write8("wBattleCount", 2)
        self.assertEqual(self.step("left"), (1, " 1"))
        self.assertEqual(self.step("left"), (99, "99"), "1 wraps to 99")


class Debug2SeedTest(HarnessTestCase):
    LOBBY_FIELDS = (
        "wLobbyDoor1StageMap",
        "wStageEvent",
        "wWitchChallenge",
        "wWitchPrize",
        "wroguenpcsell",
        "wroguenpctradeget",
    )

    def lobby_after(self, seed: int, frames_on_screen: int) -> tuple[int, ...]:
        """Boot Debug 2 to the lobby with the SEED row set to `seed`, idling
        `frames_on_screen` frames on the config screen before leaving it.

        That idle is the timing that varies in real play. Idling BEFORE boot
        does not: measured, a 37-frame shift there left the whole lobby and
        the RNG table identical with no seed at all, so a new Debug 2 game
        reaches this screen from a fixed RNG state and only the time spent ON
        it (VBlank draws Random every frame) moves the stream.

        Mirrors RedRogueHarness.boot_to_lobby, which has no hook for an idle
        between writing the rows and pressing START."""
        h = self.harness
        assert h is not None
        debug_menu = h.hook_flag("DebugMenu")
        drawn = h.hook_flag("OptDrawCursor")
        lobby_exit_done = h.hook_flag("SelectAndPatchLobbyExit.noDebug2DoorForce")
        # Snapshot at a fixed code point: PCPsychicSetup is the last roll of
        # the lobby-entry block, after the doors, stage event, wild-area
        # preload, salesman, trader, clerks and witch. Reading at whatever frame
        # the polling loop below notices the lobby would add its own phase.
        snapshot: list[tuple[int, ...]] = []

        def capture(_context) -> None:
            if not snapshot:
                snapshot.append(
                    tuple(h.read8(label) for label in self.LOBBY_FIELDS)
                    + tuple(h.read_bytes("wRandomTable", 10))
                )

        h.register_hook("PCPsychicSetup", capture)
        h.tick(240)
        h.pyboy.button_press("select")
        for _ in range(300):
            h.tap("start", 1)
            if debug_menu["count"]:
                break
        h.pyboy.button_release("select")
        h.tick(30)
        for button in ("down", "down", "down", "a"):
            h.tap(button)
        h.wait_until(lambda: drawn["count"] >= 1, "the Debug 2 config screen", 600)
        h.write8("wBattleCount", 11)
        h.write8("wItemQuantity", seed)  # Debug2ConfigMenu zeroed it before drawing
        h.tick(frames_on_screen)
        h.tap("start", 6)

        def lobby_ready() -> bool:
            return (
                lobby_exit_done["count"] > 0
                and h.read8("wLobbyDoor1StageMap") != 0
                and h.read8("wSpritePlayerStateData1", 4) != 0
            )

        for _ in range(400):
            h.tap("a", 1)
            if lobby_ready():
                break
        self.assertTrue(lobby_ready(), "lobby entry did not complete")
        # lobby_ready trips at the door roll; the NPC setups run after it.
        h.wait_until(lambda: bool(snapshot), "PCPsychicSetup", 600)
        if seed:
            self.assertFalse(
                h.read8("wDebug2ForcedDoor2") & 0x80, "the seed-pending flag was not consumed"
            )
        return snapshot[0]

    def fresh(self) -> None:
        if self.harness is not None:
            self.harness.close()
        self.setUp()

    def test_a_seed_makes_the_first_lobby_independent_of_screen_time(self) -> None:
        early = self.lobby_after(seed=7, frames_on_screen=0)
        self.fresh()
        late = self.lobby_after(seed=7, frames_on_screen=37)
        self.assertEqual(early, late, "seed 7 should give the same lobby however long the screen was up")

    def test_without_a_seed_screen_time_changes_the_lobby(self) -> None:
        # Control: proves the idle above is big enough to matter.
        early = self.lobby_after(seed=0, frames_on_screen=0)
        self.fresh()
        late = self.lobby_after(seed=0, frames_on_screen=37)
        self.assertNotEqual(early, late)

    def test_different_seeds_give_different_streams(self) -> None:
        first = self.lobby_after(seed=7, frames_on_screen=0)
        self.fresh()
        second = self.lobby_after(seed=8, frames_on_screen=0)
        self.assertNotEqual(first, second)


class SeedRngTest(HarnessTestCase):
    def table_for(self, seed: list[int]) -> list[int]:
        h = self.harness
        assert h is not None
        h.seed_rng(seed)
        return h.read_bytes("wRandomTable", 10)

    def test_every_seed_element_reaches_the_table(self) -> None:
        # Random reads only wRandomTable, so a seed element that does not
        # change the table does not change the stream. Element 0 used to sit
        # in LCG bits 24-31, which the old `>> 16` output never saw.
        base = [0x11, 0x22, 0x33, 0x44]
        base_table = self.table_for(base)
        for position in range(4):
            varied = list(base)
            varied[position] ^= 0x01
            with self.subTest(position=position):
                self.assertNotEqual(self.table_for(varied), base_table)

    def test_same_seed_same_table(self) -> None:
        self.assertEqual(self.table_for([5, 6, 7, 8]), self.table_for([5, 6, 7, 8]))


class LobbyNpcRollTest(HarnessTestCase):
    EXTRAS = ("TOGGLE_PC_POKESALESMAN", "TOGGLE_PC_TRADENERD", "TOGGLE_PC_MOVETUTOR")

    def setUp(self) -> None:
        super().setUp()
        self.toggles = parse_rgbds_constants(TOGGLE_CONSTANTS)

    def is_hidden(self, name: str) -> bool:
        h = self.harness
        assert h is not None
        index = self.toggles[name]
        return bool(h.read8("wToggleableObjectFlags", offset=index // 8) & (1 << (index % 8)))

    def set_hidden(self, name: str, hidden: bool) -> None:
        h = self.harness
        assert h is not None
        index = self.toggles[name]
        byte = h.read8("wToggleableObjectFlags", offset=index // 8)
        bit = 1 << (index % 8)
        h.write8("wToggleableObjectFlags", (byte | bit) if hidden else (byte & ~bit & 0xFF), offset=index // 8)

    def set_debug_mode(self, on: bool) -> None:
        h = self.harness
        assert h is not None
        flags = h.read8("wStatusFlags6")
        bit = 1 << BIT_DEBUG_MODE
        h.write8("wStatusFlags6", (flags | bit) if on else (flags & ~bit & 0xFF))

    def test_debug_mode_always_shows_the_extras(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)
        self.set_debug_mode(True)
        for seed in range(4):  # within call_routine's ~10-per-boot budget
            for name in self.EXTRAS:
                self.set_hidden(name, True)
            h.seed_rng([seed, 3, 5, 9])
            h.park_before_hijack()
            h.call_routine("PCPsychicSetup")
            for name in self.EXTRAS:
                self.assertFalse(self.is_hidden(name), f"{name} hidden in debug mode (seed {seed})")

    def test_normal_run_rolls_the_extras(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_fight2(seed=1)  # FIGHT 2 never sets BIT_DEBUG_MODE; clear it anyway
        self.set_debug_mode(False)
        shown = hidden = 0
        # Varies seed_rng's FIRST element on purpose: before the 2026-09-25
        # harness fix that element never reached the table, and this test
        # found it (all six "seeds" rolled the same $9f/$a2/$d1).
        for seed in range(6):
            for name in self.EXTRAS:
                self.set_hidden(name, False)
            h.seed_rng([seed, 11, 17, 23])
            h.park_before_hijack()
            h.call_routine("PCPsychicSetup")
            for name in self.EXTRAS:
                if self.is_hidden(name):
                    hidden += 1
                else:
                    shown += 1
        # 18 rolls at 85/256: a normal run must both show and hide.
        self.assertGreater(shown, 0)
        self.assertGreater(hidden, 0)
        self.assertGreater(hidden, shown, "at ~1/3 odds most rolls should hide")


class RoomPcOwnershipFilterTest(HarnessTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.maps = parse_map_constants(REPO_ROOT / "constants" / "map_constants.asm")

    def press(self, button: str, settle: int = 8) -> None:
        assert self.harness is not None
        self.harness.tap(button, 4)
        self.harness.tick(settle)

    def walk_to_pc_and_open(self) -> None:
        # Same walk as test_room_decor_new_pieces.
        h = self.harness
        assert h is not None
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (1, 7), "spawn moved; re-plan the walk")

        def step(direction: str) -> None:
            h.pyboy.button_press(direction)
            h.tick(3)
            h.pyboy.button_release(direction)
            h.tick(30)

        for _ in range(10):
            if h.read8("wYCoord") <= 2:
                break
            step("up")
        step("left")
        self.assertEqual((h.read8("wXCoord"), h.read8("wYCoord")), (0, 2), "did not reach the PC's front")
        step("up")
        self.press("a", 60)
        for _ in range(40):
            if h.read8("wMaxMenuItem") >= 3 and h.read8("wTopMenuItemY") == 2:
                break
            self.press("a", 20)

    def test_decoration_list_shows_only_owned_dolls(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_debug1(self.maps["SILPH_CO_DORM"])
        # Debug 1 owns everything; keep only OMANYTE (decoration 3, piece 16)
        # and WIGGLYTUFF (decoration 45, piece 60).
        h.write_sram_bytes("sRoomOwned", [0, 0, 1 << (16 - 16), 0])
        h.write_sram_bytes("sRoomOwnedExt", [0, 0, 0, 1 << (60 - 56)])
        h.write_sram_bytes("sRoomDecorSlots", [0] * 8)
        picker = h.hook_flag("RoomPickDecorationForSlot")
        self.walk_to_pc_and_open()
        self.press("down")
        self.press("down")
        self.press("a", 30)      # DECORATIONS
        for _ in range(4):
            self.press("down")
        self.press("a", 30)      # BEDSIDE (slot 0)
        self.assertEqual(picker["count"], 1, "the decoration picker did not open")
        self.assertEqual(h.read8("wMaxMenuItem"), 2, "NONE + the two owned dolls")
        self.assertEqual(h.read8("wBuffer", 15), 3)
        self.press("down")
        self.press("down")
        self.assertEqual(h.read8("hCurrentMenuItem"), 2)
        self.press("a", 30)
        self.assertEqual(h.read_sram_bytes("sRoomDecorSlots", 1), [45], "the real id, WIGGLYTUFF, is stored")

    def test_top_list_with_nothing_owned_offers_only_the_wall(self) -> None:
        h = self.harness
        assert h is not None
        h.boot_debug1(self.maps["SILPH_CO_DORM"])
        h.write_sram_bytes("sRoomOwned", [0, 0, 0, 0])
        h.write_sram_bytes("sRoomOwnedExt", [0, 0, 0, 0])
        self.walk_to_pc_and_open()
        self.press("down")
        self.press("a", 30)      # FURNITURE
        self.press("down")
        self.press("a", 30)      # TOP
        self.assertEqual(h.read8("wBuffer", 15), 1, "only WALL, the free default")
        self.assertEqual(h.read8("wMaxMenuItem"), 0)


if __name__ == "__main__":
    unittest.main()
