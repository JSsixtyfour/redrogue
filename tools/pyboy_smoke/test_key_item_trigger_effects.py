"""Configured routine fixtures exercising key-item consumers, not acquisition.

Random return values are controlled for exact boundary assertions. No ROM
instructions or data are replaced, and all hooks target executable seams.
"""
from routine_session import isolated_routine_calls
from source_constants import parse_rgbds_constants, parse_trainer_constants
from harness import RedRogueHarness
from test_key_item_effects import all_tiers, tier_bytes
from test_key_item_equipment import bits
from test_smoke import HarnessTestCase, REPO_ROOT

MOVES = parse_rgbds_constants(REPO_ROOT / 'constants/move_constants.asm')
RAM = parse_rgbds_constants(REPO_ROOT / 'constants/ram_constants.asm')
BALANCE = parse_rgbds_constants(REPO_ROOT / 'constants/balance_constants.asm')


class KeyItemTriggerEffectsTest(HarnessTestCase):
    def configure(self, item, tier, active=True):
        h = self.harness
        h.write_sram_bytes('sKeyItemsBitfield', bits([item], [item] if active else []))
        h.write_sram_bytes('sKeyItemTiers', tier_bytes(item, tier))

    def test_leftovers_and_pp_tonic_exact_recovery_caps_and_fainted_control(self):
        h = self.harness
        h.boot_fight2(seed=17)
        with isolated_routine_calls(h):
            for tier in range(3):
                with self.subTest(tier=tier):
                    self.configure('LEFTOVERS', tier)
                    h.call_routine('RogueResetRunState')
                    self.assertEqual(h.read8('wHealAllItemLevel'), (0,4,8)[tier])
                    h.write8('wPartyCount', 3)
                    for i, hp in enumerate((100,999,0), 1):
                        h.write8('wPartySpecies', 1, i-1)
                        for label, value in ((f'wPartyMon{i}HP', hp), (f'wPartyMon{i}MaxHP',1000)):
                            h.write8(label,value >> 8); h.write8(label,value & 255,1)
                    h.write8('wPartySpecies',255,3)
                    h.call_routine('LeftoversRecovery')
                    for i, expected in enumerate((100 + 1000//(16-(0,4,8)[tier]),1000,0),1):
                        self.assertEqual(h.read_bytes(f'wPartyMon{i}HP',2),[expected>>8,expected&255])
                    self.configure('PP_TONIC',tier)
                    h.call_routine('RogueResetRunState')
                    self.assertEqual(h.read8('wRestorePPItemLevel'),tier*2)
                    # RogueResetRunState empties the party. With wPartyCount 0 the mon
                    # loop counts down from 256 and writes PP bytes across 11 KB of the
                    # address space, so whether the test survived depended on layout.
                    h.write8('wPartyCount', 3)
                    h.write8('wPartySpecies', 255, 3)
                    for i in range(1,4):
                        for j,(move,pp) in enumerate(((MOVES['TACKLE'],0),(MOVES['TACKLE'],0xc0),
                                                     (MOVES['SPLASH'],39),(0,0xa5))):
                            h.write8(f'wPartyMon{i}Moves',move,j)
                            h.write8(f'wPartyMon{i}PP',pp,j)
                    h.call_routine('PPTonicRecovery')
                    # Tackle has 35 base PP, 56 with three PP Ups; Splash has 40.
                    expected=[max(1,35//(16-tier*2)),0xc0|max(1,56//(16-tier*2)),40,0xa5]
                    for i in range(1,4):
                        self.assertEqual(h.read_bytes(f'wPartyMon{i}PP',4),expected)
            self.assertEqual(h.hook_errors,[])

    def test_rare_lens_consumer_stacks_and_saturates(self):
        h=self.harness
        h.boot_fight2(seed=17)
        with isolated_routine_calls(h):
            for tier,bonus in enumerate((12,25,38)):
                for active in (False,True):
                    for base in (0,250):
                        with self.subTest(tier=tier,active=active,base=base):
                            self.configure('RARE_LENS',tier,active)
                            h.write8('wItemBonusRarity',base)
                            h.write8('wWitchPrizesEarned',0)
                            h.write8('wRogueFlagsBitfield',0)
                            h.write8('hRandomAdd',73)
                            h.call_routine('ItemSelectionRarityBonus')
                            self.assertEqual(h.last_call_registers['B'],min(255,base+(bonus if active else 0)))
                            self.assertEqual(h.last_call_registers['C'],73)

    def test_shiny_charm_received_mon_exact_thresholds_and_species_alias(self):
        h=self.harness
        h.boot_fight2(seed=17)
        species=h.read8('wPartyMon1Species')
        bank, following=h.symbols.get('Rangerandom')
        self.assertEqual(h.pyboy.memory[bank,following-1],0xc9,'Random must end in RET')
        h.symbols._symbols['FixtureRandomReturn']=(bank,following-1)
        with isolated_routine_calls(h):
            for tier,threshold in enumerate((2,4,8)):
                for active in (False,True):
                    cutoff=threshold if active else 1
                    for roll in (cutoff-1,cutoff):
                        with self.subTest(tier=tier,active=active,roll=roll):
                            self.configure('SHINY_CHARM',tier,active)
                            h.write8('wPartyCount',0)
                            h.write8('hIsInBattle',0)
                            h.write8('wCurPartySpecies',species)
                            h.write8('wCurEnemyLevel',10)
                            h.write8('wMonDataLocation',0x10)
                            h.write8('wSpawnForm',0); h.write8('wSpawnDVSlot',0)
                            # Random's final instruction is executable; change only
                            # its returned A, preserving the generator's other effects.
                            def random_return(_, value=roll):
                                h.pyboy.register_file.A=value
                            h.register_hook('FixtureRandomReturn',random_return)
                            try:
                                h.call_routine('_AddPartyMon',limit=60000)
                            finally:
                                h.unregister_hook('FixtureRandomReturn',random_return)
                            self.assertEqual(h.read8('wPartyMon1CatchRate')&0x10,0x10 if roll<cutoff else 0)
                            self.assertEqual(h.read8('wCurPartySpecies'),species)
                            self.assertEqual(h.read8('wPartyMon1Species'),species)
                            self.assertGreater(h.read8('wPartyMon1Level'),0)

    def test_dv_booster_info_party_and_box_agree_at_every_live_tier(self):
        h=self.harness
        h.boot_fight2(seed=17)
        species=h.read8('wPartyMon1Species')
        with isolated_routine_calls(h):
            for tier,floor in enumerate((6,10,13)):
                for active in (False,True):
                    with self.subTest(tier=tier,active=active):
                        self.configure('DV_BOOSTER',tier,active)
                        h.write_sram_bytes('sRogueOfferDVTag',[species,0,0],bank=h.symbols.bank('sRogueOfferDVTag'))
                        h.write_sram_bytes('sRogueOfferDVs',[0x1f,0xf2,0,0,0,0],bank=h.symbols.bank('sRogueOfferDVs'))
                        h.write8('wRoguePokemon1',species)
                        h.write8('wCurPartySpecies',species)
                        h.pyboy.register_file.E=1
                        h.call_routine('GetRogueOfferDVsFloored')
                        minimum=floor if active else 0
                        expected=[(max(1,minimum)<<4)|15,0xf0|max(2,minimum)]
                        result=h.last_call_registers['HL']
                        self.assertEqual([result&255,result>>8],expected)
                        self.assertEqual(h.read8('wCurPartySpecies'),species)
                        h.write8('wPartyCount',0)
                        h.write8('hIsInBattle',0)
                        h.write8('wCurEnemyLevel',10)
                        h.write8('wMonDataLocation',0x10)
                        h.write8('wSpawnForm',0); h.write8('wSpawnDVSlot',1)
                        h.call_routine('_AddPartyMon',limit=60000)
                        self.assertEqual(h.read_bytes('wPartyMon1DVs',2),expected)
                        self.assertEqual(h.read8('wSpawnDVSlot'),0)
                        h.write8('wEnemyBattleStatus3',0)
                        h.write8('wEnemyMonSpecies2',species)
                        h.write8('wSpawnDVSlot',1)
                        h.call_routine('LoadEnemyMonData',limit=60000)
                        self.assertEqual(h.read_bytes('wEnemyMonDVs',2),expected)

    def test_amulet_coin_actual_prize_bcd_consumer(self):
        h=self.harness
        h.boot_fight2(seed=17)
        with isolated_routine_calls(h):
            for tier,percent in enumerate((10,15,20)):
                for active in (False,True):
                    with self.subTest(tier=tier,active=active):
                        self.configure('AMULET_COIN',tier,active)
                        h.write8('wOptions2',0)
                        h.write8('wTrainerClass',0)
                        h.write8('wCurEnemyLevel',20)
                        for i,value in enumerate((0,0,0x10)):
                            h.write8('wTrainerBaseMoney',value,i)
                        h.call_routine('ReadTrainer.FinishUp')
                        percent_total=BALANCE['DIFF_PRIZE_BONUS_PCT_NORMAL']+(percent if active else 0)
                        value=10*(20+20*percent_total//100)
                        self.assertEqual(h.read_bytes('wAmountMoneyWon',3),list(bytes.fromhex(f'{value:06d}')))

    def test_rare_scope_roll_consumer_and_forced_class_bypass(self):
        h=self.harness
        h.boot_fight2(seed=17)
        observed=[]
        def rarity(_):
            observed.append(h.pyboy.register_file.B)
        h.register_hook('Random_Pokemon_Selection.noRareScope',rarity)
        try:
            with isolated_routine_calls(h):
                for tier,bonus in enumerate((31,63,95)):
                    for active in (False,True):
                        for forced in (False,True):
                            with self.subTest(tier=tier,active=active,forced=forced):
                                self.configure('RARE_SCOPE',tier,active)
                                for label in ('wWitchPrizesEarned','wRogueFlagsBitfield','wBridgeGlobalEffects','wRewardRarityBonus'):
                                    if label in h.symbols._symbols:
                                        h.write8(label,0)
                                h.write8('wCurEnemyLevel',10)
                                observed.clear()
                                h.pyboy.register_file.E=int(forced)
                                h.call_routine('Random_Pokemon_Selection_Far',limit=60000)
                                self.assertEqual(observed,[] if forced else [bonus if active else 0])
        finally:
            h.unregister_hook('Random_Pokemon_Selection.noRareScope',rarity)

    def test_stat_booster_five_stats_saturation_and_nonrecipient_controls(self):
        species=parse_rgbds_constants(REPO_ROOT/'constants/pokemon_constants.asm')
        trainers=parse_trainer_constants(REPO_ROOT/'constants/trainer_constants.asm')
        for tier in range(3):
            for active in (False,True):
                for initial in (0,65534):
                    with self.subTest(tier=tier,active=active,initial=initial):
                        h=RedRogueHarness(REPO_ROOT,REPO_ROOT/'tools/pyboy_smoke/artifacts')
                        try:
                            mon={'species':species['SNORLAX'],'level':50,'moves':[MOVES['TACKLE']]}
                            h.inject_fight2_spec([mon,mon,mon],
                                [{'species':species['MAGIKARP'],'level':2,'moves':[MOVES['SPLASH']]}],
                                trainer_class=trainers['COOLTRAINER_M'],ai_tier=0)
                            h.boot_fight2(seed=1)
                            h.write_sram_bytes('sKeyItemsBitfield',bits(['STAT_BOOSTER'],['STAT_BOOSTER'] if active else []))
                            h.write_sram_bytes('sKeyItemTiers',tier_bytes('STAT_BOOSTER',tier))
                            captured=[]
                            def setup(_):
                                h.write8('wPartyGainExpFlags',5)
                                h.write8('wPartyMon3HP',0); h.write8('wPartyMon3HP',0,1)
                                for i,value in enumerate((10,20,30,40,50)):
                                    h.write8('wEnemyMonBaseStats',value,i)
                                for slot in range(1,4):
                                    for i in range(5):
                                        h.write8(f'wPartyMon{slot}HPExp',initial>>8,i*2)
                                        h.write8(f'wPartyMon{slot}HPExp',initial&255,i*2+1)
                            def capture(_):
                                captured.append((h.read8('hWhichPokemon'),h.read_bytes('wPartyMon1HPExp',10)))
                            h.register_hook('GainExperience',setup)
                            h.register_hook('GainExperience.statExpDone',capture)
                            ended=h.hook_flag('EndOfBattle')
                            for frame in range(6500):
                                if frame%12==0: h.pyboy.button_press('a')
                                elif frame%12==2: h.pyboy.button_release('a')
                                h.tick(1)
                                if ended['count']: break
                            else: self.fail('no actual enemy KO / stat-exp dispatch')
                            expected=[]
                            for value in (10,20,30,40,50):
                                total=min(65535,initial+value*(tier+2 if active else 1))
                                expected.extend((total>>8,total&255))
                            self.assertEqual(captured,[(0,expected)])
                            untouched=[initial>>8,initial&255]*5
                            for slot in (2,3):
                                self.assertEqual(h.read_bytes(f'wPartyMon{slot}HPExp',10),untouched)
                            self.assertEqual(h.hook_errors,[])
                        finally:
                            h.close()

    def test_prism_species_bias_reward_starter_budget_and_form_types(self):
        h=self.harness
        h.boot_fight2(seed=17)
        species=parse_rgbds_constants(REPO_ROOT/'constants/pokemon_constants.asm')
        types=parse_rgbds_constants(REPO_ROOT/'constants/type_constants.asm')
        events=parse_rgbds_constants(REPO_ROOT/'constants/event_constants.asm')
        event=events['EVENT_GOT_STARTER']
        address=h.address('wEventFlags')+event//8
        with isolated_routine_calls(h):
            for tier in range(3):
                for starter in (False,True):
                    with self.subTest(tier=tier,starter=starter):
                        self.configure('ELEMENT_PRISM',tier)
                        h.write_sram_bytes('sElementPrismType',[types['FIRE']])
                        if starter: h.pyboy.memory[address]&=~(1<<(event%8))&255
                        else: h.pyboy.memory[address]|=1<<(event%8)
                        h.call_routine('RoguePrismSetRerollBudget')
                        budget=16 if starter else 1
                        self.assertEqual(h.read8('wPrismRerollsLeft'),budget)
                        # Matching fire candidate is kept without spending budget.
                        h.pyboy.register_file.D=species['CHARMANDER']; h.pyboy.register_file.E=0
                        h.call_routine('RoguePrismShouldRerollSpecies')
                        self.assertTrue(h.last_call_registers['F']&0x80)
                        self.assertEqual(h.read8('wPrismRerollsLeft'),budget)
                        # Water mismatch consumes exactly the full bounded budget.
                        for remaining in range(budget-1,-1,-1):
                            h.pyboy.register_file.D=species['SQUIRTLE']; h.pyboy.register_file.E=0
                            h.call_routine('RoguePrismShouldRerollSpecies')
                            self.assertFalse(h.last_call_registers['F']&0x80)
                            self.assertEqual(h.last_call_registers['D'],species['SQUIRTLE'])
                            self.assertEqual(h.read8('wPrismRerollsLeft'),remaining)
                        h.pyboy.register_file.D=species['SQUIRTLE']; h.pyboy.register_file.E=0
                        h.call_routine('RoguePrismShouldRerollSpecies')
                        self.assertTrue(h.last_call_registers['F']&0x80)
                for active,selected,form,kept in ((False,types['FIRE'],0,True),
                        (True,255,0,True),(True,types['ICE'],1,True),(True,types['ICE'],0,False)):
                    with self.subTest(tier=tier,active=active,selected=selected,form=form):
                        self.configure('ELEMENT_PRISM',tier,active)
                        h.write_sram_bytes('sElementPrismType',[selected])
                        h.write8('wPrismRerollsLeft',1)
                        h.pyboy.register_file.D=species['VULPIX']; h.pyboy.register_file.E=form
                        h.call_routine('RoguePrismShouldRerollSpecies')
                        self.assertEqual(bool(h.last_call_registers['F']&0x80),kept)
                        self.assertEqual(h.read8('wPrismRerollsLeft'),int(kept))
            self.assertEqual(h.hook_errors,[])

    def test_actual_victory_recovery_dispatch_active_inactive_and_loss_controls(self):
        species=parse_rgbds_constants(REPO_ROOT/'constants/pokemon_constants.asm')
        trainers=parse_trainer_constants(REPO_ROOT/'constants/trainer_constants.asm')
        for tier in range(3):
            for active,lost in (([],False),(['LEFTOVERS'],False),(['PP_TONIC'],False),
                                (['LEFTOVERS','PP_TONIC','STAT_BOOSTER'],False),(['LEFTOVERS','PP_TONIC','STAT_BOOSTER'],True)):
                with self.subTest(tier=tier,active=active,configured_loss_result=lost):
                    h=RedRogueHarness(REPO_ROOT,REPO_ROOT/'tools/pyboy_smoke/artifacts')
                    try:
                        mon={'species':species['SNORLAX'],'level':50,'moves':[MOVES['TACKLE']]}
                        h.inject_fight2_spec([mon,mon,mon],
                            [{'species':species['MAGIKARP'],'level':2,'moves':[MOVES['SPLASH']]}],
                            trainer_class=trainers['COOLTRAINER_M'],ai_tier=0)
                        h.boot_fight2(seed=1)
                        h.write_sram_bytes('sKeyItemsBitfield',bits(['LEFTOVERS','PP_TONIC','STAT_BOOSTER'],active))
                        h.write_sram_bytes('sKeyItemTiers',all_tiers({'LEFTOVERS':tier,'PP_TONIC':tier,'STAT_BOOSTER':tier}))
                        h.call_routine('ApplyKeyItemTierEffects')
                        def setup(_):
                            h.write8('wBattleResult',int(lost))
                            h.write8('wCanEvolveFlags',0)
                            for i,hp in enumerate((1,95,0),1):
                                h.write8(f'wPartyMon{i}HP',0); h.write8(f'wPartyMon{i}HP',hp,1)
                                h.write8(f'wPartyMon{i}MaxHP',0); h.write8(f'wPartyMon{i}MaxHP',96,1)
                                h.write8(f'wPartyMon{i}PP',0)
                        h.register_hook('EndOfBattle',setup)
                        done=h.hook_flag('EndOfBattle.clearBattleState')
                        for frame in range(6500):
                            if frame%12==0: h.pyboy.button_press('a')
                            elif frame%12==2: h.pyboy.button_release('a')
                            h.tick(1)
                            if done['count']: break
                        else: self.fail('victory recovery did not finish')
                        hp_active='LEFTOVERS' in active and not lost
                        pp_active='PP_TONIC' in active and not lost
                        self.assertEqual(h.read8('wStatExpPasses'),tier+2 if 'STAT_BOOSTER' in active else 1)
                        expected_hp=(1+96//(16-(0,4,8)[tier]),96,0) if hp_active else (1,95,0)
                        for i,hp in enumerate(expected_hp,1):
                            self.assertEqual(h.read_bytes(f'wPartyMon{i}HP',2),[0,hp])
                            self.assertEqual(h.read8(f'wPartyMon{i}PP'),max(1,35//(16-tier*2)) if pp_active else 0)
                        self.assertEqual(h.hook_errors,[])
                    finally:
                        h.close()

    def test_scope_lens_prism_three_way_consumers_keep_independent_outcomes(self):
        h=self.harness
        h.boot_fight2(seed=17)
        types=parse_rgbds_constants(REPO_ROOT/'constants/type_constants.asm')
        loadout=['RARE_SCOPE','RARE_LENS','ELEMENT_PRISM']
        observed=[]
        def scope(_): observed.append(h.pyboy.register_file.B)
        h.register_hook('Random_Pokemon_Selection.noRareScope',scope)
        try:
            with isolated_routine_calls(h):
                for tier in range(3):
                    flags=bits(loadout,loadout)
                    tiers=all_tiers({name:tier for name in loadout})
                    h.write_sram_bytes('sKeyItemsBitfield',flags)
                    h.write_sram_bytes('sKeyItemTiers',tiers)
                    h.write_sram_bytes('sElementPrismType',[types['FIRE']])
                    h.write8('wWitchPrizesEarned',0); h.write8('wRogueFlagsBitfield',0)
                    for i in range(3): h.write8('wBridgeGlobalEffects',0,i)
                    h.write8('wRewardRarityBonus',0) if 'wRewardRarityBonus' in h.symbols._symbols else None
                    h.call_routine('RoguePrismRefreshCache')
                    self.assertEqual(h.read8('wPrismDamageBonus'),(10,15,20)[tier])
                    h.write8('wMoveType',types['FIRE'])
                    h.write8('wDamage',0); h.write8('wDamage',100,1)
                    h.call_routine('RoguePrismDamageBoost')
                    self.assertEqual(h.read_bytes('wDamage',2),[0,(110,115,120)[tier]])
                    h.write8('wItemBonusRarity',0); h.write8('hRandomAdd',73)
                    h.call_routine('ItemSelectionRarityBonus')
                    self.assertEqual(h.last_call_registers['B'],(12,25,38)[tier])
                    self.assertEqual(h.last_call_registers['C'],73)
                    observed.clear()
                    h.write8('wCurEnemyLevel',10)
                    h.pyboy.register_file.E=0
                    h.call_routine('Random_Pokemon_Selection_Far',limit=60000)
                    self.assertTrue(observed)
                    self.assertEqual(set(observed),{(31,63,95)[tier]})
                    self.assertEqual(h.read_sram_bytes('sKeyItemsBitfield',4),flags)
                    self.assertEqual(h.read_sram_bytes('sKeyItemTiers',4),tiers)
        finally:
            h.unregister_hook('Random_Pokemon_Selection.noRareScope',scope)


if __name__ == '__main__':
    import unittest
    unittest.main(verbosity=2)
