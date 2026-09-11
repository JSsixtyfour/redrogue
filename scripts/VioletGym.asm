VioletGym_Script:
	call FalknerShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	call z, initialViolet
	call EnableAutoTextBoxDrawing
	ld hl, VioletGymTrainerHeaders
	ld de, VioletGym_ScriptPointers
	ld a, [wVioletGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wVioletGymCurScript], a
	ret

FalknerShowOrHideExitBlock:
; Blocks or clears the exit to the next room.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_FALKNER
	jr z, .blockExitToNextRoom
	ld a, $5
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $24
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

initialViolet:
	SetEvent EVENT_ENTER_ROOM
	farcall GymLeaderRandomItem
	ld hl, .CityName
	ld de, .LeaderName
	jp LoadGymLeaderAndCityName

.CityName:
	db "VIOLET CITY@"

.LeaderName:
	db "FALKNER@"

VioletGymResetScripts:
	xor a
	ldh [hJoyIgnore], a
	ld [wVioletGymCurScript], a
	ld [wCurMapScript], a
	ret

VioletGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_VIOLETGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_VIOLETGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_VIOLETGYM_END_BATTLE
	dw_const VioletGymFalknerPostBattle,            SCRIPT_VIOLETGYM_FALKNER_POST_BATTLE

VioletGymFalknerPostBattle:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, VioletGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
; fallthrough
VioletGymScriptReceiveTM:
	ld a, TEXT_VIOLETGYM_FALKNER_WAIT_TAKE_THIS
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
	ld a, TEXT_VIOLETGYM_RECEIVED_TM
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM_VIOLET
	jr .gymVictory
.BagFull
	ld a, TEXT_VIOLETGYM_TM_NO_ROOM
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

	ld a, TOGGLE_VIOLET_GYM_GUIDE
	ld [wToggleableObjectIndex], a
	predef HideObject

	jp VioletGymResetScripts

VioletGym_TextPointers:
	def_text_pointers
	dw_const VioletGymFalknerText,            TEXT_VIOLETGYM_FALKNER
	dw_const VioletGymCooltrainerM1Text,      TEXT_VIOLETGYM_COOLTRAINER_M1
	dw_const VioletGymCooltrainerM2Text,      TEXT_VIOLETGYM_COOLTRAINER_M2
	dw_const VioletGymCooltrainerM3Text,      TEXT_VIOLETGYM_COOLTRAINER_M3
	dw_const VioletGymCooltrainerM4Text,      TEXT_VIOLETGYM_COOLTRAINER_M4
	dw_const VioletGymGuideText,              TEXT_VIOLETGYM_GYM_GUIDE
	dw_const VioletGymFalknerWaitTakeThisText, TEXT_VIOLETGYM_FALKNER_WAIT_TAKE_THIS
	dw_const VioletGymReceivedTMText,         TEXT_VIOLETGYM_RECEIVED_TM
	dw_const VioletGymTMNoRoomText,           TEXT_VIOLETGYM_TM_NO_ROOM

VioletGymTrainerHeaders:
; def_trainers MUST be present and MUST come before the first `trainer`. Without
; it the macro silently inherits CURRENT_TRAINER_BIT from the previously
; INCLUDEd map in maps.asm and still assembles clean. See
; project_gametrainer_def_trainers_inheritance_bug.
	def_trainers 2
VioletGymTrainerHeader0:
	trainer EVENT_BEAT_VIOLET_GYM_TRAINER_0, 5, VioletGymCooltrainerM1BattleText, VioletGymCooltrainerM1EndBattleText, VioletGymCooltrainerM1AfterBattleText
VioletGymTrainerHeader1:
	trainer EVENT_BEAT_VIOLET_GYM_TRAINER_1, 2, VioletGymCooltrainerM2BattleText, VioletGymCooltrainerM2EndBattleText, VioletGymCooltrainerM2AfterBattleText
VioletGymTrainerHeader2:
	trainer EVENT_BEAT_VIOLET_GYM_TRAINER_2, 5, VioletGymCooltrainerM3BattleText, VioletGymCooltrainerM3EndBattleText, VioletGymCooltrainerM3AfterBattleText
