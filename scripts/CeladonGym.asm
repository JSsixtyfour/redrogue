CeladonGym_Script:
    call ErikaShowOrHideExitBlock
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_2, [hl]
	res BIT_CUR_MAP_LOADED_2, [hl]
	call nz, .initial
	call EnableAutoTextBoxDrawing
	ld hl, CeladonGymTrainerHeaders
	ld de, CeladonGym_ScriptPointers
	ld a, [wCeladonGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wCeladonGymCurScript], a
	ret
    
.initial:
    farcall GymLeaderRandomItem
	ld hl, .CityName
	ld de, .LeaderName
	jp LoadGymLeaderAndCityName

.CityName:
	db "CELADON CITY@"

.LeaderName:
	db "ERIKA@"
    
ErikaShowOrHideExitBlock:
; Blocks or clears the exit to the next room.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_ERIKA
	jr z, .blockExitToNextRoom
	ld a, $5
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $24
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

CeladonGymResetScripts:
	xor a ; SCRIPT_CELADONGYM_DEFAULT
	ldh [hJoyIgnore], a
	ld [wCeladonGymCurScript], a
	ld [wCurMapScript], a
	ret

CeladonGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_CELADONGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_CELADONGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_CELADONGYM_END_BATTLE
	dw_const CeladonGymErikaPostBattleScript,       SCRIPT_CELADONGYM_ERIKA_POST_BATTLE

CeladonGymErikaPostBattleScript:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, CeladonGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a

CeladonGymReceiveTM21:
	ld a, TEXT_CELADONGYM_RAINBOWBADGE_INFO
	ldh [hTextID], a
	call DisplayTextID
	
	ld a, [wRogueItem]      ; load TM
    ld b, a
	ld c, 1                 ; load amount of TM
	call GiveItem
	jr nc, .BagFull
    ld a, [wRogueItem]      ; load TM
    ld [wNamedObjectIndex], a   ; place item id in spot for GetItemName
    call GetItemName         ; get name of item to receive
	ld a, TEXT_CELADONGYM_RECEIVED_TM21
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM21
	jr .gymVictory
.BagFull
	ld a, TEXT_CELADONGYM_TM21_NO_ROOM
	ldh [hTextID], a
	call DisplayTextID
.gymVictory
	ld hl, wObtainedBadges
	set BIT_RAINBOWBADGE, [hl]

	jp CeladonGymResetScripts

CeladonGym_TextPointers:
	def_text_pointers
	dw_const CeladonGymErikaText,            TEXT_CELADONGYM_ERIKA
	dw_const CeladonGymCooltrainerF1Text,    TEXT_CELADONGYM_COOLTRAINER_F1
	dw_const CeladonGymBeauty1Text,          TEXT_CELADONGYM_BEAUTY1
	dw_const CeladonGymBeauty2Text,          TEXT_CELADONGYM_BEAUTY2
	dw_const CeladonGymCooltrainerF2Text,    TEXT_CELADONGYM_COOLTRAINER_F2
	dw_const CeladonGymRainbowBadgeInfoText, TEXT_CELADONGYM_RAINBOWBADGE_INFO
	dw_const CeladonGymReceivedTM21Text,     TEXT_CELADONGYM_RECEIVED_TM21
	dw_const CeladonGymTM21NoRoomText,       TEXT_CELADONGYM_TM21_NO_ROOM

CeladonGymTrainerHeaders:
	def_trainers 2
CeladonGymTrainerHeader0:
	trainer EVENT_BEAT_CELADON_GYM_TRAINER_0, 4, CeladonGymBattleText2, CeladonGymEndBattleText2, CeladonGymAfterBattleText2
CeladonGymTrainerHeader1:
	trainer EVENT_BEAT_CELADON_GYM_TRAINER_1, 4, CeladonGymBattleText3, CeladonGymEndBattleText3, CeladonGymAfterBattleText3
