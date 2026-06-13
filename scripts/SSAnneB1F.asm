SSAnneB1F_Script:

    CheckEvent EVENT_ENTER_ROOM
    jr nz, .normal

    SetEvent EVENT_ENTER_ROOM
    ld hl, wRogueFlagsBitfield
    set 0, [hl]                 ; gym is next after this route

    ResetEvent EVENT_GOT_ROGUE_POKEMON

    farcall rogue_pokemon_randomized_batch
    farcall Random_Item_Selection
    farcall RogueRefresh

    .normal
	call EnableAutoTextBoxDrawing
	ld hl, SSAnneB1FTrainerHeaders
	ld de, SSAnneB1F_ScriptPointers
	ld a, [wSSAnneB1FCurScript]
	call ExecuteCurMapScriptInTable
	ld [wSSAnneB1FCurScript], a
	ret

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
	dw_const SSAnneB1FJrTrainerM1Text, TEXT_SSANNEB1F_JR_TRAINER_M1
	dw_const SSAnneB1FJrTrainerM2Text, TEXT_SSANNEB1F_JR_TRAINER_M2
	dw_const SSAnneB1FJrTrainerM3Text, TEXT_SSANNEB1F_JR_TRAINER_M3
	dw_const SSAnneB1FJrTrainerM4Text, TEXT_SSANNEB1F_JR_TRAINER_M4
	dw_const SSAnneB1FJrTrainerM5Text, TEXT_SSANNEB1F_JR_TRAINER_M5
    dw_const RandomPickUpItemText,     TEXT_SSANNEB1F_RANDOM
    dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_1, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_1
    dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_2, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_2
    dw_const SSAnneB1F_Rogue_Reward_Script_PokeballText_3, TEXT_SSANNEB1F_ROGUE_REWARD_POKEBALL_3
    dw_const Rogue_SSAnneB1F_Reward_Text, TEXT_SSANNEB1F_REWARD_VENDOR_1
    EXPORT TEXT_SSANNEB1F_REWARD_VENDOR_1 ; used by engine/events/rogue_reward_menu.asm
	dw_const SSAnneB1FNoTurningBackText, TEXT_SSANNEB1F_NO_TURNING_BACK

SSAnneB1FTrainerHeaders:
	def_trainers 1
SSAnneB1FTrainerHeader0:
	trainer EVENT_BEAT_SS_ANNE_B1F_TRAINER_0, 1, SSAnneB1FJrTrainerM1BattleText, SSAnneB1FJrTrainerM1EndBattleText, SSAnneB1FJrTrainerM1AfterBattleText
SSAnneB1FTrainerHeader1:
	trainer EVENT_BEAT_SS_ANNE_B1F_TRAINER_1, 1, SSAnneB1FJrTrainerM2BattleText, SSAnneB1FJrTrainerM2EndBattleText, SSAnneB1FJrTrainerM2AfterBattleText
SSAnneB1FTrainerHeader2:
	trainer EVENT_BEAT_SS_ANNE_B1F_TRAINER_2, 1, SSAnneB1FJrTrainerM3BattleText, SSAnneB1FJrTrainerM3EndBattleText, SSAnneB1FJrTrainerM3AfterBattleText
SSAnneB1FTrainerHeader3:
	trainer EVENT_BEAT_SS_ANNE_B1F_TRAINER_3, 1, SSAnneB1FJrTrainerM4BattleText, SSAnneB1FJrTrainerM4EndBattleText, SSAnneB1FJrTrainerM4AfterBattleText
SSAnneB1FTrainerHeader4:
	trainer EVENT_BEAT_SS_ANNE_B1F_TRAINER_4, 1, SSAnneB1FJrTrainerM5BattleText, SSAnneB1FJrTrainerM5EndBattleText, SSAnneB1FJrTrainerM5AfterBattleText
	db -1 ; end

SSAnneB1FJrTrainerM1Text:
	text_asm
	ld hl, SSAnneB1FTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

SSAnneB1FJrTrainerM1BattleText:
	text_far _SSAnneB1FJrTrainerM1BattleText
	text_end

SSAnneB1FJrTrainerM1EndBattleText:
	text_far _SSAnneB1FJrTrainerM1EndBattleText
	text_end

SSAnneB1FJrTrainerM1AfterBattleText:
	text_far _SSAnneB1FJrTrainerM1AfterBattleText
	text_end

SSAnneB1FJrTrainerM2Text:
	text_asm
	ld hl, SSAnneB1FTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

SSAnneB1FJrTrainerM2BattleText:
	text_far _SSAnneB1FJrTrainerM1BattleText
	text_end

SSAnneB1FJrTrainerM2EndBattleText:
	text_far _SSAnneB1FJrTrainerM1EndBattleText
	text_end

SSAnneB1FJrTrainerM2AfterBattleText:
	text_far _SSAnneB1FJrTrainerM1AfterBattleText
	text_end

SSAnneB1FJrTrainerM3Text:
	text_asm
	ld hl, SSAnneB1FTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

SSAnneB1FJrTrainerM3BattleText:
	text_far _SSAnneB1FJrTrainerM1BattleText
	text_end

SSAnneB1FJrTrainerM3EndBattleText:
	text_far _SSAnneB1FJrTrainerM1EndBattleText
	text_end

SSAnneB1FJrTrainerM3AfterBattleText:
	text_far _SSAnneB1FJrTrainerM1AfterBattleText
	text_end

SSAnneB1FJrTrainerM4Text:
	text_asm
	ld hl, SSAnneB1FTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

SSAnneB1FJrTrainerM4BattleText:
	text_far _SSAnneB1FJrTrainerM1BattleText
	text_end

SSAnneB1FJrTrainerM4EndBattleText:
	text_far _SSAnneB1FJrTrainerM1EndBattleText
	text_end

SSAnneB1FJrTrainerM4AfterBattleText:
	text_far _SSAnneB1FJrTrainerM1AfterBattleText
	text_end

SSAnneB1FJrTrainerM5Text:
	text_asm
	ld hl, SSAnneB1FTrainerHeader4
	call TalkToTrainer
	jp TextScriptEnd

SSAnneB1FJrTrainerM5BattleText:
	text_far _SSAnneB1FJrTrainerM1BattleText
	text_end

SSAnneB1FJrTrainerM5EndBattleText:
	text_far _SSAnneB1FJrTrainerM1EndBattleText
	text_end

SSAnneB1FJrTrainerM5AfterBattleText:
    text_asm
    farcall Delay3
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
