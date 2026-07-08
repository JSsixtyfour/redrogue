; custom_functions/procedural_cemetary_gen.asm
;
; Procedural cemetery generator for PROCEDURAL_CEMETARY_1-4.
; Four maps, each 10x9 blocks = 90 bytes, stored in SRAM bank 0.
;
; Per-map: 75% procedural (scatter tombstones on floor cells),
;          25% premade (copy matching PokemonTower floor verbatim).
;
; Tombstone blocks replacing floor (block 54 or 14):
;   76,78,79,81,82,23,19,77,80,101-106
;
; Warp positions (tile coords, always fixed, confirmed with user):
;   Maps 1,3: entrance (3,9) left, exit (18,9) right
;   Map  2  : entrance (18,9) right, exit (3,9) left
;   Map  4  : entrance (18,9) right, exit (9,16) south

SECTION "ProceduralCemetaryGen", ROMX

DEF CEMAP_WIDTH   EQU 10
DEF CEMAP_HEIGHT  EQU 9
DEF CEMAP_SIZE    EQU CEMAP_WIDTH * CEMAP_HEIGHT ; 90 bytes
DEF CEMAP_STRIDE  EQU CEMAP_WIDTH + 6           ; = 16 (width + MAP_BORDER*2)
DEF CEMAP_BASE    EQU 3 + 3 * CEMAP_STRIDE      ; = 51 (wOverworldMap interior offset)

DEF CEMAP_FLOOR_1 EQU 14  ; floor block in ProceduralCemetary1.blk
DEF CEMAP_FLOOR_2 EQU 54  ; floor block in PokemonTower floors / ProceduralCemetary2.blk

DEF CEMAP_NUM_TOMBSTONES EQU 30  ; tombstones scattered per procedural map

; wBuffer scratch (never conflicts - cemetery runs at map load time only)
DEF wCemMapIndex    EQU 0  ; 0-3, which of the 4 maps is currently being generated
DEF wCemTryX        EQU 1
DEF wCemTryY        EQU 2
DEF wCemIsProcedural EQU 3 ; 1 = procedural floor, 0 = premade (for staircase patch)
DEF wCemEntX        EQU 4  ; entrance inner col for path carve
DEF wCemEntY        EQU 5  ; entrance inner row
DEF wCemExX         EQU 6  ; exit inner col
DEF wCemExY         EQU 7  ; exit inner row

; ============================================================
; PCemMapToIndex
; INPUT: hCurMap
; OUTPUT: a = 0-3 for PROCEDURAL_CEMETARY_1/2/3/4
; Explicit lookup needed because map IDs aren't consecutive
; ($6C = VICTORY_ROAD_1F sits between cemetery 3 and 4).
; ============================================================
PCemMapToIndex:
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETARY_4
	ld a, 3
	ret z
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETARY_3
	ld a, 2
	ret z
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETARY_2
	ld a, 1
	ret z
	xor a
	ret

; ============================================================
; PCemGetMapBase
; OUTPUT: hl = base SRAM address of current map's 90 bytes
; wCemMapIndex must be set. SRAM must be enabled.
; ============================================================
PCemGetMapBase:
	ld hl, sProcCemetaryMaps
	ld a, [wBuffer + wCemMapIndex]
	and a
	ret z
	ld b, a
.loop
	ld de, CEMAP_SIZE
	add hl, de
	dec b
	jr nz, .loop
	ret

; ============================================================
; PCemGetCellHL
; INPUT: [wBuffer+wCemTryX/Y], [wBuffer+wCemMapIndex]
; OUTPUT: hl = SRAM address of that cell. SRAM must be enabled.
; ============================================================
PCemGetCellHL:
	call PCemGetMapBase
	ld a, [wBuffer + wCemTryY]
	and a
	jr z, .doneY
	ld b, a
.rowLoop
	ld de, CEMAP_WIDTH
	add hl, de
	dec b
	jr nz, .rowLoop
.doneY
	ld a, [wBuffer + wCemTryX]
	ld e, a
	ld d, 0
	add hl, de
	ret

; ============================================================
; PCemIsFloor: Z set if current cell is floor (block 14 or 54)
; INPUT: a = block value
; ============================================================
PCemIsFloor:
	cp CEMAP_FLOOR_1
	ret z
	cp CEMAP_FLOOR_2
	ret

; ============================================================
; PCemGenerateMaps
; Lazy generation: just resets per-run state. Each floor is
; generated on first entry (PCemFinalizeMap checks the ready bit).
; Called (via homecall) on Pallet Town entry.
; ============================================================
PCemGenerateMaps::
	; enable SRAM bank 0
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ASSERT BANK("Sprite Buffers") == 0
	xor a
	ld [rRAMB], a

	; clear ready bits (all 4 floors need fresh generation)
	; and per-run item-collected flags
	xor a
	ld [sProcCemetaryReady], a
	ld [sProcCemetaryItemGot], a

	; close SRAM
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a

	; set wild battle budget for the entire cemetery run (10 + wBattleCount/5)
	ld a, [wBattleCount]
	ld b, 0
.cemBudgetDiv
	cp 5
	jr c, .cemBudgetDone
	sub 5
	inc b
	jr .cemBudgetDiv
.cemBudgetDone
	ld a, b
	add a, 10
	jr nc, .cemBudgetNoClamp
	ld a, 255
.cemBudgetNoClamp
	ld [wProcCemWildBudget], a
	; clear calmed events for fresh run
	ResetEvent EVENT_PC_CEM_BUDGET_ENDED
	ResetEvent EVENT_PC_CEM_CALMED_SHOWN
	ret

; ============================================================
; PCemGenerateOneMap
; Generates one 90-byte map. SRAM must be enabled.
; ============================================================
PCemGenerateOneMap:
	; 25% premade, 75% procedural
	ld c, 4
	call Rangerandom
	and a
	jr nz, .procedural
	xor a
	ld [wBuffer + wCemIsProcedural], a
	call PCemCopyPremadeTemplate
	call PCemDecorateWalls
	call PCemPlaceBall
	call PCemRollItem
	ret
