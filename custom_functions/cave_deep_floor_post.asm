; The cave's deep floor, load-time half (PROCEDURAL_DEEP_FLOOR_PLAN.md S4, S5,
; S8). Farcall/farjp only, so it lives in $15 rather than the nearly full $26
; beside the seam (custom_functions/cave_deep_floor.asm). It needs no routine of
; that file: its SRAM open/close and control-word check are repeated here.

SECTION "Cave Deep Floor 2", ROMX, BANK[$15]

	ASSERT BANK(sProcCaveStagingBuffer) == 0
	ASSERT BANK(sProcFacilityGenScratch) == 1
	ASSERT CAVE_DEEP_BALLS == 1 ; only slot 2's ball stays on floor 2

; Temporaries for the one-time conversion: wBuffer is free after PCFinalizeCave.
DEF wDeepExitX EQUS "(wBuffer + 0)"
DEF wDeepExitY EQUS "(wBuffer + 1)"
DEF wDeepCount EQUS "(wBuffer + 2)"
DEF wDeepX1    EQUS "(wBuffer + 3)" ; the first ladder: the resident's spot
DEF wDeepY1    EQUS "(wBuffer + 4)"
DEF wDeepX2    EQUS "(wBuffer + 5)" ; the second: the optional encounter's
DEF wDeepY2    EQUS "(wBuffer + 6)"
DEF CAVE_DEEP_NO_SPOT EQU $FF

