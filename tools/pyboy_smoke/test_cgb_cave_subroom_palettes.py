"""Parent theme inheritance on both palette paths, including real ladder trips."""
import io
from pathlib import Path
import unittest
from harness import RedRogueHarness
from source_constants import parse_map_constants
import test_cave_subroom as cave

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / 'tools/pyboy_smoke/artifacts'


class CaveBasementPaletteTest(unittest.TestCase):
    def test_both_selectors_range_check_and_exclude_unrelated_caves(self):
        h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=True)
        try:
            h.boot_to_lobby()
            h.park_before_hijack()
            maps = parse_map_constants(ROOT/'constants/map_constants.asm')
            baseline = io.BytesIO()
            h.save_state(baseline)
            for name in ('PROCEDURAL_CAVE_1','PROCEDURAL_CAVE_SUBROOM','MT_MOON_1F'):
                for variant in (0,1,2,255):
                    with self.subTest(map=name, variant=variant):
                        h.load_state(baseline)
                        h.write8('hCurMap', maps[name])
                        h.write8('wCurMapTileset', 17) # CAVERN
                        h.write8('wMapPalOffset',0)
                        h.write_sram_bytes('sProcCavePalette',[variant],bank=0)
                        cold = variant == 1 and name != 'MT_MOON_1F'
                        h.call_routine('ResolveEnhancedBasePalSet')
                        self.assertEqual(h.read8('wEnhBasePalSet'), int(cold))
                        h.call_routine('GetOverworldPalette')
                        self.assertEqual(h.last_call_registers['A'],0x0f if cold else 0x23)
                        self.assertEqual(h.read_sram_bytes('sProcCavePalette',1,bank=0),[variant])
        finally:
            h.close()


class ColdBasementLadderTest(cave.CaveSubroomTest):
    """Existing both-ladder round trips for all three templates, in CGB cold mode."""
    def setUp(self):
        self.maps = parse_map_constants(ROOT/'constants/map_constants.asm')
        self.sprites = cave.parse_rgbds_constants(ROOT/'constants/sprite_constants.asm')
        self.h = RedRogueHarness(ROOT, ARTIFACTS, cgb_mode=True)
        self.observed_maps = set()
        def force_parent(_):
            self.h.write_sram_bytes('sProcCavePalette',[1],bank=0)
        self.h.register_hook('PCFinalizeCave', force_parent)

    def press_until(self, button, done, description):
        super().press_until(button, done, description)
        h = self.h
        map_id = h.read8('hCurMap')
        if map_id in (self.maps['PROCEDURAL_CAVE_1'],self.maps['PROCEDURAL_CAVE_SUBROOM']):
            self.assertEqual(h.read8('wEnhBasePalSet'),1,description)
            self.observed_maps.add(map_id)

    def ride(self, index, water, land):
        super().ride(index, water, land)
        self.assertEqual(self.observed_maps,{self.maps['PROCEDURAL_CAVE_1'],self.maps['PROCEDURAL_CAVE_SUBROOM']})
