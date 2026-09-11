CianwoodGym_Script:
	call ChuckShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	call z, initialCianwood
	call EnableAutoTextBoxDrawing
	ld hl, CianwoodGymTrainerHeaders
	ld de, CianwoodGym_ScriptPointers
	ld a, [wCianwoodGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wCianwoodGymCurScript], a
	ret

ChuckShowOrHideExitBlock:
; Blocks or clears the exit to the next room.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_CHUCK
	jr z, .blockExitToNextRoom
	ld a, $5
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $24
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

initialCianwood:
	SetEvent EVENT_ENTER_ROOM
	farcall GymLeaderRandomItem
	ld hl, .CityName
	ld de, .LeaderName
	jp LoadGymLeaderAndCityName

.CityName:
	db "CIANWOOD CITY@"

.LeaderName:
	db "CHUCK@"

CianwoodGymResetScripts:
	xor a
	ldh [hJoyIgnore], a
	ld [wCianwoodGymCurScript], a
	ld [wCurMapScript], a
	ret

CianwoodGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_CIANWOODGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_CIANWOODGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_CIANWOODGYM_END_BATTLE
	dw_const CianwoodGymChuckPostBattle,            SCRIPT_CIANWOODGYM_CHUCK_POST_BATTLE

CianwoodGymChuckPostBattle:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, CianwoodGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
; fallthrough
CianwoodGymScriptReceiveTM:
	ld a, TEXT_CIANWOODGYM_CHUCK_WAIT_TAKE_THIS
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
	ld a, TEXT_CIANWOODGYM_RECEIVED_TM
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM_CIANWOOD
	jr .gymVictory
.BagFull
	ld a, TEXT_CIANWOODGYM_TM_NO_ROOM
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

	ld a, TOGGLE_CIANWOOD_GYM_GUIDE
	ld [wToggleableObjectIndex], a
	predef HideObject

	jp CianwoodGymResetScripts

CianwoodGym_TextPointers:
	def_text_pointers
	dw_const CianwoodGymChuckText,            TEXT_CIANWOODGYM_CHUCK
	dw_const CianwoodGymCooltrainerM1Text,      TEXT_CIANWOODGYM_COOLTRAINER_M1
	dw_const CianwoodGymCooltrainerM2Text,      TEXT_CIANWOODGYM_COOLTRAINER_M2
	dw_const CianwoodGymCooltrainerM3Text,      TEXT_CIANWOODGYM_COOLTRAINER_M3
	dw_const CianwoodGymCooltrainerM4Text,      TEXT_CIANWOODGYM_COOLTRAINER_M4
	dw_const CianwoodGymGuideText,              TEXT_CIANWOODGYM_GYM_GUIDE
	dw_const CianwoodGymChuckWaitTakeThisText, TEXT_CIANWOODGYM_CHUCK_WAIT_TAKE_THIS
	dw_const CianwoodGymReceivedTMText,         TEXT_CIANWOODGYM_RECEIVED_TM
	dw_const CianwoodGymTMNoRoomText,           TEXT_CIANWOODGYM_TM_NO_ROOM

CianwoodGymTrainerHeaders:
; def_trainers MUST be present and MUST come before the first `trainer`. Without
; it the macro silently inherits CURRENT_TRAINER_BIT from the previously
; INCLUDEd map in maps.asm and still assembles clean. See
; project_gametrainer_def_trainers_inheritance_bug.
	def_trainers 2
CianwoodGymTrainerHeader0:
	trainer EVENT_BEAT_CIANWOOD_GYM_TRAINER_0, 5, CianwoodGymCooltrainerM1BattleText, CianwoodGymCooltrainerM1EndBattleText, CianwoodGymCooltrainerM1AfterBattleText
CianwoodGymTrainerHeader1:
	trainer EVENT_BEAT_CIANWOOD_GYM_TRAINER_1, 2, CianwoodGymCooltrainerM2BattleText, CianwoodGymCooltrainerM2EndBattleText, CianwoodGymCooltrainerM2AfterBattleText
CianwoodGymTrainerHeader2:
	trainer EVENT_BEAT_CIANWOOD_GYM_TRAINER_2, 5, CianwoodGymCooltrainerM3BattleText, CianwoodGymCooltrainerM3EndBattleText, CianwoodGymCooltrainerM3AfterBattleText
