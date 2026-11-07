GoldenrodGym_Script:
	call WhitneyShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .loadGymNames
	SetEvent EVENT_ENTER_ROOM
	farcall GymLeaderRandomItem
.loadGymNames
	; Unsaved buffers must be rebuilt after Continue, as in Viridian Gym.
	ld hl, GoldenrodGymNames.CityName
	ld de, GoldenrodGymNames.LeaderName
	call LoadGymLeaderAndCityName
	call EnableAutoTextBoxDrawing
	ld hl, GoldenrodGymTrainerHeaders
	ld de, GoldenrodGym_ScriptPointers
	ld a, [wGoldenrodGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wGoldenrodGymCurScript], a
	ret

DEF GOLDENROD_GYM_OPEN_BLOCK EQU $33 ; the empty grass at the entry warp

WhitneyShowOrHideExitBlock:
; Beating Whitney clears the door and the trees above her. Both are baked into the
; .blk, which reloads on every map entry, so only the cleared state needs writing.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_WHITNEY
	ret z
	ld a, GOLDENROD_GYM_OPEN_BLOCK
	ld [wNewTileBlockID], a
	lb bc, 0, 4
	predef ReplaceTileBlock
	ld a, GOLDENROD_GYM_OPEN_BLOCK
	ld [wNewTileBlockID], a
	lb bc, 1, 4
	predef_jump ReplaceTileBlock

; Authored names; one-time setup runs inline above.
GoldenrodGymNames:

.CityName:
	db "GOLDENROD CITY@"

.LeaderName:
	db "WHITNEY@"

GoldenrodGymResetScripts:
	xor a
	ldh [hJoyIgnore], a
	ld [wGoldenrodGymCurScript], a
	ld [wCurMapScript], a
	ret

GoldenrodGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_GOLDENRODGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_GOLDENRODGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_GOLDENRODGYM_END_BATTLE
	dw_const GoldenrodGymWhitneyPostBattle,         SCRIPT_GOLDENRODGYM_WHITNEY_POST_BATTLE

GoldenrodGymWhitneyPostBattle:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, GoldenrodGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
; fallthrough
GoldenrodGymScriptReceiveTM:
	ld a, TEXT_GOLDENRODGYM_WHITNEY_WAIT_TAKE_THIS
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
	ld a, TEXT_GOLDENRODGYM_RECEIVED_TM
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM_GOLDENROD
	jr .gymVictory
.BagFull
	ld a, TEXT_GOLDENRODGYM_TM_NO_ROOM
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

	jp GoldenrodGymResetScripts

GoldenrodGym_TextPointers:
	def_text_pointers
	dw_const GoldenrodGymWhitneyText,            TEXT_GOLDENRODGYM_WHITNEY
	dw_const GoldenrodGymBeauty1Text,             TEXT_GOLDENRODGYM_BEAUTY1
	dw_const GoldenrodGymBeauty2Text,           TEXT_GOLDENRODGYM_BEAUTY2
    dw_const GoldenrodGymLass1Text,              TEXT_GOLDENRODGYM_LASS1
	dw_const GoldenrodGymGuideText,              TEXT_GOLDENRODGYM_GYM_GUIDE
	dw_const GoldenrodGymWhitneyWaitTakeThisText, TEXT_GOLDENRODGYM_WHITNEY_WAIT_TAKE_THIS
	dw_const GoldenrodGymReceivedTMText,         TEXT_GOLDENRODGYM_RECEIVED_TM
	dw_const GoldenrodGymTMNoRoomText,           TEXT_GOLDENRODGYM_TM_NO_ROOM

GoldenrodGymTrainerHeaders:
; def_trainers MUST be present and MUST come before the first `trainer`. Without
; it the macro silently inherits CURRENT_TRAINER_BIT from the previously
; INCLUDEd map in maps.asm and still assembles clean. See
; project_gametrainer_def_trainers_inheritance_bug.
	def_trainers 2
GoldenrodGymTrainerHeader0:
	trainer EVENT_BEAT_GOLDENROD_GYM_TRAINER_0, 2, GoldenrodGymBeauty1BattleText, GoldenrodGymBeauty1EndBattleText, GoldenrodGymBeauty1AfterBattleText
