"""One ordinary ladder gets a distinct entrance connection; zero keeps none."""
import unittest
import json
import test_cave_subroom as cave
import test_optional_cave_cold as cold
import save_reload
from harness import RedRogueHarness
from source_constants import parse_map_constants, parse_rgbds_constants


class FallbackEntry:
    def capture(self,label):
        out=cave.ROOT/'builds/procedural_updates/cave_two_returns/captures'
        out.mkdir(parents=True,exist_ok=True)
        self.h.pyboy.tick(render=True)
        self.h.pyboy.screen.image.save(out/f'{self.h.hardware_mode}_{label}.png')
        (out/f'{self.h.hardware_mode}_{label}.json').write_text(json.dumps({
            'rom':self.h.rom_sha256,'sym':self.h.sym_sha256,'mode':self.h.hardware_mode,
            'fixture':'forced partner exhaustion, Debug2 cold cave; default boot RNG',
            'map':self.h.read8('hCurMap'),'xy':[self.h.read8('wXCoord'),self.h.read8('wYCoord')],
            'tilemap_width':20,'tilemap_height':18,'tilemap':self.h.read_bytes('wTileMap',360),
            'ladders':self.h.read_sram_bytes('sProcCaveStagingBuffer',cave.TAIL+2,bank=0)[cave.TAIL:],
        },indent=2)+'\n')

    def walk_in_room(self,goal):
        h=self.h;start=(h.read8('wXCoord'),h.read8('wYCoord'))
        blocked={self.room['resident'],self.room['ball'],self.position}|(set(self.room['ladders'])-{start,goal})
        came=cave.room_reach(self.room,start,blocked)
        self.assertIn(goal,came)
        path=[];at=goal
        while came[at]:
            at,button=came[at];path.append(button)
        for button in reversed(path):
            before=(h.read8('wXCoord'),h.read8('wYCoord'))
            dx,dy={'up':(0,-1),'down':(0,1),'left':(-1,0),'right':(1,0)}[button]
            self.press_until(button,lambda before=before,dx=dx,dy=dy:(h.read8('wXCoord'),h.read8('wYCoord'))==(before[0]+dx,before[1]+dy),'safe room approach')

    def enter_subroom_as(self,kind,index):
        h=self.h;self.room=cave.ROOMS[index]
        parent=self.maps['PROCEDURAL_CAVE_1'];roommap=self.maps['PROCEDURAL_CAVE_SUBROOM']
        # Keep the first dynamic ladder. Only exhaust the distant-partner counts
        # (CaveDynWalk with CAVE_DYN_PARTNER and CAVE_DYN_COUNT; b = the count).
        def no_partner(_):
            if h.pyboy.register_file.C&0x82==0x82:h.pyboy.register_file.B=0
        h.register_hook('CaveDynWalk.end',no_partner)
        before={}
        def snapshot(_):
            before['map']=h.read_bytes('wOverworldMap',601)
            before['actors']=[h.read_bytes('wSprite01StateData2MapY',2,16*i) for i in range(7)]
        h.register_hook('CaveSubroomPlaceLadders',snapshot)
        h.boot_to_lobby(battle_count=11,encounter_kind=4);h.write8('wStageEvent',getattr(self,'stage_event',0))
        h.preload_and_enter_wild_area(parent,'cave');h.write8('wProcCaveWildBudget',0)
        raw=h.read_sram_bytes('sProcCaveStagingBuffer',cave.TAIL+4,bank=0)
        self.assertEqual(raw[cave.TAIL],cave.DYN_1)
        self.assertEqual(raw[cave.TAIL+1],254)
        ladders=cave.cave_ladders(h);self.assertEqual(len(ladders),2,ladders)
        self.ladder,entrance=ladders
        self.assertEqual(entrance['block'],cave.ENTRANCE_BLOCK)
        ax,ay=self.ladder['block']
        after=h.read_bytes('wOverworldMap',601)
        expected={81+19*26+9:40,81+ay*26+ax:40}
        if before['map'][81+19*26+10] in (14,19):expected[81+19*26+10]=1
        self.assertEqual({i:v for i,v in enumerate(after) if v!=before['map'][i]},expected)
        self.assertEqual(before['map'][81+19*26+9],36)
        self.assertEqual([h.read_bytes('wSprite01StateData2MapY',2,16*i) for i in range(7)],before['actors'])
        self.assertEqual(h.read8('wSprite08StateData1'),0)
        self.assertEqual(h.read8('wSprite09StateData1'),0)
        # Select each authored room using its existing saved record, then rearm
        # the real cave loader. No position or destination warp is injected.
        raw[cave.TAIL+2]=(raw[cave.TAIL+2]&~15)|{'gambler':0,'nerd':4,'maniac':12}[kind]
        raw[cave.TAIL+3]=cave.room_byte(index,1,1)
        toggles=parse_rgbds_constants(cave.ROOT/'constants/toggle_constants.asm')
        for name,shown in (('TOGGLE_CAVESUB_GAMBLER',kind=='gambler'),('TOGGLE_CAVESUB_SUPER_NERD',kind!='gambler')):
            i=toggles[name];byte=h.read8('wToggleableObjectFlags',offset=i//8)
            h.write8('wToggleableObjectFlags',byte&~(1<<(i%8)) if shown else byte|(1<<(i%8)),offset=i//8)
        h.park_before_hijack();h.write_sram_bytes('sProcCaveStagingBuffer',raw,bank=0)
        h.call_routine('CaveSubroomArm');h.tick(30)
        warps=h.warp_entries()
        self.entrance_slot=entrance['slot']
        self.assertEqual(warps[self.entrance_slot],[39,19,self.room['warps'][1],roommap])
        self.assertEqual(warps[self.ladder['slot']],[2*ay+1,2*ax+1,self.room['warps'][0],roommap])
        self.assertTrue(all(entry[0]==255 for i,entry in enumerate(warps[2:32],2) if i not in (self.entrance_slot,self.ladder['slot'])))
        self.assertEqual(warps[0][0],255) # the normal one-way entrance remains disarmed
        self.assertEqual((h.read8('wXCoord'),h.read8('wYCoord')),(18,39))
        self.parent_layout=h.read_bytes('wOverworldMap',601)
        self.parent_state=h.read_sram_bytes('sProcCaveStagingBuffer',cave.TAIL+4,bank=0)
        self.parent_exit=warps[1]
        self.parent_count=h.read8('wBattleCount');self.parent_last=h.read8('wLastMap')
        if index==0:self.capture('entrance')
        self.press_until('right',lambda:h.read8('hCurMap')==roommap,'entrance ladder into basement')
        self.assertEqual((h.read8('wXCoord'),h.read8('wYCoord')),self.room['ladders'][1])
        for i,n in enumerate(self.room['warps']):
            self.assertEqual(h.warp_entries()[n][2:],[self.ladder['back'] if i==0 else 0,parent])

    def return_trip(self,ladder):
        h=self.h;parent=self.maps['PROCEDURAL_CAVE_1'];roommap=self.maps['PROCEDURAL_CAVE_SUBROOM']
        lx,ly=self.room['ladders'][ladder]
        self.walk_in_room((lx-1,ly))
        self.press_until('right',lambda:h.read8('hCurMap')==parent,'basement ladder to its own return')
        ax,ay=self.ladder['block']
        x,y=(2*ax+1,2*ay+1) if ladder==0 else (18,39)
        self.assertEqual((h.read8('wXCoord'),h.read8('wYCoord')),(x,y))
        self.assertEqual((h.read8('wXBlockCoord'),h.read8('wYBlockCoord')),(x%2,y%2))
        ptr=h.address('wOverworldMap')+27+(y//2)*26+x//2
        self.assertEqual(h.read_bytes('wCurrentTileBlockMapViewPointer',2),[ptr&255,ptr>>8])
        self.assertEqual(h.read_bytes('wOverworldMap',601),self.parent_layout)
        self.assertEqual(h.warp_entries()[1],self.parent_exit)
        self.assertEqual(h.read8('wBattleCount'),self.parent_count)
        self.assertEqual(h.read8('wLastMap'),self.parent_last)
        self.assertEqual(h.warp_entries()[0][0],255)
        # The cold battle helper intentionally leaves budget9 to verify
        # independence. Disable unrelated random fights for the walking trip.
        h.write8('wProcCaveWildBudget',0)
        if ladder==0:
            self.press_until('left',lambda:h.read8('wXCoord')==x-1,'off ordinary ladder')
        self.press_until('right',lambda:h.read8('hCurMap')==roommap,'re-enter same ladder')
        self.assertEqual((h.read8('wXCoord'),h.read8('wYCoord')),self.room['ladders'][ladder])


class CaveOptionalFallbackTest(FallbackEntry,cold.CaveColdEncounterTest):
    # Reuse real battle/gift/moves/PP/Continue checks for both cold species,
    # every room, and both party and box, now reached through the fallback.
    def run_encounter(self,*args,**kwargs):
        super().run_encounter(*args,**kwargs)
        self.return_trip(0);self.return_trip(1)
        # Cold boot the real saved basement, then use both return ladders again.
        h=self.h;self.assertTrue(save_reload.settle(h));h.park_before_hijack();h.call_routine('SaveGameData')
        reboot=save_reload.Reboot(save_reload.sram_image(h),cgb_mode=h.hardware_mode=='CGB')
        try:
            reboot.load();self.assertTrue(reboot.overworld);self.assertTrue(save_reload.settle(reboot.h))
            self.h=reboot.h
            self.assertEqual(self.h.read8('hCurMap'),self.maps['PROCEDURAL_CAVE_SUBROOM'])
            self.return_trip(0);self.return_trip(1)
            if args[0]=='ONIX' and args[1]==0:self.capture('basement_after_continue')
        finally:self.h=h;reboot.close()


class EntranceCollisionTest(unittest.TestCase):
    def test_site_zero_slot_collision_and_legacy_marker(self):
        import io
        h=RedRogueHarness(cave.ROOT,cave.ARTIFACTS)
        try:
            h.boot_to_lobby();h.park_before_hijack();base=io.BytesIO();h.save_state(base)
            maps=parse_map_constants(cave.ROOT/'constants/map_constants.asm')
            for a,b in ((0,254),(7,254),(254,255)):
                h.load_state(base)
                h.write8('wNumberOfWarps',32)
                raw=[0]*600;raw[cave.TAIL:cave.TAIL+4]=[a,b,0,0]
                h.write_sram_bytes('sProcCaveStagingBuffer',raw,bank=0)
                h.write8('wOverworldMap',40,offset=81+19*26+9)
                if a<len(cave.SITES):
                    x,y=cave.SITES[a];h.write8('wOverworldMap',40,offset=81+y*26+x)
                h.call_routine('CaveSubroomArm')
                slots={i:w for i,w in enumerate(h.warp_entries()[2:32],2) if w[0]!=255}
                entrance=3 if a==0 else 2
                expected={entrance:[39,19,cave.ROOMS[0]['warps'][1 if a<30 else 0],maps['PROCEDURAL_CAVE_SUBROOM']]}
                if a<30:expected[2+a]=[2*y+1,2*x+1,cave.ROOMS[0]['warps'][0],maps['PROCEDURAL_CAVE_SUBROOM']]
                self.assertEqual(slots,expected,(a,b))
                h.write8('wNumberOfWarps',len(cave.WARPS))
                for i,(x,y) in enumerate(cave.WARPS):
                    for j,v in enumerate((y,x,0,maps['PROCEDURAL_CAVE_1'])):h.write8('wWarpEntries',v,offset=4*i+j)
                h.call_routine('CaveSubroomLoad')
                for i,warp in enumerate(cave.ROOMS[0]['warps']):
                    self.assertEqual(h.warp_entries()[warp][2:],[(2+a) if a<30 and i==0 else 0,maps['PROCEDURAL_CAVE_1']],(a,b,i))
        finally:h.close()

    def test_dynamic_ladders_arm_return_and_arrive(self):
        """Dynamic pairs: row-order ladders, the exit's own block 40 skipped,
        departures in warps 2/3, room returns to 2/3 (or the entrance), and
        CaveResolveArrival landing warps 2/3 on the drawn ladders only."""
        import io
        h=RedRogueHarness(cave.ROOT,cave.ARTIFACTS)
        try:
            h.boot_to_lobby();h.park_before_hijack();base=io.BytesIO();h.save_state(base)
            maps=parse_map_constants(cave.ROOT/'constants/map_constants.asm')
            sub,parent=maps['PROCEDURAL_CAVE_SUBROOM'],maps['PROCEDURAL_CAVE_1']
            exit_,first,second=(2,2),(5,4),(14,12)   # the exit comes first in row order
            room=cave.ROOMS[0]['warps']
            for a,b in ((cave.DYN_1,cave.DYN_2),(cave.DYN_1,254),(7,254)):
                h.load_state(base)
                h.write8('wNumberOfWarps',32)
                raw=[0]*600;raw[cave.TAIL:cave.TAIL+4]=[a,b,0,0]
                drawn=[exit_,first]+([second] if b==cave.DYN_2 else [])
                if a<len(cave.SITES):drawn=[exit_,cave.SITES[a]]
                for x,y in drawn:
                    raw[81+y*26+x]=40;h.write8('wOverworldMap',40,offset=81+y*26+x)
                h.write8('wOverworldMap',40,offset=81+19*26+9)
                h.write_sram_bytes('sProcCaveStagingBuffer',raw,bank=0)
                h.write_sram_bytes('sProcCaveStagingExitY',[exit_[1],exit_[0]],bank=0)
                h.call_routine('CaveSubroomArm')
                slots={i:w for i,w in enumerate(h.warp_entries()[2:32],2) if w[0]!=255}
                if a==cave.DYN_1:
                    expected={2:[2*first[1]+1,2*first[0]+1,room[0],sub]}
                    expected[3]=([2*second[1]+1,2*second[0]+1,room[1],sub] if b==cave.DYN_2
                                 else [39,19,room[1],sub])
                else:
                    x,y=cave.SITES[a];expected={2+a:[2*y+1,2*x+1,room[0],sub],2:[39,19,room[1],sub]}
                self.assertEqual(slots,expected,(a,b))
                h.write8('wNumberOfWarps',len(cave.WARPS))
                for i,(x,y) in enumerate(cave.WARPS):
                    for j,v in enumerate((y,x,0,parent)):h.write8('wWarpEntries',v,offset=4*i+j)
                h.call_routine('CaveSubroomLoad')
                back=[2 if a==cave.DYN_1 else 2+a, 3 if b==cave.DYN_2 else 0]
                for i,warp in enumerate(room):
                    self.assertEqual(h.warp_entries()[warp][2:],[back[i],parent],(a,b,i))
                # The arrival: warps 2/3 land on the drawn ladders; others untouched.
                for dest in (0,1,2,3):
                    h.write8('wDestinationWarpID',dest)
                    h.write8('wYCoord',0x77);h.write8('wXCoord',0x66)
                    h.write8('wCurrentTileBlockMapViewPointer',0x55);h.write8('wCurrentTileBlockMapViewPointer',0x44,offset=1)
                    h.call_routine('CaveResolveArrival')
                    got=(h.read8('wXCoord'),h.read8('wYCoord'),h.read_bytes('wCurrentTileBlockMapViewPointer',2))
                    target=None
                    if a==cave.DYN_1 and dest==2:target=first
                    if a==cave.DYN_1 and dest==3 and b==cave.DYN_2:target=second
                    if target:
                        tx,ty=2*target[0]+1,2*target[1]+1
                        ptr=h.address('wOverworldMap')+27+ty//2*26+tx//2
                        self.assertEqual(got,(tx,ty,[ptr&255,ptr>>8]),(a,b,dest))
                    elif not(a==cave.DYN_1 and dest==3):
                        self.assertEqual(got,(0x66,0x77,[0x55,0x44]),('arrival changed',a,b,dest))
        finally:h.close()

    def test_east_floor_decor_cannot_cut_the_cave(self):
        from audit_cave_optional_fallback import reach
        h=RedRogueHarness(cave.ROOT,cave.ARTIFACTS)
        try:
            h.boot_to_lobby();h.park_before_hijack()
            import io
            base=io.BytesIO();h.save_state(base)
            def open_sram(_):
                h.pyboy.memory[0x0000]=10;h.pyboy.memory[0x4000]=0
            h.register_hook('CaveAddEntranceLadder',open_sram)
            for decor in range(12,20):
                h.load_state(base)
                before=[3]*400;before[389]=36;before[390]=decor;before[391]=1
                for y in range(20):
                    for x in range(20):h.write8('wOverworldMap',before[y*20+x],offset=81+y*26+x)
                h.write8('wOptionalEncounterSpecies',cold.SPECIES['ONIX'])
                h.write8('wOptionalEncounterPackage',2)
                h.write8('wOptionalEncounterMap',parse_map_constants(cave.ROOT/'constants/map_constants.asm')['PROCEDURAL_CAVE_SUBROOM'])
                h.call_routine('CaveAddEntranceLadder')
                after=[h.read8('wOverworldMap',offset=81+y*26+x) for y in range(20) for x in range(20)]
                self.assertLessEqual(reach(before)-{(19,39)},reach(after,{(19,39)}),decor)
        finally:h.close()

    def test_floor_and_npc_quadrants_preserved(self):
        bst=(cave.ROOT/'gfx/blocksets/cavern.bst').read_bytes()
        old=[bst[36*16+i] for i in (4,6,12,14)]
        new=[bst[40*16+i] for i in (4,6,12,14)]
        self.assertEqual(old[:2],new[:2]) # two NPC floor quadrants
        self.assertTrue(set(old)<=cave.WALKABLE)
        self.assertTrue(set(new)<=cave.WALKABLE)
        self.assertNotIn((new[2],new[0]),cave.ELEVATION_PAIRS)


class CaveFallbackStageEventTest(FallbackEntry,unittest.TestCase):
    setUp=cold.CaveColdEncounterTest.setUp
    tearDown=cold.CaveColdEncounterTest.tearDown
    press_until=cold.CaveColdEncounterTest.press_until

    def run_event(self,kind):
        self.stage_event=kind;self.position=(14,1)
        self.h.register_hook('OptionalCaveAssignEncounter',lambda _:self.h.pyboy.memory.__setitem__(self.h.address('sProcCavePalette'),1))
        self.enter_subroom_as('gambler',0)
        self.assertEqual(self.h.read8('wStageEvent')&7,kind)
        self.return_trip(0);self.return_trip(1)

    def test_joy_access(self):self.run_event(4)
    def test_jenny_access(self):self.run_event(5)
