"""Live map-reload checks for seasonal graphics and shared ground retention."""
from pathlib import Path
import io
import unittest
from harness import RedRogueHarness
from source_constants import parse_map_constants

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / 'tools/pyboy_smoke/artifacts'
TREE_TILES = (4,5,6,7,35,21,22,23,36,37,38,39,53,54)


def expected_tiles(season):
    base = bytearray((ROOT / 'gfx/tilesets/forest.2bpp').read_bytes())
    if season in (0,3):
        name = 'cherry' if season == 0 else 'winter'
        packed = (ROOT / f'gfx/tilesets/forest_{name}.2bpp').read_bytes()
        assert len(packed) == 224
        for i,tile in enumerate(TREE_TILES):
            base[tile*16:(tile+1)*16] = packed[i*16:(i+1)*16]
    return bytes(base)


class ForestSeasonReloadTest(unittest.TestCase):
    def test_reload_restores_each_season_and_invalid_save_fallback(self):
        h = RedRogueHarness(ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby()
            h.preload_and_enter_wild_area(parse_map_constants(ROOT/'constants/map_constants.asm')['PROCEDURAL_FOREST'], 'forest')
            h.park_before_hijack()
            baseline = io.BytesIO()
            h.save_state(baseline)
            for season in (0,3,1,2,255,4):
                with self.subTest(season=season):
                    # Independent trials: after an LCD-off call PyBoy may halt
                    # awaiting an interrupt that this fixture has disabled.
                    h.load_state(baseline)
                    h.pyboy.memory[0xff40] &= 0x7f
                    h.write_sram_bytes('sProcForestPalette',[season],bank=0)
                    # Simulate overwritten menu/battle tile data, then use the public reload.
                    h.pyboy.memory[0x9000:0x9600] = [0x5a]*0x600
                    h.call_routine('LoadTilesetTilePatternData',limit=120)
                    self.assertEqual(bytes(h.pyboy.memory[0x9000:0x9600]), expected_tiles(season))
        finally:
            h.close()

    def test_vanilla_forest_entry_does_not_inherit_winter_art(self):
        h = RedRogueHarness(ROOT, ARTIFACTS)
        try:
            h.boot_to_lobby()
            h.write_sram_bytes('sProcForestPalette',[3],bank=0)
            maps = parse_map_constants(ROOT/'constants/map_constants.asm')
            h.enter_stage_door1(maps['VIRIDIAN_FOREST'],description='Viridian Forest')
            h.park_before_hijack()
            h.pyboy.memory[0xff40] &= 0x7f
            actual = bytes(h.pyboy.memory[0x9000:0x9600])
            expected = expected_tiles(2)
            changed = [tile for tile in range(96) if actual[tile*16:tile*16+16] != expected[tile*16:tile*16+16]]
            # AnimateWaterTile scrolls $14 during ordinary play. Every other
            # tile, including all tree and ground slots, must remain original.
            self.assertTrue(set(changed) <= {0x14},f'changed tile IDs: {changed}')
        finally:
            h.close()
