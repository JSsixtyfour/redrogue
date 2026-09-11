OlivineGym_Script:
	call JasmineShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	call z, initialOlivine
	call EnableAutoTextBoxDrawing
	ld hl, OlivineGymTrainerHeaders
	ld de, OlivineGym_ScriptPointers
	ld a, [wOlivineGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wOlivineGymCurScript], a
	ret

JasmineShowOrHideExitBlock:
; Blocks or clears the exit to the next room.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_JASMINE
	jr z, .blockExitToNextRoom
	ld a, $5
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $24
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

initialOlivine:
	SetEvent EVENT_ENTER_ROOM
	farcall GymLeaderRandomItem
	ld hl, .CityName
	ld de, .LeaderName
	jp LoadGymLeaderAndCityName

.CityName:
	db "OLIVINE CITY@"

.LeaderName:
	db "JASMINE@"

OlivineGymResetScripts:
	xor a
	ldh [hJoyIgnore], a
	ld [wOlivineGymCurScript], a
	ld [wCurMapScript], a
	ret

OlivineGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_OLIVINEGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_OLIVINEGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_OLIVINEGYM_END_BATTLE
	dw_const OlivineGymJasminePostBattle,           SCRIPT_OLIVINEGYM_JASMINE_POST_BATTLE

OlivineGymJasminePostBattle:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, OlivineGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
; fallthrough
OlivineGymScriptReceiveTM:
	ld a, TEXT_OLIVINEGYM_JASMINE_WAIT_TAKE_THIS
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
	ld a, TEXT_OLIVINEGYM_RECEIVED_TM
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM_OLIVINE
	jr .gymVictory
.BagFull
	ld a, TEXT_OLIVINEGYM_TM_NO_ROOM
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

	ld a, TOGGLE_OLIVINE_GYM_GUIDE
	ld [wToggleableObjectIndex], a
	predef HideObject

	jp OlivineGymResetScripts

OlivineGym_TextPointers:
	def_text_pointers
	dw_const OlivineGymJasmineText,            TEXT_OLIVINEGYM_JASMINE
	dw_const OlivineGymCooltrainerM1Text,      TEXT_OLIVINEGYM_COOLTRAINER_M1
	dw_const OlivineGymCooltrainerM2Text,      TEXT_OLIVINEGYM_COOLTRAINER_M2
	dw_const OlivineGymCooltrainerM3Text,      TEXT_OLIVINEGYM_COOLTRAINER_M3
	dw_const OlivineGymCooltrainerM4Text,      TEXT_OLIVINEGYM_COOLTRAINER_M4
	dw_const OlivineGymGuideText,              TEXT_OLIVINEGYM_GYM_GUIDE
	dw_const OlivineGymJasmineWaitTakeThisText, TEXT_OLIVINEGYM_JASMINE_WAIT_TAKE_THIS
	dw_const OlivineGymReceivedTMText,         TEXT_OLIVINEGYM_RECEIVED_TM
	dw_const OlivineGymTMNoRoomText,           TEXT_OLIVINEGYM_TM_NO_ROOM

OlivineGymTrainerHeaders:
; def_trainers MUST be present and MUST come before the first `trainer`. Without
; it the macro silently inherits CURRENT_TRAINER_BIT from the previously
; INCLUDEd map in maps.asm and still assembles clean. See
; project_gametrainer_def_trainers_inheritance_bug.
	def_trainers 2
OlivineGymTrainerHeader0:
	trainer EVENT_BEAT_OLIVINE_GYM_TRAINER_0, 5, OlivineGymCooltrainerM1BattleText, OlivineGymCooltrainerM1EndBattleText, OlivineGymCooltrainerM1AfterBattleText
OlivineGymTrainerHeader1:
	trainer EVENT_BEAT_OLIVINE_GYM_TRAINER_1, 2, OlivineGymCooltrainerM2BattleText, OlivineGymCooltrainerM2EndBattleText, OlivineGymCooltrainerM2AfterBattleText
OlivineGymTrainerHeader2:
	trainer EVENT_BEAT_OLIVINE_GYM_TRAINER_2, 5, OlivineGymCooltrainerM3BattleText, OlivineGymCooltrainerM3EndBattleText, OlivineGymCooltrainerM3AfterBattleText
