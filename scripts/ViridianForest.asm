DEF VIRIDIAN_FOREST_ALL_TRAINERS_MASK EQU (1 << (EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0 % 8)) \
	| (1 << (EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_1 % 8)) \
	| (1 << (EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_2 % 8)) \
	| (1 << (EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_3 % 8)) \
	| (1 << (EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_4 % 8))

ViridianForest_Script:
	
    
    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal
    
    SetEvent EVENT_ENTER_ROOM
    ld hl, wRogueFlagsBitfield
    set 0, [hl]                 ; gym is next after this route
    
    ResetEvent EVENT_GOT_ROGUE_POKEMON
    ResetEvent EVENT_ROGUE_POKEMON_OFFERED
    
    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh
    
    .normal
    CheckEvent EVENT_ROGUE_POKEMON_OFFERED
    jr nz, .afterRewardCheck
    ld a, [wStatusFlags3]
    bit BIT_PRINT_END_BATTLE_TEXT, a
    jr nz, .afterRewardCheck
    ld a, [wEventFlags + (EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0 / 8)]
    and VIRIDIAN_FOREST_ALL_TRAINERS_MASK
    cp VIRIDIAN_FOREST_ALL_TRAINERS_MASK
    jr nz, .afterRewardCheck
    SetEvent EVENT_ROGUE_POKEMON_OFFERED
    farcall Delay3
    ld a, TEXT_VIRIDIANFOREST_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .afterRewardCheck
    call EnableAutoTextBoxDrawing
	ld hl, ViridianForestTrainerHeaders
	ld de, ViridianForest_ScriptPointers
	ld a, [wViridianForestCurScript]
	call ExecuteCurMapScriptInTable
	ld [wViridianForestCurScript], a
	ret

	RogueAutoWalkScripts ViridianForest, PAD_UP, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_VIRIDIAN_FOREST, TEXT_VIRIDIANFOREST_NO_TURNING_BACK, SCRIPT_VIRIDIANFOREST_PLAYER_IS_MOVING, wViridianForestCurScript

ViridianForestEntranceCoords:
	dbmapcoord 33, 11
	dbmapcoord 33, 12
	dbmapcoord 33, 13
	dbmapcoord 33, 14
	db -1

ViridianForestNoCoords:
	dbmapcoord 32, 11
	dbmapcoord 32, 12
	dbmapcoord 32, 13
	dbmapcoord 32, 14
	dbmapcoord 31, 11
	dbmapcoord 31, 12
	dbmapcoord 31, 13
	dbmapcoord 31, 14
	db -1

ViridianForest_ScriptPointers:
	def_script_pointers
	dw_const ViridianForestDefaultScript,           SCRIPT_VIRIDIANFOREST_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_VIRIDIANFOREST_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_VIRIDIANFOREST_END_BATTLE
	dw_const ViridianForestPlayerIsMovingScript,    SCRIPT_VIRIDIANFOREST_PLAYER_IS_MOVING

ViridianForest_TextPointers:
	def_text_pointers
	dw_const ViridianForestNoTurningBackText,   TEXT_VIRIDIANFOREST_NO_TURNING_BACK
	dw_const ViridianForestYoungster2Text,      TEXT_VIRIDIANFOREST_YOUNGSTER2
	dw_const ViridianForestYoungster3Text,      TEXT_VIRIDIANFOREST_YOUNGSTER3
	dw_const ViridianForestYoungster4Text,      TEXT_VIRIDIANFOREST_YOUNGSTER4
    dw_const ViridianForestYoungster5Text,      TEXT_VIRIDIANFOREST_YOUNGSTER5
    dw_const ViridianForestCooltrainer_FText,   TEXT_VIRIDIANFOREST_COOLTRAINER_F
    dw_const RandomPickUpItemText,              TEXT_VIRIDIANFOREST_RANDOM
    dw_const ViridianForestRogue_Reward_Script_PokeballText_1, TEXT_VIRIDIANFOREST_ROGUE_REWARD_POKEBALL_1
    dw_const ViridianForestRogue_Reward_Script_PokeballText_2, TEXT_VIRIDIANFOREST_ROGUE_REWARD_POKEBALL_2
    dw_const ViridianForestRogue_Reward_Script_PokeballText_3, TEXT_VIRIDIANFOREST_ROGUE_REWARD_POKEBALL_3
    dw_const ViridianForestRogue_Reward_Script_PokeballText_1, TEXT_VIRIDIANFOREST_ROGUE_TRADE_NPC
    dw_const ViridianForestYoungster1Text,      TEXT_VIRIDIANFOREST_YOUNGSTER1
    dw_const PickUpItemText,                    TEXT_VIRIDIANFOREST_ANTIDOTE
	dw_const PickUpItemText,                    TEXT_VIRIDIANFOREST_POTION
    dw_const Rogue_ViridianForest_Reward_Text, TEXT_VIRIDIANFOREST_REWARD_VENDOR_1
    EXPORT TEXT_VIRIDIANFOREST_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
    
	dw_const ViridianForestTrainerTips1Text,    TEXT_VIRIDIANFOREST_TRAINER_TIPS1
	dw_const ViridianForestUseAntidoteSignText, TEXT_VIRIDIANFOREST_USE_ANTIDOTE_SIGN
	dw_const ViridianForestTrainerTips2Text,    TEXT_VIRIDIANFOREST_TRAINER_TIPS2
	dw_const ViridianForestTrainerTips3Text,    TEXT_VIRIDIANFOREST_TRAINER_TIPS3
	dw_const ViridianForestTrainerTips4Text,    TEXT_VIRIDIANFOREST_TRAINER_TIPS4
	dw_const ViridianForestLeavingSignText,     TEXT_VIRIDIANFOREST_LEAVING_SIGN
    

