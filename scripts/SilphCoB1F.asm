DEF SILPHCO_INTRO_WARMUP_TICKS EQU 8
DEF SILPHCOB1F_STATE_WALK_TO_DORM EQU 8
DEF SILPHCOB1F_STATE_WAIT_AT_DORM EQU 9
DEF SILPHCOB1F_STATE_WAIT_AT_CREDIT_EXCHANGE EQU 10
DEF SILPHCOB1F_STATE_WAIT_AT_VR EQU 11
DEF SILPHCOB1F_STATE_ENTER_VR EQU 12
DEF SILPHCOB1F_STATE_ELEVATOR_MOVING EQU $fe
DEF SILPHCO_INTRO_STATE_DONE EQU $ff

SilphCoB1F_Script:
	call EnableAutoTextBoxDrawing
	call SilphCoB1FHandleMapEntry
	CheckEvent EVENT_INTRO_TOUR_COMPLETE
	jp nz, SilphCoB1FElevatorBlockerScript

	ld a, [wSilphCo1FCurScript]
	cp SILPHCO_INTRO_WARMUP_TICKS
	jr nc, .runState
	inc a
	ld [wSilphCo1FCurScript], a
	ret
.runState
	sub SILPHCOB1F_STATE_WALK_TO_DORM
	ld hl, SilphCoB1F_ScriptPointers
	jp CallFunctionInTable

SilphCoB1FHandleMapEntry:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]

; The 1F escort's warp wins a race with its normal cleanup. Clear the inherited
; movement state once on arrival, following the existing B1F handoff pattern.
	call SilphCoB1FClearMovementState
	CheckEvent EVENT_INTRO_TOUR_COMPLETE
	jr nz, .showScientist

; The player arrives on the stair at (16,0), directly behind Palm at (16,1).
; Establish the intended presentation before the follower movement begins.
	ld a, PLAYER_DIR_DOWN
	ld [wPlayerMovingDirection], a
	xor a ; SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	xor a
	ld [wSilphCo1FCurScript], a
	ret

.showScientist
	; Palm and the later scientist intentionally share this authored object.
	; Their sprite, position, facing, and interaction text are identical here,
	; so toggling duplicate objects would only consume scarce bank 3 data.
	ld a, SILPHCO_INTRO_STATE_DONE
	ld [wSilphCo1FCurScript], a
	ret

SilphCoB1FClearMovementState:
	xor a
	ld [wNPCMovementScriptPointerTableNum], a
	ld [wNPCMovementScriptFunctionNum], a
	ld [wNPCMovementScriptSpriteOffset], a
	ld [wNPCNumScriptedSteps], a
	ldh [hSimulatedJoypadStatesIndex], a
	ld [wSimulatedJoypadStatesEnd], a
	ld [wOverrideSimulatedJoypadStatesMask], a
	ldh [hJoyIgnore], a
	ld [wWalkCounter], a
	ld [wSpritePlayerStateData2MovementByte1], a
	ld hl, wMovementFlags
	res BIT_STANDING_ON_DOOR, [hl]
	res BIT_EXITING_DOOR, [hl]
	ld hl, wStatusFlags5
	res BIT_SCRIPTED_NPC_MOVEMENT, [hl]
	res BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	ld hl, wStatusFlags4
	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
	ret

SilphCoB1F_ScriptPointers:
	dw SilphCoB1FWalkToDorm
	dw SilphCoB1FWaitAtDorm
	dw SilphCoB1FWaitAtCreditExchange
	dw SilphCoB1FWaitAtVR
	dw SilphCoB1FEnterVR

SilphCoB1FWalkToDorm:
	ld de, RLEList_SilphCoB1FPalmToDorm
	ld hl, RLEList_SilphCoB1FPlayerToDorm
	ld a, SILPHCOB1F_STATE_WAIT_AT_DORM
	jp SilphCoB1FStartFirstFollowerMovement

SilphCoB1FWaitAtDorm:
	call SilphCoB1FWaitForFollowerMovement
	ret nz
	call SilphCoB1FFaceTourUp
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_DORM
	ldh [hTextID], a
	call SilphCoB1FDisplayTourText
	ld de, RLEList_SilphCoB1FPalmToCreditExchange
	ld hl, RLEList_SilphCoB1FPlayerToCreditExchange
	ld a, SILPHCOB1F_STATE_WAIT_AT_CREDIT_EXCHANGE
	jp SilphCoB1FStartFollowerMovement

SilphCoB1FWaitAtCreditExchange:
	call SilphCoB1FWaitForFollowerMovement
	ret nz
	call SilphCoB1FFaceTourUp
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_CREDIT_EXCHANGE
	ldh [hTextID], a
	call SilphCoB1FDisplayTourText
	ld de, RLEList_SilphCoB1FPalmToVR
	ld hl, RLEList_SilphCoB1FPlayerToVR
	ld a, SILPHCOB1F_STATE_WAIT_AT_VR
	jp SilphCoB1FStartFollowerMovement

