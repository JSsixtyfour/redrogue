FuchsiaGym_Script:
    call KogaShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	call z, .initial
	call EnableAutoTextBoxDrawing
	ld hl, FuchsiaGymTrainerHeaders
	ld de, FuchsiaGym_ScriptPointers
	ld a, [wFuchsiaGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wFuchsiaGymCurScript], a
	ret

.initial:
	SetEvent EVENT_ENTER_ROOM
    farcall GymLeaderRandomItem
	ld hl, .CityName
	ld de, .LeaderName
	jp LoadGymLeaderAndCityName
    


.CityName:
	db "FUCHSIA CITY@"

.LeaderName:
	db "KOGA@"
    
    KogaShowOrHideExitBlock:
; Blocks or clears the exit to the next room.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_KOGA
	jr z, .blockExitToNextRoom
	ld a, $5
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $24
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

FuchsiaGymResetScripts:
	xor a ; SCRIPT_FUCHSIAGYM_DEFAULT
	ldh [hJoyIgnore], a
	ld [wFuchsiaGymCurScript], a
	ld [wCurMapScript], a
	ret

FuchsiaGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_FUCHSIAGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_FUCHSIAGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_FUCHSIAGYM_END_BATTLE
	dw_const FuchsiaGymKogaPostBattleScript,        SCRIPT_FUCHSIAGYM_KOGA_POST_BATTLE

FuchsiaGymKogaPostBattleScript:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, FuchsiaGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
; fallthrough
FuchsiaGymReceiveTM06:
	ld a, TEXT_FUCHSIAGYM_KOGA_SOUL_BADGE_INFO
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
	ld a, TEXT_FUCHSIAGYM_KOGA_RECEIVED_TM06
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM06
	jr .gymVictory
.BagFull
	ld a, TEXT_FUCHSIAGYM_KOGA_TM06_NO_ROOM
	ldh [hTextID], a
	call DisplayTextID
.gymVictory
	ld hl, wObtainedBadges
	set BIT_SOULBADGE, [hl]
	ld hl, wRogueFlagsBitfield
	res 0, [hl]                 ; route is next after this gym

	; deactivate gym trainers
	SetEventRange EVENT_BEAT_FUCHSIA_GYM_TRAINER_0, EVENT_BEAT_FUCHSIA_GYM_TRAINER_5

	jp FuchsiaGymResetScripts

FuchsiaGym_TextPointers:
	def_text_pointers
	dw_const FuchsiaGymKogaText,              TEXT_FUCHSIAGYM_KOGA
	dw_const FuchsiaGymRocker1Text,           TEXT_FUCHSIAGYM_ROCKER1
	dw_const FuchsiaGymRocker2Text,           TEXT_FUCHSIAGYM_ROCKER2
	dw_const FuchsiaGymRocker3Text,           TEXT_FUCHSIAGYM_ROCKER3
	dw_const FuchsiaGymRocker4Text,           TEXT_FUCHSIAGYM_ROCKER4
	dw_const FuchsiaGymGymGuideText,          TEXT_FUCHSIAGYM_GYM_GUIDE
	dw_const FuchsiaGymKogaSoulBadgeInfoText, TEXT_FUCHSIAGYM_KOGA_SOUL_BADGE_INFO
	dw_const FuchsiaGymKogaReceivedTM06Text,  TEXT_FUCHSIAGYM_KOGA_RECEIVED_TM06
	dw_const FuchsiaGymKogaTM06NoRoomText,    TEXT_FUCHSIAGYM_KOGA_TM06_NO_ROOM

FuchsiaGymTrainerHeaders:
	def_trainers 2
FuchsiaGymTrainerHeader0:
	trainer EVENT_BEAT_FUCHSIA_GYM_TRAINER_0, 2, FuchsiaGymRocker1BattleText, FuchsiaGymRocker1EndBattleText, FuchsiaGymRocker1AfterBattleText
FuchsiaGymTrainerHeader1:
	trainer EVENT_BEAT_FUCHSIA_GYM_TRAINER_1, 1, FuchsiaGymRocker2BattleText, FuchsiaGymRocker2EndBattleText, FuchsiaGymRocker2AfterBattleText
FuchsiaGymTrainerHeader2:
	trainer EVENT_BEAT_FUCHSIA_GYM_TRAINER_2, 1, FuchsiaGymRocker3BattleText, FuchsiaGymRocker3EndBattleText, FuchsiaGymRocker3AfterBattleText
FuchsiaGymTrainerHeader3:
	trainer EVENT_BEAT_FUCHSIA_GYM_TRAINER_3, 1, FuchsiaGymRocker4BattleText, FuchsiaGymRocker4EndBattleText, FuchsiaGymRocker4AfterBattleText
	db -1 ; end

FuchsiaGymKogaText:
	text_asm
	CheckEvent EVENT_BEAT_KOGA
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM06
	jr nz, .afterBeat
	call z, FuchsiaGymReceiveTM06
	call DisableWaitingAfterTextDisplay
	jr .done
