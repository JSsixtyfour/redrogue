; updates the types of a party mon (pointed to in hl) to the ones of the mon specified in [wPokedexNum]
SetPartyMonTypes:
	call GetPredefRegisters
	ld bc, MON_TYPE
	add hl, bc
	ld a, [wPokedexNum]
	ld [wCurSpecies], a
	push hl
	call GetMonHeader
	pop hl
	ld a, [wMonHType1]
	ld [hli], a
	ld a, [wMonHType2]
	; Evolution must retain Ghost typing, including old variants whose stored
	; type was reset by an earlier evolution. The per-mon flag is authoritative.
	inc hl ; MON_CATCH_RATE
	bit BIT_GHOST_VARIANT, [hl]
	dec hl ; MON_TYPE2
	jr z, .storeType2
	ld a, GHOST
.storeType2
	ld [hl], a
	ret
