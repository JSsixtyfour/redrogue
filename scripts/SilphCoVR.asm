DEF SILPHCOVR_INTRO_WARMUP_TICKS EQU 8
DEF SILPHCOVR_STATE_WALK_PALM_TO_PC EQU 8
DEF SILPHCOVR_STATE_WAIT_FOR_PALM EQU 9
DEF SILPHCOVR_STATE_DONE EQU $ff

SilphCoVR_Script:
	call EnableAutoTextBoxDrawing
	call SilphCoVRHandleMapEntry
	CheckEvent EVENT_INTRO_TOUR_COMPLETE
	ret nz

	ld a, [wSilphCo1FCurScript]
	cp SILPHCOVR_INTRO_WARMUP_TICKS
	jr nc, .runState
	inc a
	ld [wSilphCo1FCurScript], a
	ret
.runState
	sub SILPHCOVR_STATE_WALK_PALM_TO_PC
	ld hl, SilphCoVR_ScriptPointers
	jp CallFunctionInTable

SilphCoVRHandleMapEntry:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]
	call SilphCoVRClearMovementState
	CheckEvent EVENT_INTRO_TOUR_COMPLETE
	jr nz, .normalVisit

; Stage Palm two tiles right of his normal PC position and two tiles south. The object is authored
; at (1,5), so later map loads need no event-dependent object toggle.
	ld a, 7 + 4
	ld [wSprite01StateData2MapY], a
	ld a, 3 + 4
	ld [wSprite01StateData2MapX], a
	ld a, SILPHCOVR_PROF_PALM
	swap a
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	xor a
	ld [wSilphCo1FCurScript], a
	ret

.normalVisit
	ld a, SILPHCOVR_STATE_DONE
	ld [wSilphCo1FCurScript], a
	ret

SilphCoVRClearMovementState:
	; Both maps share bank Maps22. Use the B1F cleanup so the final warp race also
	; clears the standing/exiting-door flags and player walk byte in the VR room.
	call SilphCoB1FClearMovementState
	xor a
	ldh [hJoyIgnore], a
	ret

SilphCoVR_ScriptPointers:
	dw SilphCoVRWalkPalmToPC
	dw SilphCoVRWaitForPalm

SilphCoVRWalkPalmToPC:
	ld de, SilphCoVRPalmToPCMovement
	ld a, SILPHCOVR_PROF_PALM
	ldh [hSpriteIndex], a
	call MoveSprite
	ld a, SILPHCOVR_STATE_WAIT_FOR_PALM
	ld [wSilphCo1FCurScript], a
	ret

SilphCoVRWaitForPalm:
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	ld a, SILPHCOVR_PROF_PALM
	ldh [hSpriteIndex], a
	call GetSpriteMovementByte2Pointer
	ld [hl], UP
	ld a, SPRITE_FACING_UP
	ldh [hSpriteFacingDirection], a
	call SetSpriteFacingDirection
	call UpdateSprites
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, TEXT_SILPHCOVR_PREP
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_INTRO_TOUR_COMPLETE
	call SilphCoVRClearMovementState
	ld a, SILPHCOVR_STATE_DONE
	ld [wSilphCo1FCurScript], a
	ret

SilphCoVRPalmToPCMovement:
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1

SilphCoVR_TextPointers:
	def_text_pointers
	dw_const SilphCoVR_ProfPalmText, TEXT_SILPHCOVR_PROF_PALM
	dw_const SilphCoVRPrepText,      TEXT_SILPHCOVR_PREP

SilphCoVR_ProfPalmText:
	text_far _SilphCoVR_ProfPalmText
	text_end

SilphCoVRPrepText:
	text_far _SilphCoVRPrepText
	text_end
