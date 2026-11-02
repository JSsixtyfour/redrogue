; Same $26 section as optional encounter. wBuffer scratch is used only at
; completed enemy/gift creation, never while cave/forest generation is live.
; In DE=actual struct, B=its PP-minus-moves offset (battle differs from party).
OptionalGrantColdMoves:
	ld a, [wOptionalEncounterPackage]
	sub 2
	cp 2
	ret nc
	push bc
	push de
	ld hl, wBuffer
	xor a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ld a, [wOptionalEncounterPackage]
	cp 2
	ld a, MIST
	jr z, .status
	ld a, HAZE
.status
	ld [wBuffer + 10], a
	call OptionalColdAttack
	ld [wBuffer + 11], a
	ld hl, MON_MOVES
	add hl, de
	ld de, wBuffer
	ld b, NUM_MOVES
	ld c, 0
.normal
	ld a, [hli]
	and a
	jr z, .next
	call OptionalColdRequiredMove
	jr z, .next
	ld a, c
	cp 2
	jr nc, .next
	dec hl
	ld a, [hli]
	ld [de], a
	inc de
	inc c
.next
	dec b
	jr nz, .normal
	ld a, [wBuffer + 10]
	ld [de], a
	inc de
	ld a, [wBuffer + 11]
	ld [de], a
	pop de
	push de
	ld hl, MON_MOVES
	add hl, de
	ld d, h
	ld e, l
	ld hl, wBuffer
	ld bc, NUM_MOVES
	call CopyData
	pop de
	pop bc ; B = PP offset
	ld hl, MON_MOVES
	add hl, de
	ld c, NUM_MOVES
.pp
	push bc
	ld a, [hli]
	push hl
	and a
	jr z, .zeroPP
	push de
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld de, wBuffer + 4
	ld bc, MOVE_LENGTH
	ld a, BANK(Moves)
	call FarCopyData ; HOME performs the bank switch, never this ROMX routine
	ld a, [wBuffer + 9]
	pop de
	jr .storePP
.zeroPP
	xor a
.storePP
	pop hl
	pop bc
	push hl
	push bc
	ld c, b
	ld b, 0
	add hl, bc
	dec hl
	ld [hl], a
	pop bc
	pop hl
	dec c
	jr nz, .pp
	ret

; Never retain a second Haze/Mist or an obsolete Ice attack in the ordinary
; level slots. Compact moves prevent a zero slot hiding either required move.
OptionalColdRequiredMove:
	cp MIST
	ret z
	cp HAZE
	ret z
	cp AURORA_BEAM
	ret z
	cp ICE_PUNCH
	ret z
	cp ICE_BEAM
	ret z
	cp BLIZZARD
	ret

OptionalColdAttack::
	ld a, [wOptionalEncounterLevel]
	cp 31
	ld a, AURORA_BEAM
	ret c
	ld a, [wOptionalEncounterLevel]
	cp 36
	jr nc, .beam
	ld a, [wOptionalEncounterSpecies]
	cp SNORLAX
	ld a, AURORA_BEAM
	ret nz
	ld a, ICE_PUNCH
	ret
.beam
	cp 46
	ld a, ICE_BEAM
	ret c
	ld a, BLIZZARD
	ret

OptionalEncounterPlaceCave::
	call OptionalEncounterIsCurrent
	ret nc
	call FGOpenParentSRAM
	ld a, [CAVESUB_ROOM]
	and CAVESUB_ROOM_MASK
	ld b, a
	call FGCloseSRAM
	ld a, b
	cp 3
	jr c, .room
	xor a
.room
	add a
	ld e, a
	ld d, 0
	ld hl, .positions
	add hl, de
	ld a, [hli]
	add 4
	ld [wSprite06StateData2MapX], a
	ld a, [hl]
	add 4
	ld [wSprite06StateData2MapY], a
	ld a, SPRITE_FACING_DOWN
	ld [wSprite06StateData1FacingDirection], a
	ld [wSprite06StateData2OrigFacingDirection], a
	ld a, DOWN
	ld [wMapSpriteData + 5 * 2], a
	ret
.positions
	db 14, 1 ; Lake
	db 17, 15 ; Lake2
	db 3, 8 ; Mountains1
