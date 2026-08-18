CeruleanGym_Script:
    call MistyShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	call z, .initial
	call EnableAutoTextBoxDrawing
	ld hl, CeruleanGymTrainerHeaders
	ld de, CeruleanGym_ScriptPointers
	ld a, [wCeruleanGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wCeruleanGymCurScript], a
	ret

.initial:
	SetEvent EVENT_ENTER_ROOM
    farcall GymLeaderRandomItem
	ld hl, .CityName
	ld de, .LeaderName
	jp LoadGymLeaderAndCityName

.CityName:
	db "CERULEAN CITY@"

.LeaderName:
	db "MISTY@"
    
MistyShowOrHideExitBlock:
; Blocks or clears the exit to the next room.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_MISTY
	jr z, .blockExitToNextRoom
	ld a, $5
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $24
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

CeruleanGymResetScripts:
	xor a ; SCRIPT_CERULEANGYM_DEFAULT
	ldh [hJoyIgnore], a
	ld [wCeruleanGymCurScript], a
	ld [wCurMapScript], a
	ret

CeruleanGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_CERULEANGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_CERULEANGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_CERULEANGYM_END_BATTLE
	dw_const CeruleanGymMistyPostBattleScript,      SCRIPT_CERULEANGYM_MISTY_POST_BATTLE

CeruleanGymMistyPostBattleScript:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, CeruleanGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a

CeruleanGymReceiveTM11:
	ld a, TEXT_CERULEANGYM_MISTY_CASCADE_BADGE_INFO
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
	ld a, TEXT_CERULEANGYM_MISTY_RECEIVED_TM11
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM11
	jr .gymVictory
.BagFull
	ld a, TEXT_CERULEANGYM_MISTY_TM11_NO_ROOM
	ldh [hTextID], a
	call DisplayTextID
.gymVictory
	ld hl, wObtainedBadges
	set BIT_CASCADEBADGE, [hl]
	ld hl, wRogueFlagsBitfield
	res 0, [hl]                 ; route is next after this gym

	jp CeruleanGymResetScripts

CeruleanGym_TextPointers:
	def_text_pointers
	dw_const CeruleanGymMistyText,                 TEXT_CERULEANGYM_MISTY
    dw_const CeruleanGymSwimmer1Text,              TEXT_CERULEANGYM_SWIMMER_1
    dw_const CeruleanGymSwimmer2Text,              TEXT_CERULEANGYM_SWIMMER_2
    dw_const CeruleanGymSwimmer3Text,              TEXT_CERULEANGYM_SWIMMER_3
	dw_const CeruleanGymCooltrainerFText,          TEXT_CERULEANGYM_COOLTRAINER_F
	dw_const CeruleanGymGymGuideText,              TEXT_CERULEANGYM_GYM_GUIDE
	dw_const CeruleanGymMistyCascadeBadgeInfoText, TEXT_CERULEANGYM_MISTY_CASCADE_BADGE_INFO
	dw_const CeruleanGymMistyReceivedTM11Text,     TEXT_CERULEANGYM_MISTY_RECEIVED_TM11
	dw_const CeruleanGymMistyTM11NoRoomText,       TEXT_CERULEANGYM_MISTY_TM11_NO_ROOM

CeruleanGymTrainerHeaders:
	def_trainers 2
CeruleanGymTrainerHeader0:
	trainer EVENT_BEAT_CERULEAN_GYM_TRAINER_0, 2, CeruleanGymBattle1Text, CeruleanGymEndBattle1Text, CeruleanGymAfterBattle1Text
CeruleanGymTrainerHeader1:
	trainer EVENT_BEAT_CERULEAN_GYM_TRAINER_1, 4, CeruleanGymBattle2Text, CeruleanGymEndBattle2Text, CeruleanGymAfterBattle3Text
CeruleanGymTrainerHeader2:
	trainer EVENT_BEAT_CERULEAN_GYM_TRAINER_2, 4, CeruleanGymBattle3Text, CeruleanGymEndBattle3Text, CeruleanGymAfterBattle3Text
CeruleanGymTrainerHeader3:
	trainer EVENT_BEAT_CERULEAN_GYM_TRAINER_3, 3, CeruleanGymBattle4Text, CeruleanGymEndBattle4Text, CeruleanGymAfterBattle4Text
    db -1 ; end

