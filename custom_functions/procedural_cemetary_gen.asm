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
DEF wCemMapIndex   EQU 0  ; 0-3, which of the 4 maps is currently being generated
DEF wCemTryX       EQU 1
DEF wCemTryY       EQU 2

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
; Generates all 4 cemetery maps into SRAM. Called (via homecall)
; on Pallet Town entry, same pattern as PCPreloadCave.
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

	xor a
	ld [wBuffer + wCemMapIndex], a
.mapLoop
	call PCemGenerateOneMap
	ld a, [wBuffer + wCemMapIndex]
	inc a
	ld [wBuffer + wCemMapIndex], a
	cp 4
	jr nz, .mapLoop

	; close SRAM
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ret

; ============================================================
; PCemGenerateOneMap
; Generates one 90-byte map. SRAM must be enabled.
; ============================================================
PCemGenerateOneMap:
	; 25% premade, 75% procedural
	ld c, 4
	call Rangerandom    ; returns 0-3 in a, clobbers hl
	and a
	jr nz, .procedural
	call PCemCopyPremadeTemplate
	jr .placeBall
.procedural
	call PCemCopyBaseTemplate
	; Scatter tombstones then clear any that break connectivity.
	; If the base template itself has no path (shouldn't happen for
	; Tower floors but possible for custom templates), skip scatter.
	call PCemCheckConnected    ; carry SET = entrance→exit connected
	jr nc, .skipScatter       ; carry CLEAR = base not connected, skip scatter
	call PCemScatterTombstones
	call PCemClearBlockingTombstones
	jr .placeBall
.skipScatter
	; base template has no path - leave it unmodified
.placeBall
	call PCemPlaceBall
	call PCemRollItem
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
; PCemPlaceBall
; Finds a floor cell for the pokeball. Saves X,Y to sProcCemetaryBallX/Y.
; ============================================================
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
	; left entry: entrance=(1,4), exit=(8,4)
	ld d, 1                  ; entrance col
	ld e, 4                  ; entrance row
	ld b, 8                  ; exit col
	ld c, 4                  ; exit row
	jr .gotEntranceExit
.rightEntry
	ld d, 8                  ; entrance col
	ld e, 4                  ; entrance row
	; map 3 exits south, others exit left
	ld a, [wBuffer + wCemMapIndex]
	cp 3
	jr z, .southExit
	ld b, 1                  ; exit col
	ld c, 4                  ; exit row
	jr .gotEntranceExit
.southExit
	ld b, 4                  ; exit col
	ld c, 8                  ; exit row
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

PCemPlaceBall:
	ld b, 100
.loop
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
	jr nz, .notFloor
	; found floor - write position
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
.notFloor
	dec b
	jr nz, .loop
	; fallback: use col 5, row 4 (center-ish)
	ld hl, sProcCemetaryBallX
	ld a, [wBuffer + wCemMapIndex]
	ld e, a
	ld d, 0
	add hl, de
	ld a, 5
	ld [hl], a
	ld hl, sProcCemetaryBallY
	add hl, de
	ld a, 4
	ld [hl], a
	ret

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

	; load item into wRogueItem for pickup
	ld hl, sProcCemetaryItem
	ld a, [wBuffer + wCemMapIndex]
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	ld [wRogueItem], a

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
	ret

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
