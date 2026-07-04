ProceduralCemetary1_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	ld a, TOGGLE_CEMETARY_1_POKEBALL
	ld [wToggleableObjectIndex], a
	predef ShowObject
.afterSetup
	call EnableAutoTextBoxDrawing
	ret

ProceduralCemetary1_TextPointers:
	def_text_pointers
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETARY1_POKEBALL
