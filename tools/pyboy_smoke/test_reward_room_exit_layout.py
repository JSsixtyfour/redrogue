"""Conditional reward-room doors and restoration after a header/block reload."""
from test_smoke import HarnessTestCase, REPO_ROOT
from source_constants import parse_map_constants, parse_rgbds_constants

MAPS = parse_map_constants(REPO_ROOT / "constants/map_constants.asm")
LOAD_BIT = parse_rgbds_constants(REPO_ROOT / "constants/ram_constants.asm")["BIT_CUR_MAP_LOADED_2"]


class RewardRoomExitLayoutTest(HarnessTestCase):
    def enter_room(self, badges):
        h = self.harness
        h.boot_to_lobby(battle_count=1)
        h.write8("wObtainedBadges", badges)
        h.enter_stage_door1(MAPS["REWARD_ROOM"], description="conditional reward room")
        self.assertEqual(h.read8("hCurMap"), MAPS["REWARD_ROOM"])

    def north_blocks(self):
        h = self.harness
        start = 3 * (h.read8("wCurMapWidth") + 6) + 3
        return list(h.read_bytes("wOverworldMap", 3, offset=start + 1))

    def assert_clipboard_graphics(self):
        h = self.harness
        art = (REPO_ROOT / "gfx/sprites/clipboard.2bpp").read_bytes()
        for slot in (6, 7):
            self.assertEqual(h.read8(f"wSprite{slot:02}StateData2ImageBaseOffset"), 12)
        self.assertEqual(bytes(h.pyboy.memory[0x87C0:0x8800]), art)

    def check_reward_menu_close(self):
        h = self.harness
        self.assertTrue(h.read8("wFontLoaded") & 1)
        for _ in range(20):
            h.pyboy.button("b")
            h.tick(12)
            if not h.read8("wFontLoaded") & 1:
                break
        self.assertFalse(h.read8("wFontLoaded") & 1)
        h.tick(12)
        self.assert_clipboard_graphics()

    def assert_single_exit(self):
        h = self.harness
        self.assertEqual(self.north_blocks(), [0x5F, 0x73, 0x5F])
        self.assertEqual(len(h.warp_entries()), 3)
        self.assertEqual(h.warp_entries()[2][:2], [0, 5])
        self.assertEqual(h.read8("wSprite06StateData2MapX"), 4 + 4)
        self.assertEqual(h.read8("wSprite07StateData2MapY"), 0xFF)
        self.assertEqual(h.read8("wLobbyDoor1StageMap"), MAPS["INDIGO_PLATEAU_LOBBY"])

    def test_after_lab_retains_both_choices(self):
        self.enter_room(0)
        self.assert_clipboard_graphics()
        self.check_reward_menu_close()
        h = self.harness
        self.assertEqual(self.north_blocks(), [0x73, 0x5F, 0x73])
        self.assertEqual([w[:2] for w in h.warp_entries()[2:]], [[0, 3], [0, 7]])
        self.assertEqual(h.read8("wSprite06StateData2MapX"), 2 + 4)
        self.assertEqual(h.read8("wSprite07StateData2MapY"), 0 + 4)

    def test_between_gyms_has_one_exit(self):
        self.enter_room(1)
        self.assert_clipboard_graphics()
        self.check_reward_menu_close()
        self.assert_single_exit()

    def test_header_reload_restores_layout_without_recrediting_route(self):
        self.enter_room(1)
        h = self.harness
        h.park_before_hijack()
        before = h.read8("wBattleCount")
        # LoadMapData reloads these authored records from ROM on Continue.
        start = 3 * (h.read8("wCurMapWidth") + 6) + 3
        for index, block in enumerate([0x73, 0x5F, 0x73], 1):
            h.write8("wOverworldMap", block, offset=start + index)
        h.write8("wNumberOfWarps", 4)
        h.write8("wWarpEntries", 3, offset=9)
        h.write8("wSprite06StateData2MapX", 6)
        h.write8("wSprite07StateData2MapY", 4)
        h.write8("wCurrentMapScriptFlags", h.read8("wCurrentMapScriptFlags") | 1 << LOAD_BIT)
        h.call_routine("RewardRoom_UpdateExitLayout")
        self.assert_single_exit()
        self.assertEqual(h.read8("wBattleCount"), before)
        self.assertFalse(h.read8("wCurrentMapScriptFlags") & 1 << LOAD_BIT)
        h.call_routine("RewardRoom_UpdateExitLayout")
        self.assert_single_exit()