CeruleanGymMistyText:
	text_asm
	CheckEvent EVENT_BEAT_MISTY
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM11
	jr nz, .afterBeat
	call z, CeruleanGymReceiveTM11
	call DisableWaitingAfterTextDisplay
	jr .done
.afterBeat
	ld hl, .TM11ExplanationText
	call PrintText
	jr .done
.beforeBeat
	ld hl, .PreBattleText
	call PrintText
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, CeruleanGymMistyReceivedCascadeBadgeText
	ld de, CeruleanGymMistyReceivedCascadeBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	ld a, $2
	ld [wGymLeaderNo], a
	call EngageMapTrainer
    ;call InitBattleEnemyParameters
    ld d, OPP_MISTY
	farcall InitGymBattle
	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_CERULEANGYM_MISTY_POST_BATTLE
	ld [wCeruleanGymCurScript], a
.done
	jp TextScriptEnd

.PreBattleText:
	text_far _CeruleanGymMistyPreBattleText
	text_end

.TM11ExplanationText:
	text_far _CeruleanGymMistyTM11ExplanationText
	text_end

CeruleanGymMistyCascadeBadgeInfoText:
	text_far _CeruleanGymMistyCascadeBadgeInfoText
	text_end

CeruleanGymMistyReceivedTM11Text:
	text_far _CeruleanGymMistyReceivedTM11Text
	sound_get_item_1
	text_end

CeruleanGymMistyTM11NoRoomText:
	text_far _CeruleanGymMistyTM11NoRoomText
	text_end

CeruleanGymMistyReceivedCascadeBadgeText:
    text_asm
    SetEvent EVENT_BEAT_MISTY
    ld hl, .CeruleanGymMistyReceivedCascadeBadgeText
    call PrintText
    jp TextScriptEnd
	text_end
    
.CeruleanGymMistyReceivedCascadeBadgeText
    text_far _CeruleanGymMistyReceivedCascadeBadgeText
	sound_get_key_item
	text_end

CeruleanGymCooltrainerFText:
	text_asm
	ld hl, CeruleanGymTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

CeruleanGymBattle4Text:
	text_far _CeruleanGymBattle4Text
	text_end

CeruleanGymEndBattle4Text:
	text_far _CeruleanGymEndBattle4Text
	text_end

CeruleanGymAfterBattle4Text:
	text_far _CeruleanGymAfterBattle4Text
	text_end

CeruleanGymSwimmer1Text:
	text_asm
	ld hl, CeruleanGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

CeruleanGymBattle1Text:
	text_far _CeruleanGymBattle1Text
	text_end

CeruleanGymEndBattle1Text:
	text_far _CeruleanGymEndBattle1Text
	text_end

CeruleanGymAfterBattle1Text:
	text_far _CeruleanGymAfterBattle1Text
	text_end
    
CeruleanGymSwimmer2Text:
	text_asm
	ld hl, CeruleanGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

CeruleanGymBattle2Text:
	text_far _CeruleanGymBattle1Text
	text_end

CeruleanGymEndBattle2Text:
	text_far  _CeruleanGymEndBattle1Text
	text_end

CeruleanGymAfterBattle2Text:
	text_far _CeruleanGymAfterBattle1Text
	text_end
    
CeruleanGymSwimmer3Text:
	text_asm
	ld hl, CeruleanGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

CeruleanGymBattle3Text:
	text_far _CeruleanGymBattle1Text
	text_end

CeruleanGymEndBattle3Text:
	text_far  _CeruleanGymEndBattle1Text
	text_end

CeruleanGymAfterBattle3Text:
	text_far _CeruleanGymAfterBattle1Text
	text_end

CeruleanGymGymGuideText:
	text_asm
	CheckEvent EVENT_BEAT_MISTY
	jr nz, .afterBeat
	ld hl, .ChampInMakingText
	call PrintText
	jr .done
.afterBeat
	ld hl, .BeatMistyText
	call PrintText
.done
	jp TextScriptEnd

.ChampInMakingText:
	text_far _CeruleanGymGymGuideChampInMakingText
	text_end

.BeatMistyText:
	text_far _CeruleanGymGymGuideBeatMistyText
	text_end