.procedural
	ld a, 1
	ld [wBuffer + wCemIsProcedural], a
	call PCemCopyBaseTemplate
	call PCemFillFloorTombstones  ; fill ALL floor cells with tombstones
	call PCemDecorateWalls        ; decorate wall/edge tiles
	call PCemRollItem             ; roll item now (needs wCemMapIndex, no floor needed)
	call PCemCarveMainPath        ; carve path, place item mid-path, save ball X/Y to SRAM
	ret

; ============================================================
; PCemCopyPremadeTemplate
; Maps: 0→Tower5F, 1→Tower4F, 2→Tower3F, 3→Tower6F
; ============================================================
PCemCopyPremadeTemplate:
	; compute dest: PCemGetMapBase → de
	call PCemGetMapBase
	ld d, h
	ld e, l
	; compute source: table entry = mapIndex * 3 bytes (bank, lo, hi)
	ld a, [wBuffer + wCemMapIndex]
	ld b, a
	add a       ; *2
	add a, b    ; *3
	ld hl, PCemPremadeTable
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]  ; a = bank
	ld c, [hl]
	inc hl
	ld b, [hl]   ; bc = source address (lo in c, hi in b)
	ld h, b
	ld l, c      ; hl = source address
	ld bc, CEMAP_SIZE
	jp FarCopyData2

PCemPremadeTable:
	db BANK(PCemTower5F_Blocks), LOW(PCemTower5F_Blocks),  HIGH(PCemTower5F_Blocks)
	db BANK(PCemTower4F_Blocks), LOW(PCemTower4F_Blocks),  HIGH(PCemTower4F_Blocks)
	db BANK(PCemTower3F_Blocks), LOW(PCemTower3F_Blocks),  HIGH(PCemTower3F_Blocks)
	db BANK(PCemTower6F_Blocks), LOW(PCemTower6F_Blocks),  HIGH(PCemTower6F_Blocks)

PCemTower5F_Blocks: INCBIN "maps/PokemonTower5F.blk"
PCemTower4F_Blocks: INCBIN "maps/PokemonTower4F.blk"
PCemTower3F_Blocks: INCBIN "maps/PokemonTower3F.blk"
PCemTower6F_Blocks: INCBIN "maps/PokemonTower6F.blk"

; ============================================================
; PCemCopyBaseTemplate
; Maps 0-2 → ProceduralCemetary1.blk, map 3 → ProceduralCemetary2.blk
; ============================================================
PCemCopyBaseTemplate:
	call PCemGetMapBase
	ld d, h
	ld e, l
	ld a, [wBuffer + wCemMapIndex]
	cp 3
	jr z, .useMap2
	ld a, BANK(PCemBaseTemplate1)
	ld hl, PCemBaseTemplate1
	jr .doCopy
.useMap2
	ld a, BANK(PCemBaseTemplate2)
	ld hl, PCemBaseTemplate2
.doCopy
	ld bc, CEMAP_SIZE
	jp FarCopyData2

PCemBaseTemplate1: INCBIN "maps/ProceduralCemetary1.blk"
PCemBaseTemplate2: INCBIN "maps/ProceduralCemetary2.blk"

; ============================================================
; PCemScatterTombstones
; Replaces CEMAP_NUM_TOMBSTONES floor cells with tombstones.
; Skips cells near warp staircase positions.
; ============================================================
PCemScatterTombstones:
	ld b, CEMAP_NUM_TOMBSTONES
.scatter
	push bc
	ld c, CEMAP_WIDTH
	call Rangerandom
	ld [wBuffer + wCemTryX], a
	ld c, CEMAP_HEIGHT
	call Rangerandom
	ld [wBuffer + wCemTryY], a
	call PCemInWarpZone
	jr nz, .skip
	call PCemGetCellHL
	ld a, [hl]
	call PCemIsFloor
	jr nz, .skip
	; pick random tombstone block
	push hl
	ld c, NUM_CEMDECO_FLOOR
	call Rangerandom
	ld hl, PCemFloorTombstoneTable
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	pop hl
	ld [hl], a
.skip
	pop bc
	dec b
	jr nz, .scatter
	ret

; Wall tiles that carving must never replace with floor.
; These define the room structure and decoration anchor points.
PCemProtectedWallTable:
	db 6, 7, 10, 28, 29, 30, 32, 57
DEF NUM_PROTECTED_WALLS EQU 8

; PCemIsProtectedWall: a = cell value. Z if protected, NZ if carveable.
PCemIsProtectedWall:
	ld hl, PCemProtectedWallTable
	ld b, NUM_PROTECTED_WALLS
.loop
	cp [hl]
	ret z              ; Z = in protected list, do not carve
	inc hl
	dec b
	jr nz, .loop
	or 1               ; NZ = not protected, safe to carve
	ret

PCemFloorTombstoneTable:
	db 76, 78, 79, 81, 82, 23, 19, 77, 80, 101, 102, 103, 104, 105, 106
DEF NUM_CEMDECO_FLOOR EQU 15

; ============================================================
; PCemInWarpZone
; NZ if (TryX,TryY) is in a margin zone around any warp staircase.
; Z if safe to place tombstone.
; Staircase margin cols 0-2 (left) and cols 7-9 (right), rows 3-5.
; South staircase (map 3 only): cols 3-5, rows 7-8.
; ============================================================
PCemInWarpZone:
	ld a, [wBuffer + wCemTryX]
	ld b, a
	ld a, [wBuffer + wCemTryY]
	ld c, a
	; left staircase zone: cols 0-2, rows 3-5
	ld a, b
	cp 3
	jr nc, .notLeft
	ld a, c
	cp 3
	jr c, .notLeft
	cp 6
	jr c, .inZone
