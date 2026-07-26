ProceduralCemetery1_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall PCemRefreshBall
.afterSetup
	call PCemCalmedCheck
	call EnableAutoTextBoxDrawing
	ret

ProceduralCemetery1_TextPointers:
	def_text_pointers
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETERY1_POKEBALL
	dw_const PCemCalmedText, TEXT_PROCEDURALCEMETERY1_CALMED

PCemCalmedText::
	text_far _ProceduralCemeteryCalmedText
	text_end
