; custom_functions/procedural_forest_gen.asm
;
; Procedural forest maze generator for PROCEDURAL_FOREST ($F2).
;
; SRAM: uses sProcForestStagingBuffer (dedicated 400-byte buffer, separate
; from cave's sProcCaveStagingBuffer). sProcForestBaked controls fast re-entry.
;
; Map layout: identical to cave — 20x20 blocks with MAP_BORDER=3 border pad.
;   wOverworldMap + PC_BASE + x + y*PC_STRIDE (PC_BASE=81, PC_STRIDE=26)
;
; Maze cell grid: 9x9 cells. Cell (i,j) → block (2i+1, 2j+1).
; Wall between adjacent cells = block halfway between them.
; Top-row exit: block 88 at logical (2*exitI+1, 0), warp fires at that block.
; Entrance: cell (4,8) = block (9,17) = static warp_event tile (19,34).
;
; Algorithm: Sidewinder (guaranteed connectivity by construction, ~5-10 frames).
; Generation happens lazily at warp-in if not yet baked.
; PFPreloadForest (called at Pallet Town entry) resets bake flag for fresh run.

SECTION "ProceduralForestGen", ROMX

DEF PF_SIZE    EQU 20
DEF PF_STRIDE  EQU 26
DEF PF_BASE    EQU 81

DEF PF_CELL_W  EQU 9
DEF PF_CELL_H  EQU 9

DEF PF_TREE    EQU 2   ; base tree block
DEF PF_EXIT_N  EQU 88  ; north-edge exit block (FOREST tileset, recognized warp)

; Item placement (PFScanForBall) — mirrors cave's PCPlaceWildAreaItems spacing
; and dedup logic, adapted to the maze's sparse dead-end cells instead of
; cave's dense floor-block scan.
DEF PF_ITEM_MIN_DIST EQU 2   ; min Chebyshev distance (CELL units) between balls
DEF PF_MAX_DEADENDS  EQU 32  ; candidate list cap — fits in sProcForestGenScratch

; wBuffer scratch offsets (18 bytes; safe — forest never runs concurrently with
; cave/cemetery gen which also uses wBuffer)
DEF wPFTargetBaseLo EQU 0
DEF wPFTargetBaseHi EQU 1
DEF wPFCurX         EQU 2   ; block-space X for PFWriteBlock/PFReadBlock
DEF wPFCurY         EQU 3   ; block-space Y
DEF wPFRowJ         EQU 4   ; Sidewinder: outer row counter (0-8)
DEF wPFRunStart     EQU 5   ; Sidewinder: current run start col
DEF wPFCellI        EQU 6   ; BinaryTree: cell index 0-80
DEF wPFStackPtr     EQU 7   ; Backtracker: stack pointer into wOverworldMap[0..80]
DEF wPFCellCol      EQU 8   ; Backtracker/HuntAndKill: current cell col (0-8)
DEF wPFCellRow      EQU 9   ; Backtracker/HuntAndKill: current cell row (0-8)
DEF wPFNeighborCnt  EQU 10  ; Backtracker/HuntAndKill: count of unvisited neighbors
DEF wPFNeighbors    EQU 11  ; 4 bytes: packed neighbor list (col | row<<4)
DEF wPFNCol         EQU 15  ; chosen neighbor col
DEF wPFNRow         EQU 16  ; chosen neighbor row
DEF wPFAlgoForce    EQU 17  ; saved from sProcForestAlgoForce (read while SRAM open)
DEF wPFPassCount    EQU 18  ; braid pass: passage count for current cell
DEF wPFBraidCol     EQU 19  ; braid pass: column counter (0-8)
DEF wPFBallIdx      EQU 20  ; PFScanForBall Phase 2: current ball index (0-3)
; PFScanForBall Phase 2 scratch — all alias offsets confirmed UNTOUCHED by
; PFScanWallPassOnly during Phase 1's per-cell scan (verified: that function
; only reads/writes wPFCellCol/Row, wPFCurX/Y, wPFPassCount), so reusing them
; here is safe with no risk of Phase-1/Phase-2 collision within a single call.
DEF wPFCandCount    EQU 5   ; reuses wPFRunStart (Sidewinder-only, dead by now)
DEF wPFSpaceRetry   EQU 6   ; reuses wPFCellI (BinaryTree-only)
DEF wPFItemRetry    EQU 7   ; reuses wPFStackPtr (Backtracker-only)
DEF wPFAcceptedXY   EQU 10  ; 8 contiguous bytes (10-17): 4x(blockX,blockY) for
                            ; balls accepted so far, reuses wPFNeighborCnt/
                            ; Neighbors/NCol/NRow/AlgoForce (all dead by Phase 2)
DEF wPFItemTemp     EQU 21  ; 4 bytes (21-24): rolled item IDs before dedup-write

; ============================================================
; PFRowOffsetTable
; Byte offset for each row in the 20-row logical map space.
; Duplicated from PCRowOffsetTable — cross-bank call is a known
; silent landmine (see cross_bank_calls project note).
; ============================================================
PFRowOffsetTable:
    FOR pf_row, PF_SIZE
    dw pf_row * PF_STRIDE
    ENDR

; ============================================================
; PFWriteBlock
; INPUT: a = block ID; [wBuffer+wPFCurX/Y] = logical coords (0-19)
; Writes block a to the forest staging target (SRAM or wOverworldMap).
; ============================================================
PFWriteBlock:
    push af
    push bc         ; preserve B (Sidewinder uses B as column loop counter)
    ld a, [wBuffer + wPFTargetBaseLo]
    ld l, a
    ld a, [wBuffer + wPFTargetBaseHi]
    ld h, a
    push hl
    ld a, [wBuffer + wPFCurY]
    add a, a
    ld c, a
    ld b, 0
    ld hl, PFRowOffsetTable
    add hl, bc
    ld a, [hli]
    ld e, a
    ld a, [hl]
    ld d, a
    pop hl
    add hl, de
    ld a, [wBuffer + wPFCurX]
    add a, l
    ld l, a
    jr nc, .noCarry
    inc h
.noCarry
    pop bc          ; push order was af,bc,hl — pop hl above, then bc, then af
    pop af          ; A = original block ID
    ld [hl], a
    ret

; ============================================================
; PFReadBlock
; INPUT: [wBuffer+wPFCurX/Y] = logical coords. OUTPUT: a = block value.
; Preserves BC.
; ============================================================
PFReadBlock:
    push bc
    ld a, [wBuffer + wPFTargetBaseLo]
    ld l, a
    ld a, [wBuffer + wPFTargetBaseHi]
    ld h, a
    push hl
    ld a, [wBuffer + wPFCurY]
    add a, a
    ld c, a
    ld b, 0
    ld hl, PFRowOffsetTable
    add hl, bc
    ld a, [hli]
    ld e, a
    ld a, [hl]
    ld d, a
    pop hl
    add hl, de
    ld a, [wBuffer + wPFCurX]
    add a, l
    ld l, a
    jr nc, .noCarry
    inc h
.noCarry
    ld a, [hl]
    pop bc
    ret

; ============================================================
; PFPickFloor
; OUTPUT: a = random floor block: 75% chance of tile 1 (path/grass base),
; 25% chance of a random pick from PFFloorAltTable (visual variety tiles).
; ============================================================
PFPickFloor:
    ld c, 4
    call Rangerandom        ; a = 0..3
    and a
    jr nz, .floor1          ; 3/4 (75%): plain floor
    ld c, PFFloorAltCount
    call Rangerandom        ; a = 0..PFFloorAltCount-1
    ld hl, PFFloorAltTable
    ld e, a
    ld d, 0
    add hl, de
    ld a, [hl]
    ret