.notLeft
	; right staircase zone: cols 7-9, rows 3-5
	ld a, b
	cp 7
	jr c, .notRight
	ld a, c
	cp 3
	jr c, .notRight
	cp 6
	jr c, .inZone
.notRight
	; south staircase (map 3): cols 3-5, rows 7-8
	ld a, [wBuffer + wCemMapIndex]
	cp 3
	jr nz, .safe
	ld a, b
	cp 3
	jr c, .safe
	cp 6
	jr nc, .safe
	ld a, c
	cp 7
	jr c, .safe
.inZone
	or 1        ; NZ = in zone
	ret
.safe
	xor a       ; Z = safe
	ret

; ============================================================
; PCemPlaceBall: for premade maps — scan for a random floor cell.
; ============================================================
PCemPlaceBall:
	ld b, 100
.pbLoop
	push bc
	ld c, CEMAP_WIDTH
	call Rangerandom
	ld [wBuffer + wCemTryX], a
	ld c, CEMAP_HEIGHT
	call Rangerandom
	ld [wBuffer + wCemTryY], a
	call PCemGetCellHL
	ld a, [hl]
	call PCemIsFloor
	pop bc
	jr nz, .pbMiss
	call PCemSaveBallPos
	ret
.pbMiss
	dec b
	jr nz, .pbLoop
	; fallback: center
	ld a, 5
	ld [wBuffer + wCemTryX], a
	ld a, 4
	ld [wBuffer + wCemTryY], a
	call PCemSaveBallPos
	ret

; ============================================================
; PCemCheckConnected
; Multi-pass flood fill from entrance toward exit.
; Uses wBuffer offsets 5-16 as a 12-byte / 96-bit "reachable" bitfield
; (bits 0-89, one per cell, row-major). SRAM must be enabled.
; OUTPUT: carry SET if entrance can reach exit, carry CLEAR otherwise.
;
; Entrance/exit positions (block coords, conservative center of staircase):
;   Maps 0,2: entrance=(1,4), exit=(8,4)
;   Map  1  : entrance=(8,4), exit=(1,4)
;   Map  3  : entrance=(8,4), exit=(4,8)
;
; "Walkable" for connectivity = block 14 OR block 54 (floor only).
; Tombstone blocks (76-82 etc.) are treated as obstacles; if they turn
; out to be passable in-game, PCemClearBlockingTombstones is a no-op.
; ============================================================
PCemCheckConnected:
	; clear bitfield (wBuffer offsets 5-16 = 12 bytes)
	ld hl, wBuffer + 5
	ld b, 12
	xor a
.clearLoop
	ld [hli], a
	dec b
	jr nz, .clearLoop

	; determine entrance and exit from mapIndex
	ld a, [wBuffer + wCemMapIndex]
	; maps 0,2 enter left (col 1, row 4), exit right (col 8, row 4)
	; map 1 enters right (col 8, row 4), exits left (col 1, row 4)
	; map 3 enters right (col 8, row 4), exits south (col 4, row 8)
	; entrance col: maps 0,2 → col 1; maps 1,3 → col 8
	and 1                    ; bit 0: 0=left-entry, 1=right-entry
	jr nz, .rightEntry
	; left entry: entrance=(1,4), exit=(8,4) — both floor, works directly
	ld d, 1                  ; entrance col
	ld e, 4                  ; entrance row
	ld b, 8                  ; exit col
	ld c, 4                  ; exit row
	jr .gotEntranceExit
.rightEntry
	ld d, 8                  ; entrance col
	ld e, 4                  ; entrance row
	; map 3 exits south, others exit left.
	; Exit cells (col 1 and row 8 boundaries) hold stair blocks (21/22), not floor.
	; PCemFloodStep only marks floor cells reachable, so checking the boundary exit
	; cell directly always fails for right-entry maps. Check one step inside instead.
	ld a, [wBuffer + wCemMapIndex]
	cp 3
	jr z, .southExit
	ld b, 2                  ; exit check col (col 1 = stair, col 2 = first floor inside)
	ld c, 4                  ; exit row
	jr .gotEntranceExit
.southExit
	ld b, 4                  ; exit col
	ld c, 7                  ; exit check row (row 8 = boundary, row 7 = first floor inside)
.gotEntranceExit
	; mark entrance cell as reachable
	; bitfield index = row * CEMAP_WIDTH + col
	ld a, e                  ; entrance row
	ld h, CEMAP_WIDTH
	call PCemMul8            ; a = row * WIDTH
	add a, d                 ; + col
	call PCemSetBit          ; set bit in wBuffer+5..16

	; flood fill: 9 passes (sufficient for 9-row map)
	ld a, 9
.floodPass
	push af
	push bc                  ; save exit coords
	push de
	call PCemFloodStep
	pop de
	pop bc
	pop af
	dec a
	jr nz, .floodPass

	; check if exit cell is reachable
	ld a, c                  ; exit row
	ld h, CEMAP_WIDTH
	call PCemMul8
	add a, b                 ; + exit col
	call PCemTestBit         ; zero if not reachable
	jr z, .notConnected
	scf                      ; carry = connected
	ret
.notConnected
	and a                    ; clear carry = not connected
	ret

; One flood-fill pass: mark any floor cell reachable if any orthogonal
; neighbor is already reachable. Uses SRAM (must be enabled).
PCemFloodStep:
	xor a
	ld [wBuffer + wCemTryY], a
.rowLoop
	xor a
	ld [wBuffer + wCemTryX], a
.colLoop
	; skip if already reachable
	ld a, [wBuffer + wCemTryY]
	ld h, CEMAP_WIDTH
	call PCemMul8
	ld b, a
	ld a, [wBuffer + wCemTryX]
	add a, b                 ; bitfield index
	call PCemTestBit
	jr nz, .nextCell         ; already reachable, skip

	; check if this cell is floor
	call PCemGetCellHL
	ld a, [hl]
	call PCemIsFloor
	jr nz, .nextCell         ; not floor, skip

	; check if any orthogonal neighbor is reachable
	call PCemAnyNeighborReachable
	jr z, .nextCell          ; no reachable neighbor

	; mark reachable
	ld a, [wBuffer + wCemTryY]
	ld h, CEMAP_WIDTH
	call PCemMul8
	ld b, a
	ld a, [wBuffer + wCemTryX]
	add a, b
	call PCemSetBit
