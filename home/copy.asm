FarCopyData::
; Copy bc bytes from a:hl to de.
	ld [wBuffer], a
	ldh a, [hLoadedROMBank]
	push af
	ld a, [wBuffer]
	call SetCurBank      ; was inline ldh[hLoadedROMBank]/ld[rROMB]; -2 bytes (HOME space)
	call CopyData
	pop af
	jp SetCurBank        ; tail call = restore bank + ret; -3 bytes (HOME space)

CopyData::
; Copy bc bytes from hl to de.
	ld a, [hli]
	ld [de], a
	inc de
	dec bc
	ld a, c
	or b
	jr nz, CopyData
	ret
