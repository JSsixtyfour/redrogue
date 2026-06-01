PrintWaitingText::
	hlcoord 3, 10
	ld b, 1
	ld c, 11
	ldh a, [hIsInBattle]
	and a
	jr z, .trade
; battle
	call TextBoxBorder
	jr .border_done
.trade
	call CableClub_TextBoxBorder
.border_done
	hlcoord 4, 11
	ld de, WaitingText
	call PlaceString
	ld c, 50
	jp DelayFrames

WaitingText:
	db "Waiting...!@"