.nextCell
	ld a, [wBuffer + wCemTryX]
	inc a
	ld [wBuffer + wCemTryX], a
	cp CEMAP_WIDTH
	jr nz, .colLoop
	ld a, [wBuffer + wCemTryY]
	inc a
	ld [wBuffer + wCemTryY], a
	cp CEMAP_HEIGHT
	jr nz, .rowLoop
	ret

; Check if any orthogonal neighbor of (TryX,TryY) is reachable.
; Returns NZ if at least one neighbor is reachable, Z if none.
PCemAnyNeighborReachable:
	ld a, [wBuffer + wCemTryX]
	ld b, a
	ld a, [wBuffer + wCemTryY]
	ld c, a
	; check left (b-1, c)
	ld a, b
	and a
	jr z, .notLeft
	dec a                    ; col-1
	ld e, a
	ld a, c
	ld h, CEMAP_WIDTH
	call PCemMul8
	add a, e
	call PCemTestBit
	jr nz, .reachable
.notLeft
	; check right (b+1, c)
	ld a, b
	inc a
	cp CEMAP_WIDTH
	jr nc, .notRight
	ld e, a
	ld a, c
	ld h, CEMAP_WIDTH
	call PCemMul8
	add a, e
	call PCemTestBit
	jr nz, .reachable
.notRight
	; check up (b, c-1)
	ld a, c
	and a
	jr z, .notUp
	dec a
	ld e, a
	ld h, CEMAP_WIDTH
	call PCemMul8
	add a, b
	call PCemTestBit
	jr nz, .reachable
.notUp
	; check down (b, c+1)
	ld a, c
	inc a
	cp CEMAP_HEIGHT
	jr nc, .notDown
	ld e, a
	ld h, CEMAP_WIDTH
	call PCemMul8
	add a, b
	call PCemTestBit
	jr nz, .reachable
.notDown
	xor a   ; Z = no reachable neighbor
	ret
.reachable
	or 1    ; NZ = has reachable neighbor
	ret

; a = a * h (8-bit, result in a, h must be CEMAP_WIDTH=10)
; Only called with h=10. Computed as a*8 + a*2.
PCemMul8:
	ld b, a
	sla a
	sla a
	sla a     ; a*8
	ld c, a
	ld a, b
	sla a     ; b*2
	add a, c  ; a*2 + a*8 = a*10
	ret

; Set bit 'a' (0-89) in the 12-byte bitfield at wBuffer+5
PCemSetBit:
	ld b, a
	and 7              ; bit position within byte
	ld c, a
	ld a, b
	srl a
	srl a
	srl a              ; byte offset
	ld hl, wBuffer + 5
	add a, l
	ld l, a
	ld a, 1
	ld b, c
	inc b
.shiftLoop
	dec b
	jr z, .shifted
	sla a
	jr .shiftLoop
.shifted
	or [hl]
	ld [hl], a
	ret

; Test bit 'a' (0-89) in the 12-byte bitfield at wBuffer+5
; Returns NZ if bit is set, Z if clear.
PCemTestBit:
	ld b, a
	and 7
	ld c, a
	ld a, b
	srl a
	srl a
	srl a
	ld hl, wBuffer + 5
	add a, l
	ld l, a
	ld a, [hl]
	ld b, c
	inc b
.testShift
	dec b
	jr z, .testDone
	sra a
	jr .testShift
.testDone
	and 1              ; NZ if bit was set
	ret

; ============================================================
; PCemClearBlockingTombstones
; After scatter: re-run flood fill. For any floor cell that is NOW
; a tombstone but was reachable in the pre-scatter run, restore it
; to floor (54). This clears only tombstones that break connectivity.
; Simple version: clear any tombstone on row 4 (the staircase row)
; between the two staircases (cols 1-8). Handles the common case
; where scattered tombstones block the horizontal corridor.
; ============================================================
PCemClearBlockingTombstones:
	; clear row 4 between cols 1 and 8 of any tombstone blocks
	ld a, 4
	ld [wBuffer + wCemTryY], a
	ld a, 1
.clearRow
	ld [wBuffer + wCemTryX], a
	push af
	call PCemGetCellHL
	ld a, [hl]
	call PCemIsFloor
	jr z, .isClearFloor   ; already floor, skip
	; is this a tombstone on floor? check against known floor blocks
	; anything that's not a wall (block 1) and not already floor is a tombstone
	cp 1
	jr z, .isClearFloor   ; solid wall, leave it
	; restore to floor
	ld a, CEMAP_FLOOR_2    ; use block 54 (Tower standard floor)
	ld [hl], a
.isClearFloor
	pop af
	inc a
	cp 9               ; cols 1-8
	jr nz, .clearRow
	ret

; ============================================================
; PCemDecorateWalls
; Replaces eligible wall/feature tiles with decorative variants.
; SRAM must be enabled. Runs on both premade and procedural maps.
; Each eligible tile has a 1-in-4 chance of being decorated.
; ============================================================
PCemDecorateWalls:
	call PCemGetMapBase     ; hl = SRAM base
	ld b, CEMAP_SIZE        ; 90 cells
.decoScan
	push bc
	push hl
	ld a, [hl]
	call PCemDecoLookup     ; c = variant count, de = variant table; Z if no match
	jr z, .decoSkip
	; 25% chance
	push de
	push bc
	ld c, 4
	call Rangerandom
	pop bc
	pop de
	and a
	jr nz, .decoSkip
	; pick random variant: c = count, e = base offset
	push de                 ; save de (e=base offset, d=0)
	call Rangerandom        ; 0..c-1
	pop de                  ; restore base offset into e
	add a, e                ; final index = base_offset + random
	ld hl, PCemWallDecoVariants
	ld e, a
	ld d, 0
	add hl, de              ; hl = PCemWallDecoVariants + final_index
	ld a, [hl]              ; selected variant block
	pop hl                  ; restore cell address
	ld [hl], a
	jr .decoNext
