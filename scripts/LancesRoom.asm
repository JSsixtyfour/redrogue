LancesRoom_Script:
	call LanceShowOrHideEntranceBlocks
	call EnableAutoTextBoxDrawing
	ld hl, LancesRoomTrainerHeaders
	ld de, LancesRoom_ScriptPointers
	ld a, [wLancesRoomCurScript]
	call ExecuteCurMapScriptInTable
	ld [wLancesRoomCurScript], a
	ret

LanceShowOrHideEntranceBlocks:
; Also re-patches this room's south/north warps to match this run's
; shuffled Elite Four order (see custom_functions/final_sequence.asm) - the
; order is randomized, so the ROM-authored (vanilla-order) warps would
; misroute otherwise. Idempotent, safe to run every time this fires
; (map load, and again when the entrance locks behind the player).
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	ld d, OPP_LANCE
	farcall Elite4PatchRoomWarps
	CheckEvent EVENT_LANCES_ROOM_LOCK_DOOR
	jr nz, .closeEntrance
	; open entrance
	ld a, $31
	ld b, $32
	jp .setEntranceBlocks
.closeEntrance
	ld a, $72
	ld b, $73
.setEntranceBlocks
; Replaces the tile blocks so the player can't leave.
	push bc
	ld [wNewTileBlockID], a
	lb bc, 6, 2
	call .SetEntranceBlock
	pop bc
	ld a, b
	ld [wNewTileBlockID], a
	lb bc, 6, 3
.SetEntranceBlock:
	predef_jump ReplaceTileBlock

ResetLanceScript:
	xor a ; SCRIPT_LANCESROOM_DEFAULT
	ld [wLancesRoomCurScript], a
	ret

LancesRoom_ScriptPointers:
	def_script_pointers
	dw_const LancesRoomDefaultScript,               SCRIPT_LANCESROOM_DEFAULT
	dw_const LancesRoomStartBattleScript,           SCRIPT_LANCESROOM_LANCE_START_BATTLE
	dw_const LancesRoomLanceEndBattleScript,        SCRIPT_LANCESROOM_LANCE_END_BATTLE
	dw_const LancesRoomPlayerIsMovingScript,        SCRIPT_LANCESROOM_PLAYER_IS_MOVING
	dw_const LancesRoomNoopScript,                  SCRIPT_LANCESROOM_NOOP

LancesRoomNoopScript:
	ret

; See LoreleisRoom.asm's LoreleisRoomStartBattleScript for the full comment
; on why this doesn't set wGymLeaderNo or wRogueFlagsBitfield bit 0.
LancesRoomStartBattleScript:
	ld d, OPP_LANCE
	farcall InitElite4Battle
	jp DisplayEnemyTrainerTextAndStartBattle

LancesRoomDefaultScript:
	CheckEvent EVENT_BEAT_LANCE
	ret nz
	ld hl, LanceTriggerMovementCoords
	call ArePlayerCoordsInArray
	jp nc, CheckFightingMapTrainers
	xor a
	ldh [hJoyHeld], a
	ld a, [wCoordIndex]
	cp $3  ; Is player standing next to Lance's sprite?
	jr nc, .notStandingNextToLance
; Face Lance and the player toward each other. This is a coordinate trigger,
; not the normal "player pressed A at a sprite" input path, so TalkToTrainer's
; usual auto-facing never fires for either sprite. wCoordIndex 1 = west of
; Lance (LanceTriggerMovementCoords entry (5,1)), 2 = south of him (6,2).
	cp $1
	ld a, SPRITE_FACING_LEFT
	ld b, PLAYER_DIR_RIGHT
	jr z, .faceLance
	ld a, SPRITE_FACING_DOWN
	ld b, PLAYER_DIR_UP
.faceLance
	push bc
	ldh [hSpriteFacingDirection], a
	ld a, LANCESROOM_LANCE
	ldh [hSpriteIndex], a
	call SetSpriteFacingDirectionAndDelay
	pop bc
	ld a, b
	ld [wPlayerMovingDirection], a
	ld a, TEXT_LANCESROOM_LANCE
	ldh [hTextID], a
	jp DisplayTextID
.notStandingNextToLance
	cp $5  ; Is player standing on the entrance staircase?
	jr z, WalkToLance
	CheckAndSetEvent EVENT_LANCES_ROOM_LOCK_DOOR
	ret nz
	ld hl, wCurrentMapScriptFlags
	set BIT_CUR_MAP_LOADED_1, [hl]
	ld a, SFX_GO_INSIDE
	call PlaySound
	jp LanceShowOrHideEntranceBlocks

LanceTriggerMovementCoords:
	dbmapcoord  5,  1
	dbmapcoord  6,  2
	dbmapcoord  5, 11
	dbmapcoord  6, 11
	dbmapcoord 24, 16
	db -1 ; end

LancesRoomLanceEndBattleScript:
	call EndTrainerBattle
	ldh a, [hIsInBattle]
	cp $ff
	jp z, ResetLanceScript
	farcall RogueAwardCredits2
	farcall RogueGrantCartridgeDragon   ; ELEMENT PRISM signature-type cartridge
	ld a, TEXT_LANCESROOM_LANCE
	ldh [hTextID], a
	jp DisplayTextID

WalkToLance:
; Moves the player down the hallway to Lance's room.
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld hl, wSimulatedJoypadStatesEnd
	ld de, WalkToLance_RLEList
	call DecodeRLEList
	dec a
	ldh [hSimulatedJoypadStatesIndex], a
	call StartSimulatingJoypadStates
	ld a, SCRIPT_LANCESROOM_PLAYER_IS_MOVING
	ld [wLancesRoomCurScript], a
	ld [wCurMapScript], a
	ret

WalkToLance_RLEList:
	db PAD_UP, 12
	db PAD_LEFT, 12
	db PAD_DOWN, 7
	db PAD_LEFT, 6
	db -1 ; end

LancesRoomPlayerIsMovingScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3
	xor a ; SCRIPT_LANCESROOM_DEFAULT
	ldh [hJoyIgnore], a
	ld [wLancesRoomCurScript], a
	ld [wCurMapScript], a
	ret

LancesRoom_TextPointers:
	def_text_pointers
	dw_const LancesRoomLanceText, TEXT_LANCESROOM_LANCE

LancesRoomTrainerHeaders:
	def_trainers
LancesRoomTrainerHeader0:
	trainer EVENT_BEAT_LANCES_ROOM_TRAINER_0, 0, LancesRoomLanceBeforeBattleText, LancesRoomLanceEndBattleText, LancesRoomLanceAfterBattleText
	db -1 ; end

LancesRoomLanceText:
	text_asm
	ld hl, LancesRoomTrainerHeader0
	call TalkToTrainer
	jp TextScriptEnd

LancesRoomLanceBeforeBattleText:
	text_far _LancesRoomLanceBeforeBattleText
	text_end

LancesRoomLanceEndBattleText:
	text_far _LancesRoomLanceEndBattleText
	text_end

LancesRoomLanceAfterBattleText:
	text_asm
	SetEvent EVENT_BEAT_LANCE
	ld a, [wBattleCount]
	cp 90
	ld hl, .Normal
	jr c, .print
	ld hl, .GoToChampion
.print
	call PrintText
	jp TextScriptEnd
.Normal
	text_far _LancesRoomLanceNormalAfterBattleText
	text_end
.GoToChampion
	text_far _Elite4GoToChampionText
	text_end
