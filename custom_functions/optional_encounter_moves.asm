; Same $26 section as optional encounter. wBuffer scratch is used only at
; completed enemy/gift creation, never while cave/forest generation is live.
; In DE=actual struct, B=its PP-minus-moves offset (battle differs from party).
OptionalGrantColdMoves:
	ld a, [wOptionalEncounterPackage]
	sub 2
	cp OPTIONAL_PACKAGE_PSYCHIC + NUM_OPTIONAL_PSYCHIC_PACKAGES - 2
	ret nc
	push bc
	push de
	ld hl, wBuffer
	xor a
	ld [hli], a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	call OptionalPackageStatusMove
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

; Out: a = the package's own status move. Clobbers bc, hl: the caller has saved
; bc and reloads hl.
OptionalPackageStatusMove:
	ld a, [wOptionalEncounterPackage]
	cp OPTIONAL_PACKAGE_PSYCHIC
	jr nc, .psychic
	cp 2
	ld a, MIST
	ret z
	ld a, HAZE
	ret
.psychic
	sub OPTIONAL_PACKAGE_PSYCHIC
	ld c, a
	ld b, 0
	ld hl, OptionalPsychicSupport
	add hl, bc
	ld a, [hl]
	ret

OptionalPsychicSupport:
	db AGILITY, BARRIER, HYPNOSIS, KINESIS, MEDITATE, CONFUSE_RAY
	ASSERT @ - OptionalPsychicSupport == NUM_OPTIONAL_PSYCHIC_PACKAGES

; Never retain a second required move or an obsolete attack of the package's
; type in the ordinary level slots. Compact moves prevent a zero slot hiding
; either required move. In: a = move. Out: Z = required. Keeps bc, de, hl.
OptionalColdRequiredMove:
	push hl
	push bc
	ld b, a
	ld a, [wOptionalEncounterPackage]
	cp OPTIONAL_PACKAGE_PSYCHIC
	ld hl, .cold
	jr c, .scan
	ld hl, .psychic
.scan
	ld a, [hli]
	and a
	jr z, .ordinary
	cp b
	jr nz, .scan
	jr .done                     ; Z
.ordinary
	inc a                        ; NZ
.done
	pop bc
	pop hl
	ret
.cold
	db MIST, HAZE, AURORA_BEAM, ICE_PUNCH, ICE_BEAM, BLIZZARD, 0
.psychic
	db CONFUSION, PSYBEAM, PSYCHIC_M
	db AGILITY, BARRIER, HYPNOSIS, KINESIS, MEDITATE, CONFUSE_RAY, 0

OptionalColdAttack::
	ld a, [wOptionalEncounterPackage]
	cp OPTIONAL_PACKAGE_PSYCHIC
	jr c, .cold
	ld a, [wOptionalEncounterLevel]
	cp 20
	ld a, CONFUSION
	ret c
	ld a, [wOptionalEncounterLevel]
	cp 36
	ld a, PSYBEAM
	ret c
	ld a, PSYCHIC_M
	ret
.cold
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

INCLUDE "data/maps/facility_subroom_mon_spots.asm"

; Every load of the Facility or its subroom. A wanderer does not keep its place
; across a load; it starts from here again, on a tile nothing else stands on.
OptionalEncounterPlaceFacility::
	call OptionalEncounterIsCurrent
	ret nc
	call OptionalFacilityOpenSRAM
	ldh a, [hCurMap]
	cp PROCEDURAL_FACILITY
	jr z, .facility
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_PIECE]
	ld b, a
	call FGCloseSRAM
	ld a, b
	cp FACSUB_NUM_MON_SPOTS
	ret nc
	add a
	ld e, a
	ld d, 0
	ld hl, FacSubroomMonSpots
	add hl, de
	ld a, [hli]
	add 4
	ld [wSprite03StateData2MapX], a
	ld a, [hl]
	add 4
	ld [wSprite03StateData2MapY], a
	ld a, SPRITE_FACING_DOWN
	ld [wSprite03StateData1FacingDirection], a
	ld [wSprite03StateData2OrigFacingDirection], a
	ret
.facility
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_MON_X]
	ld d, a
	ld a, [sProcFacilityGenScratch + FACSUB_SCRATCH_MON_Y]
	ld e, a
	call FGCloseSRAM
	; The block's bottom-right quadrant, as a pad's tile and the Super Nerd's.
	ld a, d
	add a
	add 4 + 1
	ld [wSprite{d:FACILITY_OPTIONAL_MON}StateData2MapX], a
	ld a, e
	add a
	add 4 + 1
	ld [wSprite{d:FACILITY_OPTIONAL_MON}StateData2MapY], a
	ld a, SPRITE_FACING_DOWN
	ld [wSprite{d:FACILITY_OPTIONAL_MON}StateData1FacingDirection], a
	ld [wSprite{d:FACILITY_OPTIONAL_MON}StateData2OrigFacingDirection], a
	ret