.decoSkip
	pop hl
.decoNext
	inc hl
	pop bc
	dec b
	jr nz, .decoScan
	ret

; PCemDecoLookup: given block value in a, return Z if no deco match.
; If match (NZ): c = variant count, e = base offset into PCemWallDecoVariants, d=0.
; Clobbers a,b,c,d,e,hl. Preserves incoming a in d during search.
PCemDecoLookup:
	ld hl, PCemWallDecoTable
	ld d, a                 ; d = incoming block value (preserved across table scan)
.lookupLoop
	ld a, [hli]             ; a = source block from table
	cp $ff                  ; end of table? (checks TABLE byte, not incoming value)
	jr z, .noMatch
	ld b, a                 ; b = source block
	ld c, [hl]              ; c = variant count
	inc hl
	ld e, [hl]              ; e = base offset into PCemWallDecoVariants
	inc hl
	ld a, d                 ; restore incoming block value
	cp b                    ; match?
	jr z, .matched
	jr .lookupLoop
.noMatch
	xor a                   ; Z = no match
	ret
.matched
	ld d, 0                 ; de = (0, base_offset)
	or 1                    ; NZ = matched
	ret

; Table: source_block, variant_count, offset_into_PCemWallDecoVariants
PCemWallDecoTable:
	db 29, 3,  0   ; → 98, 86, 85
	db 28, 1,  3   ; → 83
	db 30, 1,  4   ; → 84
	db 32, 3,  5   ; → 95, 89, 88
	db  7, 1,  8   ; → 97
	db  6, 3,  9   ; → 99, 100, 91
	db 10, 1, 12   ; → 96
	db 57, 3, 13   ; → 90, 94, 87
	db $ff

PCemWallDecoVariants:
	db 98, 86, 85   ; offsets 0-2  (for block 29)
	db 83           ; offset  3    (for block 28)
	db 84           ; offset  4    (for block 30)
	db 95, 89, 88   ; offsets 5-7  (for block 32)
	db 97           ; offset  8    (for block 7)
	db 99, 100, 91  ; offsets 9-11 (for block 6)
	db 96           ; offset  12   (for block 10)
	db 90, 94, 87   ; offsets 13-15 (for block 57)

; ============================================================
; PCemPlaceStaircases
; Writes entrance/exit stair tiles into wOverworldMap after blit.
; Deterministic from map index — no SRAM needed.
; Map 0,2: enter west col 1 (block 17), exit east col 8 (block 18)
; Map 1:   enter east col 8 (block 22), exit west col 1 (block 21)
; Map 3:   enter east col 8 (block 22), south exit unchanged (same tile always)
; ============================================================
PCemPlaceStaircases:
	; Apply to all maps — wBuffer is unreliable across map loads so we can't
	; check wCemIsProcedural here. Tower premade floors share row 4 / cols 1,9
	; so the stair patch is safe for them too.
	ld hl, wOverworldMap + CEMAP_BASE + 4 * CEMAP_STRIDE
	ld b, h
	ld c, l                  ; bc = row 4 base
	ld a, [wBuffer + wCemMapIndex]
	and 1                    ; 0 = left entry, 1 = right entry
	jr nz, .rightEntry
.leftEntry
	; Maps 0,2: col 1 = west entrance (17), col 9 = east exit (18)
	ld de, 1
	add hl, de
	ld [hl], 17
	ld h, b
	ld l, c
	ld de, 9
	add hl, de
	ld [hl], 18
	ret
.rightEntry
	; Map 1: col 9 = east entrance (22), col 1 = west exit (21)
	; Map 3: col 9 = east entrance (22), south exit unchanged
	ld de, 9
	add hl, de
	ld [hl], 22
	ld a, [wBuffer + wCemMapIndex]
	cp 3
	ret z
	ld h, b
	ld l, c
	ld de, 1
	add hl, de
	ld [hl], 21
	ret

; ============================================================
; PCemFillFloorTombstones
; Replaces every floor cell (14 or 54) with a random tombstone.
; After this, only carved cells will become floor.
; SRAM must be enabled.
; ============================================================
PCemFillFloorTombstones:
	call PCemGetMapBase
	ld b, CEMAP_SIZE
.fftLoop
	push bc
	push hl
	ld a, [hl]
	call PCemIsFloor
	jr nz, .fftSkip
	ld c, NUM_CEMDECO_FLOOR
	call Rangerandom
	ld hl, PCemFloorTombstoneTable
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	pop hl
	ld [hl], a
	jr .fftNext
.fftSkip
	pop hl
.fftNext
	inc hl
	pop bc
	dec b
	jr nz, .fftLoop
	ret

; wBuffer slots for carving
; wCemEntX/Y (4,5), wCemExX/Y (6,7) set in PCemCarveMainPath
; wCemStepCount (8): steps taken so far during carve
; wCemItemDone  (9): 0=item not yet placed, 1=placed
DEF wCemStepCount EQU 8
DEF wCemItemDone  EQU 9

; ============================================================
; PCemCarveMainPath
; Sets inner entrance/exit, clears step state, rolls one of 4
; carving algorithms, then saves ball position at the end.
; Item is placed randomly mid-path by PCemCarveStep.
; SRAM must be enabled.
; ============================================================
PCemCarveMainPath:
	ld a, [wBuffer + wCemMapIndex]
	and 1
	jr nz, .rightEntry
	ld a, 2
	ld [wBuffer + wCemEntX], a
	ld a, 4
	ld [wBuffer + wCemEntY], a
	ld a, 8
	ld [wBuffer + wCemExX], a
	ld a, 4
	ld [wBuffer + wCemExY], a
	jr .startCarve