; ------------------------------------------------------------
; ProcBossPatchStageSprite, every PROCEDURAL_CAVE_1 load, after the boss and
; stage-event pictures and before InitMapSprites. Slot CAVE_OPTIONAL_MON gets
; the optional encounter's sheet when it stands here (floor 2), else 0. On a
; deep cave's floor 2, the floor-1 objects floor 2 does not use (the boss,
; balls 2-4, the stage NPCs) get picture 0, "this slot does not exist", so their
; toggle bits keep floor 1's state; slots 8/9 get the resident rolled with the
; floor (the fallback pair is not written yet on the first load).
; Clobbers everything.
; ------------------------------------------------------------
CaveDeepPatchSprites::
	farcall OptionalEncounterPatchSprite
	call CaveDeepPostCtrl               ; carry = deep, a = control
	ret nc
	ld c, a
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	ret z                               ; floor 1: CaveFallbackPatchSprites zeroed 8/9
	xor a
	ld [wSprite01StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite03StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite04StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite05StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite06StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld [wSprite07StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld a, c
	and CAVE_DEEP_RESIDENT_MASK
	ld b, SPRITE_GAMBLER
	ld d, 0
	ASSERT CAVE_DEEP_GAMBLER == 0
	jr z, .resident
	ld b, 0
	cp CAVE_DEEP_NO_RESIDENT << CAVE_DEEP_RESIDENT_SHIFT
	jr z, .resident
	ld d, SPRITE_SUPER_NERD             ; the Super Nerd or the PokeManiac
.resident
	ld a, b
	ld [wSprite{02d:CAVE_GAMBLER}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ld a, d
	ld [wSprite{02d:CAVE_SUPER_NERD}StateData1 + SPRITESTATEDATA1_PICTUREID], a
	ret

; ------------------------------------------------------------
; CaveDeepAfterFinalize ($26) jumps here, every PROCEDURAL_CAVE_1 load, after
; PCFinalizeCave and its CaveSubroomArm. Floor 1: ladders A/B lead down to
; floor 2's entrance (cave warp 0) and exit ladder (warp 1) instead of the B1F.
; Floor 2: its one-time conversion, then every load: the entrance ladder climbs
; to A (cave warp 2), the exit ladder to B (warp 3), no other warp, the removed
; objects parked, and the optional encounter stood on its spot.
; Clobbers everything; leaves SRAM closed.
; ------------------------------------------------------------
CaveDeepPostPass::
	call CaveDeepPostCtrl
	ret nc
	ld c, a
	ld a, [wRogueFlagsBitfield2]
	bit BIT_ROGUE_DEEP_FLOOR, a
	jr nz, .floor2
	; A deep cave has both dynamic ladders: A armed in warp slot 2, B in 3.
	ld hl, wWarpEntries + CAVE_FIRST_LADDER_WARP * 4      ; ladder A
	ld a, [hl]
	cp CAVE_LADDER_NONE
	jr z, .ladderB
	inc hl
	inc hl
	ld [hl], 0                          ; floor 2's entrance
	inc hl
	ld [hl], PROCEDURAL_CAVE_1
.ladderB
	ld hl, wWarpEntries + (CAVE_FIRST_LADDER_WARP + 1) * 4
	ld a, [hl]
	cp CAVE_LADDER_NONE
	ret z
	inc hl
	inc hl
	ld [hl], 1                          ; floor 2's exit ladder
	inc hl
	ld [hl], PROCEDURAL_CAVE_1
	ret

.floor2
	bit BIT_CAVE_DEEP_SETTLED, c
	call z, CaveDeepSettleFloor2
	; Every load: no ladder of its own, the entrance's ladder up to A.
	ld hl, wWarpEntries + CAVE_FIRST_LADDER_WARP * 4
	ld b, NUM_CAVE_LADDER_SITES
	ld de, 4
.disarm
	ld [hl], CAVE_LADDER_NONE
	add hl, de
	dec b
	jr nz, .disarm
	ld hl, wWarpEntries + CAVE_FIRST_LADDER_WARP * 4
	ld a, CAVESUB_ENTRANCE_Y * 2 + 1    ; the entrance block's bottom-right tile
	ld [hli], a
	ld a, CAVESUB_ENTRANCE_X * 2 + 1
	ld [hli], a
	ld a, CAVE_FIRST_LADDER_WARP        ; floor 1's ladder A
	ld [hli], a
	ld [hl], PROCEDURAL_CAVE_1
	ld hl, wWarpEntries + 4 + 2         ; the exit ladder (positioned by finalize)
	ld [hl], CAVE_FIRST_LADDER_WARP + 1 ; floor 1's ladder B
	inc hl
	ld [hl], PROCEDURAL_CAVE_1
	; The removed objects stand nowhere (their pictures are 0 already).
	xor a
	ld hl, wSprite01StateData2MapY
	ld [hli], a
	ld [hl], a
FOR n, 3, 8
	ld hl, wSprite{02d:n}StateData2MapY
	ld [hli], a
	ld [hl], a
ENDR
	; The optional encounter's spot (CAVESUB_TMP_X/Y on floor 2: its room
	; byte is unused, nothing reaches a B1F from here).
	call CaveDeepPostOpen0
	ld a, [CAVESUB_TMP_X]
	ld d, a
	ld a, [CAVESUB_TMP_Y]
	ld e, a
	call CaveDeepPostClose
	ld a, d
	cp CAVESUB_SIZE - 1
	ret nc
	ld a, e
	cp CAVESUB_SIZE - 1
	ret nc
	add a
	add 4 + 1                           ; bottom-right quadrant, map border included
	ld [wSprite{02d:CAVE_OPTIONAL_MON}StateData2MapY], a
	ld a, d
	add a
	add 4 + 1
	ld [wSprite{02d:CAVE_OPTIONAL_MON}StateData2MapX], a
	ld a, SPRITE_FACING_DOWN
	ld [wSprite{02d:CAVE_OPTIONAL_MON}StateData1FacingDirection], a
	ld [wSprite{02d:CAVE_OPTIONAL_MON}StateData2OrigFacingDirection], a
	ld a, DOWN
	ld [wMapSpriteData + (CAVE_OPTIONAL_MON - 1) * 2], a
	ret

; ------------------------------------------------------------
; Floor 2's first load, once: its own ladders down (to a B1F floor 2 does not
; have) go back to the plain floor they replaced (CaveLadderSiteValid accepts
; only CAVESUB_FLOOR), the first becoming the resident's spot and the second
; the optional encounter's; the entrance becomes a ladder up; the resident
; rolled with the floor is written where the cave's own fallback logic reads
; it; and the wild budget, which floor 2's fresh finalize refilled, is floor
; 1's again. In: c = the control byte. Clobbers everything; SRAM closed.
; ------------------------------------------------------------
CaveDeepSettleFloor2:
	push bc
	call CaveDeepPostOpen0
	ld a, [sProcCaveStagingExitX]
	ld [wDeepExitX], a
	ld a, [sProcCaveStagingExitY]
	ld [wDeepExitY], a
	xor a
	ld [wDeepCount], a
	ld a, CAVE_DEEP_NO_SPOT
	ld [wDeepX1], a
	ld [wDeepY1], a
	ld [wDeepX2], a
	ld [wDeepY2], a
	ld hl, sProcCaveStagingBuffer + CAVESUB_BASE + CAVESUB_STRIDE + 1 ; block (1, 1)
	ld e, 1
.row
	ld d, 1
.block
	ld a, [hl]
	cp CAVE_LADDER_BLOCK
	jr nz, .next
	ld a, [wDeepExitX]
	cp d
	jr nz, .ladder
	ld a, [wDeepExitY]
	cp e
	jr z, .next                         ; the exit ladder stays
.ladder
	ld [hl], CAVESUB_FLOOR              ; the baked buffer
	push hl
	ld bc, wOverworldMap - sProcCaveStagingBuffer
	add hl, bc
	ld [hl], CAVESUB_FLOOR              ; and the live map
	pop hl
	ld a, [wDeepCount]
	inc a
	ld [wDeepCount], a
	cp 1
	jr nz, .second
	ld a, d
	ld [wDeepX1], a
	ld a, e
	ld [wDeepY1], a
	jr .next
.second
	cp 2
	jr nz, .next
	ld a, d
	ld [wDeepX2], a
	ld a, e
	ld [wDeepY2], a
.next
	inc hl
	inc d
	ld a, d
	cp CAVESUB_SIZE - 1
	jr c, .block
	ld bc, CAVESUB_STRIDE - (CAVESUB_SIZE - 2)
	add hl, bc
	inc e
	ld a, e
	cp CAVESUB_SIZE - 1
	jr c, .row

	; The entrance ladder up (CaveAddEntranceLadder's drawing, without its
	; write to CAVESUB_LADDER_B), in both copies.
	ld hl, sProcCaveStagingBuffer + CAVESUB_BASE + CAVESUB_ENTRANCE_Y * CAVESUB_STRIDE + CAVESUB_ENTRANCE_X
	call .entranceLadder
	ld hl, wOverworldMap + CAVESUB_BASE + CAVESUB_ENTRANCE_Y * CAVESUB_STRIDE + CAVESUB_ENTRANCE_X
	call .entranceLadder

	pop bc                              ; c = control
	; The resident: on the first ladder's block, written as the cave's own
	; fallback pair, which CaveFallbackPatchSprites, CaveSubroomArm and
	; CaveFallbackShowOne all read on every later load.
	ld a, [wDeepX1]
	cp CAVE_DEEP_NO_SPOT
	jr z, .noLadder
	or CAVESUB_FALLBACK
	ld [CAVESUB_LADDER_A], a
	ld a, [wDeepY1]
	or CAVESUB_FALLBACK_ROW
	ld [CAVESUB_LADDER_B], a
	jr .state
.noLadder
	ld a, [CAVESUB_LADDER_A]            ; the generator's own fallback pair (no
	cp CAVESUB_FALLBACK                 ; ladder fitted): keep it. CaveFallbackSpot's
	jr c, .none                         ; range, not bit 7 alone: NONE and the
	cp CAVESUB_FALLBACK | 19            ; dynamic tags have bit 7 too.
	jr c, .state
