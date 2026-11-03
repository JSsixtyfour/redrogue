"""Behavioral guards for sparse seasonal copies and baked opening discovery."""
from pathlib import Path
import io
import unittest
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants
from test_procedural_forest_seasons import expected_tiles

ROOT=Path(__file__).resolve().parents[2]

class SeasonalSingleWriteTest(unittest.TestCase):
    cgb_mode=False

    def test_full_region_single_writes_and_boundary_canaries(self):
        h=RedRogueHarness(ROOT,ROOT/'tools/pyboy_smoke/artifacts',cgb_mode=self.cgb_mode)
        try:
            h.boot_to_lobby()
            maps=parse_map_constants(ROOT/'constants/map_constants.asm')
            sets=parse_rgbds_constants(ROOT/'constants/tileset_constants.asm')
            baseline=io.BytesIO();h.save_state(baseline)
            writes=[]
            def observe(_):
                r=h.pyboy.register_file;dest=r.D*256+r.E
                if 0x8ff0<=dest<0x9800:writes.append(dest)
            h.register_hook('CopyData',observe)
            for name in ('PROCEDURAL_FOREST','PROCEDURAL_FOREST_GROTTO','VIRIDIAN_FOREST','SILPH_CO_DORM'):
                for season in (0,1,2,3,4,255):
                    with self.subTest(map=name,season=season):
                        h.load_state(baseline);h.pyboy.memory[0xff40]&=127
                        h.write8('hCurMap',maps[name])
                        dorm=name=='SILPH_CO_DORM'
                        h.write8('wCurMapTileset',sets['DORM' if dorm else 'FOREST'])
                        bank,addr=h.symbols.get('Dorm_GFX' if dorm else 'Forest_GFX')
                        h.write8('wTilesetBank',bank);h.write8('wTilesetGfxPtr',addr&255);h.write8('wTilesetGfxPtr',addr>>8,offset=1)
                        h.write_sram_bytes('sProcForestPalette',[season],bank=0)
                        h.pyboy.memory[0x8ff0:0x9800]=[0x5a]*0x810
                        writes.clear();h.call_routine('LoadTilesetTilePatternData')
                        n=0x790 if dorm else 0x600
                        expected=(ROOT/'gfx/tilesets/dorm.2bpp').read_bytes()[:n] if dorm else expected_tiles(season if name.startswith('PROCEDURAL') else 2)
                        self.assertEqual(bytes(h.pyboy.memory[0x9000:0x9000+n]),expected)
                        self.assertEqual(writes,list(range(0x9000,0x9000+n)))
                        self.assertEqual(list(h.pyboy.memory[0x8ff0:0x9000]),[0x5a]*16)
                        self.assertEqual(list(h.pyboy.memory[0x9000+n:0x9800]),[0x5a]*(0x800-n))
            self.assertFalse(h.hook_errors)
        finally:h.close()

class BakedOpeningDiscoveryTest(unittest.TestCase):
    def test_unique_marker_contract_including_resolved_and_invalid_rooms(self):
        h=RedRogueHarness(ROOT,ROOT/'tools/pyboy_smoke/artifacts')
        try:
            h.boot_to_lobby()
            def open_sram(_):
                h.pyboy.memory[0]=10;h.pyboy.memory[0x6000]=1;h.pyboy.memory[0x4000]=0
            h.register_hook('FGFindOpening',open_sram)
            def check(main,markers,floor=27,connector=27,baked=1,river=255):
                grid=[2]*400
                for wall,site in markers:
                    p=site if wall==0 else site*20+(0 if wall==1 else 19)
                    grid[p]=(88,86,87)[wall]
                    grid[p+(20 if wall==0 else 1 if wall==1 else -2)]=floor
                    if wall==2:grid[p-1]=connector
                h.write_sram_bytes('sProcForestStagingBuffer',grid,bank=0)
                for name,val in [('sProcForestBaked',baked),('sProcForestRiverSide',river),('sProcForestExitEdge',main)]:h.write_sram_bytes(name,[val],bank=0)
                # Discovery must not depend on the still-visible encounter.
                h.write8('wOptionalEncounterSpecies',0);h.write8('wOptionalEncounterState',7)
                h.call_routine('FGFindOpening')
                out=h.last_call_registers
                eligible=[(w,s) for w,s in markers if w!=main and floor in (1,27,41,32,34,35,36,37) and (w!=2 or connector==27)] if baked==1 and river==255 and main<3 else []
                self.assertEqual(bool(out['F']&16),len(eligible)==1,(main,markers,floor,connector))
                if len(eligible)==1:self.assertEqual((out['D'],out['E']),eligible[0])
            for main in range(3):
                for wall in range(3):
                    for site in range(1,18,2):check(main,[(wall,site)])
            for floor in (1,27,41,32,34,35,36,37,0,2,86,255):
                for wall in range(3):check((wall+1)%3,[(wall,9)],floor)
            check(2,[]);check(2,[(0,1),(1,17)]);check(2,[(0,1),(0,17)])
            check(0,[(2,17)],connector=2)
            check(2,[(0,1)],baked=0);check(2,[(0,1)],river=0)
            check(3,[(0,1)]);check(255,[(0,1)])
            self.assertFalse(h.hook_errors)
        finally:h.close()
