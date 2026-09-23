KogasRoom_Script:
	call KogasRoomShowOrHideExitBlock
	call EnableAutoTextBoxDrawing
	ld hl, KogasRoomTrainerHeaders
	ld de, KogasRoom_ScriptPointers
	ld a, [wKogasRoomCurScript]
	call ExecuteCurMapScriptInTable
	ld [wKogasRoomCurScript], a
	ret

KogasRoomShowOrHideExitBlock:
; Blocks or clears the exit to the next room. Also re-patches this room's
; south/north warps to match this run's shuffled Elite Four order (see
; custom_functions/final_sequence.asm) - the order is randomized, so the
; ROM-authored (vanilla-order) warps would misroute otherwise. Idempotent,
; safe to run on every map load, including backtracking.
;
; The exit block ids are per TILESET, not per room: this is a FOREST-tileset
; room (maps/koga2forest.blk, 2026-09-23), so it uses $00 open path / $17
; blocked. The GYM pair ($5/$24) Bruno, Lorelei and Will use, and Agatha's
; CEMETERY pair ($e/$3b), would both paint garbage here.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	ld d, OPP_KOGA_E4
	farcall Elite4PatchRoomWarps
	CheckEvent EVENT_BEAT_KOGAS_ROOM_TRAINER_0
	jr z, .blockExitToNextRoom
	ld a, $00
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $17
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 2
	predef_jump ReplaceTileBlock

ResetKogasRoomScript:
	xor a ; SCRIPT_KOGASROOM_DEFAULT
	ld [wKogasRoomCurScript], a
	ret

KogasRoom_ScriptPointers:
	def_script_pointers
	dw_const KogasRoomDefaultScript,              SCRIPT_KOGASROOM_DEFAULT
	dw_const KogasRoomStartBattleScript,          SCRIPT_KOGASROOM_KOGA_START_BATTLE
	dw_const KogasRoomKogaEndBattleScript,        SCRIPT_KOGASROOM_KOGA_END_BATTLE
	dw_const KogasRoomPlayerIsMovingScript,       SCRIPT_KOGASROOM_PLAYER_IS_MOVING
	dw_const KogasRoomNoopScript,                 SCRIPT_KOGASROOM_NOOP

KogasRoomNoopScript:
	ret

; See LoreleisRoom.asm's LoreleisRoomStartBattleScript for the full comment
; on why this doesn't set wGymLeaderNo or wRogueFlagsBitfield bit 0.
KogasRoomStartBattleScript:
	ld d, OPP_KOGA_E4
	farcall InitElite4Battle
	jp DisplayEnemyTrainerTextAndStartBattle

KogasRoomWalkIntoRoom:
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
	ld a, SCRIPT_KOGASROOM_PLAYER_IS_MOVING
	ld [wKogasRoomCurScript], a
	ld [wCurMapScript], a
	ret

KogasRoomDefaultScript:
	ld hl, KogasRoomEntranceCoords
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
	CheckAndSetEvent EVENT_AUTOWALKED_INTO_KOGAS_ROOM
	jr z, KogasRoomWalkIntoRoom
.stopPlayerFromLeaving
	ld a, TEXT_KOGASROOM_KOGA_DONT_RUN_AWAY
	ldh [hTextID], a
	call DisplayTextID
	ld a, PAD_UP
	ld [wSimulatedJoypadStatesEnd], a
	ld a, $1
	ldh [hSimulatedJoypadStatesIndex], a
	call StartSimulatingJoypadStates
	ld a, SCRIPT_KOGASROOM_PLAYER_IS_MOVING
	ld [wKogasRoomCurScript], a
	ld [wCurMapScript], a
	ret

KogasRoomEntranceCoords:
; Rows 12 and 13, NOT the 10/11 the three original rooms use: this map is
; 7 blocks tall (14 steps), so its bottom row is 13. Get this wrong and the
; entrance auto-walk either never fires or fires one step early, and nothing
; in the build notices.
	dbmapcoord  4, 12
	dbmapcoord  5, 12
	dbmapcoord  4, 13
	dbmapcoord  5, 13
	db -1 ; end

KogasRoomPlayerIsMovingScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3
	xor a
	ldh [hJoyIgnore], a
	ld [wKogasRoomCurScript], a
	ld [wCurMapScript], a
	ret

KogasRoomKogaEndBattleScript:
; The Champion room is armed generically by Elite4PatchRoomWarps, only when
; Koga actually IS the last (wRunElite4[3]) member this run.
	call EndTrainerBattle
	ldh a, [hIsInBattle]
	cp $ff
	jp z, ResetKogasRoomScript
	farcall RogueAwardCredits2
	ld a, TEXT_KOGASROOM_KOGA
	ldh [hTextID], a
	call DisplayTextID
; ELEMENT PRISM cartridge. Granted and announced from its own text id so
; PrintText runs inside DisplayTextID - fired raw from this map script, the
; announcement drew an invisible box that silently waited for A. Gated here
; on the grant's own one-time event so a repeat win shows no empty box.
	CheckEvent EVENT_PRISM_E4_POISON_SHOWN
	ret nz
	ld a, TEXT_KOGASROOM_PRISM
	ldh [hTextID], a
	jp DisplayTextID

KogasRoom_TextPointers:
	def_text_pointers
	dw_const KogasRoomKogaText,            TEXT_KOGASROOM_KOGA
	dw_const KogasRoomKogaDontRunAwayText, TEXT_KOGASROOM_KOGA_DONT_RUN_AWAY
	dw_const KogasRoomPrismText, TEXT_KOGASROOM_PRISM

KogasRoomTrainerHeaders:
	def_trainers
KogasRoomTrainerHeader0:
	trainer EVENT_BEAT_KOGAS_ROOM_TRAINER_0, 0, KogaBeforeBattleText, KogaEndBattleText, KogaAfterBattleText
	db -1 ; end

KogasRoomKogaText:
	text_asm
	ld hl, KogasRoomTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

KogaBeforeBattleText:
	text_far _KogaBeforeBattleText
	text_end

KogaEndBattleText:
	text_far _KogaEndBattleText
	text_end

KogaAfterBattleText:
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
	text_far _KogaAfterBattleText
	text_end
.GoToChampion
	text_far _Elite4GoToChampionText
	text_end

KogasRoomKogaDontRunAwayText:
	text_far _KogasRoomKogaDontRunAwayText
	text_end

KogasRoomPrismText:
	text_asm
	farcall RogueGrantCartridgePoison
	call DisableWaitingAfterTextDisplay ; the message carries its own prompt
	jp TextScriptEnd
