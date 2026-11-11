"""The reward menu's trade must not draw the player in front of the menu box.

The menu box covers the player, so UpdatePlayerSprite hides them. Closing the
trade's party menu runs RestoreScreenTilesAndReloadTilePatterns, whose sprite
pass used to run while wTileMap still held the party menu. The tile under the
player there is an HP-bar tile ($6B), and a text-box limit of $79 on every map
(raised for the Dorm's extended tileset) counted it as map art. The player was
shown, and stayed drawn over the restored reward menu for about 10 visible
frames until the next PrintText's sprite pass. Measured 2026-11-10: 21 frames
with the player's image index set before the fix, 0 after.
"""
from pathlib import Path
import unittest

from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants

ROOT = Path(__file__).resolve().parents[2]
HIDDEN = 0xFF


class RewardTradeSpriteTest(unittest.TestCase):
    def test_player_stays_hidden_behind_reward_menu_after_party_menu(self):
        maps = parse_map_constants(ROOT / "constants/map_constants.asm")
        events = parse_rgbds_constants(ROOT / "constants/event_constants.asm")
        h = RedRogueHarness(ROOT, ROOT / "builds/reward_trade_sprite", cgb_mode=True)
        try:
            h.boot_to_lobby(battle_count=37)
            h.enter_stage_door1(maps["ROUTE_1"], description="Route 1")
            h.tick(60)
            # Offer a trade for the lead's own species so the party menu opens.
            h.write8("wroguenpctradegive", h.read8("wPartySpecies"))
            h.write8("wroguenpctradeget", 0x24)  # Pidgey
            h.write8("wroguenpctradeform", 0)
            h.write8("wroguenpctradedialogue", 0)
            h.write8("wRogueFlagsBitfield", h.read8("wRogueFlagsBitfield") | 4)  # BIT_ROGUE_TRADE_ACTIVE
            menu = h.hook_flag("RogueRewardMenu")
            party = h.hook_flag("DisplayPartyMenu")
            restored = h.hook_flag("InGameTrade_RestoreScreen")
            for i in range(4):
                h.set_event(events[f"EVENT_BEAT_ROUTE_1_TRAINER_{i}"])
            h.wait_until(lambda: menu["count"] > 0, "the reward menu", 600)

            # Cursor starts on the TRADE slot: A through the offer to the party menu.
            for _ in range(60):
                if party["count"]:
                    break
                h.tap("a", 2)
                h.tick(10)
            self.assertTrue(party["count"], "the trade never opened the party menu")
            h.tick(60)
            self.assertEqual(h.read8("wSpritePlayerStateData1ImageIndex"), HIDDEN,
                             "the menu box should already hide the player")

            h.tap("a", 2)  # pick the lead, which closes the party menu
            shown = []
            for frame in range(150):
                h.tick(1)
                if h.read8("wSpritePlayerStateData1ImageIndex") != HIDDEN:
                    shown.append(frame)
            self.assertTrue(restored["count"], "the party menu never closed")
            self.assertEqual(shown, [], "player drawn over the reward menu")
            self.assertFalse(h.hook_errors, h.hook_errors)
        finally:
            h.close()


if __name__ == "__main__":
    unittest.main()
