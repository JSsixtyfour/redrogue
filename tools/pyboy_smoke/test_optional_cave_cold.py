"""Cold encounters use real ladders, all approved cave positions, battle and gift."""
import unittest
from harness import RedRogueHarness
from source_constants import parse_map_constants
import test_cave_subroom as cave
import test_optional_encounter as encounter
from test_optional_cold_moves import MOVES,SPECIES
import save_reload


class CaveColdEncounterTest(unittest.TestCase):
    press_until=cave.CaveSubroomTest.press_until
    enter_subroom_as=cave.CaveSubroomResidentTest.enter_subroom_as
    talk_up=cave.CaveSubroomResidentTest.talk_up
    screen_text=cave.CaveSubroomResidentTest.screen_text
    fight_and_win=cave.CaveSubroomResidentTest.fight_and_win
    mash_until=encounter.OptionalEncounterTest.mash_until

    def setUp(self):
        self.maps=parse_map_constants(cave.ROOT/'constants/map_constants.asm')
        self.h=RedRogueHarness(cave.ROOT,cave.ARTIFACTS)

    def tearDown(self):self.h.close()

    def walk_in_room(self,goal):
        h=self.h;start=(h.read8('wXCoord'),h.read8('wYCoord'))
        blocked={self.room['resident'],self.room['ball'],self.position}
        came=cave.room_reach(self.room,start,blocked)
        self.assertIn(goal,came)
        path=[];at=goal
        while came[at]:
            at,button=came[at];path.append(button)
        for button in reversed(path):
            before=(h.read8('wXCoord'),h.read8('wYCoord'))
            dx,dy={'up':(0,-1),'down':(0,1),'left':(-1,0),'right':(1,0)}[button]
            self.press_until(button,lambda before=before,dx=dx,dy=dy:(h.read8('wXCoord'),h.read8('wYCoord'))==(before[0]+dx,before[1]+dy),'room approach')

    def run_encounter(self,species,room,level,boxed,resident_after=False):
        h=self.h
        # A CGB frame can end inside a palette transfer with WRAM bank 2/3
        # selected. The encounter state and party structs live in bank 1.
        def gameplay_bank_selected():
            return h.hardware_mode!='CGB' or (h.pyboy.memory[0xff70]&7) in (0,1)
        self.position=((14,1),(17,15),(3,8))[room]
        h.register_hook('OptionalCaveAssignEncounter',lambda _:h.pyboy.memory.__setitem__(h.address('sProcCavePalette'),1))
        def force(_):
            h.write8('wOptionalEncounterSpecies',SPECIES[species]);h.write8('wOptionalEncounterLevel',level)
        h.register_hook('OptionalRollColdPackage',force)
        self.enter_subroom_as('nerd' if resident_after else 'gambler',room)
        self.assertEqual((h.read8('wSprite06StateData2MapX')-4,h.read8('wSprite06StateData2MapY')-4),self.position)
        self.assertEqual(h.read8('wSprite06StateData1'),5)
        self.walk_in_room((self.position[0],self.position[1]+1))
        h.tap('up');h.tick(20)
        count=h.read8('wBattleCount');boss=h.read8('wRoguePokemon1');package=h.read8('wOptionalEncounterPackage')
        h.write8('wProcCaveWildBudget',9)
        if not boxed:
            h.write8('wPartyCount',5);h.write8('wPartySpecies',255,offset=5)
            h.register_hook('AskName',lambda _:setattr(self,'decline_nickname',True))
        self.mash_until(lambda:gameplay_bank_selected() and h.read8('hIsInBattle')==1 and h.read8('wOptionalEncounterBattle')==0 and h.read8('wEnemyMonCatchRate')&8,'cold battle starts')
        self.assertEqual(h.read8('wEnemyMonSpecies'),SPECIES[species])
        self.assertEqual(h.read8('wEnemyMonLevel'),level)
        self.assertEqual(h.read8('wEnemyMonCatchRate')&0x6c,12)
        self.assertEqual(h.read8('wEnemyMonType1'),0x19) # ICE
        self.assertEqual(h.read8('wEnemyMonType2'),4 if species=='ONIX' else 0x19)
        battle_moves=h.read_bytes('wEnemyMonMoves',4)
        status=MOVES['MIST' if package==2 else 'HAZE']
        attack=MOVES['AURORA_BEAM' if level<=30 or (species=='ONIX' and level<=35) else 'ICE_PUNCH' if level<=35 else 'ICE_BEAM' if level<=45 else 'BLIZZARD']
        self.assertEqual(battle_moves[-2:],[status,attack])
        self.assertTrue(all(h.read_bytes('wEnemyMonPP',4)))
        h.write8('wEnemyMonHP',0);h.write8('wEnemyMonHP',1,offset=1)
        self.mash_until(lambda:gameplay_bank_selected() and h.read8('hIsInBattle')==0 and h.read8('wOptionalEncounterState')&4,'cold battle -> gift',3000)
        base='wBoxMon1' if boxed else 'wPartyMon6'
        self.assertEqual(h.read8(base),SPECIES[species])
        self.assertEqual(h.read8(base,7)&0x6c,12)
        self.assertEqual(h.read_bytes(base,4,8),battle_moves)
        self.assertTrue(all(h.read_bytes(base,4,29)))
        self.assertEqual(h.read8('wBattleCount'),count)
        self.assertEqual(h.read8('wRoguePokemon1'),boss)
        self.assertEqual(h.read8('wProcCaveWildBudget'),9)
        h.tap('b');h.tick(60)
        self.assertTrue(save_reload.settle(h));h.park_before_hijack();h.call_routine('SaveGameData')
        reboot=save_reload.Reboot(save_reload.sram_image(h),cgb_mode=h.hardware_mode=='CGB')
        try:
            reboot.load();self.assertTrue(reboot.overworld);self.assertTrue(save_reload.settle(reboot.h))
            self.assertEqual(reboot.h.read8('wOptionalEncounterPackage'),package)
            self.assertEqual(reboot.h.read8('wSprite06StateData1'),0)
            self.assertEqual(reboot.h.read_bytes(base,4,8),battle_moves)
        finally:reboot.close()
        if resident_after:
            rx,ry=self.room['resident']
            self.walk_in_room((rx,ry+1))
            self.fight_and_win('nerd')
            self.assertEqual(h.read8('wOptionalEncounterState')&7,7)
            self.assertEqual(h.read8('wOptionalEncounterPackage'),package)

    def test_onix_lake_30_party(self):self.run_encounter('ONIX',0,30,False)
    def test_snorlax_lake_35_box(self):self.run_encounter('SNORLAX',0,35,True)
    def test_onix_lake2_36_box(self):self.run_encounter('ONIX',1,36,True)
    def test_snorlax_lake2_45_party(self):self.run_encounter('SNORLAX',1,45,False)
    def test_onix_mountains_46_party(self):self.run_encounter('ONIX',2,46,False)
    def test_snorlax_mountains_46_box(self):self.run_encounter('SNORLAX',2,46,True)
    def test_nerd_reward_after_cold_encounter(self):self.run_encounter('ONIX',0,35,True,True)
