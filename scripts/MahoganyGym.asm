MahoganyGym_Script:
	call PryceShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	call z, initialMahogany
	call EnableAutoTextBoxDrawing
	ld hl, MahoganyGymTrainerHeaders
	ld de, MahoganyGym_ScriptPointers
	ld a, [wMahoganyGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wMahoganyGymCurScript], a
	ret

PryceShowOrHideExitBlock:
; Blocks or clears the exit to the next room.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_PRYCE
	jr z, .blockExitToNextRoom
	ld a, $5
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $24
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

initialMahogany:
	SetEvent EVENT_ENTER_ROOM
	farcall GymLeaderRandomItem
	ld hl, .CityName
	ld de, .LeaderName
	jp LoadGymLeaderAndCityName

.CityName:
	db "MAHOGANY TOWN@"

.LeaderName:
	db "PRYCE@"

MahoganyGymResetScripts:
	xor a
	ldh [hJoyIgnore], a
	ld [wMahoganyGymCurScript], a
	ld [wCurMapScript], a
	ret

MahoganyGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_MAHOGANYGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_MAHOGANYGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_MAHOGANYGYM_END_BATTLE
	dw_const MahoganyGymPrycePostBattle,            SCRIPT_MAHOGANYGYM_PRYCE_POST_BATTLE

MahoganyGymPrycePostBattle:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, MahoganyGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
; fallthrough
MahoganyGymScriptReceiveTM:
	ld a, TEXT_MAHOGANYGYM_PRYCE_WAIT_TAKE_THIS
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
	ld a, TEXT_MAHOGANYGYM_RECEIVED_TM
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM_MAHOGANY
	jr .gymVictory
.BagFull
	ld a, TEXT_MAHOGANYGYM_TM_NO_ROOM
	ldh [hTextID], a
	call DisplayTextID
.gymVictory
; The badge granted is decided by the slot the player entered through, NOT by
; this map. See GYM_LEADER_EXPANSION_PLAN.md Phase 6 Correction 2. This predef
; is exactly 5 bytes, the same as the `ld hl, wObtainedBadges` + `set BIT_x`
; it replaces, which is what lets the four bank-$17 gym scripts carry it.
	predef RogueAwardCurrentGymBadge
	ld hl, wRogueFlagsBitfield
	res 0, [hl]                 ; route is next after this gym

	ld a, TOGGLE_MAHOGANY_GYM_GUIDE
	ld [wToggleableObjectIndex], a
	predef HideObject

	jp MahoganyGymResetScripts

MahoganyGym_TextPointers:
	def_text_pointers
	dw_const MahoganyGymPryceText,            TEXT_MAHOGANYGYM_PRYCE
	dw_const MahoganyGymCooltrainerM1Text,      TEXT_MAHOGANYGYM_COOLTRAINER_M1
	dw_const MahoganyGymCooltrainerM2Text,      TEXT_MAHOGANYGYM_COOLTRAINER_M2
	dw_const MahoganyGymCooltrainerM3Text,      TEXT_MAHOGANYGYM_COOLTRAINER_M3
	dw_const MahoganyGymCooltrainerM4Text,      TEXT_MAHOGANYGYM_COOLTRAINER_M4
	dw_const MahoganyGymGuideText,              TEXT_MAHOGANYGYM_GYM_GUIDE
	dw_const MahoganyGymPryceWaitTakeThisText, TEXT_MAHOGANYGYM_PRYCE_WAIT_TAKE_THIS
	dw_const MahoganyGymReceivedTMText,         TEXT_MAHOGANYGYM_RECEIVED_TM
	dw_const MahoganyGymTMNoRoomText,           TEXT_MAHOGANYGYM_TM_NO_ROOM

MahoganyGymTrainerHeaders:
; def_trainers MUST be present and MUST come before the first `trainer`. Without
; it the macro silently inherits CURRENT_TRAINER_BIT from the previously
; INCLUDEd map in maps.asm and still assembles clean. See
; project_gametrainer_def_trainers_inheritance_bug.
	def_trainers 2
MahoganyGymTrainerHeader0:
	trainer EVENT_BEAT_MAHOGANY_GYM_TRAINER_0, 5, MahoganyGymCooltrainerM1BattleText, MahoganyGymCooltrainerM1EndBattleText, MahoganyGymCooltrainerM1AfterBattleText
MahoganyGymTrainerHeader1:
	trainer EVENT_BEAT_MAHOGANY_GYM_TRAINER_1, 2, MahoganyGymCooltrainerM2BattleText, MahoganyGymCooltrainerM2EndBattleText, MahoganyGymCooltrainerM2AfterBattleText
