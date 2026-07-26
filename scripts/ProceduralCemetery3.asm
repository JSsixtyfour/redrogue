ProceduralCemetery3_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	farcall PCemRefreshBall
.afterSetup
	call PCemCalmedCheck
	call EnableAutoTextBoxDrawing
	ret

ProceduralCemetery3_TextPointers:
	def_text_pointers
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETERY3_POKEBALL
	dw_const PCemCalmedText, TEXT_PROCEDURALCEMETERY3_CALMED