.floor1
    ld a, 1
    ret

PFFloorAltTable:
    db 41, 27, $20, $22, $23, $24, $25
DEF PFFloorAltCount EQU 7

; ============================================================
; PFSidewinder
; Carves a perfect maze into the staging buffer using the Sidewinder
; algorithm over the 9x9 cell grid.
;
; Top row (j=0): all cells carved, all east walls carved → full corridor.
; Other rows (j=1..8): for each cell, 50% extend east OR close run.
;   Close run: pick random k in [run_start..i], carve north wall above k.
;
; Every cell (i,j) gets floor at block (2i+1, 2j+1).
; East walls carved at block (2i+2, 2j+1).
; North walls carved at block (2k+1, 2j).
; ============================================================
PFSidewinder:
    xor a
    ld [wBuffer + wPFRowJ], a       ; j = 0

.rowLoop
    xor a
    ld [wBuffer + wPFRunStart], a   ; run_start = 0
    ld b, 0                         ; b = i (column counter)

.colLoop
    ; --- Carve cell (i, j): floor at block (2i+1, 2j+1) ---
    ld a, b                         ; i
    add a, a                        ; 2i
    inc a                           ; 2i+1
    ld [wBuffer + wPFCurX], a
    ld a, [wBuffer + wPFRowJ]       ; j
    add a, a                        ; 2j
    inc a                           ; 2j+1
    ld [wBuffer + wPFCurY], a
    call PFPickFloor
    call PFWriteBlock

    ; --- Decide: extend east or close run? ---
    ld a, [wBuffer + wPFRowJ]
    and a
    jr z, .topRowCol                ; j == 0: always extend east

    ; j > 0: force close on last col, else 50% coin flip
    ld a, b
    cp PF_CELL_W - 1                ; i == 8?
    jr z, .closeRun
    call Random                     ; 0-255
    and $01                         ; bit 0: 0=close, 1=extend
    jr z, .closeRun

.extendEast
    ; Carve east wall between (i,j) and (i+1,j): block at (2i+2, 2j+1)
    ld a, b                         ; i
    add a, a                        ; 2i
    add a, 2                        ; 2i+2
    ld [wBuffer + wPFCurX], a
    ; wPFCurY already holds 2j+1
    call PFPickFloor
    call PFWriteBlock
    jr .nextCol

.topRowCol
    ; Top row: always extend east (until last column)
    ld a, b
    cp PF_CELL_W - 1
    jr z, .nextCol
    ld a, b
    add a, a
    add a, 2                        ; 2i+2
    ld [wBuffer + wPFCurX], a
    ; wPFCurY already holds 2*0+1 = 1
    call PFPickFloor
    call PFWriteBlock
    jr .nextCol

