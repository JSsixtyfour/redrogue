PrintCinnabarQuiz:
	ld a, [wSpritePlayerStateData1FacingDirection]
	cp SPRITE_FACING_UP
	ret nz
	call EnableAutoTextBoxDrawing
	tx_pre_jump CinnabarGymQuiz

CinnabarGymQuiz::
	text_asm
	xor a
	ld [wOpponentAfterWrongAnswer], a
	ld a, [wHiddenEventFunctionArgument]
	push af
	and $f
	ldh [hGymGateIndex], a
	pop af
	and $f0
	swap a
	ldh [hGymGateAnswer], a
	ld hl, CinnabarGymQuizIntroText
	call PrintText
	ldh a, [hGymGateIndex]
	dec a
	add a
	ld d, 0
	ld e, a
	ld hl, CinnabarQuizQuestions
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	call PrintText
	ld a, 1
	ldh [hNoWaitAfterText], a
	call CinnabarGymQuiz_AskQuestion
	jp TextScriptEnd

CinnabarGymQuizIntroText:
	text_far _CinnabarGymQuizIntroText
	text_end

CinnabarQuizQuestions:
	dw CinnabarQuizQuestionsText1
	dw CinnabarQuizQuestionsText2
	dw CinnabarQuizQuestionsText3
	dw CinnabarQuizQuestionsText4
	dw CinnabarQuizQuestionsText5
	dw CinnabarQuizQuestionsText6

CinnabarQuizQuestionsText1:
	text_far _CinnabarQuizQuestionsText1
	text_end

CinnabarQuizQuestionsText2:
	text_far _CinnabarQuizQuestionsText2
	text_end

CinnabarQuizQuestionsText3:
	text_far _CinnabarQuizQuestionsText3
	text_end

CinnabarQuizQuestionsText4:
	text_far _CinnabarQuizQuestionsText4
	text_end

CinnabarQuizQuestionsText5:
	text_far _CinnabarQuizQuestionsText5
	text_end

CinnabarQuizQuestionsText6:
	text_far _CinnabarQuizQuestionsText6
	text_end

CinnabarGymGateFlagAction:
	EventFlagAddress hl, EVENT_CINNABAR_GYM_GATE0_UNLOCKED
	predef_jump FlagActionPredef

CinnabarGymQuiz_AskQuestion:
	call YesNoChoice
	ldh a, [hGymGateAnswer]
	ld c, a
	ldh a, [hCurrentMenuItem]
	cp c
	jr nz, .wrongAnswer
	; A right answer no longer opens anything (user decision, 2026-09-29): only
	; beating a trainer opens a gate. It also used to set GATE0 + index, and
	; machines 5 and 6 have no gate event, so they set whatever event followed
	; GATE4 (EVENT_BEAT_BLAINE after the four-trainer event reshuffle).
	ld hl, CinnabarGymQuizCorrectText
	jp PrintText
.wrongAnswer
	call WaitForSoundToFinish
	ld a, SFX_DENIED
	call PlaySound
	call WaitForSoundToFinish
	ld hl, CinnabarGymQuizIncorrectText
	call PrintText
	ldh a, [hGymGateIndex]
	add $2
	AdjustEventBit EVENT_BEAT_CINNABAR_GYM_TRAINER_0, 2
	ld c, a
	ld b, FLAG_TEST
	EventFlagAddress hl, EVENT_BEAT_CINNABAR_GYM_TRAINER_0
	predef FlagActionPredef
	ld a, c
	and a
	ret nz
	ldh a, [hGymGateIndex]
	add $2
	ld [wOpponentAfterWrongAnswer], a
	ret

CinnabarGymQuizCorrectText:
	sound_get_item_1
	text_far _CinnabarGymQuizCorrectText
	text_promptbutton
	text_end

CinnabarGymQuizIncorrectText:
	text_far _CinnabarGymQuizIncorrectText
	text_end

UpdateCinnabarGymGateTileBlocks_::
; Update the overworld map with open floor blocks or locked gate blocks
; depending on event flags.
; Only gates 1-3 are drawn. Gate 4 (in front of Blaine) lost its trainer in the
; 4-battle cut (FOUR_TRAINER_REVISION_PLAN.md): beating the trainer in object
; slot s opens gate s-1, and slot 5 is now the gym guide. The .blk has open
; floor at every gate, so a gate this loop skips simply starts open.
	ld a, 3
	ldh [hGymGateIndex], a
.loop
	ldh a, [hGymGateIndex]
	dec a
	add a
	add a
	ld d, 0
	ld e, a
	ld hl, CinnabarGymGateCoords
	add hl, de
	ld a, [hli]
	ld b, [hl]
	ld c, a
	inc hl
	ld a, [hl]
	ld [wGymGateTileBlock], a
	push bc
	ldh a, [hGymGateIndex]
	ldh [hBackupGymGateIndex], a
	AdjustEventBit EVENT_CINNABAR_GYM_GATE0_UNLOCKED, 0
	ld c, a
	ld b, FLAG_TEST
	call CinnabarGymGateFlagAction
	ld a, c
	and a
	jr nz, .unlocked
	ld a, [wGymGateTileBlock]
	jr .next
.unlocked
	ld a, $e
.next
	pop bc
	ld [wNewTileBlockID], a
	predef ReplaceTileBlock
	ld hl, hGymGateIndex
	dec [hl]
	jr nz, .loop
    
	CheckEvent EVENT_BEAT_BLAINE
	jr z, .blockExitToNextRoom
	ld a, $E
	jp .setExitBlock
.blockExitToNextRoom
	ld a, $54
.setExitBlock
	ld [wNewTileBlockID], a
	lb bc, 0, 1
    predef_jump ReplaceTileBlock
	ret

MACRO gym_gate_coord
	db \1, \2, \3, 0
ENDM

DEF HORIZONTAL_GATE_BLOCK EQU $54
DEF VERTICAL_GATE_BLOCK   EQU $5f

CinnabarGymGateCoords:
	; x coord, y coord, block id
	gym_gate_coord 9, 3, HORIZONTAL_GATE_BLOCK
	gym_gate_coord 6, 6, HORIZONTAL_GATE_BLOCK
	gym_gate_coord 2, 6, HORIZONTAL_GATE_BLOCK
	;gym_gate_coord 2, 3, HORIZONTAL_GATE_BLOCK ; gate 4: starts open, see above
    ;gym_gate_coord 1, 0, HORIZONTAL_GATE_BLOCK