.rightEntry
	ld a, 8
	ld [wBuffer + wCemEntX], a
	ld a, 4
	ld [wBuffer + wCemEntY], a
	ld a, [wBuffer + wCemMapIndex]
	cp 3
	jr z, .southEx
	ld a, 2
	ld [wBuffer + wCemExX], a
	ld a, 4
	ld [wBuffer + wCemExY], a
	jr .startCarve
.southEx
	ld a, 4
	ld [wBuffer + wCemExX], a
	ld a, 7
	ld [wBuffer + wCemExY], a
.startCarve
	; Place cursor at entrance inner
	ld a, [wBuffer + wCemEntX]
	ld [wBuffer + wCemTryX], a
	ld a, [wBuffer + wCemEntY]
	ld [wBuffer + wCemTryY], a
	; Reset step state for mid-path item placement
	xor a
	ld [wBuffer + wCemStepCount], a
	ld [wBuffer + wCemItemDone], a
	; Roll algorithm 0-3. Extra Random call advances RNG past the
	; deterministic state that PCemFillFloorTombstones leaves behind,
	; ensuring each map gets genuine algorithm variety.
	call Random
	ld c, 4
	call Rangerandom
	and 3
	jr z, .doA
	cp 1
	jr z, .doB
	cp 2
	jr z, .doC
	call PCemAlgoD
	jr .saveBall
.doA
	call PCemAlgoA
	jr .saveBall
.doB
	call PCemAlgoB
	jr .saveBall
.doC
	call PCemAlgoC
.saveBall
	; If item wasn't placed mid-path, use current (exit inner) position
	ld a, [wBuffer + wCemItemDone]
	and a
	ret nz
	; fallback: save current position as ball
	call PCemSaveBallPos
	ret

; ============================================================
; PCemCarveStep
; Writes floor at (wCemTryX,wCemTryY), increments step counter,
; and with 15% chance after 3+ steps places the item here.
; SRAM must be enabled.
; ============================================================
PCemCarveStep:
	call PCemGetCellHL
	ld [hl], CEMAP_FLOOR_1     ; always write — path connectivity > wall aesthetics
	; Increment step counter
	ld a, [wBuffer + wCemStepCount]
	inc a
	ld [wBuffer + wCemStepCount], a
	; Only try to place item after 3+ steps and if not placed yet
	cp 3
	ret c
	ld a, [wBuffer + wCemItemDone]
	and a
	ret nz
	; 15% chance to place item here
	ld c, 20
	call Rangerandom
	cp 3
	ret nc
	call PCemSaveBallPos
	ld a, 1
	ld [wBuffer + wCemItemDone], a
	ret

PCemSaveBallPos:
	ld hl, sProcCemetaryBallX
	ld a, [wBuffer + wCemMapIndex]
	ld e, a
	ld d, 0
	add hl, de
	ld a, [wBuffer + wCemTryX]
	ld [hl], a
	ld hl, sProcCemetaryBallY
	add hl, de
	ld a, [wBuffer + wCemTryY]
	ld [hl], a
	ret

; ============================================================
; PCemStepToward: move wCemTryX/Y one step toward wCemExX/Y.
; Returns Z if already at exit.
; ============================================================
; PCemStepToward: move one step toward exit (wCemExX/Y).
; Simplified now that PCemCarveStep writes floor everywhere —
; no need to avoid any tiles. Returns Z if already at exit.
PCemStepToward:
	call .doNaturalStep
.stepOK
	or 1
	ret

.doNaturalStep:
	; Move one step toward wCemExX/Y, clamped to bounds
	ld a, [wBuffer + wCemTryX]
	ld b, a
	ld a, [wBuffer + wCemExX]
	cp b
	jr z, .natY
	jr c, .natDecX
	inc b
	ld a, b
	ld [wBuffer + wCemTryX], a
	ret
.natDecX
	dec b
	ld a, b
	ld [wBuffer + wCemTryX], a
	ret
.natY
	ld a, [wBuffer + wCemTryY]
	ld b, a
	ld a, [wBuffer + wCemExY]
	cp b
	ret z
	jr c, .natDecY
	inc b
	ld a, b
	ld [wBuffer + wCemTryY], a
	ret
.natDecY
	dec b
	ld a, b
	ld [wBuffer + wCemTryY], a
	or 1
	ret

; ============================================================
; PCemAtExit: returns Z if (wCemTryX,wCemTryY)==(wCemExX,wCemExY)
; ============================================================
PCemAtExit:
	ld a, [wBuffer + wCemTryX]
	ld b, a
	ld a, [wBuffer + wCemExX]
	cp b
	ret nz
	ld a, [wBuffer + wCemTryY]
	ld b, a
	ld a, [wBuffer + wCemExY]
	cp b
	ret

; ============================================================
; Algorithm A: Direct L-shape (random H-then-V or V-then-H)
; ============================================================
PCemAlgoA:
	; Always h-first: horizontal then vertical. vFirst hits block 32 (protected)
	; at col 8 row 6 on map 3 (south exit), creating a gap in the path.
.hFirst
	; Move horizontally to exit X, then vertically to exit Y.
	; push bc / pop bc around every PCemCarveStep because Rangerandom
	; (called inside PCemCarveStep for item placement) sets B=0.
	ld a, [wBuffer + wCemExX]
	ld b, a
.hLoopA
	push bc
	call PCemCarveStep
	pop bc                     ; restore ExX into B
	ld a, [wBuffer + wCemTryX]
	cp b
	jr z, .vA
	jr c, .hIncA
	dec a
	ld [wBuffer + wCemTryX], a
	jr .hLoopA
.hIncA
	inc a
	ld [wBuffer + wCemTryX], a
	jr .hLoopA
.vA
	ld a, [wBuffer + wCemExY]
	ld b, a