.closeRun
    ; k = run_start + Rangerandom(i - run_start + 1)
    ; range = i - run_start + 1
    ld a, [wBuffer + wPFRunStart]   ; a = run_start
    ld d, a                         ; d = run_start (may be clobbered by Rangerandom's Multiply)
    ld a, b                         ; a = i (B preserved across Rangerandom via push bc)
    sub d                           ; a = i - run_start
    inc a                           ; a = range
    ld c, a                         ; c = range (Rangerandom input)
    call Rangerandom                ; a = 0..range-1; BC restored (push bc/pop bc)
    ; After call: b = i (restored), a = random offset, d = POSSIBLY CLOBBERED
    ld e, a                         ; e = random offset
    ld a, [wBuffer + wPFRunStart]   ; re-read run_start (d may be stale)
    add a, e                        ; k = run_start + offset
    ; Carve north wall at (k, j): block (2k+1, 2j)
    add a, a                        ; 2k
    inc a                           ; 2k+1
    ld [wBuffer + wPFCurX], a
    ld a, [wBuffer + wPFRowJ]       ; j
    add a, a                        ; 2j (wall is BETWEEN cell j and cell j-1)
    ld [wBuffer + wPFCurY], a
    call PFPickFloor
    call PFWriteBlock
    ; run_start = i + 1
    ld a, b                         ; b = i (preserved by Rangerandom)
    inc a
    ld [wBuffer + wPFRunStart], a

.nextCol
    inc b                           ; i++
    ld a, b
    cp PF_CELL_W                    ; done all 9 cols?
    jr nz, .colLoop

    ld a, [wBuffer + wPFRowJ]
    inc a                           ; j++
    ld [wBuffer + wPFRowJ], a
    cp PF_CELL_H
    jp nz, .rowLoop

    ret


; ============================================================
; PFBinaryTree
; For each cell (col,row) in row-major order: carve cell, then randomly
; carve North wall (if row>0) OR East wall (if col<8). Top row always
; East-only; right column always North-only. Guarantees connectivity.
; ============================================================
PFBinaryTree:
    xor a
    ld [wBuffer + wPFCellI], a

.btCellLoop
    ld a, [wBuffer + wPFCellI]
    cp 81
    jp nc, .btDone

    ; Divide cell index by 9: col = i%9, row = i/9
    ld b, a
    ld c, 0
.btDiv
    sub 9
    jr c, .btDivDone
    inc c
    jr .btDiv
.btDivDone
    ; BUG FIX: the loop does `sub 9` THEN checks carry, so on the final
    ; (carrying) iteration it over-subtracts by 9 — a holds remainder-9
    ; (wrapped), NOT the remainder. Add 9 back to recover col = i%9.
    ; Without this, cell 0 gave col=$F7 (247), scattering floor writes to
    ; garbage map cells → BinaryTree crash / "items in odd spaces".
    ; c (quotient/row) is correct as-is (inc c is skipped on the carrying pass).
    add a, 9
    ; a = col (i%9), c = row (i/9)
    ld d, a     ; d = col
    ld e, c     ; e = row

    ; Carve cell at block (2*col+1, 2*row+1)
    ld a, d
    add a, a
    inc a
    ld [wBuffer + wPFCurX], a
    ld a, e
    add a, a
    inc a
    ld [wBuffer + wPFCurY], a
    call PFPickFloor
    call PFWriteBlock   ; D,E clobbered — reload after

    ld a, [wBuffer + wPFCellI]
    ld b, a
    ld c, 0
.btDiv2
    sub 9
    jr c, .btDiv2Done
    inc c
    jr .btDiv2
.btDiv2Done
    add a, 9    ; same over-subtraction fix as .btDivDone above (recover i%9)
    ld d, a     ; d = col
    ld e, c     ; e = row

    ; Determine which walls we can carve
    ld a, e
    and a           ; row == 0?
    jr z, .btOnlyEast
    ld a, d
    cp 8            ; col == 8?
    jr z, .btOnlyNorth
    ; Both possible: flip coin
    call Random
    and 1
    jr z, .btDoNorth

.btDoEast
    ; East wall at (2*col+2, 2*row+1)
    ld a, d
    add a, a
    add a, 2
    ld [wBuffer + wPFCurX], a
    ld a, e
    add a, a
    inc a
    ld [wBuffer + wPFCurY], a
    call PFPickFloor
    call PFWriteBlock
    jr .btNext

.btOnlyNorth
.btDoNorth
    ; North wall at (2*col+1, 2*row)
    ld a, d
    add a, a
    inc a
    ld [wBuffer + wPFCurX], a
    ld a, e
    add a, a
    ld [wBuffer + wPFCurY], a
    call PFPickFloor
    call PFWriteBlock
    jr .btNext

.btOnlyEast
    ld a, d
    cp 8
    jr z, .btNext   ; top-right corner: no wall to carve
    ld a, d
    add a, a
    add a, 2
    ld [wBuffer + wPFCurX], a
    ld a, 1         ; row=0 → 2*0+1=1
    ld [wBuffer + wPFCurY], a
    call PFPickFloor
    call PFWriteBlock

.btNext
    ld a, [wBuffer + wPFCellI]
    inc a
    ld [wBuffer + wPFCellI], a
    jp .btCellLoop

.btDone
    ret

; ============================================================
; PFCheckUnvisited
; INPUT: B=neighbor row (0-8), C=neighbor col (0-8).
; If cell (C,B) is unvisited (still PF_TREE), appends packed (C|B<<4)
; to wBuffer+wPFNeighbors list and increments wPFNeighborCnt.
; Preserves B, C.
; ============================================================
PFCheckUnvisited:
    ; Set block coords: (2*C+1, 2*B+1)
    ld a, c
    add a, a
    inc a
    ld [wBuffer + wPFCurX], a
    ld a, b
    add a, a
    inc a
    ld [wBuffer + wPFCurY], a
    call PFReadBlock        ; A = block; BC preserved
    cp PF_TREE
    ret nz                  ; already visited
    ; Append packed neighbor: C | (B<<4)
    ld a, [wBuffer + wPFNeighborCnt]
    ld e, a
    inc a
    ld [wBuffer + wPFNeighborCnt], a
    ld a, b
    swap a              ; B (row) into high nibble
    or c                ; OR with col (low nibble)
    ld d, 0
    ld hl, wBuffer + wPFNeighbors
    add hl, de
    ld [hl], a
    ret

; ============================================================
; PFCarveToNeighbor
; Pick random entry from wPFNeighbors list, carve the wall between
; current cell (wPFCellCol/Row) and neighbor, carve neighbor cell.
; Updates wPFCellCol/Row to the neighbor.
; Requires: wPFNeighborCnt > 0.
; ============================================================
PFCarveToNeighbor:
    ld a, [wBuffer + wPFNeighborCnt]
    ld c, a
    call Rangerandom        ; a = 0..count-1
    ld e, a
    ld d, 0
    ld hl, wBuffer + wPFNeighbors
    add hl, de
    ld a, [hl]              ; packed neighbor
    ld b, a
    and $0F
    ld [wBuffer + wPFNCol], a
    ld a, b
    swap a
    and $0F
    ld [wBuffer + wPFNRow], a

    ; Carve wall block: coords = (curCol+nCol+1, curRow+nRow+1)
    ld a, [wBuffer + wPFCellCol]
    ld b, a
    ld a, [wBuffer + wPFNCol]
    add a, b
    inc a
    ld [wBuffer + wPFCurX], a
    ld a, [wBuffer + wPFCellRow]
    ld b, a
    ld a, [wBuffer + wPFNRow]
    add a, b
    inc a
    ld [wBuffer + wPFCurY], a
    call PFPickFloor
    call PFWriteBlock

    ; Carve neighbor cell: (2*nCol+1, 2*nRow+1)
    ld a, [wBuffer + wPFNCol]
    add a, a
    inc a
    ld [wBuffer + wPFCurX], a
    ld a, [wBuffer + wPFNRow]
    add a, a
    inc a
    ld [wBuffer + wPFCurY], a
    call PFPickFloor
    call PFWriteBlock

    ; Advance current cell
    ld a, [wBuffer + wPFNCol]
    ld [wBuffer + wPFCellCol], a
    ld a, [wBuffer + wPFNRow]
    ld [wBuffer + wPFCellRow], a
    ret

; ============================================================
; PFBacktracker
; Iterative recursive backtracker. Stack at sProcForestGenScratch (SRAM —
; NEVER wOverworldMap; that's the live map's border padding and corrupting it
; caused trainer-! on pokeballs and hardware/emulator crashes). SRAM must
; already be open (RAMG_SRAM_ENABLE, bank 0) when this is called.
; Each stack entry: packed (col | row<<4). Visited = block != PF_TREE.
; ============================================================
PFBacktracker:
    ; Push entrance cell (col=4, row=8) → packed 0x84
    xor a
    ld [wBuffer + wPFStackPtr], a
    ld a, (4 | (8 << 4))
    ld hl, sProcForestGenScratch
    ld [hl], a
    ld a, 1
    ld [wBuffer + wPFStackPtr], a

    ; Carve entrance cell at block (9, 17)
    ld a, 9
    ld [wBuffer + wPFCurX], a
    ld a, 17
    ld [wBuffer + wPFCurY], a
    call PFPickFloor
    call PFWriteBlock

.bkLoop
    ld a, [wBuffer + wPFStackPtr]
    and a
    ret z

    ; Peek top: sProcForestGenScratch[sp-1]
    dec a
    ld e, a
    ld d, 0
    ld hl, sProcForestGenScratch
    add hl, de
    ld a, [hl]
    ld b, a
    and $0F
    ld [wBuffer + wPFCellCol], a
    ld a, b
    swap a
    and $0F
    ld [wBuffer + wPFCellRow], a

    ; Find unvisited neighbors
    xor a
    ld [wBuffer + wPFNeighborCnt], a
    ld a, [wBuffer + wPFCellRow]
    ld b, a
    ld a, [wBuffer + wPFCellCol]
    ld c, a

    ld a, b
    and a
    jr z, .bkSkipN
    dec b
    call PFCheckUnvisited
    inc b
.bkSkipN
    ld a, b
    cp 8
    jr nc, .bkSkipS
    inc b
    call PFCheckUnvisited
    dec b
.bkSkipS
    ld a, c
    and a
    jr z, .bkSkipW
    dec c
    call PFCheckUnvisited
    inc c
.bkSkipW
    ld a, c
    cp 8
    jr nc, .bkSkipE
    inc c
    call PFCheckUnvisited
    dec c
.bkSkipE

    ld a, [wBuffer + wPFNeighborCnt]
    and a
    jr z, .bkPop

    ; Carve to random neighbor (updates wPFCellCol/Row)
    call PFCarveToNeighbor

    ; Push new cell to stack
    ld a, [wBuffer + wPFStackPtr]
    ld e, a
    ld d, 0
    ld hl, sProcForestGenScratch
    add hl, de
    ld a, [wBuffer + wPFCellRow]
    swap a
    ld b, a
    ld a, [wBuffer + wPFCellCol]
    or b
    ld [hl], a
    ld a, [wBuffer + wPFStackPtr]
    inc a
    ld [wBuffer + wPFStackPtr], a
    jp .bkLoop

.bkPop
    ld a, [wBuffer + wPFStackPtr]
    dec a
    ld [wBuffer + wPFStackPtr], a
    jp .bkLoop

; ============================================================
; PFHuntAndKill
; Walk randomly from entrance, carving unvisited neighbors.
; When stuck: scan all cells for a visited cell that has at least
; one unvisited neighbor, connect to it, resume walk.
; No stack needed. Visited = block != PF_TREE.
; ============================================================
PFHuntAndKill:
    ld a, 4
    ld [wBuffer + wPFCellCol], a
    ld a, 8
    ld [wBuffer + wPFCellRow], a
    ld a, 9
    ld [wBuffer + wPFCurX], a
    ld a, 17
    ld [wBuffer + wPFCurY], a
    call PFPickFloor
    call PFWriteBlock

.hkWalk
    xor a
    ld [wBuffer + wPFNeighborCnt], a
    ld a, [wBuffer + wPFCellRow]
    ld b, a
    ld a, [wBuffer + wPFCellCol]
    ld c, a
    ld a, b
    and a
    jr z, .hkSkipN
    dec b
    call PFCheckUnvisited
    inc b
.hkSkipN
    ld a, b
    cp 8
    jr nc, .hkSkipS
    inc b
    call PFCheckUnvisited
    dec b
.hkSkipS
    ld a, c
    and a
    jr z, .hkSkipW
    dec c
    call PFCheckUnvisited
    inc c
.hkSkipW
    ld a, c
    cp 8
    jr nc, .hkSkipE
    inc c
    call PFCheckUnvisited
    dec c
.hkSkipE
    ld a, [wBuffer + wPFNeighborCnt]
    and a
    jr z, .hkHunt
    call PFCarveToNeighbor
    jp .hkWalk

.hkHunt
    ; Scan row=0..8, col=0..8 for visited cell with unvisited neighbor
    xor a
    ld [wBuffer + wPFCellRow], a
.hkHuntRow
    xor a
    ld [wBuffer + wPFCellCol], a
.hkHuntCol
    ; Check if visited
    ld a, [wBuffer + wPFCellCol]
    add a, a
    inc a
    ld [wBuffer + wPFCurX], a
    ld a, [wBuffer + wPFCellRow]
    add a, a
    inc a
    ld [wBuffer + wPFCurY], a
    call PFReadBlock
    cp PF_TREE
    jr z, .hkHuntNext   ; unvisited: skip

    ; Check its neighbors
    xor a
    ld [wBuffer + wPFNeighborCnt], a
    ld a, [wBuffer + wPFCellRow]
    ld b, a
    ld a, [wBuffer + wPFCellCol]
    ld c, a
    ld a, b
    and a
    jr z, .hkHSkipN
    dec b
    call PFCheckUnvisited
    inc b
.hkHSkipN
    ld a, b
    cp 8
    jr nc, .hkHSkipS
    inc b
    call PFCheckUnvisited
    dec b
.hkHSkipS
    ld a, c
    and a
    jr z, .hkHSkipW
    dec c
    call PFCheckUnvisited
    inc c
.hkHSkipW
    ld a, c
    cp 8
    jr nc, .hkHSkipE
    inc c
    call PFCheckUnvisited
    dec c
.hkHSkipE
    ld a, [wBuffer + wPFNeighborCnt]
    and a
    jr nz, .hkHuntFound

.hkHuntNext
    ld a, [wBuffer + wPFCellCol]
    inc a
    ld [wBuffer + wPFCellCol], a
    cp 9
    jr c, .hkHuntCol
    ld a, [wBuffer + wPFCellRow]
    inc a
    ld [wBuffer + wPFCellRow], a
    cp 9
    jr c, .hkHuntRow
    ret                     ; all done

.hkHuntFound
    call PFCarveToNeighbor
    jp .hkWalk

; ============================================================
; PFScanWall
; INPUT: B=neighbor row (0-8), C=neighbor col (0-8).
;        wPFCellCol/Row = current cell.
; If the wall between current cell and (C,B) is PF_TREE:
;   appends packed (C | B<<4) to wPFNeighbors, increments wPFNeighborCnt.
; If the wall is a passage (not PF_TREE):
;   increments wPFPassCount.
; Preserves B, C.
; ============================================================
PFScanWall:
    push bc
    ; wall coords = (curCol + nCol + 1, curRow + nRow + 1)
    ld a, [wBuffer + wPFCellCol]
    add a, c
    inc a
    ld [wBuffer + wPFCurX], a
    ld a, [wBuffer + wPFCellRow]
    add a, b
    inc a
    ld [wBuffer + wPFCurY], a
    call PFReadBlock        ; A = wall block; BC restored via push/pop bc
    pop bc                  ; B=nRow, C=nCol restored
    cp PF_TREE
    jr z, .treeWall
    ; Passage exists — count it
    ld a, [wBuffer + wPFPassCount]
    inc a
    ld [wBuffer + wPFPassCount], a
    ret
.treeWall
    ; No passage — braidable neighbor, add to list
    ld a, b
    swap a                  ; row → high nibble
    or c                    ; | col → packed = col | (row<<4)
    push af                 ; stash packed value - d/e below need to hold the
                             ; neighbor COUNT (the array index), not this value
    ld a, [wBuffer + wPFNeighborCnt]
    ld e, a
    ld d, 0
    ld hl, wBuffer + wPFNeighbors
    add hl, de
    pop af
    ld [hl], a
    ld a, [wBuffer + wPFNeighborCnt]
    inc a
    ld [wBuffer + wPFNeighborCnt], a
    ret

; ============================================================
; PFScanWallPassOnly
; Lightweight variant of PFScanWall: only counts passages (does NOT
; populate the braidable-neighbor list). Used by PFScanForBall.
; INPUT: B=neighbor row (0-8), C=neighbor col (0-8).
;        wPFCellCol/Row = current cell.
; Preserves B, C.
; ============================================================
PFScanWallPassOnly:
    push bc
    ld a, [wBuffer + wPFCellCol]
    add a, c
    inc a
    ld [wBuffer + wPFCurX], a
    ld a, [wBuffer + wPFCellRow]
    add a, b
    inc a
    ld [wBuffer + wPFCurY], a
    call PFReadBlock
    pop bc
    cp PF_TREE
    ret z                   ; tree wall = no passage
    ld a, [wBuffer + wPFPassCount]
    inc a
    ld [wBuffer + wPFPassCount], a
    ret

; ============================================================
; PFScanCellWalls
; Shared helper: scans all 4 walls of cell (wPFBraidCol, wPFRowJ),
; sets wPFCellCol/Row, resets wPFPassCount and wPFNeighborCnt,
; and calls PFScanWall for each direction.
; After return: wPFPassCount = passage count, wPFNeighborCnt/wPFNeighbors
; = braidable tree-wall neighbors.
; ============================================================
PFScanCellWalls:
    ld a, [wBuffer + wPFBraidCol]
    ld [wBuffer + wPFCellCol], a
    ld a, [wBuffer + wPFRowJ]
    ld [wBuffer + wPFCellRow], a
    xor a
    ld [wBuffer + wPFNeighborCnt], a
    ld [wBuffer + wPFPassCount], a
    ; North (j > 0): B=j-1, C=i
    ld a, [wBuffer + wPFRowJ]
    and a
    jr z, .scwNoN
    dec a
    ld b, a
    ld a, [wBuffer + wPFBraidCol]
    ld c, a
    call PFScanWall
.scwNoN
    ; South (j < 8): B=j+1, C=i
    ld a, [wBuffer + wPFRowJ]
    cp 8
    jr nc, .scwNoS
    inc a
    ld b, a
    ld a, [wBuffer + wPFBraidCol]
    ld c, a
    call PFScanWall
.scwNoS
    ; West (i > 0): B=j, C=i-1
    ld a, [wBuffer + wPFBraidCol]
    and a
    jr z, .scwNoW
    ld a, [wBuffer + wPFRowJ]
    ld b, a
    ld a, [wBuffer + wPFBraidCol]
    dec a
    ld c, a
    call PFScanWall
.scwNoW
    ; East (i < 8): B=j, C=i+1
    ld a, [wBuffer + wPFBraidCol]
    cp 8
    jr nc, .scwNoE
    ld a, [wBuffer + wPFRowJ]
    ld b, a
    ld a, [wBuffer + wPFBraidCol]
    inc a
    ld c, a
    call PFScanWall
.scwNoE
    ret

; ============================================================
; PFBraidPass
; Post-maze pass: carve extra passages through dead-end cells to
; create loops (hybrid braid). Dead end = exactly 1 passage.
; Braid rate controlled by the cp value (38 = ~15%, 0 = 100%).
; ============================================================
PFBraidPass:
    xor a
    ld [wBuffer + wPFRowJ], a

.bpRowLoop
    xor a
    ld [wBuffer + wPFBraidCol], a

.bpColLoop
    call PFScanCellWalls            ; sets pass/neighbor counts for this cell

    ld a, [wBuffer + wPFPassCount]
    cp 1
    jr nz, .bpNext
    ld a, [wBuffer + wPFNeighborCnt]
    and a
    jr z, .bpNext

    ; 100% braid rate for testing — restore "call Random / cp 38 / jr nc, .bpNext" for live 15%
    call PFCarveToNeighbor
    ; Restore wPFCellCol/Row (PFCarveToNeighbor advances them)
    ld a, [wBuffer + wPFBraidCol]
    ld [wBuffer + wPFCellCol], a
    ld a, [wBuffer + wPFRowJ]
    ld [wBuffer + wPFCellRow], a

.bpNext
    ld a, [wBuffer + wPFBraidCol]
    inc a
    ld [wBuffer + wPFBraidCol], a
    cp PF_CELL_W
    jp nz, .bpColLoop

    ld a, [wBuffer + wPFRowJ]
    inc a
    ld [wBuffer + wPFRowJ], a
    cp PF_CELL_H
    jp nz, .bpRowLoop
    ret

; ============================================================
; PFAbs
; Duplicate of cave's PCAbs (custom_functions/procedural_cave_gen.asm) —
; too tiny to justify a farcall. INPUT/OUTPUT: a = |a| (signed byte).
; ============================================================
PFAbs:
    bit 7, a
    ret z
    cpl
    inc a
    ret

; ============================================================
; PFScanForBall
; Places 4 pokeballs in distinct, well-spaced dead-end cells, mirroring
; cave's PCPlaceWildAreaItems (spacing + item-dedup with bounded retry).
; Adapted to the maze's sparse dead-end cells instead of cave's dense
; floor-block scan:
;   Phase 1: scan all 81 cells, collect up to PF_MAX_DEADENDS dead-end
;            (exactly 1 passage) cell coords into sProcForestGenScratch.
;   Phase 2: pick 4 candidates from that list, retrying (bounded budget)
;            on spacing failure (Chebyshev < PF_ITEM_MIN_DIST in CELL
;            units) or exact item-ID duplicate, exactly as cave does.
; Final ball block coords are copied to sProcForestGenScratch[0..7]
; (Y,X... no — X,Y interleaved, matching the bake step's existing read)
; so they SURVIVE the PFBraidPass call that follows (which never touches
; sProcForestGenScratch), and rolled items are written to wRogueItem/2/3/4.
; Must be called BEFORE PFBraidPass (braid removes dead ends, shrinking
; the candidate pool available here).
; ============================================================
PFScanForBall:
    ; --- Phase 1: collect dead-end candidates ---
    xor a
    ld [wBuffer + wPFCandCount], a
    ld [wBuffer + wPFRowJ], a

.sfbRow
    xor a
    ld [wBuffer + wPFBraidCol], a

.sfbCol
    ld a, [wBuffer + wPFBraidCol]
    ld [wBuffer + wPFCellCol], a
    ld a, [wBuffer + wPFRowJ]
    ld [wBuffer + wPFCellRow], a
    xor a
    ld [wBuffer + wPFPassCount], a

    ; Scan N/S/W/E passage counts (PFScanWallPassOnly only touches
    ; wPFCellCol/Row, wPFCurX/Y, wPFPassCount — confirmed safe alongside
    ; the wPFCandCount/SpaceRetry/ItemRetry/AcceptedXY aliases below)
    ld a, [wBuffer + wPFRowJ]
    and a
    jr z, .sfbNoN
    dec a
    ld b, a
    ld a, [wBuffer + wPFBraidCol]
    ld c, a
    call PFScanWallPassOnly
.sfbNoN
    ld a, [wBuffer + wPFRowJ]
    cp 8
    jr nc, .sfbNoS
    inc a
    ld b, a
    ld a, [wBuffer + wPFBraidCol]
    ld c, a
    call PFScanWallPassOnly
.sfbNoS
    ld a, [wBuffer + wPFBraidCol]
    and a
    jr z, .sfbNoW
    ld a, [wBuffer + wPFRowJ]
    ld b, a
    ld a, [wBuffer + wPFBraidCol]
    dec a
    ld c, a
    call PFScanWallPassOnly
.sfbNoW
    ld a, [wBuffer + wPFBraidCol]
    cp 8
    jr nc, .sfbNoE
    ld a, [wBuffer + wPFRowJ]
    ld b, a
    ld a, [wBuffer + wPFBraidCol]
    inc a
    ld c, a
    call PFScanWallPassOnly
.sfbNoE

    ld a, [wBuffer + wPFPassCount]
    cp 1
    jr nz, .sfbCollectNext     ; not a dead end

    ; Dead end — store if the candidate list still has room
    ld a, [wBuffer + wPFCandCount]
    cp PF_MAX_DEADENDS
    jr nc, .sfbCollectNext    ; list full — skip (mild bias, list is generous)
    ld e, a
    ld d, 0
    ld hl, sProcForestGenScratch
    add hl, de
    ld a, [wBuffer + wPFRowJ]
    swap a
    ld b, a
    ld a, [wBuffer + wPFBraidCol]
    or b
    ld [hl], a                 ; packed col | row<<4
    ld a, [wBuffer + wPFCandCount]
    inc a
    ld [wBuffer + wPFCandCount], a

.sfbCollectNext
    ld a, [wBuffer + wPFBraidCol]
    inc a
    ld [wBuffer + wPFBraidCol], a
    cp PF_CELL_W
    jp nz, .sfbCol

    ld a, [wBuffer + wPFRowJ]
    inc a
    ld [wBuffer + wPFRowJ], a
    cp PF_CELL_H
    jp nz, .sfbRow

    ; --- Phase 2: pick 4 balls with spacing + item-dedup ---
    ld a, [wBuffer + wPFCandCount]
    and a
    jp z, .sfbAllFallback      ; no dead ends at all (very unlikely on an
                               ; 81-cell maze) — default every ball to entrance

    xor a
    ld [wBuffer + wPFBallIdx], a

.sfbPickBall
    ld a, 20
    ld [wBuffer + wPFSpaceRetry], a

.sfbSpaceRetry
    ; Pick a random candidate, decode to block (X,Y), stash in wPFCurX/Y.
    ld a, [wBuffer + wPFCandCount]
    ld c, a
    call Rangerandom           ; a = 0..candCount-1
    ld e, a
    ld d, 0
    ld hl, sProcForestGenScratch
    add hl, de
    ld a, [hl]                 ; packed col|row<<4
    ld b, a
    and $0F                    ; col
    add a, a
    inc a
    ld [wBuffer + wPFCurX], a  ; candidate block X = 2*col+1
    ld a, b
    swap a
    and $0F                    ; row
    add a, a
    inc a
    ld [wBuffer + wPFCurY], a  ; candidate block Y = 2*row+1

    ; Spacing check (Chebyshev, CELL units == /2 of block distance, but
    ; comparing raw block deltas against PF_ITEM_MIN_DIST in cell-equivalent
    ; block units is fine since dead-end cells are always odd block coords
    ; 2 apart at minimum anyway — PF_ITEM_MIN_DIST is tuned in cell units).
    ld a, [wBuffer + wPFBallIdx]
    and a
    jr z, .sfbSpaceOK          ; ball 0 — nothing to compare against yet
    ld b, a                    ; b = number of earlier balls to check
    ld hl, wBuffer + wPFAcceptedXY
.sfbSpaceCheckLoop
    ld a, [wBuffer + wPFCurX]
    sub [hl]
    call PFAbs
    ld c, a                    ; c = |dx| (block units)
    inc hl
    ld a, [wBuffer + wPFCurY]
    sub [hl]
    call PFAbs                 ; a = |dy|
    inc hl
    cp c
    jr nc, .sfbHaveMax
    ld a, c
.sfbHaveMax
    ; convert block-unit Chebyshev to cell units (/2) for the PF_ITEM_MIN_DIST
    ; comparison — cells are 2 blocks apart, so block-delta/2 == cell-delta
    srl a
    cp PF_ITEM_MIN_DIST
    jr c, .sfbSpaceFail
    dec b
    jr nz, .sfbSpaceCheckLoop
.sfbSpaceOK
    jr .sfbAcceptPos
.sfbSpaceFail
    ld a, [wBuffer + wPFSpaceRetry]
    dec a
    ld [wBuffer + wPFSpaceRetry], a
    jr nz, .sfbSpaceRetry
    ; budget exhausted — accept the last candidate anyway (matches cave)
.sfbAcceptPos
    ld a, [wBuffer + wPFBallIdx]
    add a, a
    ld e, a
    ld d, 0
    ld hl, wBuffer + wPFAcceptedXY
    add hl, de
    ld a, [wBuffer + wPFCurX]
    ld [hli], a
    ld a, [wBuffer + wPFCurY]
    ld [hl], a

    ; --- Roll this ball's item, rejecting an exact duplicate of any
    ; already-placed ball's item (same retry-then-accept shape as cave). ---
    ld a, 8
    ld [wBuffer + wPFItemRetry], a
.sfbRollItem
    ld c, 4
    call Rangerandom
    ld [wRogueDoorSelection], a
    farcall Random_Item_Selection   ; result -> wRogueItem
    ld a, [wBuffer + wPFBallIdx]
    and a
    jr z, .sfbItemOK           ; ball 0 — nothing to compare against
    ld b, a
    ld hl, wBuffer + wPFItemTemp
    ld a, [wRogueItem]
    ld c, a
.sfbItemDupCheck
    ld a, [hli]
    cp c
    jr z, .sfbItemDup
    dec b
    jr nz, .sfbItemDupCheck
    jr .sfbItemOK
.sfbItemDup
    ld a, [wBuffer + wPFItemRetry]
    dec a
    ld [wBuffer + wPFItemRetry], a
    jr nz, .sfbRollItem
    ; budget exhausted — accept the duplicate rather than loop forever
.sfbItemOK
    ld a, [wBuffer + wPFBallIdx]
    ld c, a
    ld b, 0
    ld hl, wBuffer + wPFItemTemp
    add hl, bc
    ld a, [wRogueItem]
    ld [hl], a                 ; itemTemp[ball_idx] = candidate

    ld a, [wBuffer + wPFBallIdx]
    inc a
    ld [wBuffer + wPFBallIdx], a
    cp 4
    jp nz, .sfbPickBall

    ; All 4 picked — copy accepted (X,Y) pairs into sProcForestGenScratch[0..7]
    ; (the candidate list there is no longer needed) so they survive the
    ; upcoming PFBraidPass call untouched, and write items to wRogueItem/2/3/4.
    ld hl, wBuffer + wPFAcceptedXY
    ld de, sProcForestGenScratch
    ld b, 8
.sfbCopyXY
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .sfbCopyXY
    jr .sfbWriteItems

.sfbAllFallback
    ; No dead ends found at all — default all 4 balls to the entrance block.
    ld hl, sProcForestGenScratch
    ld b, 4
.sfbFallbackLoop
    ld a, 9
    ld [hli], a
    ld a, 17
    ld [hli], a
    dec b
    jr nz, .sfbFallbackLoop
    ; Roll 4 items with the same dedup logic, no position spacing needed.
    xor a
    ld [wBuffer + wPFBallIdx], a
.sfbFallbackItemLoop
    ld a, 8
    ld [wBuffer + wPFItemRetry], a
.sfbFallbackRollItem
    ld c, 4
    call Rangerandom
    ld [wRogueDoorSelection], a
    farcall Random_Item_Selection
    ld a, [wBuffer + wPFBallIdx]
    and a
    jr z, .sfbFallbackItemOK
    ld b, a
    ld hl, wBuffer + wPFItemTemp
    ld a, [wRogueItem]
    ld c, a
.sfbFallbackDupCheck
    ld a, [hli]
    cp c
    jr z, .sfbFallbackDup
    dec b
    jr nz, .sfbFallbackDupCheck
    jr .sfbFallbackItemOK
.sfbFallbackDup
    ld a, [wBuffer + wPFItemRetry]
    dec a
    ld [wBuffer + wPFItemRetry], a
    jr nz, .sfbFallbackRollItem
.sfbFallbackItemOK
    ld a, [wBuffer + wPFBallIdx]
    ld c, a
    ld b, 0
    ld hl, wBuffer + wPFItemTemp
    add hl, bc
    ld a, [wRogueItem]
    ld [hl], a
    ld a, [wBuffer + wPFBallIdx]
    inc a
    ld [wBuffer + wPFBallIdx], a
    cp 4
    jr nz, .sfbFallbackItemLoop

.sfbWriteItems
    ld hl, wBuffer + wPFItemTemp
    ld de, wRogueItem
    ld b, 4
.sfbWriteItemsLoop
    ld a, [hli]
    ld [de], a
    inc de
    inc de                     ; skip high byte of each dw slot
    dec b
    jr nz, .sfbWriteItemsLoop
    ret

; ============================================================
; PFRollMonClass
; Duplicate of PCRollMonClass (custom_functions/procedural_cave_gen.asm) —
; NOT farcall'd because it takes its rarity bump via register B, and
; farcall/Bankswitch clobbers B for the target bank number before the
; farcall'd function ever runs. Per the project's cross-bank-call lesson:
; duplicate tiny primitives into this bank rather than fight that.
; INPUT:  b = extra rarity bump (0 = wild baseline, higher = rarer, e.g. boss)
; OUTPUT: c = class 1-4. Clobbers a, d (b preserved).
; ============================================================
PFRollMonClass:
    ld a, [wBattleCount]
    cp 90
    jr c, .noClamp
    ld a, 89
.noClamp
    ld d, 0
.divLoop
    cp 10
    jr c, .gotRound
    sub 10
    inc d
    jr .divLoop
.gotRound
    ld a, d
    add a, a
    add a, a
    add a, a            ; round * 8
    add a, b            ; + bump
    jr nc, .noShiftClamp
    ld a, 255
.noShiftClamp
    ld d, a
    call Random         ; a = 0-255
    add a, d
    jr nc, .noEffClamp
    ld a, 255
.noEffClamp
    ld c, 1
    cp 205
    jr c, .done
    inc c
    cp 243
    jr c, .done
    inc c
    cp 253
    jr c, .done
    inc c
.done
    ret

; ============================================================
; PFRollBoss
; Mirrors PCRollBoss (cave). Rolls the forest boss species + overworld
; sprite category, stores both to SRAM. Called from PFPreloadForest at
; Pallet Town entry while SRAM is open.
;
; farcall return-value rules (all bank 7, learned the hard way):
;   PCGetBossLevel    → returns via wCurEnemyLevel (memory). farcall-safe.
;   Random_Pokemon_Selection → returns species in D. Bankswitch preserves
;                       D/E/H/L, so D survives. farcall-safe.
;   PCGetBossOWSprite → returns in A. farcall CLOBBERS A with the restored
;                       bank number → NOT farcall-safe. Use the bank-7
;                       wrapper PFStoreBossOWSpriteToSRAM (writes SRAM itself).
;   PFRollMonClass    → takes rarity bump in B (input). farcall clobbers B
;                       before the callee runs → duplicated into THIS bank.
; ============================================================
PFRollBoss:
    farcall PCGetBossLevel           ; sets wCurEnemyLevel (mirrors cave's order)
    ld b, 48                         ; boss rarity bump, matches cave's PCRollBoss
    call PFRollMonClass              ; c = rarity class (same bank, plain call OK)
    farcall Random_Pokemon_Selection ; -> d = species (d survives farcall)
    ld a, d
    ld [wRoguePokemon1], a
    ld [sProcForestBossSpecies], a
    ; Store the OW sprite category. Must NOT `farcall PCGetBossOWSprite` —
    ; that returns the sprite in A, and farcall's Bankswitch clobbers A with
    ; the restored bank number on return (was the "boss = gentleman" bug).
    ; The bank-7 wrapper stores it straight to SRAM, avoiding any A-return.
    farcall PFStoreBossOWSpriteToSRAM
    ret

; ============================================================
; PFPreloadForest
; Called at Pallet Town entry. Resets sProcForestBaked so the next
; forest visit generates a fresh maze instead of fast-blitting the
; previous run's layout.
; ============================================================
PFPreloadForest::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    ASSERT BANK("Sprite Buffers") == 0
    xor a
    ld [rRAMB], a
    ld [sProcForestBaked], a        ; 0 = needs fresh generation
    ld [sProcForestItemGot], a      ; clear all ball-collected bits
    ld [sProcForestAlgoForce], a    ; 0 = random; set in BGB after this runs to force an algo

    ; Roll the forest's OWN boss (previously this read wRoguePokemon1 as if
    ; PCRollBoss — the CAVE's roller — had already set it for the forest;
    ; that was a bug: it grabbed the cave's leftover species/sprite instead
    ; of an independent roll).
    call PFRollBoss

    ; Set the forest's wild-battle budget for this run: 10 + wBattleCount/5,
    ; saturating at 255 (identical formula to cave's PCPreloadCave).
    ld a, [wBattleCount]
    ld b, 0
.budgetDivLoop
    cp 5
    jr c, .budgetGotQuotient
    sub 5
    inc b
    jr .budgetDivLoop
.budgetGotQuotient
    ld a, b
    add a, 10
    jr nc, .budgetNoClamp
    ld a, 255
.budgetNoClamp
    ld [wProcForestWildBudget], a

    ; Reset run events so sprites re-appear on next visit. Reuses the cave's
    ; EVENT_PC_BUDGET_ENDED/EVENT_PC_CALMED_SHOWN/EVENT_BEAT_PC_BOSS for the
    ; forest's own systems (calmed message, boss-defeated) — safe because
    ; cave/cemetery/forest never run concurrently and this preload always
    ; resets them fresh before any of the three stages could read them.
    ; EVENT_BEAT_PC_BOSS in particular MUST be reused (not a new forest-only
    ; event) since the trainer battle system requires it bit-aligned to
    ; %8==1 for a slot-1 trainer, and that alignment was already spent here.
    ResetEvent EVENT_PF_ITEM_GOT
    ResetEvent EVENT_BEAT_PC_BOSS
    ResetEvent EVENT_ENTER_ROOM
    ResetEvent EVENT_PC_BUDGET_ENDED
    ResetEvent EVENT_PC_CALMED_SHOWN
    ld a, BMODE_SIMPLE
    ld [rBMODE], a
    ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
    ld [rRAMG], a
    ret

; ============================================================
; PFinalizeForest
; Called at PROCEDURAL_FOREST warp-in (home/overworld.asm hook).
;
; First visit (sProcForestBaked=0):
;   LoadTileBlockMap has already filled wOverworldMap with all trees (block 2)
;   from ProceduralForest.blk — no manual fill needed. Generate directly into
;   wOverworldMap, then bake to sProcForestStagingBuffer.
;
; Re-entry (sProcForestBaked=1):
;   Fast-blit SRAM staging buffer → wOverworldMap.
;
; Both paths: patch wWarpEntries[1] with the exit tile coords.
; ============================================================
PFinalizeForest::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    ASSERT BANK("Sprite Buffers") == 0
    xor a
    ld [rRAMB], a

    ; Save algo-force byte to wBuffer while SRAM is open
    ld a, [sProcForestAlgoForce]
    ld [wBuffer + wPFAlgoForce], a

    ld a, [sProcForestBaked]
    and a
    jp nz, .fastBlit

    ; === First visit: generate directly into wOverworldMap ===
    ; (LoadTileBlockMap already filled it with all trees)
    ;
    ; SRAM is left OPEN through the entire generation phase (algorithm, ball
    ; scan, braid) on purpose: RAMG/BMODE/RAMB only gate $A000-$BFFF, they have
    ; ZERO effect on WRAM ($C000-$DFFF) reads/writes, so wOverworldMap and
    ; wBuffer work identically whether SRAM is open or not. Keeping it open
    ; lets PFBacktracker and PFScanForBall use sProcForestGenScratch (SRAM)
    ; directly instead of clobbering wOverworldMap's live border padding
    ; (confirmed corruption hazard — see their header comments). farcall/
    ; Bankswitch only touches rROMB, never rRAMG/rRAMB/rBMODE, so this is also
    ; safe across the farcall Random_Item_Selection / farcall PCGetBossLevel
    ; calls later in this function.

    ; Point PFWriteBlock at wOverworldMap
    ld a, LOW(wOverworldMap + PF_BASE)
    ld [wBuffer + wPFTargetBaseLo], a
    ld a, HIGH(wOverworldMap + PF_BASE)
    ld [wBuffer + wPFTargetBaseHi], a

    ; Algorithm selection. sProcForestAlgoForce (SRAM): 0=random, 1-4=force.
    ; Debug: set sProcForestAlgoForce in debugger to lock an algorithm.
    ld a, [wBuffer + wPFAlgoForce]
    and a
    jr nz, .algoForced
    ld c, 4
    call Rangerandom        ; a = 0..3
    jr .algoDispatch
.algoForced
    dec a                   ; 1→0, 2→1, 3→2, 4→3
.algoDispatch
    and 3                   ; clamp
    jr z, .useAlgoA
    cp 1
    jr z, .useAlgoB
    cp 2
    jr z, .useAlgoC
.useAlgoD
    call PFHuntAndKill
    jr .algosDone
.useAlgoA
    call PFSidewinder
    jr .algosDone
.useAlgoB
    call PFBinaryTree
    jr .algosDone
.useAlgoC
    call PFBacktracker
.algosDone

    ; Phase 4: scan for a dead-end cell to place the pokeball (BEFORE braid
    ; removes dead ends). Stores block coords in wBuffer+wPFBallX/Y,
    ; rolls item into wRogueItem.
    call PFScanForBall

    ; Phase 3: braid dead ends to add loops
    call PFBraidPass

    ; Roll exit column i (0-8), write block 88, save i in B for later.
    ; B is preserved by PFWriteBlock (push/pop bc). E is NOT preserved — it
    ; gets clobbered by the row-offset load inside PFWriteBlock.
    ld c, PF_CELL_W
    call Rangerandom        ; a = 0..8
    ld b, a                 ; b = i (B preserved by PFWriteBlock)
    add a, a                ; 2i
    inc a                   ; 2i+1
    ld [wBuffer + wPFCurX], a
    xor a                   ; block Y = 0
    ld [wBuffer + wPFCurY], a
    ld a, PF_EXIT_N
    call PFWriteBlock       ; B = i preserved via push bc / pop bc ✓

    ; === Bake: copy wOverworldMap → sProcForestStagingBuffer, then mark baked ===
    ; SRAM is already open (kept open since the top of the first-visit path).

    ; Save exit column and boss exit I (B preserved from Rangerandom earlier)
    ld a, b
    ld [sProcForestExitI], a

    ; Save 4 ball positions (from sProcForestGenScratch[0..7], block X,Y pairs)
    ; as tile coords (block*2+4) in Y,X order to match sProcForestBallXY/
    ; sProcCaveBallXY's Y0,X0,Y1,X1,... layout.
    ld hl, sProcForestBallXY
    ld de, sProcForestGenScratch  ; [0]=X0,[1]=Y0,[2]=X1,[3]=Y1...
    ld b, 4
.pfbBallSave
    ld a, [de]                  ; block X
    inc de
    add a, a
    add a, 4                    ; tile X = block*2+4
    ld c, a                     ; save tile X for after Y is written
    ld a, [de]                  ; block Y
    inc de
    add a, a
    add a, 4                    ; tile Y = block*2+4
    ld [hli], a                 ; store tile Y first
    ld a, c
    ld [hli], a                 ; then tile X
    dec b
    jr nz, .pfbBallSave

    ; Roll 4 items into sProcForestBallItems
    ; (mirrors PCPlaceWildAreaItems' temp-buffer approach: roll 4, write after)
    ld hl, wBuffer + wPFBraidCol ; reuse wBuffer temp space [19..22]
    ld b, 4
.pfbItemRoll
    ld c, 4
    push hl
    push bc
    call Rangerandom
    ld [wRogueDoorSelection], a
    farcall Random_Item_Selection
    pop bc
    pop hl
    ld a, [wRogueItem]
    ld [hli], a                 ; wBuffer[19], [20], [21], [22]
    dec b
    jr nz, .pfbItemRoll
    ; Copy from wBuffer[19..22] to sProcForestBallItems
    ld de, sProcForestBallItems
    ld hl, wBuffer + wPFBraidCol
    ld b, 4
.pfbItemCopy
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .pfbItemCopy

    ld hl, wOverworldMap + PF_BASE
    ld de, sProcForestStagingBuffer + PF_BASE
    ld b, PF_SIZE
.bakeRowLoop
    push bc
    ld c, PF_SIZE
.bakeColLoop
    ld a, [hli]
    ld [de], a
    inc de
    dec c
    jr nz, .bakeColLoop
    ld a, l
    add a, PF_STRIDE - PF_SIZE
    ld l, a
    jr nc, .bakeNoCarryHL
    inc h
.bakeNoCarryHL
    ld a, e
    add a, PF_STRIDE - PF_SIZE
    ld e, a
    jr nc, .bakeNoCarryDE
    inc d
.bakeNoCarryDE
    pop bc
    dec b
    jr nz, .bakeRowLoop

    ld a, 1
    ld [sProcForestBaked], a

    ; Read exit column and close SRAM before patching WRAM
    ld a, [sProcForestExitI]
    ld b, a
    ld a, BMODE_SIMPLE
    ld [rBMODE], a
    ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
    ld [rRAMG], a
    jr .patchWarp

.fastBlit
    ; === Re-entry: blit SRAM staging buffer → wOverworldMap ===
    ld hl, sProcForestStagingBuffer + PF_BASE
    ld de, wOverworldMap + PF_BASE
    ld b, PF_SIZE
.blitRowLoop
    push bc
    ld c, PF_SIZE
.blitColLoop
    ld a, [hli]
    ld [de], a
    inc de
    dec c
    jr nz, .blitColLoop
    ld a, l
    add a, PF_STRIDE - PF_SIZE
    ld l, a
    jr nc, .blitNoCarryHL
    inc h
.blitNoCarryHL
    ld a, e
    add a, PF_STRIDE - PF_SIZE
    ld e, a
    jr nc, .blitNoCarryDE
    inc d
.blitNoCarryDE
    pop bc
    dec b
    jr nz, .blitRowLoop

    ld a, [sProcForestExitI]
    ld b, a
    ld a, BMODE_SIMPLE
    ld [rBMODE], a
    ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
    ld [rRAMG], a

.patchWarp
    ; Patch exit warp entries 1 and 2 (left/right tiles of exit block).
    ld a, b                         ; exitI (saved before SRAM closed)
    add a, a                        ; 2*exitI
    add a, a                        ; 4*exitI
    add a, 2                        ; 4*exitI+2 = left tile X
    ld c, a
    ld hl, wWarpEntries + 4
    xor a
    ld [hli], a                     ; entry1 Y = 0
    ld a, c
    ld [hli], a                     ; entry1 X = 4*exitI+2
    inc hl
    inc hl
    xor a
    ld [hli], a                     ; entry2 Y = 0
    ld a, c
    inc a
    ld [hl], a                      ; entry2 X = 4*exitI+3

    ; Re-open SRAM to read ball positions, boss species, item-got mask
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    xor a
    ld [rRAMB], a

    ; Restore wRoguePokemon1 (may have been clobbered since Pallet Town)
    ld a, [sProcForestBossSpecies]
    ld [wRoguePokemon1], a

    ; Boss sprite: slot 1 = wSprite01. Exit cell = block (2*exitI+1, 1).
    ; tile = block*2+4 matching cave's PCPlaceBoss formula.
    ld a, [sProcForestExitI]
    ld b, a                         ; b = exitI (reload; B may have changed)
    add a, a                        ; 2*exitI
    add a, a                        ; 4*exitI
    add a, 2                        ; 4*exitI+2
    add a, 4                        ; +4 = tile X (block*2+4 formula)
    ld [wSprite01StateData2MapX], a
    ld a, 1*2+4                     ; exit cell block_y=1 → 1*2+4=6
    ld [wSprite01StateData2MapY], a

    ; Set boss species/level in wMapSpriteExtraData (slot 1 = offset 0)
    farcall PCGetBossLevel          ; bank 7 — must farcall from bank 6
    ld hl, wMapSpriteExtraData + 0
    ld a, [wRoguePokemon1]
    ld [hli], a
    ld a, [wCurEnemyLevel]
    set 7, a                        ; OW_POKEMON bit
    ld [hl], a

    ; Pokeballs: slots 2-5 = wSprite01StateData2MapY + 16*slot
    ; Restore from sProcForestBallXY (Y0,X0,Y1,X1,...) and items
    ld hl, sProcForestBallXY
    ld de, wSprite01StateData2MapY + 16
    ld b, 4
.pfbRestoreXY
    ld a, [hli]                     ; tile Y
    ld [de], a
    inc de
    ld a, [hli]                     ; tile X
    ld [de], a
    ld a, e
    add a, 15                       ; advance by 15 → next slot MapY (+16 total)
    ld e, a
    jr nc, .pfbNoCarryXY
    inc d
.pfbNoCarryXY
    dec b
    jr nz, .pfbRestoreXY

    ; Restore ball items to wRogueItem..+6 (2 bytes/slot, low = ID)
    ld hl, sProcForestBallItems
    ld de, wRogueItem
    ld b, 4
.pfbRestoreItem
    ld a, [hli]
    ld [de], a
    inc de
    inc de
    dec b
    jr nz, .pfbRestoreItem

    ; Close SRAM. Ball/boss hide state is now owned entirely by the toggle
    ; system (ShowObject/HideObject + wToggleableObjectFlags via the shared
    ; TOGGLE_WILD_AREA_BOSS/POKEBALL_1-4 constants, matching cave — see
    ; scripts/ProceduralForest.asm). sProcForestItemGot is dead: nothing sets
    ; it anymore, so its old hide-check here always read 0 and never actually
    ; hid anything — removed to avoid confusing future debugging.
    ld a, BMODE_SIMPLE
    ld [rBMODE], a
    ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
    ld [rRAMG], a
    ret
