WillsRoom_Script:
	call WillsRoomShowOrHideExitBlock
	call EnableAutoTextBoxDrawing
	ld hl, WillsRoomTrainerHeaders
	ld de, WillsRoom_ScriptPointers
	ld a, [wWillsRoomCurScript]
	call ExecuteCurMapScriptInTable
	ld [wWillsRoomCurScript], a
	ret

WillsRoomShowOrHideExitBlock:
; Blocks or clears the exit to the next room. Also re-patches this room's
; south/north warps to match this run's shuffled Elite Four order (see
; custom_functions/final_sequence.asm) - the order is randomized, so the
; ROM-authored (vanilla-order) warps would misroute otherwise. Idempotent,
; safe to run on every map load, including backtracking.
;
; The exit block ids are per TILESET, not per room: this is a GYM-tileset room,
; so it uses $5 open / $24 blocked like Bruno's and Lorelei's. Agatha's $e/$3b
; are the CEMETERY pair and would paint garbage here.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	ld d, OPP_WILL
	farcall Elite4PatchRoomWarps
	CheckEvent EVENT_BEAT_WILLS_ROOM_TRAINER_0
	jr z, .blockExitToNextRoom
	ld a, $5
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $24
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

ResetWillsRoomScript:
	xor a ; SCRIPT_WILLSROOM_DEFAULT
	ld [wWillsRoomCurScript], a
	ret

WillsRoom_ScriptPointers:
	def_script_pointers
	dw_const WillsRoomDefaultScript,              SCRIPT_WILLSROOM_DEFAULT
	dw_const WillsRoomStartBattleScript,          SCRIPT_WILLSROOM_WILL_START_BATTLE
	dw_const WillsRoomWillEndBattleScript,        SCRIPT_WILLSROOM_WILL_END_BATTLE
	dw_const WillsRoomPlayerIsMovingScript,       SCRIPT_WILLSROOM_PLAYER_IS_MOVING
	dw_const WillsRoomNoopScript,                 SCRIPT_WILLSROOM_NOOP

WillsRoomNoopScript:
	ret

; See LoreleisRoom.asm's LoreleisRoomStartBattleScript for the full comment
; on why this doesn't set wGymLeaderNo or wRogueFlagsBitfield bit 0.
WillsRoomStartBattleScript:
	ld d, OPP_WILL
	farcall InitElite4Battle
	jp DisplayEnemyTrainerTextAndStartBattle

WillsRoomWalkIntoRoom:
; Walk six steps upward.
	ld hl, wSimulatedJoypadStatesEnd
	ld a, PAD_UP
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ld a, $6
	ldh [hSimulatedJoypadStatesIndex], a
	call StartSimulatingJoypadStates
	ld a, SCRIPT_WILLSROOM_PLAYER_IS_MOVING
	ld [wWillsRoomCurScript], a
	ld [wCurMapScript], a
	ret

WillsRoomDefaultScript:
	ld hl, WillsRoomEntranceCoords
	call ArePlayerCoordsInArray
	jp nc, CheckFightingMapTrainers
	xor a
	ldh [hJoyPressed], a
	ldh [hJoyHeld], a
	ld [wSimulatedJoypadStatesEnd], a
	ldh [hSimulatedJoypadStatesIndex], a
	ld a, [wCoordIndex]
	cp $3  ; Is player standing one tile above the exit?
	jr c, .stopPlayerFromLeaving
	CheckAndSetEvent EVENT_AUTOWALKED_INTO_WILLS_ROOM
	jr z, WillsRoomWalkIntoRoom
.stopPlayerFromLeaving
	ld a, TEXT_WILLSROOM_WILL_DONT_RUN_AWAY
	ldh [hTextID], a
	call DisplayTextID
	ld a, PAD_UP
	ld [wSimulatedJoypadStatesEnd], a
	ld a, $1
	ldh [hSimulatedJoypadStatesIndex], a
	call StartSimulatingJoypadStates
	ld a, SCRIPT_WILLSROOM_PLAYER_IS_MOVING
	ld [wWillsRoomCurScript], a
	ld [wCurMapScript], a
	ret

WillsRoomEntranceCoords:
; Rows 12 and 13, NOT the 10/11 the three original rooms use: this map is
; 7 blocks tall (14 steps), so its bottom row is 13. Get this wrong and the
; entrance auto-walk either never fires or fires one step early, and nothing
; in the build notices.
	dbmapcoord  4, 12
	dbmapcoord  5, 12
	dbmapcoord  4, 13
	dbmapcoord  5, 13
	db -1 ; end

WillsRoomPlayerIsMovingScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3
	xor a
	ldh [hJoyIgnore], a
	ld [wWillsRoomCurScript], a
	ld [wCurMapScript], a
	ret

WillsRoomWillEndBattleScript:
; The Champion room is armed generically by Elite4PatchRoomWarps, only when
; Will actually IS the last (wRunElite4[3]) member this run.
	call EndTrainerBattle
	ldh a, [hIsInBattle]
	cp $ff
	jp z, ResetWillsRoomScript
	farcall RogueAwardCredits2
	ld a, TEXT_WILLSROOM_WILL
	ldh [hTextID], a
	call DisplayTextID
; ELEMENT PRISM cartridge. Granted and announced from its own text id so
; PrintText runs inside DisplayTextID - fired raw from this map script, the
; announcement drew an invisible box that silently waited for A. Gated here
; on the grant's own one-time event so a repeat win shows no empty box.
	CheckEvent EVENT_PRISM_E4_PSYCHIC_SHOWN
	ret nz
	ld a, TEXT_WILLSROOM_PRISM
	ldh [hTextID], a
	jp DisplayTextID

WillsRoom_TextPointers:
	def_text_pointers
	dw_const WillsRoomWillText,            TEXT_WILLSROOM_WILL
	dw_const WillsRoomWillDontRunAwayText, TEXT_WILLSROOM_WILL_DONT_RUN_AWAY
	dw_const WillsRoomPrismText, TEXT_WILLSROOM_PRISM

WillsRoomTrainerHeaders:
	def_trainers
WillsRoomTrainerHeader0:
	trainer EVENT_BEAT_WILLS_ROOM_TRAINER_0, 0, WillBeforeBattleText, WillEndBattleText, WillAfterBattleText
	db -1 ; end

WillsRoomWillText:
	text_asm
	ld hl, WillsRoomTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

WillBeforeBattleText:
	text_far _WillBeforeBattleText
	text_end

WillEndBattleText:
	text_far _WillEndBattleText
	text_end

WillAfterBattleText:
	text_asm
	ld a, [wBattleCount]
	cp 90
	ld hl, .Normal
	jr c, .print
	ld hl, .GoToChampion
.print
	call PrintText
	jp TextScriptEnd
.Normal
	text_far _WillAfterBattleText
	text_end
.GoToChampion
	text_far _Elite4GoToChampionText
	text_end

WillsRoomWillDontRunAwayText:
	text_far _WillsRoomWillDontRunAwayText
	text_end

WillsRoomPrismText:
	text_asm
	farcall RogueGrantCartridgePsychic
	call DisableWaitingAfterTextDisplay ; the message carries its own prompt
	jp TextScriptEnd