.vLoopA
	push bc
	call PCemCarveStep
	pop bc                     ; restore ExY into B
	call PCemAtExit
	ret z
	ld a, [wBuffer + wCemTryY]
	cp b
	jr z, .doneA
	jr c, .vIncA
	dec a
	ld [wBuffer + wCemTryY], a
	jr .vLoopA
.vIncA
	inc a
	ld [wBuffer + wCemTryY], a
	jr .vLoopA
.doneA
	ret
.vFirst
	ld a, [wBuffer + wCemExY]
	ld b, a
.vFirstLoop
	push bc
	call PCemCarveStep
	pop bc
	ld a, [wBuffer + wCemTryY]
	cp b
	jr z, .hSecA
	jr c, .vFInc
	dec a
	ld [wBuffer + wCemTryY], a
	jr .vFirstLoop
.vFInc
	inc a
	ld [wBuffer + wCemTryY], a
	jr .vFirstLoop
.hSecA
	ld a, [wBuffer + wCemExX]
	ld b, a
.hSecLoop
	push bc
	call PCemCarveStep
	pop bc
	call PCemAtExit
	ret z
	ld a, [wBuffer + wCemTryX]
	cp b
	ret z
	jr c, .hSInc
	dec a
	ld [wBuffer + wCemTryX], a
	jr .hSecLoop
.hSInc
	inc a
	ld [wBuffer + wCemTryX], a
	jr .hSecLoop

; ============================================================
; Algorithm B: Wobble (70% toward exit, 30% random adjacent)
; ============================================================
PCemAlgoB:
.stepB
	call PCemCarveStep
	call PCemAtExit
	ret z
	ld c, 10
	call Rangerandom
	cp 7
	jr nc, .wobbleB
	call PCemStepToward
	jp .stepB
.wobbleB
	; Random step N/S/E/W — save old pos, check protection before committing
	ld a, [wBuffer + wCemTryX]
	ld d, a                  ; d = old X
	ld a, [wBuffer + wCemTryY]
	ld e, a                  ; e = old Y
	ld c, 4
	call Rangerandom
	and 3
	jr z, .wbNorth
	cp 1
	jr z, .wbSouth
	cp 2
	jr z, .wbEast
.wbWest
	ld a, d
	cp 3
	jp c, .stepB             ; out of bounds, abort wobble, retry next step
	dec a
	ld [wBuffer + wCemTryX], a
	jr .wbOK
.wbNorth
	ld a, e
	cp 2
	jp c, .stepB
	dec a
	ld [wBuffer + wCemTryY], a
	jr .wbOK
.wbSouth
	ld a, e
	cp 7
	jp nc, .stepB
	inc a
	ld [wBuffer + wCemTryY], a
	jr .wbOK
.wbEast
	ld a, d
	cp 8
	jp nc, .stepB
	inc a
	ld [wBuffer + wCemTryX], a
.wbOK
	jp .stepB

; ============================================================
; Algorithm C: U-route via random midpoint then to exit
; ============================================================
PCemAlgoC:
	; Save real exit, temporarily target a midpoint
	ld a, [wBuffer + wCemExX]
	push af
	ld a, [wBuffer + wCemExY]
	push af
	; Pick midpoint: one of 4 interior corners
	ld c, 4
	call Rangerandom
	and 3
	add a, a            ; *2
	ld e, a
	ld d, 0
	ld hl, PCemMidpointTable
	add hl, de
	ld a, [hli]
	ld [wBuffer + wCemExX], a
	ld a, [hl]
	ld [wBuffer + wCemExY], a
	call PCemAlgoB      ; wobble to midpoint
	; Restore real exit and continue
	pop af
	ld [wBuffer + wCemExY], a
	pop af
	ld [wBuffer + wCemExX], a
	jp PCemAlgoB        ; wobble midpoint → real exit

PCemMidpointTable:
	db 4, 2  ; upper middle
	db 5, 6  ; lower middle
	db 2, 2  ; upper left inner
	db 7, 6  ; lower right inner

; ============================================================
; Algorithm D: Drunk walk — skips protected wall tiles.
; Saves position before each step attempt; restores if wall hit.
; Falls back to PCemStepToward after 8 failed attempts.
; ============================================================
PCemAlgoD:
.stepD
	call PCemCarveStep
	call PCemAtExit
	ret z
	ld b, 8            ; attempt budget
.tryDir
	; Save current position in (d,e) before attempting move
	ld a, [wBuffer + wCemTryX]
	ld d, a
	ld a, [wBuffer + wCemTryY]
	ld e, a
	; Roll direction 0-3
	push bc
	ld c, 4
	call Rangerandom
	and 3              ; a = direction 0-3; pop bc does not touch a
	pop bc             ; restore b=retry count
	; Attempt move — a still holds the direction from Rangerandom
	jr z, .dN
	cp 1
	jr z, .dS
	cp 2
	jr z, .dE
	; West
	ld a, d
	cp 3
	jr c, .dBadMove
	dec a
	ld [wBuffer + wCemTryX], a
	jp .stepD
.dN
	ld a, e
	cp 2
	jr c, .dBadMove
	dec a
	ld [wBuffer + wCemTryY], a
	jp .stepD
.dS
	ld a, e
	cp 7
	jr nc, .dBadMove
	inc a
	ld [wBuffer + wCemTryY], a
	jp .stepD
.dE
	ld a, d
	cp 8
	jr nc, .dBadMove
	inc a
	ld [wBuffer + wCemTryX], a
	jp .stepD          ; move committed — proceed
.dBadMove
	; Restore position and try again
	ld a, d
	ld [wBuffer + wCemTryX], a
	ld a, e
	ld [wBuffer + wCemTryY], a
	dec b
	jr nz, .tryDir
	; Budget exhausted — force step toward exit
	call PCemStepToward
	jp .stepD

