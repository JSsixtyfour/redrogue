BlackthornGym_Script:
	call ClairShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	call z, initialBlackthorn
	call EnableAutoTextBoxDrawing
	ld hl, BlackthornGymTrainerHeaders
	ld de, BlackthornGym_ScriptPointers
	ld a, [wBlackthornGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wBlackthornGymCurScript], a
	ret

ClairShowOrHideExitBlock:
; Blocks or clears the exit to the next room.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_CLAIR
	jr z, .blockExitToNextRoom
	ld a, $5
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $24
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

initialBlackthorn:
	SetEvent EVENT_ENTER_ROOM
	farcall GymLeaderRandomItem
	ld hl, .CityName
	ld de, .LeaderName
	jp LoadGymLeaderAndCityName

.CityName:
	db "BLACKTHORN CITY@"

.LeaderName:
	db "CLAIR@"

BlackthornGymResetScripts:
	xor a
	ldh [hJoyIgnore], a
	ld [wBlackthornGymCurScript], a
	ld [wCurMapScript], a
	ret

BlackthornGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_BLACKTHORNGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_BLACKTHORNGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_BLACKTHORNGYM_END_BATTLE
	dw_const BlackthornGymClairPostBattle,          SCRIPT_BLACKTHORNGYM_CLAIR_POST_BATTLE

BlackthornGymClairPostBattle:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, BlackthornGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
; fallthrough
BlackthornGymScriptReceiveTM:
	ld a, TEXT_BLACKTHORNGYM_CLAIR_WAIT_TAKE_THIS
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
	ld a, TEXT_BLACKTHORNGYM_RECEIVED_TM
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM_BLACKTHORN
	jr .gymVictory
.BagFull
	ld a, TEXT_BLACKTHORNGYM_TM_NO_ROOM
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

	ld a, TOGGLE_BLACKTHORN_GYM_GUIDE
	ld [wToggleableObjectIndex], a
	predef HideObject

	jp BlackthornGymResetScripts

BlackthornGym_TextPointers:
	def_text_pointers
	dw_const BlackthornGymClairText,            TEXT_BLACKTHORNGYM_CLAIR
	dw_const BlackthornGymCooltrainerM1Text,      TEXT_BLACKTHORNGYM_COOLTRAINER_M1
	dw_const BlackthornGymCooltrainerM2Text,      TEXT_BLACKTHORNGYM_COOLTRAINER_M2
	dw_const BlackthornGymCooltrainerM3Text,      TEXT_BLACKTHORNGYM_COOLTRAINER_M3
	dw_const BlackthornGymCooltrainerM4Text,      TEXT_BLACKTHORNGYM_COOLTRAINER_M4
	dw_const BlackthornGymGuideText,              TEXT_BLACKTHORNGYM_GYM_GUIDE
	dw_const BlackthornGymClairWaitTakeThisText, TEXT_BLACKTHORNGYM_CLAIR_WAIT_TAKE_THIS
	dw_const BlackthornGymReceivedTMText,         TEXT_BLACKTHORNGYM_RECEIVED_TM
	dw_const BlackthornGymTMNoRoomText,           TEXT_BLACKTHORNGYM_TM_NO_ROOM

BlackthornGymTrainerHeaders:
; def_trainers MUST be present and MUST come before the first `trainer`. Without
; it the macro silently inherits CURRENT_TRAINER_BIT from the previously
; INCLUDEd map in maps.asm and still assembles clean. See
; project_gametrainer_def_trainers_inheritance_bug.
	def_trainers 2
BlackthornGymTrainerHeader0:
	trainer EVENT_BEAT_BLACKTHORN_GYM_TRAINER_0, 5, BlackthornGymCooltrainerM1BattleText, BlackthornGymCooltrainerM1EndBattleText, BlackthornGymCooltrainerM1AfterBattleText
BlackthornGymTrainerHeader1:
	trainer EVENT_BEAT_BLACKTHORN_GYM_TRAINER_1, 2, BlackthornGymCooltrainerM2BattleText, BlackthornGymCooltrainerM2EndBattleText, BlackthornGymCooltrainerM2AfterBattleText
BlackthornGymTrainerHeader2:
	trainer EVENT_BEAT_BLACKTHORN_GYM_TRAINER_2, 5, BlackthornGymCooltrainerM3BattleText, BlackthornGymCooltrainerM3EndBattleText, BlackthornGymCooltrainerM3AfterBattleText
