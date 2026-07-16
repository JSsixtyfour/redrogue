ProceduralCemetary3_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall PCemRefreshBall
.afterSetup
	call PCemCalmedCheck
	call EnableAutoTextBoxDrawing
	ret

ProceduralCemetary3_TextPointers:
	def_text_pointers
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETARY3_POKEBALL
	dw_const PCemCalmedText, TEXT_PROCEDURALCEMETARY3_CALMED
