OlivineGym_Script:
	call JasmineShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .loadGymNames
	SetEvent EVENT_ENTER_ROOM
	farcall GymLeaderRandomItem
.loadGymNames
	; Unsaved buffers must be rebuilt after Continue, as in Viridian Gym.
	ld hl, OlivineGymNames.CityName
	ld de, OlivineGymNames.LeaderName
	call LoadGymLeaderAndCityName
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

; Authored names; one-time setup runs inline above.
OlivineGymNames:

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

	jp OlivineGymResetScripts

OlivineGym_TextPointers:
	def_text_pointers
	dw_const OlivineGymJasmineText,            TEXT_OLIVINEGYM_JASMINE
	dw_const OlivineGymLassText,              TEXT_OLIVINEGYM_LASS
	dw_const OlivineGymGentlemanText,         TEXT_OLIVINEGYM_GENTLEMAN
	dw_const OlivineGymEngineerText,          TEXT_OLIVINEGYM_ENGINEER
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
	trainer EVENT_BEAT_OLIVINE_GYM_TRAINER_0, 2, OlivineGymLassBattleText, OlivineGymLassEndBattleText, OlivineGymLassAfterBattleText
OlivineGymTrainerHeader1:
	trainer EVENT_BEAT_OLIVINE_GYM_TRAINER_1, 3, OlivineGymGentlemanBattleText, OlivineGymGentlemanEndBattleText, OlivineGymGentlemanAfterBattleText
OlivineGymTrainerHeader2:
	trainer EVENT_BEAT_OLIVINE_GYM_TRAINER_2, 2, OlivineGymEngineerBattleText, OlivineGymEngineerEndBattleText, OlivineGymEngineerAfterBattleText
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
	ret

ReceivedMineralBadgeText:
	text_far _OlivineGymJasmineReceivedBadgeText
	sound_get_key_item
	text_end

OlivineGymLassText:
	text_asm
	ld hl, OlivineGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

OlivineGymLassBattleText:
	text_far _OlivineGymLassBattleText
	text_end

OlivineGymLassEndBattleText:
	text_far _OlivineGymLassEndBattleText
	text_end

OlivineGymLassAfterBattleText:
	text_far _OlivineGymLassAfterBattleText
	text_end

OlivineGymGentlemanText:
	text_asm
	ld hl, OlivineGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

OlivineGymGentlemanBattleText:
	text_far _OlivineGymGentlemanBattleText
	text_end

OlivineGymGentlemanEndBattleText:
	text_far _OlivineGymGentlemanEndBattleText
	text_end

OlivineGymGentlemanAfterBattleText:
	text_far _OlivineGymGentlemanAfterBattleText
	text_end

OlivineGymEngineerText:
	text_asm
	ld hl, OlivineGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

OlivineGymEngineerBattleText:
	text_far _OlivineGymEngineerBattleText
	text_end

OlivineGymEngineerEndBattleText:
	text_far _OlivineGymEngineerEndBattleText
	text_end

OlivineGymEngineerAfterBattleText:
	text_far _OlivineGymEngineerAfterBattleText
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
