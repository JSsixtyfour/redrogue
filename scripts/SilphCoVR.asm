DEF SILPHCOVR_INTRO_WARMUP_TICKS EQU 8
DEF SILPHCOVR_STATE_WALK_PALM_TO_PC EQU 8
DEF SILPHCOVR_STATE_WAIT_FOR_PALM EQU 9
DEF SILPHCOVR_STATE_CRISIS_WALK_PALM_TO_PC EQU 10
DEF SILPHCOVR_STATE_CRISIS_WAIT_FOR_PALM EQU 11
DEF SILPHCOVR_STATE_DONE EQU $ff

SilphCoVR_Script:
	call EnableAutoTextBoxDrawing
	call SilphCoVRHandleMapEntry
	ld a, [wSilphCo1FCurScript]
	cp SILPHCOVR_STATE_CRISIS_WALK_PALM_TO_PC
	jr nc, .crisisState
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
.crisisState
	cp SILPHCOVR_STATE_DONE
	ret z
	sub SILPHCOVR_STATE_CRISIS_WALK_PALM_TO_PC
	ld hl, SilphCoVRCrisisScriptPointers
	jp CallFunctionInTable

SilphCoVRHandleMapEntry:
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]
	call SilphCoVRClearMovementState
	call SilphCoVRPatchMachineWarp
	call SilphCoVRShouldStageCrisisBriefing
	jr c, .crisisBriefing
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

.crisisBriefing
	; The player arrives at (3,7). Start Palm one tile ahead at (3,6), then
	; reuse his normal workstation endpoint at (1,5) without sprite overlap.
	ld a, 6 + 4
	ld [wSprite01StateData2MapY], a
	ld a, 3 + 4
	ld [wSprite01StateData2MapX], a
	ld a, SILPHCOVR_PROF_PALM
	swap a
	ldh [hCurrentSpriteOffset], a
	farcall InitializeSpriteScreenPosition
	ld a, PAD_BUTTONS | PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	ld a, SILPHCOVR_STATE_CRISIS_WALK_PALM_TO_PC
	ld [wSilphCo1FCurScript], a
	ret

.normalVisit
	ld a, SILPHCOVR_STATE_DONE
	ld [wSilphCo1FCurScript], a
	ret

SilphCoVRShouldStageCrisisBriefing:
	ld a, [wWarpedFromWhichMap]
	cp SILPH_CO_B1F
	jr nz, .no
	CheckEvent EVENT_OAK_CHAMPION_DEFEATED
	jr z, .no
	CheckEvent EVENT_PALMS_ROOM_OPEN
	jr z, .no
	CheckEvent EVENT_FINAL_BRIEFING_COMPLETE
	jr nz, .no
	scf
	ret
.no
	and a
	ret

; Carry set iff the VR machine should send the player to the AI Lair.
SilphCoVRAILairAuthorized:
	CheckEvent EVENT_FINAL_BRIEFING_COMPLETE
	jr z, .no
	CheckEvent EVENT_AI_DEFEATED
	jr nz, .no
	CheckEvent EVENT_AI_ATTEMPT_SPENT
	jr nz, .no
	farcall FinalTeamArchiveHasValidTeam
	ld a, [wActionResultOrTookBattleTurn]
	and a
	jr z, .no
	scf
	ret
.no
	and a
	ret

DEF SILPHCOVR_MACHINE_WARP_INDEX EQU 2 ; third warp_event in SilphCoVR.asm

; Rewrite the machine warp's in-RAM destination on every VR load. wWarpEntries
; is rebuilt from ROM each time, so this must run on every entry, not just once.
SilphCoVRPatchMachineWarp:
	call SilphCoVRAILairAuthorized
	ret nc
	ld hl, wWarpEntries + SILPHCOVR_MACHINE_WARP_INDEX * 4 + 2
	xor a ; AI_LAIR warp 1, stored as warp id - 1
	ld [hli], a
	ld [hl], AI_LAIR
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

SilphCoVRCrisisScriptPointers:
	dw SilphCoVRCrisisWalkPalmToPC
	dw SilphCoVRCrisisWaitForPalm

SilphCoVRCrisisWalkPalmToPC:
	ld de, SilphCoVRCrisisPalmToPCMovement
	ld a, SILPHCOVR_PROF_PALM
	ldh [hSpriteIndex], a
	call MoveSprite
	ld a, SILPHCOVR_STATE_CRISIS_WAIT_FOR_PALM
	ld [wSilphCo1FCurScript], a
	ret

SilphCoVRCrisisWaitForPalm:
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
	ld a, TEXT_SILPHCOVR_FINAL_BRIEFING
	ldh [hTextID], a
	call DisplayTextID
	SetEvent EVENT_FINAL_BRIEFING_COMPLETE
	farcall SaveGameData
	call SilphCoVRPatchMachineWarp
	call SilphCoVRClearMovementState
	ld a, SILPHCOVR_STATE_DONE
	ld [wSilphCo1FCurScript], a
	ret

SilphCoVRCrisisPalmToPCMovement:
	db NPC_MOVEMENT_UP
	db NPC_MOVEMENT_LEFT
	db NPC_MOVEMENT_LEFT
	db -1

SilphCoVR_TextPointers:
	def_text_pointers
	dw_const SilphCoVR_ProfPalmText, TEXT_SILPHCOVR_PROF_PALM
	dw_const SilphCoVRPrepText,      TEXT_SILPHCOVR_PREP
	dw_const SilphCoVRFinalBriefingText, TEXT_SILPHCOVR_FINAL_BRIEFING
	dw_const SilphCoVRFinalRepeatText,   TEXT_SILPHCOVR_FINAL_REPEAT

SilphCoVR_ProfPalmText:
	text_asm
	push bc
	ld hl, .normalText
	CheckEvent EVENT_AI_DEFEATED ; postgame: back to his ordinary line
	jr nz, .print
	CheckEvent EVENT_FINAL_BRIEFING_COMPLETE
	jr z, .print
	ld hl, SilphCoVRAttemptSpentText
	CheckEvent EVENT_AI_ATTEMPT_SPENT
	jr nz, .print
	ld hl, SilphCoVRFinalRepeatText
.print
	call PrintText
	pop bc
	jp TextScriptEnd
.normalText
	text_far _SilphCoVR_ProfPalmText
	text_end

SilphCoVRPrepText:
	text_far _SilphCoVRPrepText
	text_end

SilphCoVRFinalBriefingText:
	text_far _SilphCoVRFinalBriefingText
	text_end

SilphCoVRFinalRepeatText:
	text_far _SilphCoVRFinalRepeatText
	text_end

SilphCoVRAttemptSpentText:
	text_far _SilphCoVRAttemptSpentText
	text_end