.none
	ld a, CAVE_LADDER_NONE
	ld [CAVESUB_LADDER_A], a
	ld [CAVESUB_LADDER_B], a
	ld a, c
	or CAVE_DEEP_NO_RESIDENT << CAVE_DEEP_RESIDENT_SHIFT
	ld c, a
.state
	; CAVESUB_STATE's resident bits from the control byte (bit 7, objects
	; shown, is still clear: CaveStageFirstEntry runs after this load).
	ld a, c
	and CAVE_DEEP_RESIDENT_MASK
	ld b, 0
	cp CAVE_DEEP_SUPER_NERD << CAVE_DEEP_RESIDENT_SHIFT
	jr nz, .notNerd
	ld b, 1 << BIT_CAVESUB_SUPER_NERD
.notNerd
	cp CAVE_DEEP_MANIAC << CAVE_DEEP_RESIDENT_SHIFT
	jr nz, .notManiac
	ld b, (1 << BIT_CAVESUB_SUPER_NERD) | (1 << BIT_CAVESUB_MANIAC)
.notManiac
	ld a, [CAVESUB_STATE]
	and ~((1 << BIT_CAVESUB_SUPER_NERD) | (1 << BIT_CAVESUB_MANIAC)) & $ff
	or b
	ld [CAVESUB_STATE], a
	; The optional encounter's spot.
	ld a, [wDeepX2]
	ld [CAVESUB_TMP_X], a
	ld a, [wDeepY2]
	ld [CAVESUB_TMP_Y], a
	; Floor 1's wild budget back, and the conversion recorded.
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld a, [CAVE_DEEP_SAVE + CAVE_DEEP_SAVED_BUDGET]
	ld [wProcCaveWildBudget], a
	ld a, c
	or 1 << BIT_CAVE_DEEP_SETTLED
	ld hl, CAVE_DEEP_CTRL
	ld [hli], a
	cpl
	ld [hl], a
	call CaveDeepPostClose
	; The resident stands there on this first load too (CaveSubroomArm ran
	; before the pair existed).
	ld a, [wDeepX1]
	cp CAVE_DEEP_NO_SPOT
	jr z, .encounter
	add a
	add 4 + 1
	ld [wSprite{02d:CAVE_GAMBLER}StateData2MapX], a
	ld [wSprite{02d:CAVE_SUPER_NERD}StateData2MapX], a
	ld a, [wDeepY1]
	add a
	add 4 + 1
	ld [wSprite{02d:CAVE_GAMBLER}StateData2MapY], a
	ld [wSprite{02d:CAVE_SUPER_NERD}StateData2MapY], a