; The wandering Psychic package starts its own battle, once per frame from the
; map script: when the player stands on any of the four tiles beside it, whichever
; way it faces and whatever is held. RunMapScript only runs with the player between
; steps, so a slide passes by it and a walk past it does not.
OptionalEncounterContact:
	ld a, [wOptionalEncounterPackage]
	cp OPTIONAL_PACKAGE_PSYCHIC
	ret c
	ld a, [wOptionalEncounterState]
	and (1 << BIT_OPTIONAL_DEFEATED) | (1 << BIT_OPTIONAL_RESOLVED)
	ret nz
	ldh a, [hJoyIgnore]
	and a
	ret nz
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz                          ; a spinner's slide
	ld a, [wCurOpponent]
	and a
	ret nz
	ld a, [wMiscFlags]
	bit BIT_SEEN_BY_TRAINER, a
	ret nz
	ld a, [wStatusFlags5]
	bit BIT_SCRIPTED_NPC_MOVEMENT, a
	ret nz
	ldh a, [hCurMap]
	cp PROCEDURAL_FACILITY
	jr nz, .scriptIdle
	ld a, [wProceduralCave1CurScript]
	and a
	ret nz                          ; a trainer or the boss has the map script
.scriptIdle
IF DEF(_DEBUG)
	call DebugPressedOrHeldB        ; as trainers do: B walks past it in Debug
	ret nz
ENDC
	call OptionalSpriteAddress
	inc hl                          ; MOVEMENTSTATUS
	ASSERT SPRITESTATEDATA1_MOVEMENTSTATUS == 1
	ld a, [hl]
	and %11
	cp 3
	ret z                           ; mid-step: its map tile is already the next one
	call OptionalSpriteAddress
	inc h                           ; wSpriteStateData2
	ld a, l
	add SPRITESTATEDATA2_MAPY
	ld l, a
	ld a, [hli]
	sub 4
	ld d, a                         ; d = its Y
	ASSERT SPRITESTATEDATA2_MAPX == SPRITESTATEDATA2_MAPY + 1
	ld a, [hl]
	sub 4
	ld e, a                         ; e = its X
	ld a, [wXCoord]
	cp e
	jr nz, .sameRow
	ld a, [wYCoord]
	dec a
	cp d
	ld c, SPRITE_FACING_UP
	jr z, .contact                  ; the player is below it
	add 2
	cp d
	ld c, SPRITE_FACING_DOWN
	jr z, .contact                  ; above it
	ret
.sameRow
	ld a, [wYCoord]
	cp d
	ret nz
	ld a, [wXCoord]
	inc a
	cp e
	ld c, SPRITE_FACING_RIGHT
	jr z, .contact                  ; left of it
	sub 2
	cp e
	ld c, SPRITE_FACING_LEFT
	ret nz                          ; right of it, or no contact
.contact
	call OptionalPlayerOnWarp       ; A still starts it from a warp tile
	ret c
	ld a, c
	ld [wSpritePlayerStateData1FacingDirection], a
	call UpdateSprites
	call OptionalEncounterSlot
	ld e, a
	push de
	ld [wEmotionBubbleSpriteIndex], a
	xor a ; EXCLAMATION_BUBBLE
	ld [wWhichEmotionBubble], a
	predef EmotionBubble
	pop de
	xor a
	ldh [hJoyHeld], a
	ld a, e
	ldh [hTextID], a
	jp DisplayTextID

; Out: a = its object slot, also its text id on these maps.
OptionalEncounterSlot:
	ldh a, [hCurMap]
	cp PROCEDURAL_FACILITY
	ld a, FACILITY_OPTIONAL_MON
	ret z
	ld a, FACSUBROOM_OPTIONAL_MON
	ret

; Out: carry = the player stands on a live warp. Keeps bc, de.
OptionalPlayerOnWarp:
	push bc
	ld hl, wWarpEntries
	ld a, [wNumberOfWarps]
	and a
	jr z, .no
	ld b, a
.loop
	ld a, [wYCoord]
	cp [hl]
	inc hl
	jr nz, .next
	ld a, [wXCoord]
	cp [hl]
	jr nz, .next
	pop bc
	scf
	ret
.next
	inc hl
	inc hl
	inc hl
	dec b
	jr nz, .loop
.no
	pop bc
	and a
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
