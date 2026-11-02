; Map/helpers share $26. Markers are existing N/W/E exit blocks on a wall
; OTHER than the main exit. Geometry uses no saved scratch aliases.
DEF FG_PARENT_BASE EQU 81
DEF FG_PARENT_STRIDE EQU 26
DEF FG_WARP EQU 31
DEF FG_FIRST_ROW EQU 1
DEF FG_LAST_ROW EQU 17

; Assignment means the stage was given a Pokemon, not that its sprite is
; still visible after a resolved reward. Checkpoint 4 owns independent saved
; identity; Debug 2 forces Pink or winter Snowlax, release odds stay disabled.
; Geometry-only tests can force this predicate at .return.
FGHasAssignedEncounter::
	ld a, [wOptionalEncounterMap]
	cp PROCEDURAL_FOREST_GROTTO
	jr nz, .none
	call OptionalEncounterAssigned
	jr .return
.none
	xor a
.return
	ret

; SRAM0 open throughout this generation hook. No wBuffer use. Pick one of
; the two eligible walls, then try its nine sites and the other wall once.
; No rare-outcome writer exists yet, so production never drops a winning roll.
FGPrototypeCarve::
	call FGHasAssignedEncounter
	and a
	ret z
	ld a, [sProcForestRiverSide]
	cp $ff
	ret nz
	ld a, [sProcForestExitEdge]
	cp 3
	ret nc
	call FGChooseWall
	ld b, a
	push bc
	call FGTryWall
	pop bc ; preserve the carry result and recover the preferred wall
	ret c
	ld a, [sProcForestExitEdge]
	add b
	ld b, a
	ld a, 3 ; sum of wall ids 0+1+2, so this is the other allowed wall
	sub b
	jp FGTryWall

FGChooseWall:
	ld c, 2
	call Rangerandom
	ld b, a
	ld a, [sProcForestExitEdge]
	cp b
	ld a, b
	jr z, .skipMain
	jr nc, .return
.skipMain
	inc a
.return
	ret

; A=wall 0N/1W/2E. Carry set only if one opening was carved.
FGTryWall:
	ld d, a
	ld a, [sProcForestExitEdge]
	cp d
	jr z, .none
	ld e, FG_FIRST_ROW
.site
	push de
	call FGSiteFree
	pop de
	jr c, .carve
	inc e
	inc e
	ld a, e
	cp FG_LAST_ROW + 1
	jr c, .site
.none
	and a
	ret
.carve
	call FGCellXY
	push de
	call FGBlockAddress
	pop de
	ld a, d
	and a
	jr z, .north
	cp 1
	jr z, .west
	inc hl
	ld [hl], 27
	inc hl
	ld [hl], 87
	jr .done
.west
	dec hl
	ld [hl], 86
	jr .done
.north
	ld de, -FG_PARENT_STRIDE
	add hl, de
	ld [hl], 88
.done
	scf
	ret

; D=wall, E=odd block site. B/C=adjacent inner cell X/Y.
FGCellXY:
	ld b, e
	ld c, 1
	ld a, d
	and a
	ret z
	ld c, e
	ld b, 1
	cp 1
	ret z
	ld b, 17
	ret

; B/C=block X/Y. Preserve BC; clobber AF/DE/HL.
FGBlockAddress:
	ld hl, wOverworldMap + FG_PARENT_BASE
	ld de, FG_PARENT_STRIDE
	ld a, c
	and a
	jr z, .col
.row
	add hl, de
	dec a
	jr nz, .row
.col
	ld e, b
	ld d, 0
	add hl, de
	ret

; All four quadrants of these existing maze floors are walkable and have
; no elevation barrier against the exit blocks. Keep marker reads in sync.
FGIsFloor:
	cp 1
	ret z
	cp 27
	ret z
	cp 41
	ret z
	cp $20
	ret z
	cp $22
	ret z
	cp $23
	ret z
	cp $24
	ret z
	cp $25
	ret

; D/E=wall/site. Only boundary trees (and the east connector) are written.
; Odd inner cells never overlap the even-row house. Clearing art is kept
; intact: accept only its fully walkable floors, with no surrounding margin.
; Preserve the hideout's sight distance and the main boss's approach.
FGSiteFree:
	call FGCellXY
	push de
	call FGBlockAddress
	pop de
	ld a, [hl]
	call FGIsFloor
	jp nz, .no
.floor
	push bc ; inner cell for the persistent placement checks
	push de
	push hl
	call FGBoundaryFree
	pop hl
	pop de
	jp nc, .badCell
	pop bc
	; Main boss block: N=(2*i+1,1), W=(1,2*i+1), E=(18,2*i+1).
	; Reject a one-block square, including shared corner approaches.
	ld a, [sProcForestExitI]
	add a
	inc a
	ld e, a
	ld d, 1
	ld a, [sProcForestExitEdge]
	and a
	jr z, .northBoss
	cp 1
	jr z, .boss
	ld d, 18
	jr .boss
