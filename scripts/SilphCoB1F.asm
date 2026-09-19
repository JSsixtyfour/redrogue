DEF SILPHCOB1F_STATE_ELEVATOR_MOVING EQU $fe

SilphCoB1F_Script:
	call EnableAutoTextBoxDrawing
	call SilphCoB1FHandleMapEntry
	CheckEvent EVENT_INTRO_TOUR_COMPLETE
	jr z, .introTour
	ld a, [wSilphCoB1FCurScript]
	cp SCRIPT_SILPHCOB1F_JOHTO_APPROACH
	jp c, SilphCoB1FElevatorBlockerScript
	cp SCRIPT_SILPHCOB1F_JOHTO_RETURN_DONE + 1
	jp nc, SilphCoB1FElevatorBlockerScript
.introTour
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
	dw_const SilphCoB1FJohtoApproachScript,         SCRIPT_SILPHCOB1F_JOHTO_APPROACH
	dw_const SilphCoB1FJohtoGreetingScript,         SCRIPT_SILPHCOB1F_JOHTO_GREETING
	dw_const SilphCoB1FJohtoReturnScript,           SCRIPT_SILPHCOB1F_JOHTO_RETURN_DONE

; Normalize the distinct Palm and stair-scientist objects on every map load,
; then stage Checkpoint 2 on the first fresh return from the Dorm after the
; Rival Champion. wWarpedFromWhichMap is written by the common warp handler
; before hCurMap changes, so it is authoritative rather than wLastMap.
SilphCoB1FHandleMapEntry:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]
	; A warp can interrupt the shared 1F/B1F dispatcher before its Done state.
	; Clear that inherited movement owner before staging any B1F actor.
	call SilphCoB1FClearMovementState
	CheckEvent EVENT_INTRO_TOUR_COMPLETE
	jr z, .introTourActors
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_SCIENTIST
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, SCRIPT_SILPHCOB1F_NOOP
	ld [wSilphCoB1FCurScript], a
	ld a, [wWarpedFromWhichMap]
	cp SILPH_CO_DORM
	ret nz
	ld a, [wYCoord]
	and a
	ret nz
	ld a, [wXCoord]
	cp 2
	jr z, .eligibleDormWarp
	cp 3
	ret nz
.eligibleDormWarp
	CheckEvent EVENT_RIVAL_CHAMPION_DEFEATED
	ret z
	CheckEvent EVENT_JOHTO_ACTIVATED
	ret nz
	ld a, TOGGLE_SILPH_CO_B1F_SCIENTIST
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef ShowObject

	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, PLAYER_DIR_DOWN
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a

	; Sprite map coordinates include the four-tile map border.
	ld a, 1 + 4
	ld [wSprite02StateData2MapY], a
	ld a, 8 + 4
	ld [wSprite02StateData2MapX], a
	ld a, SILPHCOB1F_PROF_PALM
	swap a
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition
	ld a, SCRIPT_SILPHCOB1F_JOHTO_APPROACH
	ld [wSilphCoB1FCurScript], a
	ret
.introTourActors
	ld a, TOGGLE_SILPH_CO_B1F_SCIENTIST
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef_jump ShowObject

SilphCoB1FJohtoApproachScript:
	ld de, SilphCoB1FPalmLeftSixMovement
	ld a, [wXCoord]
	cp 2
	jr z, .start
	ld de, SilphCoB1FPalmLeftFiveMovement
.start
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	call MoveSprite
	ld a, SCRIPT_SILPHCOB1F_JOHTO_GREETING
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FJohtoGreetingScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	ld a, PLAYER_DIR_DOWN
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_DOWN
	ld [wSpritePlayerStateData1FacingDirection], a
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	call GetSpriteMovementByte2Pointer
	ld [hl], UP
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirection
	call UpdateSprites
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, TEXT_SILPHCOB1F_JOHTO_ACTIVATION
	ldh [hTextID], a
	call DisplayTextID
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a

	; Match the Room PC's short SRAM transaction and preserve every other group
	; toggle.  This activation starts Johto enabled rather than replacing the
	; complete option mask.
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ASSERT BANK("Save Data") == 1
	ld a, 1
	ld [rRAMB], a
	ld a, [sRogueSpeciesGroupsEnabled]
	set BIT_GROUP_JOHTO, a
	ld [sRogueSpeciesGroupsEnabled], a
	xor a
	ld [rRAMG], a
	SetEvent EVENT_JOHTO_ACTIVATED
	farcall SaveGameData

	ld de, SilphCoB1FPalmRightSixMovement
	ld a, [wXCoord]
	cp 2
	jr z, .startReturn
	ld de, SilphCoB1FPalmRightFiveMovement
.startReturn
	ld a, SILPHCOB1F_PROF_PALM
	ldh [hSpriteIndex], a
	call MoveSprite
	ld a, SCRIPT_SILPHCOB1F_JOHTO_RETURN_DONE
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FJohtoReturnScript:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	; Palm has returned to his offscreen (8,1) start. Hide his dedicated story
	; object and restore the separate stair scientist for ordinary B1F play.
	ld a, TOGGLE_SILPH_CO_B1F_PROF_PALM
	ld [wToggleableObjectIndex], a
	predef HideObject
	ld a, TOGGLE_SILPH_CO_B1F_SCIENTIST
	ld [wToggleableObjectIndex], a
	predef ShowObject
	call UpdateSprites
	xor a
	ldh [hJoyIgnore], a
	ld a, SCRIPT_SILPHCOB1F_NOOP
	ld [wSilphCoB1FCurScript], a
	ret

SilphCoB1FPalmLeftSixMovement:
	db NPC_MOVEMENT_LEFT
SilphCoB1FPalmLeftFiveMovement:
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1

SilphCoB1FPalmRightSixMovement:
	db NPC_MOVEMENT_RIGHT
SilphCoB1FPalmRightFiveMovement:
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db NPC_MOVEMENT_RIGHT
	db -1

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
	dw_const SilphCoB1FProfPalmText,       TEXT_SILPHCOB1F_PROF_PALM
	dw_const SilphCoB1FElevatorText,       TEXT_SILPHCOB1F_ELEVATOR
	dw_const SilphCoB1FDormText,           TEXT_SILPHCOB1F_DORM
	dw_const SilphCoB1FCreditExchangeText, TEXT_SILPHCOB1F_CREDIT_EXCHANGE
	dw_const SilphCoB1FVRText,             TEXT_SILPHCOB1F_VR
	dw_const SilphCoB1FJohtoActivationText, TEXT_SILPHCOB1F_JOHTO_ACTIVATION

SilphCoB1FScientistText:
	text_far _SilphCoB1FScientistText
	text_end

; Palm is controlled by map scripts while visible. This fallback keeps the
; object-slot text table aligned if he is ever interacted with unexpectedly.
SilphCoB1FProfPalmText:
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

SilphCoB1FJohtoActivationText:
	text_far _SilphCoB1FJohtoActivationText
	text_end
