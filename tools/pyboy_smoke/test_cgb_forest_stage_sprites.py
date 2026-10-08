"""Forest and facility finalization must publish sprites after their lazy
hideout selection, without a second InitMapSprites in normal play."""
from pathlib import Path
import unittest
from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]

class ForestStageSpritesTest(unittest.TestCase):
    def test_event_graphics_follow_resolved_hideout(self):
        for event, expected in [(1, [75, 76]), (2, [4, 0]), (3, [12, 0]),
                                (4, [41, 0]), (5, [77, 0])]:
            with self.subTest(event=event):
                h = RedRogueHarness(ROOT, ROOT / 'tmp/pforest-diagnosis', cgb_mode=True)
                try:
                    h.boot_to_lobby()
                    h.write8('wStageEvent', event)
                    h.write_sram_bytes('sStageEventHideoutX', [255, 255], bank=0)
                    h.write_sram_bytes('sStageEventHideoutFloor', [255], bank=0)
                    h.preload_and_enter_wild_area(0xf2, 'forest')
                    ids = [h.read8('wSprite06StateData1PictureID'),
                           h.read8('wSprite07StateData1PictureID')]
                    self.assertEqual(ids, expected)
                    self.assertNotEqual(h.read8('wSprite06StateData2ImageBaseOffset'), 0)
                    if expected[1]:
                        self.assertNotEqual(h.read8('wSprite07StateData2ImageBaseOffset'), 0)
                finally:
                    h.close()

    def _enter_counting_reloads(self, h, event):
        """Enter the forest with a stale NO_HIDEOUT (the ghost condition);
        return how many times finalize reloaded sprite tiles."""
        reloads = []
        h.write8('wStageEvent', event)
        h.write_sram_bytes('sStageEventHideoutX', [255, 255], bank=0)
        h.write_sram_bytes('sStageEventHideoutFloor', [255], bank=0)
        h.register_hook('PFRestageEventSprites.reloadStageSprites',
                        lambda _: reloads.append(1))
        return reloads

    def test_normal_entry_loads_sprites_once(self):
        # The preload's pending hideout must stage the pair before the map's
        # own InitMapSprites, so finalize has nothing to redo (no slowdown).
        h = RedRogueHarness(ROOT, ROOT / 'tmp/pforest-diagnosis', cgb_mode=True)
        try:
            h.boot_to_lobby()
            reloads = self._enter_counting_reloads(h, 1)
            h.preload_and_enter_wild_area(0xf2, 'forest')
            self.assertEqual(len(reloads), 0, 'finalize reloaded sprite tiles')
            self.assertEqual([h.read8('wSprite06StateData1PictureID'),
                              h.read8('wSprite07StateData1PictureID')], [75, 76])
            self.assertNotEqual(h.read8('wSprite06StateData2ImageBaseOffset'), 0)
            self.assertNotEqual(h.read8('wSprite07StateData2ImageBaseOffset'), 0)
            self.assertEqual(h.read8('wStageEvent'), 1)
        finally:
            h.close()

    def test_facility_normal_entry_loads_sprites_once(self):
        # Same ghost, same fix: the facility also picks its hideout at
        # finalize (PFacPickHideout). Measured 2026-10-08 before the fix:
        # wStageEvent armed, hideout (11,10), slots 10/11 = 0/0.
        h = RedRogueHarness(ROOT, ROOT / 'tmp/pforest-diagnosis', cgb_mode=True)
        try:
            h.boot_to_lobby()
            reloads = []
            h.write8('wStageEvent', 1)
            h.write_sram_bytes('sStageEventHideoutX', [255, 255], bank=0)
            h.write_sram_bytes('sStageEventHideoutFloor', [255], bank=0)
            h.register_hook('PFacRestageEventSprites.reloadStageSprites',
                            lambda _: reloads.append(1))
            facility = parse_map_constants(
                ROOT / 'constants/map_constants.asm')['PROCEDURAL_FACILITY']
            h.preload_and_enter_wild_area(facility, 'facility')
            self.assertEqual(len(reloads), 0, 'finalize reloaded sprite tiles')
            self.assertEqual([h.read8('wSprite10StateData1PictureID'),
                              h.read8('wSprite11StateData1PictureID')], [75, 76])
            self.assertNotEqual(h.read8('wSprite10StateData2ImageBaseOffset'), 0)
            self.assertNotEqual(h.read8('wSprite11StateData2ImageBaseOffset'), 0)
            self.assertEqual(h.read8('wStageEvent'), 1)
        finally:
            h.close()

    def test_ghost_from_old_preload_is_republished(self):
        # A save from a build whose preload staged nothing: the map loads with
        # empty slots 6/7 while the event is armed. Finalize must republish.
        h = RedRogueHarness(ROOT, ROOT / 'tmp/pforest-diagnosis', cgb_mode=True)
        try:
            h.boot_to_lobby()
            reloads = self._enter_counting_reloads(h, 1)
            def stale_sprites(_):
                if h.read8('hCurMap') == 0xf2:
                    h.write_sram_bytes('sStageEventSprite6', [0, 0], bank=0)
            h.register_hook('ProcBossPatchStageSprite', stale_sprites)
            h.preload_and_enter_wild_area(0xf2, 'forest')
            self.assertEqual(len(reloads), 1)
            self.assertEqual([h.read8('wSprite06StateData1PictureID'),
                              h.read8('wSprite07StateData1PictureID')], [75, 76])
            self.assertNotEqual(h.read8('wSprite06StateData2ImageBaseOffset'), 0)
            self.assertNotEqual(h.read8('wSprite07StateData2ImageBaseOffset'), 0)
            self.assertEqual(h.read8('wStageEvent'), 1)
        finally:
            h.close()

    def test_missing_hideout_disarms_arrival(self):
        h = RedRogueHarness(ROOT, ROOT / 'tmp/pforest-diagnosis', cgb_mode=True)
        try:
            h.boot_to_lobby()
            h.write8('wStageEvent', 1)
            def no_hideout(_):
                if h.read8('hCurMap') == 0xf2:
                    h.write_sram_bytes('sStageEventHideoutX', [255, 255], bank=0)
                    h.write_sram_bytes('sStageEventHideoutFloor', [255], bank=0)
            h.register_hook('StageEventStageSprites', no_hideout)
            h.preload_and_enter_wild_area(0xf2, 'forest')
            self.assertEqual(h.read8('wStageEvent'), 0)
            self.assertEqual(h.read8('wSprite06StateData1PictureID'), 0)
            self.assertEqual(h.read8('wSprite07StateData1PictureID'), 0)
        finally:
            h.close()
