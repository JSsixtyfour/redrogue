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
	; next run starts Victory Road again, Pokecenter lobby music. Now an event
	; flag (ROGUE_RUN_EVENTS), so it no longer rides the wElite4Flags pointer
	; above; hl is dead after this point anyway.
	ResetEvent EVENT_VICTORY_ROAD_CLEARED
	xor a ; SCRIPT_*_DEFAULT
	ld [wElite4Order], a
	ld hl, wLoreleisRoomCurScript
	ld [hli], a ; wLoreleisRoomCurScript
	ld [hli], a ; wBrunosRoomCurScript
	ld [hl], a ; wAgathasRoomCurScript
	ld [wLancesRoomCurScript], a
	ld [wChampionsRoomCurScript], a
	ld [wHallOfFameCurScript], a
	; Elite 4 events
	ResetEventRange INDIGO_PLATEAU_EVENTS_START, INDIGO_PLATEAU_EVENTS_END, 1
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
