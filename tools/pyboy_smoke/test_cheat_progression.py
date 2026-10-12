"""Changing active expansion content must not erase permanent story history."""

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT


class CheatProgressionTest(HarnessTestCase):
    def test_cycle_preserves_story_and_saves_active_selection(self):
        h = self.harness
        h.boot_fight2(seed=1)
        events = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")
        event_offset = events["EVENT_RIVAL_CHAMPION_DEFEATED"] // 8
        # Before Johto, after Johto, after Warp, and after the final boss.
        # Keep lower story bits distinct to catch whole-byte overwrites too.
        for story in (0x01, 0x21, 0x63, 0xFF):
            for right in (True, False):
                with self.subTest(story=story, right=right):
                    h.park_before_hijack()
                    h.write8("wEventFlags", story, offset=event_offset)
                    h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [1], bank=1)
                    expected_story = story
                    index = 0
                    for _ in range(4):
                        h.write8("hJoy5", 0x10 if right else 0x20)
                        h.write8("hCurrentMenuItem", 7)
                        h.call_routine("OptCycleCheat")
                        index = (index + (1 if right else -1)) % 4
                        expected_story |= index << 5
                        self.assertEqual(h.read_sram_bytes(
                            "sRogueSpeciesGroupsEnabled", 1), [1 | (index << 1)])
                        self.assertEqual(h.read8("wEventFlags", offset=event_offset),
                                         expected_story)
                        self.assertEqual(h.read8("hCurrentMenuItem"), 7)
                        # Exercise the real save written by OptCycleCheat.
                        h.write8("wEventFlags", 0, offset=event_offset)
                        h.call_routine("LoadMainData")
                        self.assertEqual(h.read8("wEventFlags", offset=event_offset),
                                         expected_story)

    def test_pc_disabled_groups_drive_selector_and_pool(self):
        h = self.harness
        h.boot_fight2(seed=1)
        events = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")
        h.set_event(events["EVENT_JOHTO_ACTIVATED"])
        h.set_event(events["EVENT_KANTO_TIMEWARP_ACTIVATED"])
        for index in range(4):
            with self.subTest(index=index):
                h.park_before_hijack()
                h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [1 | index << 1])
                h.write8("hJoy5", 0x10)
                h.call_routine("OptCycleCheat")
                self.assertEqual(h.read_sram_bytes("sRogueSpeciesGroupsEnabled", 1),
                                 [1 | (((index + 1) % 4) << 1)])
                self.assertTrue(h.event_is_set(events["EVENT_JOHTO_ACTIVATED"]))
                self.assertTrue(h.event_is_set(events["EVENT_KANTO_TIMEWARP_ACTIVATED"]))
