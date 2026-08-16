MiniSaffron_Script:
	call EnableAutoTextBoxDrawing
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	res BIT_CUR_MAP_LOADED_1, [hl]
	ret z

; The truck exit has no meaningful facing direction. Set both the movement
; direction consumed by UpdateSprites and the displayed facing before Palm's
; first textbox so the player immediately looks up at him.
	ld a, PLAYER_DIR_UP
	ld [wPlayerMovingDirection], a
	ld a, SPRITE_FACING_UP
	ld [wSpritePlayerStateData1FacingDirection], a

; Block d-pad movement but leave A/B available for the text prompt.
	ld a, PAD_CTRL_PAD
	ldh [hJoyIgnore], a
	call UpdateSprites

	ld a, TEXT_MINISAFFRON_PROF_PALM
	ldh [hTextID], a
	call DisplayTextID

; Reuse the existing one-shot escort slot. Its Palm movement is UP 1 and its
; simulated player movement is NO_INPUT 1, UP 2, which reaches this map's
; Silph Co door at (12,9).
	ld a, MINISAFFRON_PROF_PALM
	ldh [hActiveSpriteIndex], a
	xor a
	ld [wNPCMovementScriptFunctionNum], a
	ld a, 1 ; SaffronPalmMovementScriptPointerTable
	ld [wNPCMovementScriptPointerTableNum], a
	ld a, BANK(SaffronPalmMovementScriptPointerTable)
	ld [wNPCMovementScriptBank], a
	ret

MiniSaffron_TextPointers:
	def_text_pointers
	dw_const MiniSaffronProfPalmText, TEXT_MINISAFFRON_PROF_PALM

MiniSaffronProfPalmText:
	text_far _MiniSaffronProfPalmText
	text_end