.encounter
	; No second spot (never seen in simulation: the generator draws two
	; ladders): an encounter that lives here would have nowhere to stand.
	ld a, [wDeepX2]
	cp CAVE_DEEP_NO_SPOT
	ret nz
	ld a, [wOptionalEncounterMap]
	cp PROCEDURAL_CAVE_1
	ret nz
	farjp OptionalEncounterClear

; hl = the entrance block in one copy. Block 40, then the floor decal east of
; it restored (cave_subroom_fallback.asm, CaveAddEntranceLadder).
.entranceLadder
	ld [hl], CAVE_LADDER_BLOCK
	inc hl
	ld a, [hl]
	cp 14
	jr z, .decal
	cp 19
	ret nz
.decal
	ld [hl], CAVESUB_FLOOR
	ret

; Out: carry = a deep cave, a = the control byte. Leaves SRAM closed.
CaveDeepPostCtrl:
	call CaveDeepPostOpen0
	ld a, BANK(sProcFacilityGenScratch)
	ld [rRAMB], a
	ld a, [CAVE_DEEP_CTRL + 1]
	cpl
	ld b, a
	ld a, [CAVE_DEEP_CTRL]
	cp b
	jr nz, .no
	and CAVE_DEEP_MAGIC_MASK
	cp CAVE_DEEP_MAGIC
	jr nz, .no
	call CaveDeepPostClose
	ld a, b
	scf
	ret
.no
	call CaveDeepPostClose
	and a
	ret

CaveDeepPostOpen0:
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ret

; Clobbers a; keeps the flags (ld never sets them).
CaveDeepPostClose:
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret
