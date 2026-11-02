"""Checkpoint 4: real grove entry/battle/offer, own saved state and no leakage."""
import io
import json
import shutil
import unittest
from harness import RedRogueHarness
from test_forest_rest_house import ForestWalk
import test_forest_grotto as geometry
from source_constants import parse_rgbds_constants
import save_reload


class OptionalEncounterTest(ForestWalk, unittest.TestCase):
    walk_room = geometry.ForestGrottoTripTest.walk_room

    def enter_grove(self):
        h = self.h
        h.boot_to_lobby(battle_count=11)
        h.write8('wStageEvent', 0)
        def force_geometry(_):
            h.pyboy.memory[h.address('sProcForestExitEdge')]=0
            h.pyboy.memory[h.address('sProcForestAlgoForce')]=1
        h.register_hook('PFRollBoss',force_geometry)
        h.register_hook('FGChooseWall.return',lambda _:setattr(h.pyboy.register_file,'A',1))
        initial = io.BytesIO(); h.save_state(initial)
        for seed in (17,31,53,91,137,203,251):
            h.load_state(initial); h.seed_rng((seed,seed ^ 0xa5,1,1))
            h.preload_and_enter_wild_area(self.maps['PROCEDURAL_FOREST'],'forest')
            entry = h.warp_entries()[31]
            if entry[0] != 255: break
        self.assertNotEqual(entry[0],255)
        self.assertGreater(h.read8('wOptionalEncounterLevel'),0)
        self.assertEqual(h.read8('wOptionalEncounterPackage'),1)
        self.parent_state = (h.read8('wBattleCount'),h.read8('wRoguePokemon1'),h.read8('wRoguePokemonForm1'),
                             h.read8('wProcForestWildBudget'),self.hidden('TOGGLE_WILD_AREA_BOSS'))
        self.parent_grid = h.read_sram_bytes('sProcForestStagingBuffer',400,bank=0)
        side = entry[2]//2
        self.grove_side=side
        button,(dx,dy)=geometry.DIRECTIONS[side]
        h.write8('wProcForestWildBudget',0)
        self.walk_to((entry[1]-dx,entry[0]-dy))
        self.press_until(button,self.maps['PROCEDURAL_FOREST_GROTTO'],'enter encounter grove')
        h.write8('wProcForestWildBudget',self.parent_state[3])
        self.grid=[h.read8('wOverworldMap',offset=42+y*13+x) for y in range(6) for x in range(7)]
        self.walk_room((6,6),self.grid)
        h.tap('up'); h.tick(20)
        self.assertEqual((h.read8('wXCoord'),h.read8('wYCoord')),(6,6))
        self.assertEqual(h.read8('wSprite01StateData1'),5)
        return h

    def mash_until(self,predicate,description,limit=1800):
        for i in range(limit):
            if predicate(): return
            self.h.tap('b' if getattr(self,'decline_nickname',False) else 'a'); self.h.tick(2)
        evidence=geometry.ROOT/'builds/procedural_updates/checkpoint4'/('failure_'+self._testMethodName)
        evidence.mkdir(parents=True,exist_ok=True)
        with (evidence/'failure.state').open('wb') as state:self.h.save_state(state)
        for name in ('pokered','pokeblue','pokeblue_debug'):
            for ext in ('gbc','sym','map'):shutil.copyfile(geometry.ROOT/f'{name}.{ext}',evidence/f'{name}.{ext}')
        (evidence/'tilemap.json').write_text(json.dumps({'wTileMap':self.h.read_bytes('wTileMap',360),
            'sprite1':self.h.read_bytes('wSprite01StateData1',16),
            'sprite2':self.h.read_bytes('wSprite01StateData2',16),
            'state':self.h.read_bytes('wOptionalEncounterSpecies',7), 'trace':getattr(self,'trace',[])},indent=2))
        self.fail(description + ': ' + str({n:self.h.read8(n) for n in
            ('hIsInBattle','wOptionalEncounterState','wOptionalEncounterScript','wCurMapScript','wPartyCount','wXCoord','wYCoord',
             'wSprite01StateData2MapX','wSprite01StateData2MapY','wSprite01StateData1ImageIndex','wSpritePlayerStateData1FacingDirection')}))

    def test_real_battle_and_party_reward(self):
        h=self.enter_grove()
        h.write8('wPartyCount',5)
        h.write8('wPartySpecies',255,offset=5)
        before=h.read8('wPartyCount')
        h.register_hook('AskName',lambda _:setattr(self,'decline_nickname',True))
        offer_entries=[]
        self.trace=[]
        for label in ('FGEncounterOffer.choiceMade','GivePokemon','_GivePokemon.addToParty','AskName','FGEncounterOffer.done'):
            h.register_hook(label,lambda _,label=label:self.trace.append((label,h.read8('wPartyCount'),h.read8('hCurrentMenuItem'),h.read8('wOptionalEncounterState'))))
        # Hook executed code, never the TX_ASM byte, which is interpreted data.
        h.register_hook('FGEncounterOffer.choiceMade',lambda _:offer_entries.append((h.read8('wOptionalEncounterState'),h.read8('wStatusFlags3'))))
        self.mash_until(lambda:h.read8('hIsInBattle')==1 and h.read8('wEnemyMonCatchRate') & 8,'start Pink battle')
        self.assertEqual(h.read8('wEnemyMonSpecies'),h.read8('wOptionalEncounterSpecies'))
        self.assertEqual(h.read8('wEnemyMonCatchRate') & 0x6c,8)
        self.assertEqual(h.read8('wEnemyMonLevel'),h.read8('wOptionalEncounterLevel'))
        self.assertEqual(h.read8('wOptionalEncounterBattle'),0)
        # Bounded combat fixture: give player a safe advantage and let the actual
        # battle loop take its ordinary victory/end-text/offer path.
        h.write8('wEnemyMonHP',0);h.write8('wEnemyMonHP',1,offset=1)
        self.mash_until(lambda:h.read8('wOptionalEncounterState') & 4,'battle -> join reward',3000)
        self.assertEqual(h.read8('wPartyCount'),before+1)
        mon=h.address('wPartyMons')+before*44
        self.assertEqual(h.pyboy.memory[mon],h.read8('wOptionalEncounterSpecies'))
        self.assertEqual(h.pyboy.memory[mon+7]&0x6c,8)
        self.assertEqual(h.pyboy.memory[mon+33],h.read8('wOptionalEncounterLevel'))
        self.assertEqual(len(offer_entries),1)
        self.assertTrue(offer_entries[0][0]&2)
        self.assertFalse(offer_entries[0][1]&128,'offer must wait for end-battle text')
        self.mash_until(lambda:h.read8('wOptionalEncounterScript')==0 and h.read8('hIsInBattle')==0,'return to grove')
        self.assertEqual(h.read8('wBattleCount'),self.parent_state[0])
        self.assertEqual(h.read8('wProcForestWildBudget'),self.parent_state[3])
        self.assertEqual(h.read8('wRoguePokemon1'),self.parent_state[1])
        self.assertEqual(self.hidden('TOGGLE_WILD_AREA_BOSS'),self.parent_state[4])
        self.assertEqual(h.read_sram_bytes('sProcForestStagingBuffer',400,bank=0),self.parent_grid)
        self.assertTrue(save_reload.settle(h));h.park_before_hijack();h.call_routine('SaveGameData')
        reboot=save_reload.Reboot(save_reload.sram_image(h),cgb_mode=h.hardware_mode=='CGB')
        try:
            reboot.load();self.assertTrue(reboot.overworld)
            self.assertTrue(save_reload.settle(reboot.h))
            self.assertEqual(reboot.h.read8('wOptionalEncounterState')&6,6)
            self.assertEqual(reboot.h.read8('wSprite01StateData1'),0)
            self.assertEqual(reboot.h.read8('wPartyCount'),before+1)
        finally:reboot.close()

    def test_request_scope_and_one_shot(self):
        h=self.h;h.boot_to_lobby();h.park_before_hijack()
        h.call_routine('OptionalForcePink')
        state=io.BytesIO();h.save_state(state)
        for map_id,species,battle,expected in ((71,125,1,8),(242,125,1,0),(71,1,1,0),(71,125,2,0)):
            h.load_state(state)
            h.write8('hCurMap',map_id);h.write8('wEnemyMonSpecies',species)
            h.write8('hIsInBattle',battle);h.write8('wOptionalEncounterBattle',1)
            def inject(_):h.pyboy.register_file.E=0
            h.register_hook('OptionalEncounterEnemyFlags',inject)
            flags=[]
            capture=lambda _:flags.append(h.pyboy.register_file.E)
            h.register_hook('OptionalEncounterEnemyFlags.done',capture)
            h.call_routine('OptionalEncounterEnemyFlags')
            h.unregister_hook('OptionalEncounterEnemyFlags',inject);h.unregister_hook('OptionalEncounterEnemyFlags.done',capture)
            self.assertEqual(flags[-1],expected,(map_id,species,battle))
            self.assertEqual(h.read8('wOptionalEncounterBattle'),0)

    def defeat(self):
        h=self.h
        self.mash_until(lambda:h.read8('hIsInBattle')==1 and h.read8('wEnemyMonCatchRate')&8,'begin actual battle')
        h.write8('wEnemyMonHP',0);h.write8('wEnemyMonHP',1,offset=1)

    def test_full_box_keeps_retry_then_front_inserts_special_gift(self):
        h=self.enter_grove()
        # Populate a valid full current box from the existing party struct.
        species=h.read8('wPartyMon1Species')
        h.write8('wBoxCount',20)
        for i in range(20):
            h.write8('wBoxSpecies',species,offset=i)
            for j,b in enumerate(h.read_bytes('wPartyMon1',33)):
                h.write8('wBoxMon1',b,offset=i*33+j)
        h.write8('wBoxSpecies',255,offset=20)
        before=h.read_bytes('wBoxMon1',33*20)
        offers=[]
        h.register_hook('FGEncounterOffer.done',lambda _:offers.append(h.read8('wOptionalEncounterState')))
        self.defeat()
        self.mash_until(lambda:len(offers)==1,'full storage offer returns')
        self.assertEqual(h.read8('wOptionalEncounterState')&7,3)
        self.assertEqual(h.read_bytes('wBoxMon1',33*20),before)
        self.assertEqual(h.read8('wSprite01StateData1'),5)
        self.mash_until(lambda:h.read8('wOptionalEncounterScript')==0,'battle script idle')
        h.tap('b');h.tick(60)
        self.assertTrue(save_reload.settle(h));h.park_before_hijack();h.call_routine('SaveGameData')
        reboot=save_reload.Reboot(save_reload.sram_image(h),cgb_mode=h.hardware_mode=='CGB')
        try:
            reboot.load();self.assertTrue(reboot.overworld)
            self.assertTrue(save_reload.settle(reboot.h))
            self.assertEqual(reboot.h.read8('wOptionalEncounterState')&7,3)
            self.assertEqual(reboot.h.read8('wSprite01StateData1'),5)
        finally:reboot.close()
        # Make exactly one box slot available, then talk to the survivor.
        h.write8('wBoxCount',19);h.write8('wBoxSpecies',255,offset=19)
        h.tick(60)
        h.tap('up');h.tick(20)
        self.mash_until(lambda:len(offers)==2,'retry gives boxed special Pokemon')
        self.assertEqual(h.read8('wBoxCount'),20)
        self.assertEqual(h.read8('wBoxMon1Species'),125)
        self.assertEqual(h.read8('wBoxMon1CatchRate')&0x6c,8)
        self.assertEqual(h.read_bytes('wBoxMon1',33,offset=33),before[:33])
        self.assertEqual(h.read8('wOptionalEncounterState')&7,7)
        self.assertEqual(h.read8('wBattleCount'),self.parent_state[0])

    def test_decline_resolves_without_gift(self):
        h=self.enter_grove();party=h.read8('wPartyCount');box=h.read8('wBoxCount')
        h.register_hook('FGEncounterOffer.choiceMade',lambda _:h.write8('hCurrentMenuItem',1))
        self.defeat()
        self.mash_until(lambda:h.read8('wOptionalEncounterState')&4,'explicit decline')
        self.assertEqual((h.read8('wPartyCount'),h.read8('wBoxCount')),(party,box))
        self.assertEqual(h.read8('wSprite01StateData1'),0)

    def test_level_latch_and_clear_preserve_main_boss_and_follower(self):
        h=self.h;h.boot_to_lobby();h.park_before_hijack()
        snapshot=io.BytesIO();h.save_state(snapshot)
        for count in (1,8,9,70,250):
            h.load_state(snapshot);h.write8('wBattleCount',count)
            h.call_routine('PCGetBossLevel');level=h.read8('wCurEnemyLevel')
            follower=h.read_bytes('wFollowerDataStart',19)
            boss=h.read8('wRoguePokemon1')
            h.call_routine('OptionalForcePink')
            expected=max(1,level-(1 if count<=8 else 2))
            self.assertEqual(h.read8('wOptionalEncounterLevel'),expected)
            self.assertEqual(h.read8('wRoguePokemon1'),boss)
            h.call_routine('OptionalEncounterClear')
            self.assertEqual(h.read_bytes('wOptionalEncounterSpecies',7),[0]*7)
            self.assertEqual(h.read_bytes('wFollowerDataStart',19),follower)

    def test_loss_resets_optional_state_with_run(self):
        h=self.enter_grove()
        self.mash_until(lambda:h.read8('hIsInBattle')==1 and h.read8('wEnemyMonCatchRate')&8,'start loss fixture')
        h.write8('wKODefianceUsages',0)
        for i in range(h.read8('wPartyCount')):
            h.write8('wPartyMon1HP',0,offset=i*44);h.write8('wPartyMon1HP',0,offset=i*44+1)
        h.write8('wBattleMonHP',0);h.write8('wBattleMonHP',0,offset=1)
        self.mash_until(lambda:h.read8('hCurMap')==self.maps['SILPH_CO_DORM'] and h.read8('wOptionalEncounterSpecies')==0,
                        'blackout ends run and clears optional encounter',4000)
        self.assertEqual(h.read_bytes('wOptionalEncounterSpecies',7),[0]*7)

    def test_main_boss_still_engages_after_optional_decline(self):
        h=self.enter_grove()
        h.register_hook('FGEncounterOffer.choiceMade',lambda _:h.write8('hCurrentMenuItem',1))
        self.defeat();self.mash_until(lambda:h.read8('wOptionalEncounterState')&4,'decline optional mon')
        h.tap('b');h.tick(60)
        exit_button,(dx,dy)=geometry.GROVE_DIRECTIONS[self.grove_side]
        gx,gy={0:(6,11),1:(13,6),2:(0,6)}[self.grove_side]
        self.walk_room((gx-dx,gy-dy),self.grid)
        self.press_until(exit_button,self.maps['PROCEDURAL_FOREST'],'return to parent before main boss')
        self.assertEqual(h.read8('wProcForestWildBudget'),self.parent_state[3])
        h.write8('wProcForestWildBudget',0) # suppress random battles on the approach
        bx=h.read8('wSprite01StateData2MapX')-4;by=h.read8('wSprite01StateData2MapY')-4
        ordinary_objects=self.objects
        for goal,face in (((bx,by+1),'up'),((bx+1,by),'left'),((bx-1,by),'right')):
            # ForestWalk normally blocks every boss neighbor to avoid its
            # automatic engage guard. This test intentionally approaches it.
            self.objects=lambda:ordinary_objects()-{goal}
            try:self.walk_to(goal)
            except AssertionError:continue
            break
        else:self.fail('no reachable neighbor of main boss')
        self.objects=ordinary_objects
        h.tap(face);h.tick(20)
        # Discard the optional-offer-only menu fixture before the main boss.
        self.mash_until(lambda:h.read8('hIsInBattle')==1 and h.read8('wEnemyMonSpecies')==self.parent_state[1],
                        'subsequent main boss engages independently')
        self.assertEqual(h.read8('wEnemyMonCatchRate')&8,0)
        self.assertEqual(h.read8('wBattleCount'),self.parent_state[0])


if __name__=='__main__':unittest.main()
