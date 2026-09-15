HallOfFame_Script:
	call EnableAutoTextBoxDrawing
	ld hl, HallOfFame_ScriptPointers
	ld a, [wHallOfFameCurScript]
	jp CallFunctionInTable

HallofFameRoomClearScripts: ; unreferenced
	xor a
	ldh [hJoyIgnore], a
	ld [wHallOfFameCurScript], a
	ret

HallOfFame_ScriptPointers:
	def_script_pointers
	dw_const HallOfFameDefaultScript,            SCRIPT_HALLOFFAME_DEFAULT
	dw_const HallOfFameOakCongratulationsScript, SCRIPT_HALLOFFAME_OAK_CONGRATULATIONS
	dw_const HallOfFameResetEventsAndSaveScript, SCRIPT_HALLOFFAME_RESET_EVENTS_AND_SAVE
	dw_const HallOfFameNoopScript,               SCRIPT_HALLOFFAME_NOOP

HallOfFameNoopScript:
	ret

HallOfFameResetEventsAndSaveScript:
	predef SingleCPUSpeed ; Hall of Fame and credits retain single-speed timing
	call Delay3
	ld a, [wLetterPrintingDelayFlags]
	push af
	xor a
	ldh [hJoyIgnore], a
	predef HallOfFamePC
	pop af
	ld [wLetterPrintingDelayFlags], a
	ld hl, wStatusFlags7
	res BIT_NO_MAP_MUSIC, [hl]
	ASSERT wStatusFlags7 + 1 == wElite4Flags
	inc hl
	set BIT_UNUSED_BEAT_ELITE_4, [hl] ; unused
	res BIT_STARTED_ELITE_4, [hl]
	xor a ; SCRIPT_*_DEFAULT
	; Phase 7: wElite4Order is gone. The run's drawn Elite Four and Champion
	; live in wRunElite4 / wRunChampion, which are cleared with the rest of the
	; run block below rather than one byte at a time here.
	ld hl, wLoreleisRoomCurScript
	ld [hli], a ; wLoreleisRoomCurScript
	ld [hli], a ; wBrunosRoomCurScript
	ld [hl], a ; wAgathasRoomCurScript
	ld [wLancesRoomCurScript], a
	ld [wChampionsRoomCurScript], a
	ld [wHallOfFameCurScript], a
	; The three Phase 7 Elite Four rooms. Not contiguous with the three above,
	; so they get their own stores rather than extending that hli run.
	ld [wKogasRoomCurScript], a
	ld [wWillsRoomCurScript], a
	ld [wKarensRoomCurScript], a
	; wRunGymLineup / wBadgeSlotOrder / wRunElite4 / wRunChampion are NOT
	; cleared here: they sit inside wGameProgressFlags, so the farcall to
	; RogueResetRunState at the end of this script already blanket-clears them,
	; and that routine is also the one place that knows to preserve
	; wGymsUsedMask across the wipe. Duplicating the clear here would be
	; redundant at best and, if it ever grew to cover the mask, wrong.
	; Finishing the game ends the run exactly like a blackout does: one wipe
	; over ZONE 1 of constants/event_constants.asm plus badges and the
	; visited-stage bitfield. That range subsumes the Elite 4 events and
	; EVENT_VICTORY_ROAD_CLEARED, which used to be reset separately here.
	farcall RogueResetRunState
	xor a
	ld [wHallOfFameCurScript], a
	ld a, PALLET_TOWN
	ld [wLastBlackoutMap], a
	farcall SaveGameData
	ld b, 5
.delayLoop
	ld c, 600 / 5
	call DelayFrames
	dec b
	jr nz, .delayLoop
	call WaitForTextScrollButtonPress
	jp Init

HallOfFameDefaultScript:
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld hl, wSimulatedJoypadStatesEnd
	ld de, HallOfFameEntryMovement
	call DecodeRLEList
	dec a
	ldh [hSimulatedJoypadStatesIndex], a
	call StartSimulatingJoypadStates
	ld a, SCRIPT_HALLOFFAME_OAK_CONGRATULATIONS
	ld [wHallOfFameCurScript], a
	ret

HallOfFameEntryMovement:
	db PAD_UP, 5
	db -1 ; end

HallOfFameOakCongratulationsScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	ld a, PLAYER_DIR_RIGHT
	ld [wPlayerMovingDirection], a
	ld a, HALLOFFAME_OAK
	ldh [hSpriteIndex], a
	call SetSpriteMovementBytesToFF
	ld a, SPRITE_FACING_LEFT
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirectionAndDelay
	call Delay3
	xor a
	ldh [hJoyIgnore], a
	inc a ; PLAYER_DIR_RIGHT
	ld [wPlayerMovingDirection], a
	ld a, TEXT_HALLOFFAME_OAK
	ldh [hTextID], a
	call DisplayTextID
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, TOGGLE_CERULEAN_CAVE_GUY
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, SCRIPT_HALLOFFAME_RESET_EVENTS_AND_SAVE
	ld [wHallOfFameCurScript], a
	ret

HallOfFame_TextPointers:
	def_text_pointers
	dw_const HallOfFameOakText, TEXT_HALLOFFAME_OAK

HallOfFameOakText:
	text_far _HallOfFameOakText
	text_end