; ============================================================
; PCemRollItem: rolls a random item for this map's pokeball.
; Stores in sProcCemetaryItem[mapIndex].
; ============================================================
PCemRollItem:
	ld c, 4
	call Rangerandom
	ld [wRogueDoorSelection], a
	farcall Random_Item_Selection   ; result in wRogueItem
	ld a, [wRogueItem]
	ld hl, sProcCemetaryItem
	ld b, a
	ld a, [wBuffer + wCemMapIndex]
	ld e, a
	ld d, 0
	add hl, de
	ld a, b
	ld [hl], a
	ret

; ============================================================
; PCemFinalizeMap
; Called when loading a PROCEDURAL_CEMETARY_N map.
; Blits 90-byte map from SRAM into wOverworldMap, patches pokeball
; sprite position, and loads item into wRogueItem.
; ============================================================
PCemFinalizeMap::
	; enable SRAM bank 0
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a

	; which map? 0-3 (not consecutive IDs, must use explicit lookup)
	call PCemMapToIndex
	ld [wBuffer + wCemMapIndex], a

	; Lazy generation: generate this floor now if its ready bit is not set.
	; Bit N of sProcCemetaryReady = floor N has been generated.
	; Spreads cost across floor entries instead of all at Pallet Town entry.
	; Compute mask = 1 << mapIndex using B as shift count (not bitwise AND).
	ld c, a                    ; c = mapIndex (0-3)
	ld b, 1                    ; b = mask, start at bit 0
	ld a, c
	and a                      ; test if mapIndex == 0 (sets Z if c==0)
	jr z, .cemGotMask
.cemShiftMask
	sla b                      ; b <<= 1
	dec c
	jr nz, .cemShiftMask
.cemGotMask                    ; b = (1 << mapIndex)
	ld a, [sProcCemetaryReady]
	and b
	jr nz, .cemAlreadyReady    ; bit set = already generated
	; generate this floor now
	call PCemGenerateOneMap
	; set ready bit (recompute mask — PCemGenerateOneMap may clobber b/c)
	ld a, [wBuffer + wCemMapIndex]
	ld c, a
	ld b, 1
	and c                      ; test if mapIndex == 0
	jr z, .cemSetBit
.cemSetShift
	sla b
	dec c
	jr nz, .cemSetShift
.cemSetBit
	ld a, [sProcCemetaryReady]
	or b
	ld [sProcCemetaryReady], a
.cemAlreadyReady

	; get SRAM source for this map
	call PCemGetMapBase
	; blit row by row (10 bytes/row, skip 6-byte border gap on dest)
	ld de, wOverworldMap + CEMAP_BASE
	ld b, CEMAP_HEIGHT
.blitRowLoop
	push bc
	ld c, CEMAP_WIDTH
.blitColLoop
	ld a, [hli]
	ld [de], a
	inc de
	dec c
	jr nz, .blitColLoop
	ld a, e
	add a, CEMAP_STRIDE - CEMAP_WIDTH
	ld e, a
	jr nc, .blitNoCarry
	inc d
.blitNoCarry
	pop bc
	dec b
	jr nz, .blitRowLoop

	; place staircase tiles (deterministic from map index, no SRAM needed)
	call PCemPlaceStaircases

	; load item into wRogueItem for pickup
	ld hl, sProcCemetaryItem
	ld a, [wBuffer + wCemMapIndex]
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	ld [wRogueItem], a

	; check if this floor's item was already collected; if so, will hide ball after blit
	ld a, [sProcCemetaryItemGot]
	ld b, a                    ; b = collected bitfield
	ld a, [wBuffer + wCemMapIndex]
	ld c, 1
.shiftBit
	and a
	jr z, .bitReady
	sla c
	dec a
	jr .shiftBit
.bitReady
	ld a, b
	and c                      ; Z if this floor's bit not set (item not yet collected)
	push af                    ; save Z flag for after SRAM close

	; close SRAM before patching WRAM sprite state
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a

	; re-enable SRAM to read ball position
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a

	ld hl, sProcCemetaryBallX
	ld a, [wBuffer + wCemMapIndex]
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	ld b, a             ; b = ball block X
	ld hl, sProcCemetaryBallY
	add hl, de
	ld a, [hl]
	ld c, a             ; c = ball block Y

	; close SRAM
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ld [rRAMG], a

	; patch pokeball sprite (slot 1 = wSprite01StateData2MapY)
	; formula: block * 2 + 4 (confirmed same origin offset as cave pokeballs)
	ld hl, wSprite01StateData2MapY
	ld a, c
	add a, a
	add a, 4
	ld [hli], a          ; MapY
	ld a, b
	add a, a
	add a, 4
	ld [hl], a           ; MapX

	; if item was already collected (Z was clear when saved), hide the pokeball now
	pop af
	ret z                ; Z = not collected, leave visible
	; item was collected — hide the pokeball sprite via toggle
	call PCemMapToIndex
	ld b, a
	ld hl, PCemToggleTable
	ld e, b
	ld d, 0
	add hl, de
	ld a, [hl]
	ld [wToggleableObjectIndex], a
	predef HideObject
	ret

PCemToggleTable:
	db TOGGLE_CEMETARY_1_POKEBALL
	db TOGGLE_CEMETARY_2_POKEBALL
	db TOGGLE_CEMETARY_3_POKEBALL
	db TOGGLE_CEMETARY_4_POKEBALL

; ============================================================
; IsCemetaryMap
; Returns Z clear if current map is one of the 4 cemetery maps.
; Preserves all registers except flags/a.
; ============================================================
IsCemetaryMap::
	ldh a, [hCurMap]
	cp PROCEDURAL_CEMETARY_1
	ret z
	cp PROCEDURAL_CEMETARY_2
	ret z
	cp PROCEDURAL_CEMETARY_3
	ret z
	cp PROCEDURAL_CEMETARY_4
	ret z
	; not cemetery - set Z=0 by comparing unequal values
	; (a already = hCurMap which != PROCEDURAL_CEMETARY_4 from above, so Z is already clear)
	ret