.northBoss
	ld d, e
	ld e, 1
.boss
	ld a, d
	sub b
	inc a
	cp 3
	jr nc, .objects
	ld a, e
	sub c
	inc a
	cp 3
	jr c, .no
.objects
	ld a, [sStageEventHideoutX]
	cp STAGE_EVENT_NO_HIDEOUT
	jr z, .balls
	sub b
	add 2
	cp 5
	jr nc, .balls
	ld a, [sStageEventHideoutY]
	sub c
	add 2
	cp 5
	jr c, .no
.balls
	ld hl, sProcForestBallXY ; sprite coords = block*2+4
	ld e, 4
.ball
	ld a, [hli]
	ld d, a
	ld a, [hli]
	sub b
	sub b
	cp 4 ; only the actual occupied cell, not neighboring maze cells
	jr nz, .nextBall
	ld a, d
	sub c
	sub c
	cp 4
	jr z, .no
.nextBall
	dec e
	jr nz, .ball
	scf
	ret
.badCell
	pop bc
.no
	and a
	ret

; HL=inner cell, D=wall. Boundary and east connector must still be trees.
FGBoundaryFree:
	ld a, d
	and a
	jr z, .north
	cp 1
	jr z, .west
	inc hl
	ld a, [hli]
	cp 2
	jr nz, .no
	jr .check
.west
	dec hl
	jr .check
.north
	ld de, -FG_PARENT_STRIDE
	add hl, de
.check
	ld a, [hl]
	cp 2
	jr nz, .no
	scf
	ret
.no
	and a
	ret

FGOpenParentSRAM:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK(sProcForestStagingBuffer) == 0
	xor a
	ld [rRAMB], a
	ret

FGCloseSRAM:
	xor a
	ld [rBMODE], a
	ld [rRAMG], a
	ret

; SRAM0 open. Carry set, D=wall and E=site for ONE valid marker. Reading
; markers does not require an active encounter, so old/finished rooms can exit.
FGFindOpening:
	ld a, [sProcForestBaked]
	cp 1
	jr nz, .none
	ld a, [sProcForestRiverSide]
	cp $ff
	jr nz, .none
	ld a, [sProcForestExitEdge]
	cp 3
	jr nc, .none
	ld bc, $ffff
	ld d, 0
.wall
	ld a, [sProcForestExitEdge]
	cp d
	jr z, .nextWall
	ld e, FG_FIRST_ROW
.site
	push bc
	push de
	call FGMarkerMatches
	pop de
	pop bc
	jr nc, .nextSite
	ld a, b
	cp $ff
	jr nz, .none
	ld b, d
	ld c, e
.nextSite
	inc e
	inc e
	ld a, e
	cp FG_LAST_ROW + 1
	jr c, .site
.nextWall
	inc d
	ld a, d
	cp 3
	jr c, .wall
	ld a, b
	cp $ff
	jr z, .none
	ld d, b
	ld e, c
	scf
	ret
.none
	and a
	ret

FGMarkerMatches:
	push de
	ld hl, sProcForestStagingBuffer
	ld a, d
	and a
	jr z, .northAddress
	ld b, e
	ld de, 20
.row
	add hl, de
	dec b
	jr nz, .row
	pop de
	ld a, d
	cp 1
	jr z, .west
	ld bc, 19
	add hl, bc
	ld a, [hl]
	cp 87
	jr nz, .no
	dec hl
	ld a, [hl]
	cp 27
	jr nz, .no
	dec hl
	jr .cell
.west
	ld a, [hli]
	cp 86
	jr nz, .no
	jr .cell
.northAddress
	ld d, 0
	add hl, de
	pop de
	ld a, [hl]
	cp 88
	jr nz, .no
	ld bc, 20
	add hl, bc
.cell
	ld a, [hl]
	call FGIsFloor
	jr nz, .no
.yes
	scf
	ret
.no
	and a
	ret

; D/E=wall/site -> B/C=top/left event X/Y. D/E preserved.
FGParentEventCoords:
	ld a, e
	add a
	ld c, a
	ld b, 0
	ld a, d
	and a
	jr nz, .vertical
	ld b, c
	ld c, 0
	ret
.vertical
	cp 1
	ret z
	ld b, 39
	ret

FGArmForestWarp::
	call FGHasAssignedEncounter
	and a
	jr z, .none
	call FGOpenParentSRAM
	call FGFindOpening
	push af
	push de
	call FGCloseSRAM
	pop de
	pop af
	jr nc, .none
	call FGParentEventCoords
	ld hl, wWarpEntries + FG_WARP * 4
	ld a, c
	ld [hli], a
	ld a, b
	ld [hli], a
	ld a, d
	add a
	ld [hli], a
	ld [hl], PROCEDURAL_FOREST_GROTTO
	ld a, d
	and a
	jr z, .horizontal
	inc c
	jr .second
