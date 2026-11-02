"""Placement exclusions and the finite candidate bound, using current art/data."""
import io
import re
import unittest
from itertools import combinations
from harness import RedRogueHarness
from test_forest_grotto import ROOT, ARTIFACTS, fc
from test_forest_rest_house import house_sites

FLOORS=(1,27,41,0x20,0x22,0x23,0x24,0x25)


class ForestGrottoCapacityTest(unittest.TestCase):
    def test_floor_collision_and_elevation(self):
        bst=fc.BLOCKSET.read_bytes();walk=fc.walkable_tiles();pairs=fc.forest_tile_pairs()
        tiles={bst[block*16+i] for block in FLOORS for i in fc.QUADRANT_TILES}
        self.assertLessEqual(tiles,walk)
        for tile in tiles:
            self.assertNotIn(frozenset((tile,fc.MAZE_FLOOR_TILE)),pairs)

    def test_candidate_bound_and_house_parity(self):
        # Each maze carves all odd cells. Only one <=6x6 clearing can replace
        # their floors; the hideout rejects a 5x5 square, four balls one cell
        # each, and the main boss at most one cell on either other wall.
        descriptors=(ROOT/'data/maps/forest_clearing_pieces.asm').read_text()
        sizes=[tuple(map(int,m)) for m in re.findall(r'^\s*db (\d+), (\d+),',descriptors,re.M)]
        self.assertEqual(len(sizes),6)
        self.assertTrue(all(w<=6 and h<=6 for w,h in sizes))
        walls=({(i,1) for i in range(1,18,2)},
               {(1,i) for i in range(1,18,2)},
               {(17,i) for i in range(1,18,2)})
        for a,b in combinations(range(3),2):
            cells=walls[a]|walls[b]
            clearing=max(sum(x<=cx<x+w and y<=cy<y+h for cx,cy in cells)
                         for w,h in sizes for x in range(1,19-w,2) for y in range(1,19-h,2))
            hideout=max(sum(abs(x-cx)<=2 and abs(y-cy)<=2 for cx,cy in cells)
                        for x in range(1,19) for y in range(1,19))
            main=3-a-b
            bosses=[(2*i+1,1) if main==0 else (1 if main==1 else 18,2*i+1) for i in range(9)]
            boss=max(sum(abs(x-cx)<=1 and abs(y-cy)<=1 for cx,cy in cells) for x,y in bosses)
            self.assertGreaterEqual(len(cells)-clearing-hideout-4-boss,2)
        for x,y in house_sites():
            self.assertEqual(y%2,0)
            self.assertTrue(1<=x<=17 and 2<=y<=16)


class ForestGrottoSiteTest(unittest.TestCase):
    def test_live_site_exclusions_and_floor_variants(self):
        h=RedRogueHarness(ROOT,ARTIFACTS)
        try:
            h.boot_to_lobby();h.park_before_hijack()
            start=io.BytesIO();h.save_state(start)
            def open_sram(_):
                # The injected call can finish a frame before returning control
                # to Python. Open at the predicate itself, as generation does.
                h.pyboy.memory[0x0000]=0x0a
                h.pyboy.memory[0x4000]=0
            h.register_hook('FGSiteFree',open_sram)
            def probe(*,floor=1,side=0,site=1,hideout=(255,255),ball=None,boss=(2,4),boundary=2):
                h.load_state(start)
                grid=[2]*400
                x,y=(site,1) if side==0 else (1 if side==1 else 17,site)
                grid[20*y+x]=floor
                marker=(site,0) if side==0 else (0,site) if side==1 else (19,site)
                grid[marker[1]*20+marker[0]]=boundary
                for yy in range(20):
                    for xx in range(20):h.write8('wOverworldMap',grid[yy*20+xx],offset=81+26*yy+xx)
                h.write_sram_bytes('sStageEventHideoutX',list(hideout),bank=0)
                h.write_sram_bytes('sProcForestBallXY',([2*ball[1]+4,2*ball[0]+4] if ball else [0,0])+[0]*6,bank=0)
                h.write_sram_bytes('sProcForestExitEdge',[boss[0]],bank=0)
                h.write_sram_bytes('sProcForestExitI',[boss[1]],bank=0)
                h.pyboy.register_file.D=side;h.pyboy.register_file.E=site
                h.call_routine('FGSiteFree')
                return bool(h.last_call_registers['F']&16)
            for floor in FLOORS:
                for side in range(3):
                    self.assertTrue(probe(floor=floor,side=side,site=9,boss=((side+1)%3,0)),(floor,side))
            self.assertTrue(probe()) # FF sentinel must not wrap onto corner 1,1.
            self.assertFalse(probe(floor=2))
            self.assertFalse(probe(boundary=25)) # authored house/art is never overwritten.
            self.assertFalse(probe(hideout=(3,3)))
            self.assertTrue(probe(hideout=(4,3)))
            self.assertFalse(probe(ball=(1,1)))
            self.assertTrue(probe(ball=(3,1)))
            self.assertFalse(probe(boss=(1,0))) # north corner beside west boss.
            self.assertFalse(probe(side=1,boss=(0,0)))
            self.assertFalse(probe(side=0,site=17,boss=(2,0)))
            self.assertFalse(h.hook_errors,h.hook_errors)
        finally:h.close()