GoldenrodGymTrainerHeader1:
	trainer EVENT_BEAT_GOLDENROD_GYM_TRAINER_1, 4, GoldenrodGymBeauty2BattleText, GoldenrodGymBeauty2EndBattleText, GoldenrodGymBeauty2AfterBattleText
GoldenrodGymTrainerHeader2:
	trainer EVENT_BEAT_GOLDENROD_GYM_TRAINER_2, 1, GoldenrodGymLass1BattleText, GoldenrodGymLass1EndBattleText, GoldenrodGymLass1AfterBattleText
	db -1 ; end

GoldenrodGymReceivedTMText:
	text_far _GoldenrodGymReceivedTMText
	sound_get_item_1
	text_far _TM34ExplanationText
	text_end

GoldenrodGymWhitneyText:
	text_asm
	CheckEvent EVENT_BEAT_WHITNEY
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM_GOLDENROD
	jr nz, .afterBeat
	call z, GoldenrodGymScriptReceiveTM
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
	ld hl, GoldenrodGymWhitneyReceivedBadgeText
	ld de, GoldenrodGymWhitneyReceivedBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	ld a, $3
	ld [wGymLeaderNo], a
	call EngageMapTrainer
	ld d, OPP_WHITNEY
	farcall InitGymBattle
	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_GOLDENRODGYM_WHITNEY_POST_BATTLE
	ld [wGoldenrodGymCurScript], a
	ld [wCurMapScript], a
.done
	jp TextScriptEnd

.PreBattleText:
	text_far _GoldenrodGymWhitneyPreBattleText
	text_end

.PostBattleAdviceText:
	text_far _GoldenrodGymWhitneyPostBattleAdviceText
	text_end

GoldenrodGymWhitneyWaitTakeThisText:
	text_far _GoldenrodGymWhitneyWaitTakeThisText
	text_end

GoldenrodGymTMNoRoomText:
	text_far _GoldenrodGymTMNoRoomText
	text_end

GoldenrodGymWhitneyReceivedBadgeText:
	text_asm
	SetEvent EVENT_BEAT_WHITNEY
	ld hl, ReceivedPlainBadgeText
	ret

ReceivedPlainBadgeText:
	text_far _GoldenrodGymWhitneyReceivedBadgeText
	sound_get_key_item
	text_end

GoldenrodGymBeauty1Text:
	text_asm
	ld hl, GoldenrodGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

GoldenrodGymBeauty1BattleText:
	text_far _GoldenrodGymBeauty1BattleText
	text_end

GoldenrodGymBeauty1EndBattleText:
	text_far _GoldenrodGymBeauty1EndBattleText
	text_end

GoldenrodGymBeauty1AfterBattleText:
	text_far _GoldenrodGymBeauty1AfterBattleText
	text_end

GoldenrodGymLass1Text:
	text_asm
	ld hl, GoldenrodGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

GoldenrodGymLass1BattleText:
	text_far _GoldenrodGymLass1BattleText
	text_end

GoldenrodGymLass1EndBattleText:
	text_far _GoldenrodGymLass1EndBattleText
	text_end

GoldenrodGymLass1AfterBattleText:
	text_far _GoldenrodGymLass1AfterBattleText
	text_end

GoldenrodGymBeauty2Text:
	text_asm
	ld hl, GoldenrodGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

GoldenrodGymBeauty2BattleText:
	text_far _GoldenrodBeauty2BattleText
	text_end

GoldenrodGymBeauty2EndBattleText:
	text_far _GoldenrodBeauty2EndBattleText
	text_end

GoldenrodGymBeauty2AfterBattleText:
	text_far _GoldenrodBeauty2AfterBattleText
	text_end

GoldenrodGymGuideText:
	text_asm
	CheckEvent EVENT_BEAT_WHITNEY
	ld hl, .Advice
	jr z, .print
	ld hl, .Victory
.print
	call PrintText
	jp TextScriptEnd

.Advice:
	text_far _GoldenrodGymGuideAdviceText
	text_end

.Victory:
	text_far _GoldenrodGymGuideVictoryText
	text_end