CeladonGymTrainerHeader2:
	trainer EVENT_BEAT_CELADON_GYM_TRAINER_2, 1, CeladonGymBattleText4, CeladonGymEndBattleText4, CeladonGymAfterBattleText4
CeladonGymTrainerHeader3:
	trainer EVENT_BEAT_CELADON_GYM_TRAINER_3, 3, CeladonGymBattleText5, CeladonGymEndBattleText5, CeladonGymAfterBattleText5
	db -1 ; end

CeladonGymErikaText:
	text_asm
	CheckEvent EVENT_BEAT_ERIKA
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM21
	jr nz, .afterBeat
	call z, CeladonGymReceiveTM21
	call DisableWaitingAfterTextDisplay
	jr .done
.afterBeat
	ld hl, .PostBattleAdviceText
	call PrintText
	jr .done
.beforeBeat
	ld hl, .PreBattleText
	call PrintText
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, .ReceivedRainbowBadgeText
	ld de, .ReceivedRainbowBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	call EngageMapTrainer
	;call InitBattleEnemyParameters
    ld d, OPP_ERIKA
    farcall InitGymBattle
	ld a, $4
	ld [wGymLeaderNo], a
	ld a, SCRIPT_CELADONGYM_ERIKA_POST_BATTLE
	ld [wCeladonGymCurScript], a
	ld [wCurMapScript], a
.done
	jp TextScriptEnd

.PreBattleText:
	text_far _CeladonGymErikaPreBattleText
	text_end

.ReceivedRainbowBadgeText:
    text_asm
    SetEvent EVENT_BEAT_ERIKA
	ld hl, .CeladonGymErikaReceivedRainbowBadgeText
    call PrintText
    jp TextScriptEnd
    text_promptbutton
	text_end

.CeladonGymErikaReceivedRainbowBadgeText
    text_far _CeladonGymErikaReceivedRainbowBadgeText
    text_end

.PostBattleAdviceText:
	text_far _CeladonGymErikaPostBattleAdviceText
	text_end

CeladonGymRainbowBadgeInfoText:
	text_far _CeladonGymRainbowBadgeInfoText
	text_end

CeladonGymReceivedTM21Text:
	text_far _CeladonGymReceivedTM21Text
	sound_get_item_1
	text_far _TM21ExplanationText
	text_end

CeladonGymTM21NoRoomText:
	text_far _CeladonGymTM21NoRoomText
	text_end

CeladonGymCooltrainerF1Text:
	text_asm
	ld hl, CeladonGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

CeladonGymBattleText2:
	text_far _CeladonGymBattleText2
	text_end

CeladonGymEndBattleText2:
	text_far _CeladonGymEndBattleText2
	text_end

CeladonGymAfterBattleText2:
	text_far _CeladonGymAfterBattleText2
	text_end

CeladonGymBeauty1Text:
	text_asm
	ld hl, CeladonGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

CeladonGymBattleText3:
	text_far _CeladonGymBattleText3
	text_end

CeladonGymEndBattleText3:
	text_far _CeladonGymEndBattleText3
	text_end

CeladonGymAfterBattleText3:
	text_far _CeladonGymAfterBattleText3
	text_end

CeladonGymCooltrainerF2Text:
	text_asm
	ld hl, CeladonGymTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

CeladonGymBattleText4:
	text_far _CeladonGymBattleText4
	text_end

CeladonGymEndBattleText4:
	text_far _CeladonGymEndBattleText4
	text_end

CeladonGymAfterBattleText4:
	text_far _CeladonGymAfterBattleText4
	text_end

CeladonGymBeauty2Text:
	text_asm
	ld hl, CeladonGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

CeladonGymBattleText5:
	text_far _CeladonGymBattleText5
	text_end

CeladonGymEndBattleText5:
	text_far _CeladonGymEndBattleText5
	text_end

CeladonGymAfterBattleText5:
	text_far _CeladonGymAfterBattleText5
	text_end

