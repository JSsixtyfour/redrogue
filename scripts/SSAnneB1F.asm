; UNIQUE STAGE: SS Anne B1F has custom multi-room door/lock mechanics and a separate
; EVENT_SSANNE_ALL_TRAINERS_DEFEATED gate. Reward trigger handled via custom flow,
; not the standard ALL_TRAINERS_MASK pattern.
SSAnneB1F_Script:
    CheckEvent EVENT_SSANNE_ALL_TRAINERS_DEFEATED
    jr z, .rogue
    
    .entry
   
    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal
    
    SetEvent EVENT_ENTER_ROOM
    ld hl, wRogueFlagsBitfield
    set 0, [hl]                 ; gym is next after this route

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh
    
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef HideObject
    
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef HideObject

    

    .normal
    ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_2, [hl]
	res BIT_CUR_MAP_LOADED_2, [hl]
	call nz, .initial
    
    .normal_2
	call EnableAutoTextBoxDrawing
	;ld hl, SSAnneB1FTrainerHeaders
	ld de, SSAnneB1F_ScriptPointers
	ld a, [wSSAnneB1FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wSSAnneB1FCurScript], a
	ret
    
    
    .rogue
    CheckEvent EVENT_BEAT_SS_ANNE_10_TRAINER_0
    jr z, .entry
    CheckEvent EVENT_BEAT_SS_ANNE_10_TRAINER_1
    jr z, .entry
    CheckEvent EVENT_BEAT_SS_ANNE_10_TRAINER_2
    jr z, .entry
    CheckEvent EVENT_BEAT_SS_ANNE_10_TRAINER_3
    jp z, .entry
    CheckEvent EVENT_BEAT_SS_ANNE_10_TRAINER_4
    jp z, .entry

    SetEvent EVENT_SSANNE_ALL_TRAINERS_DEFEATED
    
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef ShowObject
    
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef ShowObject
    
    ld a, TOGGLE_ROGUE_REWARD_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef ShowObject
    
    ld a, TOGGLE_SS_ANNE_B1F_CAPTAIN
    ld [wToggleableObjectIndex], a
    predef HideObject
     
    jp .entry
    
    .initial
    CheckEvent EVENT_SSANNE_ALL_TRAINERS_DEFEATED
    jr z, .normal_2
    xor a
	ldh [hJoyHeld], a
	ld a, TEXT_SSANNEB1F_SAILOR
	ldh [hTextID], a
	call DisplayTextID
    jp .normal_2
    

	RogueAutoWalkScripts SSAnneB1F, PAD_RIGHT, CheckFightingMapTrainers, EVENT_AUTOWALKED_INTO_SS_ANNE_B1F, TEXT_SSANNEB1F_NO_TURNING_BACK, SCRIPT_SSANNEB1F_PLAYER_IS_MOVING, wSSAnneB1FCurScript

SSAnneB1FEntranceCoords:
	dbmapcoord 3, 15
	db -1

SSAnneB1FNoCoords:
	dbmapcoord 3, 14
	dbmapcoord 3, 13
	db -1

SSAnneB1F_ScriptPointers:
	def_script_pointers
	dw_const SSAnneB1FDefaultScript,                SCRIPT_SSANNEB1F_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_SSANNEB1F_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_SSANNEB1F_END_BATTLE
	dw_const SSAnneB1FPlayerIsMovingScript,         SCRIPT_SSANNEB1F_PLAYER_IS_MOVING

SSAnneB1F_TextPointers:
	def_text_pointers
	dw_const SSAnneB1FCaptainText, TEXT_SSANNEB1F_CAPTAIN
	dw_const SSAnneB1FSailorText, TEXT_SSANNEB1F_SAILOR
	dw_const SSAnneB1FJrTrainerM3Text, TEXT_SSANNEB1F_JR_TRAINER_M3
	dw_const SSAnneB1FJrTrainerM4Text, TEXT_SSANNEB1F_JR_TRAINER_M4
	dw_const SSAnneB1FJrTrainerM5Text, TEXT_SSANNEB1F_JR_TRAINER_M5
    dw_const RandomPickUpItemText,     TEXT_SSANNEB1F_RANDOM
    dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_1, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_1
    dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_2, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_2
    dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_3, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_3
    dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_1, TEXT_SSANNEB1F_ROGUE_TRADE_NPC
    dw_const Rogue_SSAnneB1F_Reward_Text, TEXT_SSANNEB1F_REWARD_VENDOR_1
    EXPORT TEXT_SSANNEB1F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const SSAnneB1FNoTurningBackText, TEXT_SSANNEB1F_NO_TURNING_BACK


SSAnneB1FCaptainText:
	text_far _SSAnneB1FCaptainText
	text_end

SSAnneB1FSailorText:
    text_asm
    CheckEvent EVENT_SSANNE_ALL_TRAINERS_DEFEATED
    jr nz, .reward
    
	text_far _SSAnneB1FSailorText
	text_end
    
    ld hl, .SSAnneB1FSailorText
	call PrintText
	jr .done
    
    .reward
    CheckEvent EVENT_GOT_ROGUE_POKEMON
    jr z, .GetMon

    ld hl, SSAnneB1FGreedyText
    call PrintText
    jr .done

    .GetMon
    xor a
    ld a, TEXT_SSANNEB1F_REWARD_VENDOR_1
    ldh [hTextID], a
    call DisplayTextID
    call DisableWaitingAfterTextDisplay
    .done
    jp TextScriptEnd
    
.SSAnneB1FSailorText
text_far _SSAnneB1FSailorText
text_end

Rogue_SSAnneB1F_Reward_Text:
script_rogue_reward

SSAnneB1F_Rogue_Reward_Script_PokeballText_1:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_1
farcall Rogue_Reward_Script_PokeballText_1
jp TextScriptEnd

SSAnneB1F_Rogue_Reward_Script_PokeballText_2:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_2
farcall Rogue_Reward_Script_PokeballText_2
jp TextScriptEnd

SSAnneB1F_Rogue_Reward_Script_PokeballText_3:
text_asm
ld d, TOGGLE_ROGUE_REWARD_POKEBALL_3
farcall Rogue_Reward_Script_PokeballText_3
jp TextScriptEnd

SSAnneB1FNoTurningBackText:
	text_far _NoTurningBackText
	text_end

SSAnneB1FGreedyText:
	text_far _GreedyText
	text_end

SSAnneB1FJrTrainerM3Text:
	text_far _SSAnneB1FCaptainText
	text_end
    
SSAnneB1FJrTrainerM4Text:
	text_far _SSAnneB1FCaptainText
	text_end
    
SSAnneB1FJrTrainerM5Text:
	text_far _SSAnneB1FCaptainText
	text_end