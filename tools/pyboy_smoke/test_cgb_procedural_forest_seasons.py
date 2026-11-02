"""CGB season resolution, isolated tree palette, and scrolling table choice."""
from pathlib import Path
import io
import unittest
from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]


class ForestSeasonColorTest(unittest.TestCase):
    def test_first_entry_colors_visible_trees_before_any_text_refresh(self):
        for season in (0,3):
            with self.subTest(season=season):
                h = RedRogueHarness(ROOT, ROOT/'tools/pyboy_smoke/artifacts', cgb_mode=True)
                try:
                    h.boot_to_lobby()
                    h.write8('wStageEvent',0)
                    h.write8('wOptions2',h.read8('wOptions2') | 64)
                    def force(_):
                        if h.read8('hCurMap')==242:
                            h.write_sram_bytes('sProcForestPalette',[season],bank=0)
                    h.register_hook('LoadProcForestTreeTiles',force)
                    h.preload_and_enter_wild_area(242,'forest')
                    h.park_before_hijack()
                    map_base = 0x9c00 if h.pyboy.memory[0xff40]&8 else 0x9800
                    h.pyboy.memory[0xff4f] = 0
                    tiles = list(h.pyboy.memory[map_base:map_base+1024])
                    h.pyboy.memory[0xff4f] = 1
                    attributes = list(h.pyboy.memory[map_base:map_base+1024])
                    h.pyboy.memory[0xff4f] = 0
                    tree_tiles = {4,5,6,7,0x15,0x16,0x17,0x23,0x24,0x25,0x26,0x27,0x35,0x36,0x54,0x55,0x56,0x57}
                    sx,sy = h.pyboy.memory[0xff43]//8,h.pyboy.memory[0xff42]//8
                    trees = grass = 0
                    for y in range(18):
                        for x in range(20):
                            index = ((sy+y)%32)*32+(sx+x)%32
                            tile = tiles[index]
                            if tile in tree_tiles:
                                trees += 1
                                self.assertEqual(attributes[index]&7,2,(season,x,y,tile))
                            if tile==0x20:
                                grass += 1
                                self.assertEqual(attributes[index]&7,4,(season,x,y,tile))
                    self.assertGreater(trees,0)
                    self.assertGreater(grass,0)
                finally:
                    h.pyboy.memory[0xff4f] = 0
                    h.close()

    def test_palette_and_attribute_selection_preserve_grass_and_other_maps(self):
        h = RedRogueHarness(ROOT, ROOT/'tools/pyboy_smoke/artifacts', cgb_mode=True)
        try:
            h.boot_to_lobby()
            maps = parse_map_constants(ROOT/'constants/map_constants.asm')
            h.preload_and_enter_wild_area(maps['PROCEDURAL_FOREST'], 'forest')
            h.park_before_hijack()
            baseline = io.BytesIO()
            h.save_state(baseline)
            for season,base in ((0,3),(1,4),(2,0),(3,6),(255,0),(4,0)):
                with self.subTest(season=season):
                    h.load_state(baseline)
                    h.write_sram_bytes('sProcForestPalette',[season],bank=0)
                    h.call_routine('ResolveEnhancedBasePalSet')
                    self.assertEqual(h.read8('wEnhBasePalSet'),base)
                    h.write8('hAutoBGTransferEnabled',0)
                    h.write8('hUILayoutFlags',h.read8('hUILayoutFlags') & ~8)
                    h.write8('wMapViewVRAMPointer',0)
                    h.write8('wMapViewVRAMPointer',0x98,offset=1)
                    sample = (4,0x20,0x35,0x54,0x14,8)
                    for row in range(18):
                        for column,tile in enumerate(sample):
                            h.write8('wTileMap',tile,offset=row*20+column)
                    h.call_routine('MakeOverworldBGMapAttributes')
                    pointer = h.read8('hSPTemp')*256+h.read8('hSPTemp',offset=1)
                    label = 'PalSettings_SeasonalForest' if season in (0,3) else 'PalSettings_FOREST'
                    self.assertEqual(pointer,h.address(label))
                    self.assertEqual(h.pyboy.memory[0xff70]&7,1)
                    expected = [2,4,2,2,7,6] if season in (0,3) else [4,4,6,4,7,6]
                    h.pyboy.memory[0xff70] = 2
                    actual = list(h.pyboy.memory[0xd100:0xd106])
                    h.pyboy.memory[0xff70] = 1
                    self.assertEqual(actual,expected)
                    # Scroll path must pick the same table without palette spill.
                    h.write8('hUILayoutFlags',h.read8('hUILayoutFlags') | 8)
                    h.write8('wSpriteStateData1',1,offset=3) # scrolling south
                    h.call_routine('MakeOverworldBGMapAttributes')
                    self.assertEqual(h.read8('hSPTemp')*256+h.read8('hSPTemp',offset=1),h.address(label))
                    h.pyboy.memory[0xff70] = 2
                    actual = list(h.pyboy.memory[0xd300:0xd306])
                    h.pyboy.memory[0xff70] = 1
                    self.assertEqual(actual,expected)
                    h.write8('hUILayoutFlags',h.read8('hUILayoutFlags') & ~8)
        finally:
            h.pyboy.memory[0xff70] = 1
            h.close()

    def test_vanilla_forest_keeps_ordinary_palette_with_saved_winter(self):
        h = RedRogueHarness(ROOT, ROOT/'tools/pyboy_smoke/artifacts', cgb_mode=True)
        try:
            h.boot_to_lobby()
            h.write_sram_bytes('sProcForestPalette',[3],bank=0)
            maps = parse_map_constants(ROOT/'constants/map_constants.asm')
            h.enter_stage_door1(maps['VIRIDIAN_FOREST'],description='Viridian Forest')
            h.park_before_hijack()
            h.call_routine('ResolveEnhancedBasePalSet')
            self.assertEqual(h.read8('wEnhBasePalSet'),0)
            h.write8('hAutoBGTransferEnabled',0)
            h.write8('hUILayoutFlags',h.read8('hUILayoutFlags') & ~8)
            h.call_routine('MakeOverworldBGMapAttributes')
            self.assertEqual(h.read8('hSPTemp')*256+h.read8('hSPTemp',offset=1),h.address('PalSettings_FOREST'))
        finally:
            h.close()
