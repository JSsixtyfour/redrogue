EcruteakGym_Script:
	call MortyShowOrHideExitBlock
	CheckEvent EVENT_ENTER_ROOM
	call z, initialEcruteak
	call EnableAutoTextBoxDrawing
	ld hl, EcruteakGymTrainerHeaders
	ld de, EcruteakGym_ScriptPointers
	ld a, [wEcruteakGymCurScript]
	call ExecuteCurMapScriptInTable
	ld [wEcruteakGymCurScript], a
	ret

MortyShowOrHideExitBlock:
; Blocks or clears the exit to the next room.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	CheckEvent EVENT_BEAT_MORTY
	jr z, .blockExitToNextRoom
	ld a, $E
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $3B
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

initialEcruteak:
	SetEvent EVENT_ENTER_ROOM
	farcall GymLeaderRandomItem
	ld hl, .CityName
	ld de, .LeaderName
	jp LoadGymLeaderAndCityName

.CityName:
	db "ECRUTEAK CITY@"

.LeaderName:
	db "MORTY@"

EcruteakGymResetScripts:
	xor a
	ldh [hJoyIgnore], a
	ld [wEcruteakGymCurScript], a
	ld [wCurMapScript], a
	ret

EcruteakGym_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_ECRUTEAKGYM_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_ECRUTEAKGYM_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_ECRUTEAKGYM_END_BATTLE
	dw_const EcruteakGymMortyPostBattle,            SCRIPT_ECRUTEAKGYM_MORTY_POST_BATTLE

EcruteakGymMortyPostBattle:
	ldh a, [hIsInBattle]
	cp $ff
	jp z, EcruteakGymResetScripts
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
; fallthrough
EcruteakGymScriptReceiveTM:
	ld a, TEXT_ECRUTEAKGYM_MORTY_WAIT_TAKE_THIS
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
	ld a, TEXT_ECRUTEAKGYM_RECEIVED_TM
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_GOT_TM_ECRUTEAK
	jr .gymVictory
.BagFull
	ld a, TEXT_ECRUTEAKGYM_TM_NO_ROOM
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

	ld a, TOGGLE_ECRUTEAK_GYM_GUIDE
	ld [wToggleableObjectIndex], a
	predef HideObject

	jp EcruteakGymResetScripts

EcruteakGym_TextPointers:
	def_text_pointers
	dw_const EcruteakGymMortyText,            TEXT_ECRUTEAKGYM_MORTY
	dw_const EcruteakGymCooltrainerM1Text,      TEXT_ECRUTEAKGYM_COOLTRAINER_M1
	dw_const EcruteakGymCooltrainerM2Text,      TEXT_ECRUTEAKGYM_COOLTRAINER_M2
	dw_const EcruteakGymCooltrainerM3Text,      TEXT_ECRUTEAKGYM_COOLTRAINER_M3
	dw_const EcruteakGymCooltrainerM4Text,      TEXT_ECRUTEAKGYM_COOLTRAINER_M4
	dw_const EcruteakGymGuideText,              TEXT_ECRUTEAKGYM_GYM_GUIDE
	dw_const EcruteakGymMortyWaitTakeThisText, TEXT_ECRUTEAKGYM_MORTY_WAIT_TAKE_THIS
	dw_const EcruteakGymReceivedTMText,         TEXT_ECRUTEAKGYM_RECEIVED_TM
	dw_const EcruteakGymTMNoRoomText,           TEXT_ECRUTEAKGYM_TM_NO_ROOM

EcruteakGymTrainerHeaders:
; def_trainers MUST be present and MUST come before the first `trainer`. Without
; it the macro silently inherits CURRENT_TRAINER_BIT from the previously
; INCLUDEd map in maps.asm and still assembles clean. See
; project_gametrainer_def_trainers_inheritance_bug.
	def_trainers 2
EcruteakGymTrainerHeader0:
	trainer EVENT_BEAT_ECRUTEAK_GYM_TRAINER_0, 5, EcruteakGymCooltrainerM1BattleText, EcruteakGymCooltrainerM1EndBattleText, EcruteakGymCooltrainerM1AfterBattleText
EcruteakGymTrainerHeader1:
	trainer EVENT_BEAT_ECRUTEAK_GYM_TRAINER_1, 2, EcruteakGymCooltrainerM2BattleText, EcruteakGymCooltrainerM2EndBattleText, EcruteakGymCooltrainerM2AfterBattleText
EcruteakGymTrainerHeader2:
	trainer EVENT_BEAT_ECRUTEAK_GYM_TRAINER_2, 5, EcruteakGymCooltrainerM3BattleText, EcruteakGymCooltrainerM3EndBattleText, EcruteakGymCooltrainerM3AfterBattleText
