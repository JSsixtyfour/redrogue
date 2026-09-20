PalmsRoom_Script:
	call EnableAutoTextBoxDrawing
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	ret z
	res BIT_CUR_MAP_LOADED_1, [hl]
	; Checkpoint 5 ends here. Clear the B1F escort dispatcher so the player can
	; inspect the inert room; rescue choreography begins in Checkpoint 6.
	call EndNPCMovementScript
	xor a
	ldh [hJoyIgnore], a
	ret

PalmsRoom_TextPointers:
	def_text_pointers
	dw_const PalmsRoomPalmText,  TEXT_PALMSROOM_PALM
	dw_const PalmsRoomLanceText, TEXT_PALMSROOM_LANCE

PalmsRoomPalmText:
	text "..."
	text_end

PalmsRoomLanceText:
	text "..."
	text_end
