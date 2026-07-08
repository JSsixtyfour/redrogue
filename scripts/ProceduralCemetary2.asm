ProceduralCemetary2_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	ld a, TOGGLE_CEMETARY_2_POKEBALL
	ld [wToggleableObjectIndex], a
	predef ShowObject
.afterSetup
	call PCemCalmedCheck
	call EnableAutoTextBoxDrawing
	ret

ProceduralCemetary2_TextPointers:
	def_text_pointers
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETARY2_POKEBALL
	dw_const PCemCalmedText, TEXT_PROCEDURALCEMETARY2_CALMED