CianwoodGymTrainerHeader3:
	trainer EVENT_BEAT_CIANWOOD_GYM_TRAINER_3, 5, CianwoodGymCooltrainerM4BattleText, CianwoodGymCooltrainerM4EndBattleText, CianwoodGymCooltrainerM4AfterBattleText
	db -1 ; end

CianwoodGymReceivedTMText:
	text_far _CianwoodGymReceivedTMText
	sound_get_item_1
	text_far _TM34ExplanationText
	text_end

CianwoodGymChuckText:
	text_asm
	CheckEvent EVENT_BEAT_CHUCK
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM_CIANWOOD
	jr nz, .afterBeat
	call z, CianwoodGymScriptReceiveTM
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
	ld hl, CianwoodGymChuckReceivedBadgeText
	ld de, CianwoodGymChuckReceivedBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	ld a, $5
	ld [wGymLeaderNo], a
	call EngageMapTrainer
	ld d, OPP_CHUCK
	farcall InitGymBattle
	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_CIANWOODGYM_CHUCK_POST_BATTLE
	ld [wCianwoodGymCurScript], a
	ld [wCurMapScript], a
.done
	jp TextScriptEnd

.PreBattleText:
	text_far _CianwoodGymChuckPreBattleText
	text_end

.PostBattleAdviceText:
	text_far _CianwoodGymChuckPostBattleAdviceText
	text_end

CianwoodGymChuckWaitTakeThisText:
	text_far _CianwoodGymChuckWaitTakeThisText
	text_end

CianwoodGymTMNoRoomText:
	text_far _CianwoodGymTMNoRoomText
	text_end

CianwoodGymChuckReceivedBadgeText:
	text_asm
	SetEvent EVENT_BEAT_CHUCK
	ld hl, ReceivedStormBadgeText
	call PrintText
	jp TextScriptEnd
	text_end

ReceivedStormBadgeText:
	text_far _CianwoodGymChuckReceivedBadgeText
	sound_get_key_item
	text_end

CianwoodGymCooltrainerM1Text:
	text_asm
	ld hl, CianwoodGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

CianwoodGymCooltrainerM1BattleText:
	text_far _CianwoodGymCooltrainerMBattleText
	text_end

CianwoodGymCooltrainerM1EndBattleText:
	text_far _CianwoodGymCooltrainerMEndBattleText
	text_end

CianwoodGymCooltrainerM1AfterBattleText:
	text_far _CianwoodGymCooltrainerMAfterBattleText
	text_end

CianwoodGymCooltrainerM2Text:
	text_asm
	ld hl, CianwoodGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

CianwoodGymCooltrainerM2BattleText:
	text_far _CianwoodGymCooltrainerMBattleText
	text_end

CianwoodGymCooltrainerM2EndBattleText:
	text_far _CianwoodGymCooltrainerMEndBattleText
	text_end

CianwoodGymCooltrainerM2AfterBattleText:
	text_far _CianwoodGymCooltrainerMAfterBattleText
	text_end

CianwoodGymCooltrainerM3Text:
	text_asm
	ld hl, CianwoodGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

CianwoodGymCooltrainerM3BattleText:
	text_far _CianwoodGymCooltrainerMBattleText
	text_end

CianwoodGymCooltrainerM3EndBattleText:
	text_far _CianwoodGymCooltrainerMEndBattleText
	text_end

CianwoodGymCooltrainerM3AfterBattleText:
	text_far _CianwoodGymCooltrainerMAfterBattleText
	text_end

CianwoodGymCooltrainerM4Text:
	text_asm
	ld hl, CianwoodGymTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

CianwoodGymCooltrainerM4BattleText:
	text_far _CianwoodGymCooltrainerMBattleText
	text_end

CianwoodGymCooltrainerM4EndBattleText:
	text_far _CianwoodGymCooltrainerMEndBattleText
	text_end

CianwoodGymCooltrainerM4AfterBattleText:
	text_far _CianwoodGymCooltrainerMAfterBattleText
	text_end

CianwoodGymGuideText:
	text_asm
	CheckEvent EVENT_BEAT_CHUCK
	ld hl, .Advice
	jr z, .print
	ld hl, .Victory
.print
	call PrintText
	jp TextScriptEnd

.Advice:
	text_far _CianwoodGymGuideAdviceText
	text_end

.Victory:
	text_far _CianwoodGymGuideVictoryText
	text_end
