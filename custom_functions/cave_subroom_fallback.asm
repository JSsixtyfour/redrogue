; Bank26 helpers for the cave ($3F has little room). The entrance ladder: when
; ladder A has no distant partner, the entrance supplies ladder B.
; Applies to all one-ladder caves. SRAM0 stays open; no new scans or RNG rolls.
CaveAddEntranceLadder::
	; The protected entrance block36 is four walkable floor quadrants. Block40
	; preserves its two NPC spots and BL arrival; only BR becomes a ladder.
	; No item/prefab is placed on block36. Its return uses existing ROM warp0,
	; so no dynamic camera/parity override or extra warp slot is needed.
	ld a, CAVE_LADDER_BLOCK
	ld hl, wOverworldMap + 81 + CAVESUB_ENTRANCE_Y * 26 + CAVESUB_ENTRANCE_X
	ld [hl], a
	; Floor decals14/19 east of BR have BL open but TL blocked. Restore that
	; known floor cell so its route goes around the ladder through TR instead.
	; Other decals and all authored terrain remain untouched. Items cannot
	; stand this close to the entrance, and drop-in buffers exclude this row.
	inc hl
	ld a, [hl]
	cp 14
	jr z, .floor
	cp 19
	jr nz, .saved
.floor
	ld [hl], 1
.saved
	ld a, CAVESUB_ENTRANCE_LADDER
	ld [CAVESUB_LADDER_B], a
	ret

; ------------------------------------------------------------
; Dynamic cave ladders (FOLLOWUPS #93): finding them in the baked cave, arming
; their departures and landing their returns. Kept here, beside the forest's
; arrival seam, because bank $3F is nearly full.
; ------------------------------------------------------------

; CaveSubroomArm ($3F), every cave load. In: d = k (1 or 2), e = the subroom
; warp its room ladder is. Arms warp slot CAVE_FIRST_LADDER_WARP + k - 1 at the
; k-th drawn ladder; leaves it disarmed if none is drawn. Clobbers everything.
CaveDynArmSlot::
	push de
	call FGOpenParentSRAM
	pop de
	push de
	ld a, d
	call CaveDynFindLadder          ; carry, d/e = its block
	push af
	call FGCloseSRAM
	pop af
	pop bc                          ; b = k, c = the subroom warp
	ret nc
	ld a, b
	add CAVE_FIRST_LADDER_WARP - 1
	add a
	add a                           ; entry * 4
	ld l, a
	ld h, 0
	push de
	ld de, wWarpEntries
	add hl, de
	pop de
	ld a, e
	add a
	inc a
	ld [hli], a                     ; Y = 2 * blockY + 1
	ld a, d
	add a
	inc a
	ld [hli], a                     ; X = 2 * blockX + 1
	ld a, c
	ld [hli], a                     ; destination warp (0-based): that room ladder
	ld [hl], PROCEDURAL_CAVE_SUBROOM
	ret

; In: a = k (1 or 2). Out: carry = the k-th dynamic ladder was found in the
; BAKED cave (SRAM), d/e = its block: block CAVE_LADDER_BLOCK in rows/columns
; 1-18 in row order, the exit skipped (it may be drawn as block 40 too).
; SRAM bank 0 open (FGOpenParentSRAM opens bank 0). Clobbers a/b/hl.
	ASSERT BANK(sProcCaveStagingBuffer) == 0
CaveDynFindLadder:
	ld b, a
	ld hl, sProcCaveStagingBuffer + CAVESUB_BASE + CAVESUB_STRIDE + 1
	ld e, 1
.row
	ld d, 1
.block
	ld a, [hli]
	cp CAVE_LADDER_BLOCK
	jr nz, .next
	ld a, [sProcCaveStagingExitX]
	cp d
	jr nz, .ladder
	ld a, [sProcCaveStagingExitY]
	cp e
	jr z, .next                     ; the exit, not a ladder down
.ladder
	dec b
	jr nz, .next
	scf
	ret
.next
	inc d
	ld a, d
	cp CAVESUB_SIZE - 1
	jr c, .block
	ld a, l
	add CAVESUB_STRIDE - (CAVESUB_SIZE - 2)
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	inc e
	ld a, e
	cp CAVESUB_SIZE - 1
	jr c, .row
	and a
	ret

; ------------------------------------------------------------
; FGResolveArrival (HOME LoadDestinationWarpPosition, every warp) jumps here
; for PROCEDURAL_CAVE_1. A dynamic ladder has no ROM arrival, so a warp into
; cave warp 2/3 of a cave whose A is CAVESUB_DYN_LADDER_1 lands on the first/
; second dynamic ladder instead of the ROM record (an old cave's site 0/1).
; Gated on the saved tag and the warp, not the source map: only the subroom's
; ladders target warps 2/3 (the trip tests also retarget the entrance at them).
; Sets all four arrival bytes the ROM record would, before parity is derived.
; Clobbers everything (the HOME seam saves the registers).
; ------------------------------------------------------------
CaveResolveArrival::
	ld a, [wDestinationWarpID]
	sub CAVE_FIRST_LADDER_WARP
	cp 2
	ret nc                          ; not warp 2 or 3
	inc a
	ld c, a                         ; k = 1 or 2
	call FGOpenParentSRAM
	ld a, [CAVESUB_LADDER_A]
	cp CAVESUB_DYN_LADDER_1
	jr nz, .rom                     ; an old cave: its ROM site record stands
	ld a, c
	call CaveDynFindLadder
	push af
	call FGCloseSRAM
	pop af
	jr c, .found
	ld de, (CAVESUB_ENTRANCE_X << 8) | CAVESUB_ENTRANCE_Y ; never expected: ROM warp 0's spot
	ld a, CAVESUB_ENTRANCE_Y * 2 + 1
	ld [wYCoord], a
	ld a, CAVESUB_ENTRANCE_X * 2
	ld [wXCoord], a
	jr .pointer
.found
	ld a, e
	add a
	inc a
	ld [wYCoord], a                 ; the ladder quadrant: (2x+1, 2y+1)
	ld a, d
	add a
	inc a
	ld [wXCoord], a
.pointer
	; event_displacement for a 20-wide map: wOverworldMap + 27 + 26*y + x.
	ld hl, wOverworldMap + CAVESUB_STRIDE + 1
	ld bc, CAVESUB_STRIDE
	ld a, e
	and a
	jr z, .col
.addRow
	add hl, bc
	dec a
	jr nz, .addRow
.col
	ld c, d
	add hl, bc                      ; b = 0
	ld a, l
	ld [wCurrentTileBlockMapViewPointer], a
	ld a, h
	ld [wCurrentTileBlockMapViewPointer + 1], a
	ret
.rom
	jp FGCloseSRAM