.afterBeat
	ld hl, .PostBattleAdviceText
	call PrintText
	jr .done
.beforeBeat
	ld hl, .BeforeBattleText
	call PrintText
	ld hl, wStatusFlags3
	set BIT_TALKED_TO_TRAINER, [hl]
	set BIT_PRINT_END_BATTLE_TEXT, [hl]
	ld hl, .ReceivedSoulBadgeText
	ld de, .ReceivedSoulBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	ld a, $5
	ld [wGymLeaderNo], a
	call EngageMapTrainer
	ld d, OPP_KOGA
    farcall InitGymBattle
	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_FUCHSIAGYM_KOGA_POST_BATTLE
	ld [wFuchsiaGymCurScript], a
.done
	jp TextScriptEnd

.BeforeBattleText:
	text_far _FuchsiaGymKogaBeforeBattleText
	text_end

.ReceivedSoulBadgeText:
    text_asm
    SetEvent EVENT_BEAT_KOGA
    ld hl, .FuchsiaGymKogaReceivedSoulBadgeText
    call PrintText
    jp TextScriptEnd
	text_end

    .FuchsiaGymKogaReceivedSoulBadgeText
    text_far _FuchsiaGymKogaReceivedSoulBadgeText
	sound_get_key_item
	text_end

.PostBattleAdviceText:
	text_far _FuchsiaGymKogaPostBattleAdviceText
	text_end

FuchsiaGymKogaSoulBadgeInfoText:
	text_far _FuchsiaGymKogaSoulBadgeInfoText
	text_end

FuchsiaGymKogaReceivedTM06Text:
	text_far _FuchsiaGymKogaReceivedTM06Text
	sound_get_item_1
	text_far _FuchsiaGymKogaTM06ExplanationText
	text_end

FuchsiaGymKogaTM06NoRoomText:
	text_far _FuchsiaGymKogaTM06NoRoomText
	text_end

FuchsiaGymRocker1Text:
	text_asm
	ld hl, FuchsiaGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

FuchsiaGymRocker1BattleText:
	text_far _FuchsiaGymRocker1BattleText
	text_end

FuchsiaGymRocker1EndBattleText:
	text_far _FuchsiaGymRocker1EndBattleText
	text_end

FuchsiaGymRocker1AfterBattleText:
	text_far _FuchsiaGymRocker1AfterBattleText
	text_end

FuchsiaGymRocker2Text:
	text_asm
	ld hl, FuchsiaGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

FuchsiaGymRocker2BattleText:
	text_far _FuchsiaGymRocker2BattleText
	text_end

FuchsiaGymRocker2EndBattleText:
	text_far _FuchsiaGymRocker2EndBattleText
	text_end

FuchsiaGymRocker2AfterBattleText:
	text_far _FuchsiaGymRocker2AfterBattleText
	text_end

FuchsiaGymRocker3Text:
	text_asm
	ld hl, FuchsiaGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

FuchsiaGymRocker3BattleText:
	text_far _FuchsiaGymRocker3BattleText
	text_end

FuchsiaGymRocker3EndBattleText:
	text_far _FuchsiaGymRocker3EndBattleText
	text_end

FuchsiaGymRocker3AfterBattleText:
	text_far _FuchsiaGymRocker3AfterBattleText
	text_end

FuchsiaGymRocker4Text:
	text_asm
	ld hl, FuchsiaGymTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

FuchsiaGymRocker4BattleText:
	text_far _FuchsiaGymRocker4BattleText
	text_end

FuchsiaGymRocker4EndBattleText:
	text_far _FuchsiaGymRocker4EndBattleText
	text_end

FuchsiaGymRocker4AfterBattleText:
	text_far _FuchsiaGymRocker4AfterBattleText
	text_end

FuchsiaGymRocker5BattleText:
	text_far _FuchsiaGymRocker5BattleText
	text_end

FuchsiaGymRocker5EndBattleText:
	text_far _FuchsiaGymRocker5EndBattleText
	text_end

FuchsiaGymRocker5AfterBattleText:
	text_far _FuchsiaGymRocker5AfterBattleText
	text_end


FuchsiaGymRocker6BattleText:
	text_far _FuchsiaGymRocker6BattleText
	text_end

FuchsiaGymRocker6EndBattleText:
	text_far _FuchsiaGymRocker6EndBattleText
	text_end

FuchsiaGymRocker6AfterBattleText:
	text_far _FuchsiaGymRocker6AfterBattleText
	text_end

FuchsiaGymGymGuideText:
	text_asm
	CheckEvent EVENT_BEAT_KOGA
	ld hl, .BeatKogaText
	jr nz, .afterBeat
	ld hl, .ChampInMakingText
.afterBeat
	call PrintText
	jp TextScriptEnd

.ChampInMakingText:
	text_far _FuchsiaGymGymGuideChampInMakingText
	text_end

.BeatKogaText:
	text_far _FuchsiaGymGymGuideBeatKogaText
	text_end