OlivineGymTrainerHeader3:
	trainer EVENT_BEAT_OLIVINE_GYM_TRAINER_3, 5, OlivineGymCooltrainerM4BattleText, OlivineGymCooltrainerM4EndBattleText, OlivineGymCooltrainerM4AfterBattleText
	db -1 ; end

OlivineGymReceivedTMText:
	text_far _OlivineGymReceivedTMText
	sound_get_item_1
	text_far _TM34ExplanationText
	text_end

OlivineGymJasmineText:
	text_asm
	CheckEvent EVENT_BEAT_JASMINE
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM_OLIVINE
	jr nz, .afterBeat
	call z, OlivineGymScriptReceiveTM
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
	ld hl, OlivineGymJasmineReceivedBadgeText
	ld de, OlivineGymJasmineReceivedBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	ld a, $6
	ld [wGymLeaderNo], a
	call EngageMapTrainer
	ld d, OPP_JASMINE
	farcall InitGymBattle
	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_OLIVINEGYM_JASMINE_POST_BATTLE
	ld [wOlivineGymCurScript], a
	ld [wCurMapScript], a
.done
	jp TextScriptEnd

.PreBattleText:
	text_far _OlivineGymJasminePreBattleText
	text_end

.PostBattleAdviceText:
	text_far _OlivineGymJasminePostBattleAdviceText
	text_end

OlivineGymJasmineWaitTakeThisText:
	text_far _OlivineGymJasmineWaitTakeThisText
	text_end

OlivineGymTMNoRoomText:
	text_far _OlivineGymTMNoRoomText
	text_end

OlivineGymJasmineReceivedBadgeText:
	text_asm
	SetEvent EVENT_BEAT_JASMINE
	ld hl, ReceivedMineralBadgeText
	call PrintText
	jp TextScriptEnd
	text_end

ReceivedMineralBadgeText:
	text_far _OlivineGymJasmineReceivedBadgeText
	sound_get_key_item
	text_end

OlivineGymCooltrainerM1Text:
	text_asm
	ld hl, OlivineGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

OlivineGymCooltrainerM1BattleText:
	text_far _OlivineGymCooltrainerMBattleText
	text_end

OlivineGymCooltrainerM1EndBattleText:
	text_far _OlivineGymCooltrainerMEndBattleText
	text_end

OlivineGymCooltrainerM1AfterBattleText:
	text_far _OlivineGymCooltrainerMAfterBattleText
	text_end

OlivineGymCooltrainerM2Text:
	text_asm
	ld hl, OlivineGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

OlivineGymCooltrainerM2BattleText:
	text_far _OlivineGymCooltrainerMBattleText
	text_end

OlivineGymCooltrainerM2EndBattleText:
	text_far _OlivineGymCooltrainerMEndBattleText
	text_end

OlivineGymCooltrainerM2AfterBattleText:
	text_far _OlivineGymCooltrainerMAfterBattleText
	text_end

OlivineGymCooltrainerM3Text:
	text_asm
	ld hl, OlivineGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

OlivineGymCooltrainerM3BattleText:
	text_far _OlivineGymCooltrainerMBattleText
	text_end

OlivineGymCooltrainerM3EndBattleText:
	text_far _OlivineGymCooltrainerMEndBattleText
	text_end

OlivineGymCooltrainerM3AfterBattleText:
	text_far _OlivineGymCooltrainerMAfterBattleText
	text_end

OlivineGymCooltrainerM4Text:
	text_asm
	ld hl, OlivineGymTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

OlivineGymCooltrainerM4BattleText:
	text_far _OlivineGymCooltrainerMBattleText
	text_end

OlivineGymCooltrainerM4EndBattleText:
	text_far _OlivineGymCooltrainerMEndBattleText
	text_end

OlivineGymCooltrainerM4AfterBattleText:
	text_far _OlivineGymCooltrainerMAfterBattleText
	text_end

OlivineGymGuideText:
	text_asm
	CheckEvent EVENT_BEAT_JASMINE
	ld hl, .Advice
	jr z, .print
	ld hl, .Victory
.print
	call PrintText
	jp TextScriptEnd

.Advice:
	text_far _OlivineGymGuideAdviceText
	text_end

.Victory:
	text_far _OlivineGymGuideVictoryText
	text_end
