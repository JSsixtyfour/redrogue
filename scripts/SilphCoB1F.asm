DEF SILPHCOB1F_STATE_ELEVATOR_MOVING EQU $fe

SilphCoB1F_Script:
	call EnableAutoTextBoxDrawing
	CheckEvent EVENT_INTRO_TOUR_COMPLETE
	jp nz, SilphCoB1FElevatorBlockerScript
	ld hl, SilphCoB1F_ScriptPointers
	ld a, [wSilphCoB1FCurScript]
	jp CallFunctionInTable

SilphCoB1F_ScriptPointers:
	def_script_pointers
	dw_const SilphCoB1FDefaultScript,              SCRIPT_SILPHCOB1F_DEFAULT
	dw_const SilphCoB1FWalkToDormScript,           SCRIPT_SILPHCOB1F_WALK_TO_DORM
	dw_const SilphCoB1FWaitAtDormScript,           SCRIPT_SILPHCOB1F_WAIT_AT_DORM
	dw_const SilphCoB1FWalkToCreditExchangeScript, SCRIPT_SILPHCOB1F_WALK_TO_CREDIT
	dw_const SilphCoB1FWaitAtCreditExchangeScript, SCRIPT_SILPHCOB1F_WAIT_AT_CREDIT
	dw_const SilphCoB1FWalkToVRScript,             SCRIPT_SILPHCOB1F_WALK_TO_VR
	dw_const SilphCoB1FWaitAtVRScript,             SCRIPT_SILPHCOB1F_WAIT_AT_VR
	dw_const SilphCoB1FEnterVRScript,              SCRIPT_SILPHCOB1F_ENTER_VR
	dw_const SilphCoB1FNoopScript,                 SCRIPT_SILPHCOB1F_NOOP

SilphCoB1FDefaultScript:
	;ld hl, wCurrentMapScriptFlags
	;bit BIT_CUR_MAP_LOADED_1, [hl]
	;jr z, .checkPosition
	;res BIT_CUR_MAP_LOADED_1, [hl]
	; The 1F stairs warp can change maps before its dispatcher reaches Done.
	; Clear that inherited dispatcher before B1F starts its own Pallet-style leg.

.checkPosition
	;ld a, [wYCoord]
	;cp 1
	;ret nz
    call EndNPCMovementScript
	ld c, 8
	call DelayFrames
	ld a, PLAYER_DIR_DOWN
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, SCRIPT_SILPHCOB1F_WALK_TO_DORM
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWalkToDormScript:
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, 7
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_WAIT_AT_DORM
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWaitAtDormScript:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	call SilphCoB1FFaceTourUp
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_DORM
	call SilphCoB1FDisplayTourText
	ld a, SCRIPT_SILPHCOB1F_WALK_TO_CREDIT
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWalkToCreditExchangeScript:
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, 9
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_WAIT_AT_CREDIT
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWaitAtCreditExchangeScript:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	call SilphCoB1FFaceTourUp
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_CREDIT_EXCHANGE
	call SilphCoB1FDisplayTourText
	ld a, SCRIPT_SILPHCOB1F_WALK_TO_VR
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWalkToVRScript:
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, 11
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_WAIT_AT_VR
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FWaitAtVRScript:
	ld a, [wNPCMovementScriptPointerTableNum]
	and a
	ret nz
	call SilphCoB1FFaceTourUp
	call UpdateSprites
	ld a, TEXT_SILPHCOB1F_VR
	call SilphCoB1FDisplayTourText
	ld a, SCRIPT_SILPHCOB1F_ENTER_VR
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FEnterVRScript:
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hActiveSpriteIndex], a
	ld a, 13
	call SilphCoB1FStartMovementDispatcher
	ld a, SCRIPT_SILPHCOB1F_NOOP
	ld [wSilphCoB1FCurScript], a
	ret

; IN: a = function index in SaffronPalmMovementScriptPointerTable.
SilphCoB1FStartMovementDispatcher:
	ld [wNPCMovementScriptFunctionNum], a
	ld a, 1
	ld [wNPCMovementScriptPointerTableNum], a
	ld a, BANK(SaffronPalmMovementScriptPointerTable)
	ld [wNPCMovementScriptBank], a
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

; IN: a = text ID.
SilphCoB1FDisplayTourText:
	ldh [hTextID], a
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	call DisplayTextID
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ret

SilphCoB1FNoopScript:
	ret

; The final B1F warp can interrupt the dispatcher before its Done function.
; VR calls this standard cleanup on entry before starting its own script.
SilphCoB1FClearMovementState:
	jp EndNPCMovementScript

; Viridian City's closed Gym establishes the convention: detect entry onto a
; forbidden warp, explain why it is blocked, then simulate one step back out.
SilphCoB1FElevatorBlockerScript:
	ld a, [wSilphCoB1FCurScript]
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
	ld a, SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, SILPHCOB1F_STATE_ELEVATOR_MOVING
	ld [wSilphCoB1FCurScript], a
	ret
.waitForMovement
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	ld a, SCRIPT_SILPHCOB1F_NOOP
	ld [wSilphCoB1FCurScript], a
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
