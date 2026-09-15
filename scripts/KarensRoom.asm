KarensRoom_Script:
	call KarensRoomShowOrHideExitBlock
	call EnableAutoTextBoxDrawing
	ld hl, KarensRoomTrainerHeaders
	ld de, KarensRoom_ScriptPointers
	ld a, [wKarensRoomCurScript]
	call ExecuteCurMapScriptInTable
	ld [wKarensRoomCurScript], a
	ret

KarensRoomShowOrHideExitBlock:
; Blocks or clears the exit to the next room. Also re-patches this room's
; south/north warps to match this run's shuffled Elite Four order (see
; custom_functions/final_sequence.asm) - the order is randomized, so the
; ROM-authored (vanilla-order) warps would misroute otherwise. Idempotent,
; safe to run on every map load, including backtracking.
;
; The exit block ids are per TILESET, not per room: this is a CEMETERY-tileset
; room, so it uses $e open / $3b blocked like Agatha's. The $5/$24 pair Bruno,
; Lorelei, Koga and Will use is the GYM one and would paint garbage here.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	ld d, OPP_KAREN
	farcall Elite4PatchRoomWarps
	CheckEvent EVENT_BEAT_KARENS_ROOM_TRAINER_0
	jr z, .blockExitToNextRoom
	ld a, $e
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $3b
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

ResetKarensRoomScript:
	xor a ; SCRIPT_KARENSROOM_DEFAULT
	ld [wKarensRoomCurScript], a
	ret

KarensRoom_ScriptPointers:
	def_script_pointers
	dw_const KarensRoomDefaultScript,              SCRIPT_KARENSROOM_DEFAULT
	dw_const KarensRoomStartBattleScript,          SCRIPT_KARENSROOM_KAREN_START_BATTLE
	dw_const KarensRoomKarenEndBattleScript,        SCRIPT_KARENSROOM_KAREN_END_BATTLE
	dw_const KarensRoomPlayerIsMovingScript,       SCRIPT_KARENSROOM_PLAYER_IS_MOVING
	dw_const KarensRoomNoopScript,                 SCRIPT_KARENSROOM_NOOP

KarensRoomNoopScript:
	ret

; See LoreleisRoom.asm's LoreleisRoomStartBattleScript for the full comment
; on why this doesn't set wGymLeaderNo or wRogueFlagsBitfield bit 0.
KarensRoomStartBattleScript:
	ld d, OPP_KAREN
	farcall InitElite4Battle
	jp DisplayEnemyTrainerTextAndStartBattle

KarensRoomWalkIntoRoom:
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
	ld a, SCRIPT_KARENSROOM_PLAYER_IS_MOVING
	ld [wKarensRoomCurScript], a
	ld [wCurMapScript], a
	ret

KarensRoomDefaultScript:
	ld hl, KarensRoomEntranceCoords
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
	CheckAndSetEvent EVENT_AUTOWALKED_INTO_KARENS_ROOM
	jr z, KarensRoomWalkIntoRoom
.stopPlayerFromLeaving
	ld a, TEXT_KARENSROOM_KAREN_DONT_RUN_AWAY
	ldh [hTextID], a
	call DisplayTextID
	ld a, PAD_UP
	ld [wSimulatedJoypadStatesEnd], a
	ld a, $1
	ldh [hSimulatedJoypadStatesIndex], a
	call StartSimulatingJoypadStates
	ld a, SCRIPT_KARENSROOM_PLAYER_IS_MOVING
	ld [wKarensRoomCurScript], a
	ld [wCurMapScript], a
	ret

KarensRoomEntranceCoords:
; Rows 14 and 15, NOT the 10/11 the three original rooms use and NOT the 12/13
; Koga and Will use: this map is 8 blocks tall (16 steps), so its bottom row is
; 15. Get this wrong and the entrance auto-walk either never fires or fires one
; step early, and nothing in the build notices.
	dbmapcoord  4, 14
	dbmapcoord  5, 14
	dbmapcoord  4, 15
	dbmapcoord  5, 15
	db -1 ; end

KarensRoomPlayerIsMovingScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3
	xor a
	ldh [hJoyIgnore], a
	ld [wKarensRoomCurScript], a
	ld [wCurMapScript], a
	ret

KarensRoomKarenEndBattleScript:
; The Champion room is armed generically by Elite4PatchRoomWarps, only when
; Karen actually IS the last (wRunElite4[3]) member this run.
	call EndTrainerBattle
	ldh a, [hIsInBattle]
	cp $ff
	jp z, ResetKarensRoomScript
	farcall RogueAwardCredits2
	; No ELEMENT PRISM cartridge: Karen's signature type is DARK, which does not
	; exist in Gen 1, and GHOST is already Agatha's. User decision 2026-09-15 is
	; that she awards credits only rather than duplicating another member's type,
	; whose one-time event gate would silently grant nothing to whoever came second.
	ld a, TEXT_KARENSROOM_KAREN
	ldh [hTextID], a
	jp DisplayTextID

KarensRoom_TextPointers:
	def_text_pointers
	dw_const KarensRoomKarenText,            TEXT_KARENSROOM_KAREN
	dw_const KarensRoomKarenDontRunAwayText, TEXT_KARENSROOM_KAREN_DONT_RUN_AWAY

KarensRoomTrainerHeaders:
	def_trainers
KarensRoomTrainerHeader0:
	trainer EVENT_BEAT_KARENS_ROOM_TRAINER_0, 0, KarenBeforeBattleText, KarenEndBattleText, KarenAfterBattleText
	db -1 ; end

KarensRoomKarenText:
	text_asm
	ld hl, KarensRoomTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

KarenBeforeBattleText:
	text_far _KarenBeforeBattleText
	text_end

KarenEndBattleText:
	text_far _KarenEndBattleText
	text_end

KarenAfterBattleText:
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
	text_far _KarenAfterBattleText
	text_end
.GoToChampion
	text_far _Elite4GoToChampionText
	text_end

KarensRoomKarenDontRunAwayText:
	text_far _KarensRoomKarenDontRunAwayText
	text_end
