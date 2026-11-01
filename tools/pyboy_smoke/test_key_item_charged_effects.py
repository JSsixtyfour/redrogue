"""Exact charged-item transactions in configured ROM routine fixtures.

Dialogue, sound waits and HUD drawing are bypassed, not effect code. These
fixtures complement real-input journeys and do not establish visual acceptance.
"""
from routine_session import isolated_routine_calls
from source_constants import parse_map_constants, parse_rgbds_constants
from test_key_item_effects import all_tiers, tier_bytes
from test_key_item_equipment import ITEMS, bits
from test_move_tutor_prices import return_from_call
from test_smoke import HarnessTestCase, REPO_ROOT

MAPS=parse_map_constants(REPO_ROOT/'constants/map_constants.asm')
RAM=parse_rgbds_constants(REPO_ROOT/'constants/ram_constants.asm')
BATTLE=parse_rgbds_constants(REPO_ROOT/'constants/battle_constants.asm')
SERIAL=parse_rgbds_constants(REPO_ROOT/'constants/serial_constants.asm')
EVENTS=parse_rgbds_constants(REPO_ROOT/'constants/event_constants.asm')
TOGGLES=parse_rgbds_constants(REPO_ROOT/'constants/toggle_constants.asm')


class ChargedKeyItemEffectTest(HarnessTestCase):
    def test_three_equipped_dice_spend_only_their_own_packed_charge_bits(self):
        h=self.harness
        h.boot_to_lobby(battle_count=1)
        self.bypass('PrintText')
        loadout=['DOOR_DICE','MON_DICE','ITEM_DICE']
        with isolated_routine_calls(h):
            for tier in range(3):
                flags=bits(loadout,loadout)
                h.write_sram_bytes('sKeyItemsBitfield',flags)
                h.write_sram_bytes('sKeyItemTiers',all_tiers({name:tier for name in loadout}))
                h.call_routine('RogueResetRunState')
                packed=(tier+1)*0x15
                self.assertEqual(h.read8('wDiceCharges'),packed)
                h.write8('wRogueFlagsBitfield',0); h.write8('wGymChoice',0)
                for label in ('wDebug2ForcedDoor1','wDebug2ForcedDoor2'):
                    h.write8(label,MAPS['ROUTE_1'])
                for name,shift,curmap,routine in (
                    ('DOOR_DICE',0,'INDIGO_PLATEAU_LOBBY','RogueItemUseDoorDice'),
                    ('MON_DICE',2,'REWARD_ROOM','RogueItemUseMonDice'),
                    ('ITEM_DICE',4,'ROUTE_1','RogueItemUseItemDice')):
                    h.write8('hCurMap',MAPS[curmap])
                    event=EVENTS['EVENT_GOT_ROGUE_POKEMON']
                    address=h.address('wEventFlags')+event//8
                    h.pyboy.memory[address]&=~(1<<(event%8))&255
                    toggle=TOGGLES['TOGGLE_STAGE_RANDOM_ITEM']
                    address=h.address('wToggleableObjectFlags')+toggle//8
                    h.pyboy.memory[address]&=~(1<<(toggle%8))&255
                    h.call_routine(routine,limit=200000)
                    packed-=1<<shift
                    self.assertEqual(h.read8('wDiceCharges'),packed,(name,tier))
                    self.assertEqual(h.read_sram_bytes('sKeyItemsBitfield',4),flags)

    def configure(self,name,tier,active=True):
        h=self.harness
        h.write_sram_bytes('sKeyItemsBitfield',bits([name],[name] if active else []))
        h.write_sram_bytes('sKeyItemTiers',tier_bytes(name,tier))

    def bypass(self,*labels):
        h=self.harness
        def skip(_):
            return_from_call(h)
        for label in labels:
            h.register_hook(label,skip)
            self.addCleanup(h.unregister_hook,label,skip)

    def test_ko_defiance_tier_charges_final_use_and_refusal_controls(self):
        h=self.harness
        h.boot_fight2(seed=17)
        self.bypass('PrintText','PlaySoundWaitForCurrent','UpdateHPBar2','DrawPlayerHUDAndHPBar')
        def faint():
            h.write8('wBattleMonHP',0); h.write8('wBattleMonHP',0,1)
            h.write8('wBattleMonStatus',8)
            for i in range(6):
                h.write8('wPlayerMonStatMods',1,i)
        with isolated_routine_calls(h):
            for tier in range(3):
                self.configure('KO_DEFIANCE',tier)
                h.call_routine('RogueResetRunState')
                self.assertEqual(h.read8('wKODefianceUsages'),tier+1)
                h.write8('wPartyCount',1); h.write8('wPlayerMonNumber',0)
                h.write8('wPartySpecies',255,1)
                h.write8('hCurMap',MAPS['ROUTE_1']); h.write8('wLinkState',0)
                h.write8('wBattleMonMaxHP',0); h.write8('wBattleMonMaxHP',101,1)
                for remaining in range(tier,-1,-1):
                    with self.subTest(tier=tier,remaining=remaining):
                        faint(); h.call_routine('TryKODefiance')
                        self.assertEqual(h.read_bytes('wBattleMonHP',2),[0,50])
                        self.assertEqual(h.read_bytes('wPartyMon1HP',2),[0,50])
                        self.assertEqual(h.read8('wBattleMonStatus'),0)
                        self.assertEqual(h.read8('wPartyMon1Status'),0)
                        self.assertEqual(h.read_bytes('wPlayerMonStatMods',6),[7]*6)
                        self.assertEqual(h.read8('wKODefianceUsages'),remaining)
                faint(); h.call_routine('TryKODefiance')
                self.assertEqual(h.read_bytes('wBattleMonHP',2),[0,0])
            self.configure('KO_DEFIANCE',0)
            h.write8('wKODefianceUsages',1)
            h.write8('wBattleMonMaxHP',0); h.write8('wBattleMonMaxHP',1,1)
            faint(); h.call_routine('TryKODefiance')
            self.assertEqual(h.read_bytes('wBattleMonHP',2),[0,1],'minimum revival is one HP')
            for reason in ('inactive','bench_alive','link','oak'):
                with self.subTest(refusal=reason):
                    self.configure('KO_DEFIANCE',0,reason!='inactive')
                    h.write8('wKODefianceUsages',1)
                    h.write8('wPartyCount',2 if reason=='bench_alive' else 1)
                    h.write8('wPartyMon2HP',0); h.write8('wPartyMon2HP',1,1)
                    h.write8('wLinkState',SERIAL['LINK_STATE_BATTLING'] if reason=='link' else 0)
                    h.write8('hCurMap',MAPS['OAKS_LAB'] if reason=='oak' else MAPS['ROUTE_1'])
                    faint(); h.call_routine('TryKODefiance')
                    self.assertEqual(h.read_bytes('wBattleMonHP',2),[0,0])
                    self.assertEqual(h.read8('wKODefianceUsages'),1)

    def test_rewind_snapshot_full_player_state_enemy_asymmetry_and_charge_gate(self):
        h=self.harness
        h.boot_fight2(seed=17)
        self.bypass('PrintText')
        spans={'wBattleMonHP':2,'wBattleMonStatus':1,'wBattleMonPP':4,
               'wBattleMonAttack':8,'wPlayerMonStatMods':8}
        singles=('wPlayerBattleStatus1','wPlayerBattleStatus2','wPlayerBattleStatus3',
                 'wPlayerDisabledMove','wPlayerDisabledMoveNumber','wPlayerConfusedCounter',
                 'wPlayerToxicCounter','wPlayerSubstituteHP','wPlayerNumAttacksLeft')
        spans.update({name:1 for name in singles})
        def image():
            return {name:h.read_bytes(name,size) for name,size in spans.items()}
        def use():
            h.write8('wCurItem',ITEMS['TURN_REWIND'])
            h.call_routine('BattleKeyItemGate')
            self.assertEqual(h.read8('wActionResultOrTookBattleTurn'),0)
        with isolated_routine_calls(h):
            for tier in range(3):
                self.configure('TURN_REWIND',tier)
                h.call_routine('RogueResetRunState')
                h.write8('hIsInBattle',2); h.write8('wBattleType',0)
                h.write8('wPlayerMonNumber',0)
                h.call_routine('TurnRewindInit')
                original=image(); use()
                self.assertEqual(image(),original)
                self.assertEqual(h.read8('wTurnRewindUsages'),tier+2)
                for name,size in spans.items():
                    for i in range(size):
                        h.write8(name,7 if name=='wPlayerMonStatMods' else i+1,i)
                h.write8('wPlayerBattleStatus3',0)
                saved=image()
                h.call_routine('TurnRewindSnapshot')
                for remaining in range(tier+1,-1,-1):
                    for name,size in spans.items():
                        for i in range(size): h.write8(name,0,i)
                    h.write8('wEnemyMonHP',0); h.write8('wEnemyMonHP',17,1)
                    use()
                    self.assertEqual(image(),saved)
                    self.assertEqual(h.read_bytes('wEnemyMonHP',2),[0,17])
                    self.assertEqual(h.read_bytes('wPartyMon1PP',4),saved['wBattleMonPP'])
                    self.assertEqual(h.read8('wTurnRewindUsages'),remaining)
                h.write8('wBattleMonHP',0); h.write8('wBattleMonHP',5,1)
                before=image(); use()
                self.assertEqual(image(),before)
                h.write8('wTurnRewindUsages',1); h.write8('wPlayerMonNumber',1)
                before=image(); use()
                self.assertEqual(image(),before)
                self.assertEqual(h.read8('wTurnRewindUsages'),1)
            self.assertEqual(h.hook_errors,[])

    def test_three_dice_real_rerolls_final_charge_exhaustion_and_location_gates(self):
        h=self.harness
        h.boot_to_lobby(battle_count=1)
        self.bypass('PrintText')
        calls=[]
        observed=('SelectAndPatchLobbyExit','rogue_pokemon_randomized_batch','Random_Item_Selection',
                  'RefreshBallRarityCache')
        for label in observed:
            def record(_,name=label): calls.append(name)
            h.register_hook(label,record)
            self.addCleanup(h.unregister_hook,label,record)
        with isolated_routine_calls(h):
            for name,shift,curmap,producer in (
                ('DOOR_DICE',0,'INDIGO_PLATEAU_LOBBY','SelectAndPatchLobbyExit'),
                ('MON_DICE',2,'REWARD_ROOM','rogue_pokemon_randomized_batch'),
                ('ITEM_DICE',4,'ROUTE_1','Random_Item_Selection')):
                for tier in range(3):
                    with self.subTest(item=name,tier=tier):
                        self.configure(name,tier)
                        h.call_routine('RogueResetRunState')
                        self.assertEqual((h.read8('wDiceCharges')>>shift)&3,tier+1)
                        h.write8('hCurMap',MAPS[curmap])
                        h.write8('wRogueFlagsBitfield',0)
                        h.write8('wGymChoice',0)
                        for label in ('wDebug2ForcedDoor1','wDebug2ForcedDoor2'):
                            h.write8(label,MAPS['ROUTE_1'])
                        event=EVENTS['EVENT_GOT_ROGUE_POKEMON']
                        address=h.address('wEventFlags')+event//8
                        h.pyboy.memory[address]&=~(1<<(event%8))&255
                        toggle=TOGGLES['TOGGLE_STAGE_RANDOM_ITEM']
                        address=h.address('wToggleableObjectFlags')+toggle//8
                        h.pyboy.memory[address]&=~(1<<(toggle%8))&255
                        routine={'DOOR_DICE':'RogueItemUseDoorDice','MON_DICE':'RogueItemUseMonDice',
                                 'ITEM_DICE':'RogueItemUseItemDice'}[name]
                        other=h.read8('wDiceCharges')&~(3<<shift)
                        for remaining in range(tier,-1,-1):
                            calls.clear()
                            h.call_routine(routine,limit=200000)
                            self.assertIn(producer,calls)
                            self.assertEqual(h.read8('wDiceCharges'),other|(remaining<<shift))
                            if name=='DOOR_DICE':
                                self.assertNotEqual(h.read8('wLobbyDoor1StageMap'),0)
                                self.assertNotEqual(h.read8('wLobbyDoor2StageMap'),0)
                            elif name=='MON_DICE':
                                self.assertTrue(all(h.read8(f'wRoguePokemon{i}') not in (0,255) for i in range(1,4)))
                            else:
                                self.assertNotIn(h.read8('wRogueItem'),(0,255))
                                self.assertIn('RefreshBallRarityCache',calls)
                        calls.clear(); h.call_routine(routine)
                        self.assertNotIn(producer,calls)
                        self.assertEqual(h.read8('wDiceCharges'),other)
                        h.write8('wDiceCharges',other|(1<<shift))
                        h.write8('hCurMap',MAPS['PALLET_TOWN'])
                        calls.clear(); h.call_routine(routine)
                        self.assertNotIn(producer,calls)
                        self.assertEqual(h.read8('wDiceCharges'),other|(1<<shift))
                        h.write8('hCurMap',MAPS[curmap])
                        if name=='MON_DICE':
                            h.set_event(EVENTS['EVENT_GOT_ROGUE_POKEMON'])
                        elif name=='ITEM_DICE':
                            toggle=TOGGLES['TOGGLE_STAGE_RANDOM_ITEM']
                            address=h.address('wToggleableObjectFlags')+toggle//8
                            h.pyboy.memory[address]|=1<<(toggle%8)
                        else:
                            h.write8('wRogueFlagsBitfield',1<<RAM['BIT_WITCH_ACCEPTED'])
                            h.write8('wWitchChallenge',RAM['CHALLENGE_LEGENDARY_BOSS'])
                            def no(_):
                                h.write8('hCurrentMenuItem',1)
                                return_from_call(h)
                            h.register_hook('YesNoChoice',no)
                        try:
                            calls.clear(); h.call_routine(routine)
                            self.assertNotIn(producer,calls)
                            self.assertEqual(h.read8('wDiceCharges'),other|(1<<shift))
                        finally:
                            if name=='DOOR_DICE': h.unregister_hook('YesNoChoice',no)
                        if name=='ITEM_DICE':
                            h.pyboy.memory[address]&=~(1<<(toggle%8))&255
                            h.write8('hCurMap',MAPS['PROCEDURAL_CAVE_1'])
                            calls.clear(); h.call_routine(routine)
                            self.assertNotIn(producer,calls)
                            self.assertEqual(h.read8('wDiceCharges'),other|(1<<shift))
            self.assertEqual(h.hook_errors,[])


if __name__=='__main__':
    import unittest
    unittest.main(verbosity=2)