SilphCoB1FWaitAtVR:
	call SilphCoB1FWaitForFollowerMovement
	ret nz
	call SilphCoB1FFaceTourUp
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_VR
	ldh [hTextID], a
	call SilphCoB1FDisplayTourText
	ld de, RLEList_SilphCoB1FPalmEnterVR
	ld hl, RLEList_SilphCoB1FPlayerEnterVR
	ld a, SILPHCOB1F_STATE_ENTER_VR
	jp SilphCoB1FStartFollowerMovement

SilphCoB1FEnterVR:
; The player's final UP normally fires the warp before this state completes.
	call SilphCoB1FWaitForFollowerMovement
	ret nz
	call SilphCoB1FClearMovementState
	ld a, SILPHCOB1F_STATE_ENTER_VR
	ld [wSilphCo1FCurScript], a
	ret

; The first leg matches Silph Co 1F's follower setup, including deriving Palm's
; screen position from the authored object position before synchronized motion.
SilphCoB1FStartFirstFollowerMovement:
	push af
	push de
	push hl
	ld a, SILPHCOB1F_PROF_PALM
	swap a
	ld [wNPCMovementScriptSpriteOffset], a
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition
	pop hl
	pop de
	pop af
	; fallthrough

; IN: de = Palm RLE, hl = player RLE, a = next state. Later legs intentionally
; do not reinitialize Palm, matching the established 1F multi-leg escort.
SilphCoB1FStartFollowerMovement:
	push af
	push de
	ld d, h
	ld e, l
	ld hl, wSimulatedJoypadStatesEnd
	call DecodeRLEList
	dec a
	ldh [hSimulatedJoypadStatesIndex], a
	pop de
	ld hl, wNPCMovementDirections2
	call DecodeRLEList
	xor a
	ld [wOverrideSimulatedJoypadStatesMask], a
	ld [wSpritePlayerStateData2MovementByte1], a
	ld hl, wStatusFlags4
	res BIT_INIT_SCRIPTED_MOVEMENT, [hl]
	ld hl, wStatusFlags5
	set BIT_SCRIPTED_MOVEMENT_STATE, [hl]
	pop af
	ld [wSilphCo1FCurScript], a
	ret

; As in the proven 1F and Pewter escorts, each player list has a final executed
; NO_INPUT beat so the player queue remains the synchronization clock until
; Palm has settled.
SilphCoB1FWaitForFollowerMovement:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret

SilphCoB1FFaceTourUp:
	ld a, PLAYER_DIR_UP
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_UP
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	jp SetSpriteFacingDirection

SilphCoB1FDisplayTourText:
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	jp DisplayTextID

; Viridian City's closed Gym establishes the convention: detect entry onto a
; forbidden warp, explain why it is blocked, then simulate one step back out.
SilphCoB1FElevatorBlockerScript:
	ld a, [wSilphCo1FCurScript]
	cp SILPHCOB1F_STATE_ELEVATOR_MOVING
	jr z, .waitForMovement
	ld a, [wYCoord]
	and a
	ret nz
	ld a, [wXCoord]
	cp 18
	ret nz
	ld a, TEXT_SILPHCOB1F_ELEVATOR
	ldh [hTextID], a
	call DisplayTextID
	xor a
	ldh [hJoyHeld], a
	call StartSimulatingJoypadStates
	ld a, 1
	ldh [hSimulatedJoypadStatesIndex], a
	ld a, PAD_DOWN
	ld [wSimulatedJoypadStatesEnd], a
	xor a ; SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, SILPHCOB1F_STATE_ELEVATOR_MOVING
	ld [wSilphCo1FCurScript], a
	ret
.waitForMovement
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	ld a, SILPHCO_INTRO_STATE_DONE
	ld [wSilphCo1FCurScript], a
	ret

SilphCoB1F_TextPointers:
	def_text_pointers
	dw_const SilphCoB1FScientistText,      TEXT_SILPHCOB1F_SCIENTIST
	dw_const SilphCoB1FElevatorText,       TEXT_SILPHCOB1F_ELEVATOR
	dw_const SilphCoB1FDormText,           TEXT_SILPHCOB1F_DORM
	dw_const SilphCoB1FCreditExchangeText, TEXT_SILPHCOB1F_CREDIT_EXCHANGE
	dw_const SilphCoB1FVRText,             TEXT_SILPHCOB1F_VR

SilphCoB1FScientistText:
	text_far _SilphCoB1FScientistText
	text_end

SilphCoB1FElevatorText:
	text_far _SilphCoB1FElevatorText
	text_end

SilphCoB1FDormText:
	text_far _SilphCoB1FDormText
	text_end

SilphCoB1FCreditExchangeText:
	text_far _SilphCoB1FCreditExchangeText
	text_end

SilphCoB1FVRText:
	text_far _SilphCoB1FVRText
	text_end
