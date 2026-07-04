ProceduralCemetary4_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	ld a, TOGGLE_CEMETARY_4_POKEBALL
	ld [wToggleableObjectIndex], a
	predef ShowObject
.afterSetup
	call EnableAutoTextBoxDrawing
	ret

ProceduralCemetary4_TextPointers:
	def_text_pointers
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETARY4_POKEBALL