BlackthornGymTrainerHeader3:
	trainer EVENT_BEAT_BLACKTHORN_GYM_TRAINER_3, 5, BlackthornGymCooltrainerM4BattleText, BlackthornGymCooltrainerM4EndBattleText, BlackthornGymCooltrainerM4AfterBattleText
	db -1 ; end

BlackthornGymReceivedTMText:
	text_far _BlackthornGymReceivedTMText
	sound_get_item_1
	text_far _TM34ExplanationText
	text_end

BlackthornGymClairText:
	text_asm
	CheckEvent EVENT_BEAT_CLAIR
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM_BLACKTHORN
	jr nz, .afterBeat
	call z, BlackthornGymScriptReceiveTM
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
	ld hl, BlackthornGymClairReceivedBadgeText
	ld de, BlackthornGymClairReceivedBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	ld a, $8
	ld [wGymLeaderNo], a
	call EngageMapTrainer
	ld d, OPP_CLAIR
	farcall InitGymBattle
	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_BLACKTHORNGYM_CLAIR_POST_BATTLE
	ld [wBlackthornGymCurScript], a
	ld [wCurMapScript], a
.done
	jp TextScriptEnd

.PreBattleText:
	text_far _BlackthornGymClairPreBattleText
	text_end

.PostBattleAdviceText:
	text_far _BlackthornGymClairPostBattleAdviceText
	text_end

BlackthornGymClairWaitTakeThisText:
	text_far _BlackthornGymClairWaitTakeThisText
	text_end

BlackthornGymTMNoRoomText:
	text_far _BlackthornGymTMNoRoomText
	text_end

BlackthornGymClairReceivedBadgeText:
	text_asm
	SetEvent EVENT_BEAT_CLAIR
	ld hl, ReceivedRisingBadgeText
	call PrintText
	jp TextScriptEnd
	text_end

ReceivedRisingBadgeText:
	text_far _BlackthornGymClairReceivedBadgeText
	sound_get_key_item
	text_end

BlackthornGymCooltrainerM1Text:
	text_asm
	ld hl, BlackthornGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

BlackthornGymCooltrainerM1BattleText:
	text_far _BlackthornGymCooltrainerMBattleText
	text_end

BlackthornGymCooltrainerM1EndBattleText:
	text_far _BlackthornGymCooltrainerMEndBattleText
	text_end

BlackthornGymCooltrainerM1AfterBattleText:
	text_far _BlackthornGymCooltrainerMAfterBattleText
	text_end

BlackthornGymCooltrainerM2Text:
	text_asm
	ld hl, BlackthornGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

BlackthornGymCooltrainerM2BattleText:
	text_far _BlackthornGymCooltrainerMBattleText
	text_end

BlackthornGymCooltrainerM2EndBattleText:
	text_far _BlackthornGymCooltrainerMEndBattleText
	text_end

BlackthornGymCooltrainerM2AfterBattleText:
	text_far _BlackthornGymCooltrainerMAfterBattleText
	text_end

BlackthornGymCooltrainerM3Text:
	text_asm
	ld hl, BlackthornGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

BlackthornGymCooltrainerM3BattleText:
	text_far _BlackthornGymCooltrainerMBattleText
	text_end

BlackthornGymCooltrainerM3EndBattleText:
	text_far _BlackthornGymCooltrainerMEndBattleText
	text_end

BlackthornGymCooltrainerM3AfterBattleText:
	text_far _BlackthornGymCooltrainerMAfterBattleText
	text_end

BlackthornGymCooltrainerM4Text:
	text_asm
	ld hl, BlackthornGymTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

BlackthornGymCooltrainerM4BattleText:
	text_far _BlackthornGymCooltrainerMBattleText
	text_end

BlackthornGymCooltrainerM4EndBattleText:
	text_far _BlackthornGymCooltrainerMEndBattleText
	text_end

BlackthornGymCooltrainerM4AfterBattleText:
	text_far _BlackthornGymCooltrainerMAfterBattleText
	text_end

BlackthornGymGuideText:
	text_asm
	CheckEvent EVENT_BEAT_CLAIR
	ld hl, .Advice
	jr z, .print
	ld hl, .Victory
.print
	call PrintText
	jp TextScriptEnd

.Advice:
	text_far _BlackthornGymGuideAdviceText
	text_end

.Victory:
	text_far _BlackthornGymGuideVictoryText
	text_end
