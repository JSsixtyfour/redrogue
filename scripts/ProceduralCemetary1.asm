ProceduralCemetary1_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall PCemRefreshBall
.afterSetup
	call PCemCalmedCheck
	call EnableAutoTextBoxDrawing
	ret

ProceduralCemetary1_TextPointers:
	def_text_pointers
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETARY1_POKEBALL
	dw_const PCemCalmedText, TEXT_PROCEDURALCEMETARY1_CALMED

PCemCalmedText::
	text_far _ProceduralCemetaryCalmedText
	text_end
