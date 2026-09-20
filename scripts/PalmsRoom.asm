PalmsRoom_Script:
	jp EnableAutoTextBoxDrawing

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
