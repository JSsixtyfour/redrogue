AzaleaGym_Script:
	call BugsyShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	call z, initialAzalea
	call EnableAutoTextBoxDrawing
	ld hl, AzaleaGymTrainerHeaders
	ld de, AzaleaGym_ScriptPointers
	ld a, [wAzaleaGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wAzaleaGymCurScript], a
	ret

BugsyShowOrHideExitBlock:
; Blocks or clears the exit to the next room.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_BUGSY
	jr z, .blockExitToNextRoom
	ld a, $5
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $24
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

initialAzalea:
	SetEvent EVENT_ENTER_ROOM
	farcall GymLeaderRandomItem
	ld hl, .CityName
	ld de, .LeaderName
	jp LoadGymLeaderAndCityName

.CityName:
	db "AZALEA TOWN@"

.LeaderName:
	db "BUGSY@"

AzaleaGymResetScripts:
	xor a
	ldh [hJoyIgnore], a
	ld [wAzaleaGymCurScript], a
	ld [wCurMapScript], a
	ret

AzaleaGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_AZALEAGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_AZALEAGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_AZALEAGYM_END_BATTLE
	dw_const AzaleaGymBugsyPostBattle,              SCRIPT_AZALEAGYM_BUGSY_POST_BATTLE

AzaleaGymBugsyPostBattle:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, AzaleaGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
; fallthrough
AzaleaGymScriptReceiveTM:
	ld a, TEXT_AZALEAGYM_BUGSY_WAIT_TAKE_THIS
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
	ld a, TEXT_AZALEAGYM_RECEIVED_TM
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM_AZALEA
	jr .gymVictory
.BagFull
	ld a, TEXT_AZALEAGYM_TM_NO_ROOM
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

	ld a, TOGGLE_AZALEA_GYM_GUIDE
	ld [wToggleableObjectIndex], a
	predef HideObject

	jp AzaleaGymResetScripts

AzaleaGym_TextPointers:
	def_text_pointers
	dw_const AzaleaGymBugsyText,            TEXT_AZALEAGYM_BUGSY
	dw_const AzaleaGymCooltrainerM1Text,      TEXT_AZALEAGYM_COOLTRAINER_M1
	dw_const AzaleaGymCooltrainerM2Text,      TEXT_AZALEAGYM_COOLTRAINER_M2
	dw_const AzaleaGymCooltrainerM3Text,      TEXT_AZALEAGYM_COOLTRAINER_M3
	dw_const AzaleaGymCooltrainerM4Text,      TEXT_AZALEAGYM_COOLTRAINER_M4
	dw_const AzaleaGymGuideText,              TEXT_AZALEAGYM_GYM_GUIDE
	dw_const AzaleaGymBugsyWaitTakeThisText, TEXT_AZALEAGYM_BUGSY_WAIT_TAKE_THIS
	dw_const AzaleaGymReceivedTMText,         TEXT_AZALEAGYM_RECEIVED_TM
	dw_const AzaleaGymTMNoRoomText,           TEXT_AZALEAGYM_TM_NO_ROOM

AzaleaGymTrainerHeaders:
; def_trainers MUST be present and MUST come before the first `trainer`. Without
; it the macro silently inherits CURRENT_TRAINER_BIT from the previously
; INCLUDEd map in maps.asm and still assembles clean. See
; project_gametrainer_def_trainers_inheritance_bug.
	def_trainers 2
AzaleaGymTrainerHeader0:
	trainer EVENT_BEAT_AZALEA_GYM_TRAINER_0, 5, AzaleaGymCooltrainerM1BattleText, AzaleaGymCooltrainerM1EndBattleText, AzaleaGymCooltrainerM1AfterBattleText
AzaleaGymTrainerHeader1:
	trainer EVENT_BEAT_AZALEA_GYM_TRAINER_1, 2, AzaleaGymCooltrainerM2BattleText, AzaleaGymCooltrainerM2EndBattleText, AzaleaGymCooltrainerM2AfterBattleText
AzaleaGymTrainerHeader2:
	trainer EVENT_BEAT_AZALEA_GYM_TRAINER_2, 5, AzaleaGymCooltrainerM3BattleText, AzaleaGymCooltrainerM3EndBattleText, AzaleaGymCooltrainerM3AfterBattleText
