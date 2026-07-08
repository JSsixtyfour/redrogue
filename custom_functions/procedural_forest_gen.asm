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
; OUTPUT: a = random floor block: 41 (tall grass), 1 (path), or 27 (flowers)
; ============================================================
PFPickFloor:
    ld c, 3
    call Rangerandom    ; a = 0, 1, or 2
    and a
    jr z, .zero
    cp 2
    jr z, .two
    ld a, 1
    ret
.zero
    ld a, 41
    ret
.two
    ld a, 27
    ret

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
; Iterative recursive backtracker. Stack at wOverworldMap[0..80]
; (the border area before PF_BASE — not part of the logical map blit).
; Each stack entry: packed (col | row<<4). Visited = block != PF_TREE.
; ============================================================
PFBacktracker:
    ; Push entrance cell (col=4, row=8) → packed 0x84
    xor a
    ld [wBuffer + wPFStackPtr], a
    ld a, (4 | (8 << 4))
    ld hl, wOverworldMap
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

    ; Peek top: wOverworldMap[sp-1]
    dec a
    ld e, a
    ld d, 0
    ld hl, wOverworldMap
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
    ld hl, wOverworldMap
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

    ; close SRAM — generation writes to WRAM (wOverworldMap), not SRAM
    ld a, BMODE_SIMPLE
    ld [rBMODE], a
    ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
    ld [rRAMG], a

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
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    xor a
    ld [rRAMB], a

    ; Save exit column to SRAM now (bake loop will clobber B)
    ld a, b
    ld [sProcForestExitI], a

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
    ; Patch wWarpEntries entries 1 and 2 with the exit tile coords.
    ; Exit block at logical (2i+1, 0): left tile=(4i+2,0), right tile=(4i+3,0).
    ; wWarpEntries format per entry: [Y, X, map, warpID] = 4 bytes.
    ; B = i (0-8) saved before SRAM was closed.
    ld a, b                         ; i
    add a, a                        ; 2i
    add a, a                        ; 4i
    add a, 2                        ; 4i+2 = left tile X
    ld c, a                         ; c = left tile X
    ld hl, wWarpEntries + 4         ; entry 1
    xor a
    ld [hli], a                     ; entry1 Y = 0
    ld a, c
    ld [hli], a                     ; entry1 X = 4i+2
    inc hl                          ; skip map byte
    inc hl                          ; skip warpID byte  — now at entry 2
    xor a
    ld [hli], a                     ; entry2 Y = 0
    ld a, c
    inc a                           ; 4i+3 = right tile X
    ld [hl], a                      ; entry2 X = 4i+3
    ret