VioletGymTrainerHeader3:
	trainer EVENT_BEAT_VIOLET_GYM_TRAINER_3, 5, VioletGymCooltrainerM4BattleText, VioletGymCooltrainerM4EndBattleText, VioletGymCooltrainerM4AfterBattleText
	db -1 ; end

VioletGymReceivedTMText:
	text_far _VioletGymReceivedTMText
	sound_get_item_1
	text_far _TM34ExplanationText
	text_end

VioletGymFalknerText:
	text_asm
	CheckEvent EVENT_BEAT_FALKNER
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM_VIOLET
	jr nz, .afterBeat
	call z, VioletGymScriptReceiveTM
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
	ld hl, VioletGymFalknerReceivedBadgeText
	ld de, VioletGymFalknerReceivedBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	ld a, $1
	ld [wGymLeaderNo], a
	call EngageMapTrainer
	ld d, OPP_FALKNER
	farcall InitGymBattle
	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_VIOLETGYM_FALKNER_POST_BATTLE
	ld [wVioletGymCurScript], a
	ld [wCurMapScript], a
.done
	jp TextScriptEnd

.PreBattleText:
	text_far _VioletGymFalknerPreBattleText
	text_end

.PostBattleAdviceText:
	text_far _VioletGymFalknerPostBattleAdviceText
	text_end

VioletGymFalknerWaitTakeThisText:
	text_far _VioletGymFalknerWaitTakeThisText
	text_end

VioletGymTMNoRoomText:
	text_far _VioletGymTMNoRoomText
	text_end

VioletGymFalknerReceivedBadgeText:
	text_asm
	SetEvent EVENT_BEAT_FALKNER
	ld hl, ReceivedZephyrBadgeText
	call PrintText
	jp TextScriptEnd
	text_end

ReceivedZephyrBadgeText:
	text_far _VioletGymFalknerReceivedBadgeText
	sound_get_key_item
	text_end

VioletGymCooltrainerM1Text:
	text_asm
	ld hl, VioletGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

VioletGymCooltrainerM1BattleText:
	text_far _VioletGymCooltrainerMBattleText
	text_end

VioletGymCooltrainerM1EndBattleText:
	text_far _VioletGymCooltrainerMEndBattleText
	text_end

VioletGymCooltrainerM1AfterBattleText:
	text_far _VioletGymCooltrainerMAfterBattleText
	text_end

VioletGymCooltrainerM2Text:
	text_asm
	ld hl, VioletGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

VioletGymCooltrainerM2BattleText:
	text_far _VioletGymCooltrainerMBattleText
	text_end

VioletGymCooltrainerM2EndBattleText:
	text_far _VioletGymCooltrainerMEndBattleText
	text_end

VioletGymCooltrainerM2AfterBattleText:
	text_far _VioletGymCooltrainerMAfterBattleText
	text_end

VioletGymCooltrainerM3Text:
	text_asm
	ld hl, VioletGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

VioletGymCooltrainerM3BattleText:
	text_far _VioletGymCooltrainerMBattleText
	text_end

VioletGymCooltrainerM3EndBattleText:
	text_far _VioletGymCooltrainerMEndBattleText
	text_end

VioletGymCooltrainerM3AfterBattleText:
	text_far _VioletGymCooltrainerMAfterBattleText
	text_end

VioletGymCooltrainerM4Text:
	text_asm
	ld hl, VioletGymTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

VioletGymCooltrainerM4BattleText:
	text_far _VioletGymCooltrainerMBattleText
	text_end

VioletGymCooltrainerM4EndBattleText:
	text_far _VioletGymCooltrainerMEndBattleText
	text_end

VioletGymCooltrainerM4AfterBattleText:
	text_far _VioletGymCooltrainerMAfterBattleText
	text_end

VioletGymGuideText:
	text_asm
	CheckEvent EVENT_BEAT_FALKNER
	ld hl, .Advice
	jr z, .print
	ld hl, .Victory
.print
	call PrintText
	jp TextScriptEnd

.Advice:
	text_far _VioletGymGuideAdviceText
	text_end

.Victory:
	text_far _VioletGymGuideVictoryText
	text_end