AzaleaGymTrainerHeader3:
	trainer EVENT_BEAT_AZALEA_GYM_TRAINER_3, 5, AzaleaGymCooltrainerM4BattleText, AzaleaGymCooltrainerM4EndBattleText, AzaleaGymCooltrainerM4AfterBattleText
	db -1 ; end

AzaleaGymReceivedTMText:
	text_far _AzaleaGymReceivedTMText
	sound_get_item_1
	text_far _TM34ExplanationText
	text_end

AzaleaGymBugsyText:
	text_asm
	CheckEvent EVENT_BEAT_BUGSY
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM_AZALEA
	jr nz, .afterBeat
	call z, AzaleaGymScriptReceiveTM
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
	ld hl, AzaleaGymBugsyReceivedBadgeText
	ld de, AzaleaGymBugsyReceivedBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	ld a, $2
	ld [wGymLeaderNo], a
	call EngageMapTrainer
	ld d, OPP_BUGSY
	farcall InitGymBattle
	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_AZALEAGYM_BUGSY_POST_BATTLE
	ld [wAzaleaGymCurScript], a
	ld [wCurMapScript], a
.done
	jp TextScriptEnd

.PreBattleText:
	text_far _AzaleaGymBugsyPreBattleText
	text_end

.PostBattleAdviceText:
	text_far _AzaleaGymBugsyPostBattleAdviceText
	text_end

AzaleaGymBugsyWaitTakeThisText:
	text_far _AzaleaGymBugsyWaitTakeThisText
	text_end

AzaleaGymTMNoRoomText:
	text_far _AzaleaGymTMNoRoomText
	text_end

AzaleaGymBugsyReceivedBadgeText:
	text_asm
	SetEvent EVENT_BEAT_BUGSY
	ld hl, ReceivedHiveBadgeText
	call PrintText
	jp TextScriptEnd
	text_end

ReceivedHiveBadgeText:
	text_far _AzaleaGymBugsyReceivedBadgeText
	sound_get_key_item
	text_end

AzaleaGymCooltrainerM1Text:
	text_asm
	ld hl, AzaleaGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

AzaleaGymCooltrainerM1BattleText:
	text_far _AzaleaGymCooltrainerMBattleText
	text_end

AzaleaGymCooltrainerM1EndBattleText:
	text_far _AzaleaGymCooltrainerMEndBattleText
	text_end

AzaleaGymCooltrainerM1AfterBattleText:
	text_far _AzaleaGymCooltrainerMAfterBattleText
	text_end

AzaleaGymCooltrainerM2Text:
	text_asm
	ld hl, AzaleaGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

AzaleaGymCooltrainerM2BattleText:
	text_far _AzaleaGymCooltrainerMBattleText
	text_end

AzaleaGymCooltrainerM2EndBattleText:
	text_far _AzaleaGymCooltrainerMEndBattleText
	text_end

AzaleaGymCooltrainerM2AfterBattleText:
	text_far _AzaleaGymCooltrainerMAfterBattleText
	text_end

AzaleaGymCooltrainerM3Text:
	text_asm
	ld hl, AzaleaGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

AzaleaGymCooltrainerM3BattleText:
	text_far _AzaleaGymCooltrainerMBattleText
	text_end

AzaleaGymCooltrainerM3EndBattleText:
	text_far _AzaleaGymCooltrainerMEndBattleText
	text_end

AzaleaGymCooltrainerM3AfterBattleText:
	text_far _AzaleaGymCooltrainerMAfterBattleText
	text_end

AzaleaGymCooltrainerM4Text:
	text_asm
	ld hl, AzaleaGymTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

AzaleaGymCooltrainerM4BattleText:
	text_far _AzaleaGymCooltrainerMBattleText
	text_end

AzaleaGymCooltrainerM4EndBattleText:
	text_far _AzaleaGymCooltrainerMEndBattleText
	text_end

AzaleaGymCooltrainerM4AfterBattleText:
	text_far _AzaleaGymCooltrainerMAfterBattleText
	text_end

AzaleaGymGuideText:
	text_asm
	CheckEvent EVENT_BEAT_BUGSY
	ld hl, .Advice
	jr z, .print
	ld hl, .Victory
.print
	call PrintText
	jp TextScriptEnd

.Advice:
	text_far _AzaleaGymGuideAdviceText
	text_end

.Victory:
	text_far _AzaleaGymGuideVictoryText
	text_end