.horizontal
	inc b
.second
	ld hl, wWarpEntries + FOREST_GROTTO_SECOND_WARP * 4
	ld a, c
	ld [hli], a
	ld a, b
	ld [hli], a
	ld a, d
	add a
	inc a
	ld [hli], a
	ld [hl], PROCEDURAL_FOREST_GROTTO
	ret
.none
	ld a, $ff
	ld [wWarpEntries + FG_WARP * 4], a
	ret ; legacy saved house0 retains its normal door at the second slot

; Normal arrival copy has run. Resolve all four bytes before parity. No
; assignment gate here: a legacy or resolved room must always have a way out.
FGResolveArrival::
	ldh a, [hCurMap]
	cp PROCEDURAL_FOREST
	ret nz
	ld a, [wWarpedFromWhichMap]
	cp PROCEDURAL_FOREST_GROTTO
	ret nz
	ld a, [wDestinationWarpID]
	cp FG_WARP
	jr z, .validWarp
	cp FOREST_GROTTO_SECOND_WARP
	ret nz
.validWarp
	call FGOpenParentSRAM
	call FGFindOpening
	push af
	push de
	call FGCloseSRAM
	pop de
	pop af
	jr nc, .fallback
	call FGParentEventCoords
	ld a, [wDestinationWarpID]
	cp FOREST_GROTTO_SECOND_WARP
	jr nz, .position
	ld a, d
	and a
	jr z, .horizontal
	inc c
	jr .position
.horizontal
	inc b
.position
	ld a, c
	ld [wYCoord], a
	srl a
	ld c, a
	ld a, b
	ld [wXCoord], a
	srl a
	ld b, a
	call FGBlockAddress
	ld de, -54 ; event_displacement uses base27, not playable block base81
	add hl, de
.storePointer
	ld a, l
	ld [wCurrentTileBlockMapViewPointer], a
	ld a, h
	ld [wCurrentTileBlockMapViewPointer + 1], a
	ret
.fallback
	ld a, 35
	ld [wYCoord], a
	ld a, 18
	ld [wXCoord], a
	ld hl, wOverworldMap + 27 + 26 * 17 + 9
	jr .storePointer

; Rebuild all six departure records even on Continue from a two-warp legacy
; grove. Only the opposite side is opened; authored blocks remain unchanged.
FGLoadGrotto::
	ld hl, wOverworldMap + 42
	ld b, PROCEDURAL_FOREST_GROTTO_HEIGHT
.row
	ld c, PROCEDURAL_FOREST_GROTTO_WIDTH
.col
	ld a, [hl]
	and a
	jr nz, .next
	ld [hl], 27
.next
	inc hl
	dec c
	jr nz, .col
	ld de, 6
	add hl, de
	dec b
	jr nz, .row
	ld a, 6
	ld [wNumberOfWarps], a
	ld b, 3
	ld hl, wWarpEntries
.warpPair
	ld a, $ff
	ld [hli], a
	xor a
	ld [hli], a
	ld a, FG_WARP
	ld [hli], a
	ld a, PROCEDURAL_FOREST
	ld [hli], a
	ld a, $ff
	ld [hli], a
	xor a
	ld [hli], a
	ld a, FOREST_GROTTO_SECOND_WARP
	ld [hli], a
	ld a, PROCEDURAL_FOREST
	ld [hli], a
	dec b
	jr nz, .warpPair
	call FGOpenParentSRAM
	call FGFindOpening
	push af
	push de
	call FGCloseSRAM
	pop de
	pop af
	jr c, .haveWall
	ld d, 2 ; safe legacy/corrupt-room fallback to the west opening
.haveWall
	ld hl, wWarpEntries
	ld a, d
	add a
	add a
	add a
	ld e, a
	ld a, d
	ld d, 0
	add hl, de
	and a
	jr z, .south
	cp 1
	jr z, .east
	ld b, 0
	ld c, 6
	ld a, 86
	ld [wOverworldMap + 42 + 3 * 13], a
	jr .vertical
.east
	ld b, 13
	ld c, 6
	ld a, 87
	ld [wOverworldMap + 42 + 3 * 13 + 6], a
.vertical
	ld [hl], c
	inc hl
	ld [hl], b
	ld de, 3
	add hl, de
	inc c
	ld [hl], c
	inc hl
	ld [hl], b
	ret
.south
	ld b, 6
	ld c, 11
	ld a, 89
	ld [wOverworldMap + 42 + 5 * 13 + 3], a
	ld [hl], c
	inc hl
	ld [hl], b
	ld de, 3
	add hl, de
	inc b
	ld [hl], c
	inc hl
	ld [hl], b
	ret