ViridianForestTrainerHeaders:
	def_trainers 1
ViridianForestTrainerHeader0:
	trainer EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_0, 4, ViridianForestYoungster2BattleText, ViridianForestYoungster2EndBattleText, ViridianForestYoungster2AfterBattleText
ViridianForestTrainerHeader1:
	trainer EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_1, 4, ViridianForestYoungster3BattleText, ViridianForestYoungster3EndBattleText, ViridianForestYoungster3AfterBattleText
ViridianForestTrainerHeader2:
	trainer EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_2, 4, ViridianForestYoungster4BattleText, ViridianForestYoungster4EndBattleText, ViridianForestYoungster4AfterBattleText
ViridianForestTrainerHeader3:
	trainer EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_3, 4, ViridianForestYoungster5BattleText, ViridianForestYoungster5EndBattleText, ViridianForestYoungster5AfterBattleText
ViridianForestTrainerHeader4:
	trainer EVENT_BEAT_VIRIDIAN_FOREST_TRAINER_4, 4, ViridianForestCooltrainer_FBattleText, ViridianForestCooltrainer_FEndBattleText, ViridianForestCooltrainer_FAfterBattleText
	db -1 ; end
    


ViridianForestYoungster1Text:
	text_far _ViridianForestYoungster1Text
	text_end

ViridianForestYoungster2Text:
	text_asm
	ld hl, ViridianForestTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

ViridianForestYoungster3Text:
	text_asm
	ld hl, ViridianForestTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

ViridianForestYoungster4Text:
	text_asm
	ld hl, ViridianForestTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd
    
ViridianForestYoungster5Text:
	text_asm
	ld hl, ViridianForestTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

ViridianForestYoungster2BattleText:
	text_far _ViridianForestYoungster2BattleText
	text_end

ViridianForestYoungster2EndBattleText:
	text_far _ViridianForestYoungster2EndBattleText
	text_end

ViridianForestYoungster2AfterBattleText:
	text_far _ViridianForestYoungster2AfterBattleText
	text_end

ViridianForestYoungster3BattleText:
	text_far _ViridianForestYoungster3BattleText
	text_end

ViridianForestYoungster3EndBattleText:
	text_far _ViridianForestYoungster3EndBattleText
	text_end

ViridianForestYoungster3AfterBattleText:
	text_far _ViridianForestYoungster3AfterBattleText
	text_end

ViridianForestYoungster4BattleText:
	text_far _ViridianForestYoungster4BattleText
	text_end

ViridianForestYoungster4EndBattleText:
	text_far _ViridianForestYoungster4EndBattleText
	text_end

ViridianForestYoungster4AfterBattleText:
	text_far _ViridianForestYoungster4AfterBattleText
	text_end

ViridianForestYoungster5BattleText:
	text_far _ViridianForestYoungster4BattleText
	text_end

ViridianForestYoungster5EndBattleText:
	text_far _ViridianForestYoungster4EndBattleText
	text_end

ViridianForestYoungster5AfterBattleText:
	text_far _ViridianForestYoungster4AfterBattleText
	text_end
    
ViridianForestYoungster6Text:
	text_far _ViridianForestYoungster5Text
	text_end

ViridianForestTrainerTips1Text:
	text_far _ViridianForestTrainerTips1Text
	text_end

ViridianForestUseAntidoteSignText:
	text_far _ViridianForestUseAntidoteSignText
	text_end

ViridianForestTrainerTips2Text:
	text_far _ViridianForestTrainerTips2Text
	text_end

ViridianForestTrainerTips3Text:
	text_far _ViridianForestTrainerTips3Text
	text_end

ViridianForestTrainerTips4Text:
	text_far _ViridianForestTrainerTips4Text
	text_end

ViridianForestLeavingSignText:
	text_far _ViridianForestLeavingSignText
	text_end
    
ViridianForestCooltrainer_FText:
	text_asm
	ld hl, ViridianForestTrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd
    
ViridianForestCooltrainer_FBattleText:
	text_far _ViridianForestYoungster4BattleText
	text_end

ViridianForestCooltrainer_FEndBattleText:
	text_far _ViridianForestYoungster4EndBattleText
	text_end

ViridianForestCooltrainer_FAfterBattleText:
    text_asm
	farcall Delay3
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon
   
    ld hl, viridianforestGreedyText
	call PrintText
	jr .done
    
    .GetMon
    xor a
    ld a, TEXT_VIRIDIANFOREST_REWARD_VENDOR_1
	ldh [hTextID], a
	call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd

Rogue_ViridianForest_Reward_Text:
script_rogue_reward


ViridianForestRogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

ViridianForestRogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

ViridianForestRogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd


viridianforestGreedyText:
	text_far _GreedyText
	text_end

ViridianForestNoTurningBackText:
	text_far _NoTurningBackText
	text_end