MahoganyGymTrainerHeader2:
	trainer EVENT_BEAT_MAHOGANY_GYM_TRAINER_2, 5, MahoganyGymCooltrainerM3BattleText, MahoganyGymCooltrainerM3EndBattleText, MahoganyGymCooltrainerM3AfterBattleText
MahoganyGymTrainerHeader3:
	trainer EVENT_BEAT_MAHOGANY_GYM_TRAINER_3, 5, MahoganyGymCooltrainerM4BattleText, MahoganyGymCooltrainerM4EndBattleText, MahoganyGymCooltrainerM4AfterBattleText
	db -1 ; end

MahoganyGymReceivedTMText:
	text_far _MahoganyGymReceivedTMText
	sound_get_item_1
	text_far _TM34ExplanationText
	text_end

MahoganyGymPryceText:
	text_asm
	CheckEvent EVENT_BEAT_PRYCE
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM_MAHOGANY
	jr nz, .afterBeat
	call z, MahoganyGymScriptReceiveTM
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
	ld hl, MahoganyGymPryceReceivedBadgeText
	ld de, MahoganyGymPryceReceivedBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	ld a, $7
	ld [wGymLeaderNo], a
	call EngageMapTrainer
	ld d, OPP_PRYCE
	farcall InitGymBattle
	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_MAHOGANYGYM_PRYCE_POST_BATTLE
	ld [wMahoganyGymCurScript], a
	ld [wCurMapScript], a
.done
	jp TextScriptEnd

.PreBattleText:
	text_far _MahoganyGymPrycePreBattleText
	text_end

.PostBattleAdviceText:
	text_far _MahoganyGymPrycePostBattleAdviceText
	text_end

MahoganyGymPryceWaitTakeThisText:
	text_far _MahoganyGymPryceWaitTakeThisText
	text_end

MahoganyGymTMNoRoomText:
	text_far _MahoganyGymTMNoRoomText
	text_end

MahoganyGymPryceReceivedBadgeText:
	text_asm
	SetEvent EVENT_BEAT_PRYCE
	ld hl, ReceivedGlacierBadgeText
	call PrintText
	jp TextScriptEnd
	text_end

ReceivedGlacierBadgeText:
	text_far _MahoganyGymPryceReceivedBadgeText
	sound_get_key_item
	text_end

MahoganyGymCooltrainerM1Text:
	text_asm
	ld hl, MahoganyGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

MahoganyGymCooltrainerM1BattleText:
	text_far _MahoganyGymCooltrainerMBattleText
	text_end

MahoganyGymCooltrainerM1EndBattleText:
	text_far _MahoganyGymCooltrainerMEndBattleText
	text_end

MahoganyGymCooltrainerM1AfterBattleText:
	text_far _MahoganyGymCooltrainerMAfterBattleText
	text_end

MahoganyGymCooltrainerM2Text:
	text_asm
	ld hl, MahoganyGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

MahoganyGymCooltrainerM2BattleText:
	text_far _MahoganyGymCooltrainerMBattleText
	text_end

MahoganyGymCooltrainerM2EndBattleText:
	text_far _MahoganyGymCooltrainerMEndBattleText
	text_end

MahoganyGymCooltrainerM2AfterBattleText:
	text_far _MahoganyGymCooltrainerMAfterBattleText
	text_end

MahoganyGymCooltrainerM3Text:
	text_asm
	ld hl, MahoganyGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

MahoganyGymCooltrainerM3BattleText:
	text_far _MahoganyGymCooltrainerMBattleText
	text_end

MahoganyGymCooltrainerM3EndBattleText:
	text_far _MahoganyGymCooltrainerMEndBattleText
	text_end

MahoganyGymCooltrainerM3AfterBattleText:
	text_far _MahoganyGymCooltrainerMAfterBattleText
	text_end

MahoganyGymCooltrainerM4Text:
	text_asm
	ld hl, MahoganyGymTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

MahoganyGymCooltrainerM4BattleText:
	text_far _MahoganyGymCooltrainerMBattleText
	text_end

MahoganyGymCooltrainerM4EndBattleText:
	text_far _MahoganyGymCooltrainerMEndBattleText
	text_end

MahoganyGymCooltrainerM4AfterBattleText:
	text_far _MahoganyGymCooltrainerMAfterBattleText
	text_end

MahoganyGymGuideText:
	text_asm
	CheckEvent EVENT_BEAT_PRYCE
	ld hl, .Advice
	jr z, .print
	ld hl, .Victory
.print
	call PrintText
	jp TextScriptEnd

.Advice:
	text_far _MahoganyGymGuideAdviceText
	text_end

.Victory:
	text_far _MahoganyGymGuideVictoryText
	text_end
