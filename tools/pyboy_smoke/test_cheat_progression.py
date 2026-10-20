"""Active expansion overrides must neither grant nor erase story progress."""

import io

from source_constants import parse_rgbds_constants
from test_smoke import HarnessTestCase, REPO_ROOT


class CheatProgressionTest(HarnessTestCase):
    def test_cycle_preserves_story_and_saves_active_selection(self):
        h = self.harness
        h.boot_fight2(seed=1)
        baseline = io.BytesIO()
        h.save_state(baseline)
        events = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")
        event_offset = events["EVENT_RIVAL_CHAMPION_DEFEATED"] // 8
        # Before Johto, after Johto, after Warp, and after the final boss.
        # Keep lower story bits distinct to catch whole-byte overwrites too.
        for story in (0x01, 0x21, 0x63, 0xFF):
            for right in (True, False):
                with self.subTest(story=story, right=right):
                    h.load_state(baseline)
                    h.park_before_hijack()
                    h.write8("wEventFlags", story, offset=event_offset)
                    h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [1], bank=1)
                    index = 0
                    for _ in range(4):
                        h.write8("hJoy5", 0x10 if right else 0x20)
                        h.write8("hCurrentMenuItem", 7)
                        h.call_routine("OptCycleCheat")
                        index = (index + (1 if right else -1)) % 4
                        self.assertEqual(h.read_sram_bytes(
                            "sRogueSpeciesGroupsEnabled", 1), [0x81 | (index << 1)])
                        self.assertEqual(h.read8("wEventFlags", offset=event_offset),
                                         story)
                        self.assertEqual(h.read8("hCurrentMenuItem"), 7)
                        h.call_routine("RogueGetActiveGroupMaskFar")
                        self.assertEqual(h.last_call_registers["E"], 1 | (index << 1))
                        # Exercise the real save written by OptCycleCheat.
                        h.write8("wEventFlags", 0, offset=event_offset)
                        h.call_routine("LoadMainData")
                        self.assertEqual(h.read8("wEventFlags", offset=event_offset),
                                         story)

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
                                 [0x81 | (((index + 1) % 4) << 1)])
                self.assertTrue(h.event_is_set(events["EVENT_JOHTO_ACTIVATED"]))
                self.assertTrue(h.event_is_set(events["EVENT_KANTO_TIMEWARP_ACTIVATED"]))

    def test_legacy_ff_and_ordinary_toggles_still_require_story_unlocks(self):
        h = self.harness
        h.boot_fight2(seed=1)
        events = parse_rgbds_constants(REPO_ROOT / "constants/event_constants.asm")
        offset = events["EVENT_RIVAL_CHAMPION_DEFEATED"] // 8
        baseline = io.BytesIO()
        h.save_state(baseline)
        for story, enabled, expected in (
            (0, 0xff, 1), (0, 7, 1), (0x20, 0xff, 3),
            (0x60, 0xff, 7), (0x60, 1, 1),
            (0, 0x83, 3), (0, 0x85, 5), (0, 0x87, 7),
        ):
            with self.subTest(story=story, enabled=enabled):
                h.load_state(baseline)
                h.write8("wEventFlags", story, offset=offset)
                h.write_sram_bytes("sRogueSpeciesGroupsEnabled", [enabled])
                h.call_routine("RogueGetActiveGroupMaskFar")
                self.assertEqual(h.last_call_registers["E"], expected)
                self.assertEqual(h.read8("wEventFlags", offset=offset), story)