EcruteakGymTrainerHeader3:
	trainer EVENT_BEAT_ECRUTEAK_GYM_TRAINER_3, 5, EcruteakGymCooltrainerM4BattleText, EcruteakGymCooltrainerM4EndBattleText, EcruteakGymCooltrainerM4AfterBattleText
	db -1 ; end

EcruteakGymReceivedTMText:
	text_far _EcruteakGymReceivedTMText
	sound_get_item_1
	text_far _TM34ExplanationText
	text_end

EcruteakGymMortyText:
	text_asm
	CheckEvent EVENT_BEAT_MORTY
	jr z, .beforeBeat
	CheckEventReuseA EVENT_GOT_TM_ECRUTEAK
	jr nz, .afterBeat
	call z, EcruteakGymScriptReceiveTM
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
	ld hl, EcruteakGymMortyReceivedBadgeText
	ld de, EcruteakGymMortyReceivedBadgeText
	call SaveEndBattleTextPointers
	ldh a, [hSpriteIndex]
	ldh [hActiveSpriteIndex], a
	ld a, $4
	ld [wGymLeaderNo], a
	call EngageMapTrainer
	ld d, OPP_MORTY
	farcall InitGymBattle
	xor a
	ldh [hJoyHeld], a
	ld a, SCRIPT_ECRUTEAKGYM_MORTY_POST_BATTLE
	ld [wEcruteakGymCurScript], a
	ld [wCurMapScript], a
.done
	jp TextScriptEnd

.PreBattleText:
	text_far _EcruteakGymMortyPreBattleText
	text_end

.PostBattleAdviceText:
	text_far _EcruteakGymMortyPostBattleAdviceText
	text_end

EcruteakGymMortyWaitTakeThisText:
	text_far _EcruteakGymMortyWaitTakeThisText
	text_end

EcruteakGymTMNoRoomText:
	text_far _EcruteakGymTMNoRoomText
	text_end

EcruteakGymMortyReceivedBadgeText:
	text_asm
	SetEvent EVENT_BEAT_MORTY
	ld hl, ReceivedFogBadgeText
	call PrintText
	jp TextScriptEnd
	text_end

ReceivedFogBadgeText:
	text_far _EcruteakGymMortyReceivedBadgeText
	sound_get_key_item
	text_end

EcruteakGymCooltrainerM1Text:
	text_asm
	ld hl, EcruteakGymTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

EcruteakGymCooltrainerM1BattleText:
	text_far _EcruteakGymCooltrainerMBattleText
	text_end

EcruteakGymCooltrainerM1EndBattleText:
	text_far _EcruteakGymCooltrainerMEndBattleText
	text_end

EcruteakGymCooltrainerM1AfterBattleText:
	text_far _EcruteakGymCooltrainerMAfterBattleText
	text_end

EcruteakGymCooltrainerM2Text:
	text_asm
	ld hl, EcruteakGymTrainerHeader1
	call TalkToTrainer
	jp TextScriptEnd

EcruteakGymCooltrainerM2BattleText:
	text_far _EcruteakGymCooltrainerMBattleText
	text_end

EcruteakGymCooltrainerM2EndBattleText:
	text_far _EcruteakGymCooltrainerMEndBattleText
	text_end

EcruteakGymCooltrainerM2AfterBattleText:
	text_far _EcruteakGymCooltrainerMAfterBattleText
	text_end

EcruteakGymCooltrainerM3Text:
	text_asm
	ld hl, EcruteakGymTrainerHeader2
	call TalkToTrainer
	jp TextScriptEnd

EcruteakGymCooltrainerM3BattleText:
	text_far _EcruteakGymCooltrainerMBattleText
	text_end

EcruteakGymCooltrainerM3EndBattleText:
	text_far _EcruteakGymCooltrainerMEndBattleText
	text_end

EcruteakGymCooltrainerM3AfterBattleText:
	text_far _EcruteakGymCooltrainerMAfterBattleText
	text_end

EcruteakGymCooltrainerM4Text:
	text_asm
	ld hl, EcruteakGymTrainerHeader3
	call TalkToTrainer
	jp TextScriptEnd

EcruteakGymCooltrainerM4BattleText:
	text_far _EcruteakGymCooltrainerMBattleText
	text_end

EcruteakGymCooltrainerM4EndBattleText:
	text_far _EcruteakGymCooltrainerMEndBattleText
	text_end

EcruteakGymCooltrainerM4AfterBattleText:
	text_far _EcruteakGymCooltrainerMAfterBattleText
	text_end

EcruteakGymGuideText:
	text_asm
	CheckEvent EVENT_BEAT_MORTY
	ld hl, .Advice
	jr z, .print
	ld hl, .Victory
.print
	call PrintText
	jp TextScriptEnd

.Advice:
	text_far _EcruteakGymGuideAdviceText
	text_end

.Victory:
	text_far _EcruteakGymGuideVictoryText
	text_end
