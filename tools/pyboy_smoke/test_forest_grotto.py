"""N/W/E forest/grove geometry, independent assignment and legacy-save returns.

Geometry fixtures can force the predicate; Debug 2 also owns a saved Pink
Butterfree fixture. Neither establishes production odds or placement guarantees.
"""
import io
from pathlib import Path
from collections import deque
import unittest
from harness import RedRogueHarness
from source_constants import parse_map_constants
from test_forest_rest_house import ForestWalk
import forest_clearings as fc
import save_reload

ROOT=Path(__file__).resolve().parents[2]
ARTIFACTS=ROOT/'tools/pyboy_smoke/artifacts'
BASE,STRIDE,WARP=81,26,31
DIRECTIONS={0:('up',(0,-1)),1:('left',(-1,0)),2:('right',(1,0))}
GROVE_DIRECTIONS={0:('down',(0,1)),1:('right',(1,0)),2:('left',(-1,0))}


def assignment_fixture(h):
    h.register_hook('FGHasAssignedEncounter.return',lambda _:setattr(h.pyboy.register_file,'A',1))


def cells_for_grid(grid,w,h):
    bst=fc.BLOCKSET.read_bytes();walk=fc.walkable_tiles();out={}
    for y in range(h):
        for x in range(w):
            for q,i in enumerate(fc.QUADRANT_TILES):
                tile=bst[grid[y*w+x]*16+i]
                if tile in walk:out[(2*x+q%2,2*y+q//2)]=tile
    return out


class ForestGrottoTripTest(ForestWalk,unittest.TestCase):
    def run_pair(self,main,side):
        h=self.h
        forest,grove=self.maps['PROCEDURAL_FOREST'],self.maps['PROCEDURAL_FOREST_GROTTO']
        h.boot_to_lobby(battle_count=11,encounter_kind=4)
        h.write8('wStageEvent',0)
        assignment_fixture(h)
        # PFRollBoss begins with preload SRAM0 still open, after the wall roll.
        h.register_hook('PFRollBoss',lambda _:h.pyboy.memory.__setitem__(h.address('sProcForestExitEdge'),main))
        h.register_hook('FGChooseWall.return',lambda _:setattr(h.pyboy.register_file,'A',side))
        lobby=io.BytesIO();h.save_state(lobby)
        attempts=[]
        for seed in (17,31,53,91,137,203,251,7,11,19):
            h.load_state(lobby);h.seed_rng((seed,seed^0xa5,main+1,1))
            h.preload_and_enter_wild_area(forest,'forest')
            entry=h.warp_entries()[31]
            attempts.append((seed,entry))
            if entry[0]!=255 and entry[2]==2*side:break
        self.assertNotEqual(entry[0],255,attempts)
        self.assertEqual(entry[2:],[2*side,grove],attempts)
        self.assertNotEqual(main,side)
        self.assertEqual(h.read_sram_bytes('sProcForestExitEdge',1,bank=0),[main])
        h.write8('wProcForestWildBudget',0)
        layout=h.read_bytes('wOverworldMap',601)
        packed=h.read_sram_bytes('sProcForestStagingBuffer',400,bank=0)
        scratch=h.read_sram_bytes('sProcForestGenScratch',81,bank=0)
        house=h.read_sram_bytes('sProcForestItemGot',1,bank=0)
        balls=h.read_sram_bytes('sProcForestBallXY',8,bank=0)
        boss=h.read_bytes('wSprite01StateData2MapY',2)
        count,last=h.read8('wBattleCount'),h.read8('wLastMap')
        parent=[(entry[1],entry[0])]
        parent.append((parent[0][0]+(side==0),parent[0][1]+(side!=0)))
        self.assertEqual(h.warp_entries()[3],[parent[1][1],parent[1][0],2*side+1,grove])
        self.hide('TOGGLE_WILD_AREA_POKEBALL_1')
        arrivals=[]
        def observe(_):
            if h.read8('hCurMap')==forest and h.read8('wWarpedFromWhichMap')==grove:
                arrivals.append((h.read_bytes('wCurrentTileBlockMapViewPointer',4),h.read8('wYBlockCoord'),h.read8('wXBlockCoord')))
        h.register_hook('LoadTilesetHeader.done',observe)
        parent_button,(dx,dy)=DIRECTIONS[side]
        room_button,(rx,ry)=GROVE_DIRECTIONS[side]
        room_spawns={0:((6,11),(7,11)),1:((13,6),(13,7)),2:((0,6),(0,7))}[side]
        authored=(ROOT/'maps/ProceduralForestGrotto.blk').read_bytes()
        expected=[27 if b==0 else b for b in authored]
        opening={0:(5*7+3,89),1:(3*7+6,87),2:(3*7,86)}[side]
        expected[opening[0]]=opening[1]
        for trip in range(2):
            px,py=parent[trip]
            self.walk_to((px-dx,py-dy))
            self.press_until(parent_button,grove,'into opposite grove opening')
            self.assertEqual((h.read8('wXCoord'),h.read8('wYCoord')),room_spawns[trip])
            self.assertEqual(h.read8('wNumberOfWarps'),6)
            loaded=[h.read8('wOverworldMap',offset=42+y*13+x) for y in range(6) for x in range(7)]
            self.assertEqual(loaded,expected)
            warps=h.warp_entries()
            for n,w in enumerate(warps):
                if n//2==side:
                    x,y=room_spawns[n%2]
                    self.assertEqual(w,[y,x,31 if n%2==0 else 3,forest])
                else:self.assertEqual(w[0],255)
            self.walk_room((6,6),expected)
            if trip==0:
                ARTIFACTS.mkdir(parents=True,exist_ok=True)
                h.pyboy.tick(render=True)
                h.pyboy.screen.image.save(str(ARTIFACTS/f'grove_geometry_only_{main}_{side}_{h.hardware_mode}.png'))
                self.assertTrue(save_reload.settle(h));h.park_before_hijack();h.call_routine('SaveGameData')
                battery=save_reload.sram_image(h)
                reboot=save_reload.Reboot(battery,cgb_mode=h.hardware_mode=='CGB')
                try:
                    reboot.load();self.assertEqual(reboot.status,2);self.assertTrue(reboot.overworld)
                    self.assertTrue(save_reload.settle(reboot.h))
                    fresh=reboot.h
                    self.assertEqual((fresh.read8('hCurMap'),fresh.read8('wXCoord'),fresh.read8('wYCoord')),(grove,6,6))
                    self.assertEqual(fresh.read8('wNumberOfWarps'),6)
                    self.assertEqual(fresh.read_sram_bytes('sProcForestStagingBuffer',400,bank=0),packed)
                    # Saved encounter identity must preserve the parent opening.
                    old_h=self.h;self.h=fresh
                    try:
                        self.walk_room((room_spawns[0][0]-rx,room_spawns[0][1]-ry),expected)
                        self.press_until(room_button,forest,'cold Continue exit')
                    finally:self.h=old_h
                    self.assertEqual((fresh.read8('wXCoord'),fresh.read8('wYCoord')),parent[0])
                    self.assertEqual(fresh.read_bytes('wOverworldMap',601),layout)
                    self.assertEqual((fresh.read8('wBattleCount'),fresh.read8('wLastMap')),(count,last))
                    self.assertNotEqual(fresh.warp_entries()[31][0],255,'saved assignment must keep its return opening')
                finally:reboot.close()
            gx,gy=room_spawns[trip]
            self.walk_room((gx-rx,gy-ry),expected)
            self.press_until(room_button,forest,'back to same forest opening')
            self.assertEqual((h.read8('wXCoord'),h.read8('wYCoord')),(px,py))
            pointer=h.address('wOverworldMap')+27+26*(py//2)+px//2
            self.assertEqual(arrivals[-1],([pointer&255,pointer>>8,py,px],py&1,px&1))
            self.assertEqual(h.read_bytes('wOverworldMap',601),layout)
            self.assertEqual(h.read_sram_bytes('sProcForestStagingBuffer',400,bank=0),packed)
            self.assertEqual(h.read_sram_bytes('sProcForestGenScratch',81,bank=0),scratch)
            self.assertEqual(h.read_sram_bytes('sProcForestItemGot',1,bank=0),house)
            self.assertEqual(h.read_sram_bytes('sProcForestBallXY',8,bank=0),balls)
            self.assertEqual(h.read_bytes('wSprite01StateData2MapY',2),boss)
            self.assertEqual((h.read8('wBattleCount'),h.read8('wLastMap')),(count,last))
            self.assertTrue(self.hidden('TOGGLE_WILD_AREA_POKEBALL_1'))
        self.assertEqual(len(arrivals),2)

    def walk_room(self,goal,grid):
        h=self.h;cells=cells_for_grid(grid,7,6);pairs=fc.forest_tile_pairs()
        start=(h.read8('wXCoord'),h.read8('wYCoord'));came={start:None};todo=deque([start])
        moves=(('up',0,-1),('down',0,1),('left',-1,0),('right',1,0))
        while todo and goal not in came:
            p=todo.popleft()
            for button,dx,dy in moves:
                q=(p[0]+dx,p[1]+dy)
                if q in cells and q not in came and frozenset((cells[p],cells[q])) not in pairs:
                    came[q]=(p,button);todo.append(q)
        self.assertIn(goal,came)
        path=[];node=goal
        while came[node]:node,button=came[node];path.append(button)
        for button in reversed(path):self.step(button)

    def test_main_north_grove_west(self):self.run_pair(0,1)
    def test_main_north_grove_east(self):self.run_pair(0,2)
    def test_main_west_grove_north(self):self.run_pair(1,0)
    def test_main_west_grove_east(self):self.run_pair(1,2)
    def test_main_east_grove_north(self):self.run_pair(2,0)
    def test_main_east_grove_west(self):self.run_pair(2,1)


class ForestGrottoContractTest(unittest.TestCase):
    def test_no_encounter_means_no_grotto_including_debug2(self):
        h=RedRogueHarness(ROOT,ARTIFACTS)
        try:
            h.boot_to_lobby();h.write8('wStageEvent',0)
            # Remove the Debug 2 fixture at the assignment consumer. A real main
            # boss must never substitute for the optional encounter's identity.
            h.register_hook('FGHasAssignedEncounter',lambda _:h.write8('wOptionalEncounterSpecies',0))
            snapshot=io.BytesIO();h.save_state(snapshot)
            walls=set()
            for seed in range(1,25):
                h.load_state(snapshot);h.seed_rng((seed,seed^0xa5,0,1))
                h.preload_and_enter_wild_area(242,'forest')
                main=h.read_sram_bytes('sProcForestExitEdge',1,bank=0)[0];walls.add(main)
                self.assertIn(main,(0,1,2))
                self.assertGreater(h.read8('wRoguePokemon1'),0,'the main boss must not act as a grotto assignment')
                self.assertEqual(h.warp_entries()[31][0],255)
                packed=h.read_sram_bytes('sProcForestStagingBuffer',400,bank=0)
                # Only the main exit's wall may contain an opening marker.
                for side in range(3):
                    if side==main:continue
                    boundary=[packed[x] for x in range(20)] if side==0 else [packed[y*20+(0 if side==1 else 19)] for y in range(20)]
                    self.assertNotIn({0:88,1:86,2:87}[side],boundary)
            self.assertEqual(walls,{0,1,2})
        finally:h.close()

    def test_legacy_saved_house_site_zero_keeps_its_door(self):
        h=RedRogueHarness(ROOT,ARTIFACTS)
        try:
            h.boot_to_lobby();h.park_before_hijack()
            maps=parse_map_constants(ROOT/'constants/map_constants.asm');house=maps['PROCEDURAL_FOREST_REST_HOUSE']
            h.write_sram_bytes('sProcForestStagingBuffer',[2]*400,bank=0)
            h.write_sram_bytes('sProcForestItemGot',[129],bank=0)
            for i,v in enumerate((5,3,0,house)):h.write8('wWarpEntries',v,offset=12+i)
            h.call_routine('PFArmHouseDoor');h.call_routine('FGArmForestWarp')
            self.assertEqual(h.read_bytes('wWarpEntries',4,12),[5,3,0,house])
            self.assertEqual(h.read8('wWarpEntries',offset=124),255)
        finally:h.close()

    def test_dynamic_arrival_all_sides_rows_parities_and_invalid_marker(self):
        h=RedRogueHarness(ROOT,ARTIFACTS)
        try:
            h.boot_to_lobby();h.park_before_hijack();maps=parse_map_constants(ROOT/'constants/map_constants.asm')
            start=io.BytesIO();h.save_state(start)
            for side in range(3):
                for site in (5,7,9,11,13):
                    for second in (0,1):
                        h.load_state(start)
                        packed=[2]*400
                        if side==0:packed[site]=88;packed[20+site]=1;x,y=2*site+second,0
                        elif side==1:packed[20*site]=86;packed[20*site+1]=1;x,y=0,2*site+second
                        else:packed[20*site+17:20*site+20]=[1,27,87];x,y=39,2*site+second
                        h.write_sram_bytes('sProcForestStagingBuffer',packed,bank=0)
                        h.write_sram_bytes('sProcForestBaked',[1],bank=0)
                        h.write_sram_bytes('sProcForestRiverSide',[255],bank=0)
                        h.write_sram_bytes('sProcForestExitEdge',[(side+1)%3],bank=0)
                        h.write8('hCurMap',maps['PROCEDURAL_FOREST']);h.write8('wWarpedFromWhichMap',maps['PROCEDURAL_FOREST_GROTTO'])
                        h.write8('wDestinationWarpID',3 if second else 31)
                        h.call_routine('FGResolveArrival')
                        ptr=h.address('wOverworldMap')+27+26*(y//2)+x//2
                        self.assertEqual(h.read_bytes('wCurrentTileBlockMapViewPointer',4),[ptr&255,ptr>>8,y,x])
            # Same-wall markers must never be treated as a grotto.
            h.write_sram_bytes('sProcForestExitEdge',[2],bank=0)
            h.call_routine('FGResolveArrival')
            ptr=h.address('wOverworldMap')+27+26*17+9
            self.assertEqual(h.read_bytes('wCurrentTileBlockMapViewPointer',4),[ptr&255,ptr>>8,35,18])
        finally:h.close()

    def test_retired_river_force_runs_sidewinder(self):
        h=RedRogueHarness(ROOT,ARTIFACTS)
        try:
            h.boot_to_lobby();h.write8('wStageEvent',0)
            river=h.hook_flag('PFGenerateRiverMaze');normal=h.hook_flag('PFSidewinder')
            h.register_hook('PFinalizeForest',lambda _:h.write_sram_bytes('sProcForestAlgoForce',[6],bank=0))
            h.preload_and_enter_wild_area(242,'forest')
            self.assertEqual(river['count'],0);self.assertEqual(normal['count'],1)
            self.assertEqual(h.read_sram_bytes('sProcForestRiverSide',1,bank=0),[255])
        finally:h.close()
