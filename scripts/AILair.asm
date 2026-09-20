AILair_Script:
	call EnableAutoTextBoxDrawing
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]
	; The final arena is deliberately silent outside its eventual battle.
	ld a, SFX_STOP_ALL_MUSIC
	ld [wNewSoundID], a
	jp PlaySound

AILair_TextPointers:
	def_text_pointers
	dw_const AILairOpponentText, TEXT_AILAIR_OPPONENT

AILairOpponentText:
	text "..."
	text_end
