; custom_functions/procedural_facility_gen.asm
;
; Procedural facility generator for PROCEDURAL_FACILITY ($F3).
;
; Almost identical in structure to procedural_forest_gen.asm, but:
;   - Rooms/Dungeon layout ONLY (no maze-algo rotation, no river).
;   - FACILITY tileset uses DIRECTIONAL walls (top/left/right/bottom + corners),
;     so after carving we run PFacAutotilePass (an 8-neighbour classifier) to
;     turn every wall cell into the correct directional block.
;   - The player area is FLOOR-based: PFacFillWalls seeds the working buffer with
;     a wall SENTINEL (PFAC_WALL=46), the maze carves floor (14), and the
;     autotiler replaces EVERY sentinel cell with either a directional wall or
;     floor. No 46 survives inside the player area (46 = border/void only).
;
; SRAM: uses its own sProcFacility* fields (see ram/sram.asm). sProcFacilityBaked
; controls fast re-entry. Reuses the cave's boss/wild/item engine + PC_* events
; (never concurrent), exactly like the forest.
;
; Steps 5+6 scope: generation core + autotiler + bake/blit. Boss placement,
; item placement, and exit-warp patching are added in step 7; the overworld
; preload/finalize hooks in step 8.

SECTION "ProceduralFacilityGen", ROMX

DEF PFAC_SIZE    EQU 20
DEF PFAC_STRIDE  EQU 26
DEF PFAC_BASE    EQU 81

DEF PFAC_CELL_W  EQU 9
DEF PFAC_CELL_H  EQU 9

DEF PFAC_FLOOR   EQU 14   ; facility floor block (all-$01, passable)
DEF PFAC_WALL    EQU 46   ; generation-time wall sentinel + map border/void block.
                          ; Never survives inside the player area: the autotiler
                          ; converts every one to a directional wall or floor.
DEF PFAC_PENDING EQU 255  ; autotile "will become floor" sentinel (cascade-safe,
                          ; same idea as cave's PC_BLOCK_PENDING_FLOOR). Converted
                          ; to real floor in the autotiler's second pass.

; --- Directional wall 9-slice (block IDs pinned from facility.bst / user) ---
; Straight walls, named by which side the open floor is on:
DEF PFAC_W_TOP    EQU 65  ; floor to the SOUTH (solid top, walkable bottom)
DEF PFAC_W_BOTTOM EQU 73  ; floor to the NORTH
DEF PFAC_W_LEFT   EQU 68  ; floor to the EAST
DEF PFAC_W_RIGHT  EQU 70  ; floor to the WEST
; Corners, named by which corner of the block is solid (floor is the opposite):
DEF PFAC_C_TL     EQU 64  ; solid top-left,  floor SE  (floor to S and E)
DEF PFAC_C_TR     EQU 66  ; solid top-right, floor SW  (floor to S and W)
DEF PFAC_C_BL     EQU 72  ; solid bottom-left,  floor NE (floor to N and E)
DEF PFAC_C_BR     EQU 74  ; solid bottom-right, floor NW (floor to N and W)

; Item placement spacing (step 7) - kept here for parity with forest/cave.
DEF PFAC_ITEM_MIN_DIST EQU 2
DEF PFAC_MAX_DEADENDS  EQU 80  ; candidate cap = all 9x9 cells (fits the 81-byte scratch)

; wBuffer scratch offsets. Facility never runs concurrently with cave/cemetery/
; forest generation, so it reuses the same wBuffer window they use.
DEF wPFacTargetBaseLo EQU 0
DEF wPFacTargetBaseHi EQU 1
DEF wPFacCurX         EQU 2   ; block-space X for PFacWriteBlock/PFacReadBlock
DEF wPFacCurY         EQU 3   ; block-space Y
; Rooms/HuntAndKill scratch (mirror forest's offsets exactly).
DEF wPFacRoomCol      EQU 4
DEF wPFacRoomRow      EQU 5
DEF wPFacRoomW        EQU 6
DEF wPFacRoomH        EQU 7
DEF wPFacCellCol      EQU 8
DEF wPFacCellRow      EQU 9
DEF wPFacNeighborCnt  EQU 10
DEF wPFacNeighbors    EQU 11  ; 4 bytes: packed neighbor list (col | row<<4)
DEF wPFacNCol         EQU 15
DEF wPFacNRow         EQU 16
DEF wPFacRoomCount    EQU 25  ; survives the PFacHuntAndKill call between
                              ; PFacPlaceRooms and PFacConnectRooms
DEF wPFacRoomTries    EQU 26
DEF wPFacRoomIdx      EQU 27
DEF wPFacScanColLo    EQU 27  ; alias (PFacPlaceRooms, dead before PFacConnectRooms)
DEF wPFacDoorCount    EQU 28
DEF wPFacScanColHi    EQU 28  ; alias
DEF wPFacSideBound    EQU 29
DEF wPFacScanRowHi    EQU 29  ; alias
; Autotile scratch (runs after all generation, so offsets 4-7 are dead here).
DEF wPFacLoopX        EQU 4
DEF wPFacLoopY        EQU 5
DEF wPFacDX           EQU 6   ; classify: saved cell X
DEF wPFacDY           EQU 7   ; classify: saved cell Y
DEF wPFacFlags        EQU 18  ; classify: orthogonal floor mask (N1 S2 E4 W8)
DEF wPFacDiag         EQU 19  ; classify: diagonal floor mask (NE1 NW2 SE4 SW8)

; Item-scan scratch (PFacScanForBall). Runs BEFORE the autotile pass, so it
; freely reuses the same numeric offsets the forest's PFScanForBall uses.
DEF wPFacRowJ         EQU 4   ; scan row
DEF wPFacBraidCol     EQU 19  ; scan col (dead before autotile's wPFacDiag reuse)
DEF wPFacPassCount    EQU 18  ; passage count for current cell
DEF wPFacCandCount    EQU 5   ; dead-end candidate count
DEF wPFacSpaceRetry   EQU 6
DEF wPFacItemRetry    EQU 7
DEF wPFacAcceptedXY   EQU 10  ; 8 bytes (10-17): 4x(blockX,blockY)
DEF wPFacBallIdx      EQU 20
DEF wPFacItemTemp     EQU 21  ; 4 bytes (21-24): rolled item IDs
; Dead-end prune scratch (runs after connect, before the item scan/autotile).
DEF wPFacPruneRow     EQU 4
DEF wPFacPruneCol     EQU 5
DEF wPFacPruneChanged EQU 6
; Grid generator scratch (PowerPlant path; alternative to the dungeon path).
DEF wPFacGridRows     EQU 4
DEF wPFacGridCols     EQU 5
DEF wPFacGridR        EQU 6
DEF wPFacGridC        EQU 7
DEF wPFacGridX0       EQU 8
DEF wPFacGridX1       EQU 9
DEF wPFacGridY0       EQU 10
DEF wPFacGridY1       EQU 11

; ============================================================
; PFacRowOffsetTable / PFacWriteBlock / PFacReadBlock / PFacPickFloor
; Direct ports of the forest primitives (PFRowOffsetTable etc.). Duplicated
; in-bank because a cross-bank call to the forest copies is a silent landmine.
; ============================================================
PFacRowOffsetTable:
    FOR pfac_row, PFAC_SIZE
    dw pfac_row * PFAC_STRIDE
    ENDR

; INPUT: a = block ID; [wBuffer+wPFacCurX/Y] = logical coords (0-19). Preserves BC.
PFacWriteBlock:
    push af
    push bc
    ld a, [wBuffer + wPFacTargetBaseLo]
    ld l, a
    ld a, [wBuffer + wPFacTargetBaseHi]
    ld h, a
    push hl
    ld a, [wBuffer + wPFacCurY]
    add a, a
    ld c, a
    ld b, 0
    ld hl, PFacRowOffsetTable
    add hl, bc
    ld a, [hli]
    ld e, a
    ld a, [hl]
    ld d, a
    pop hl
    add hl, de
    ld a, [wBuffer + wPFacCurX]
    add a, l
    ld l, a
    jr nc, .noCarry
    inc h
.noCarry
    pop bc
    pop af
    ld [hl], a
    ret

; INPUT: [wBuffer+wPFacCurX/Y] = logical coords. OUTPUT: a = block value. Preserves BC.
PFacReadBlock:
    push bc
    ld a, [wBuffer + wPFacTargetBaseLo]
    ld l, a
    ld a, [wBuffer + wPFacTargetBaseHi]
    ld h, a
    push hl
    ld a, [wBuffer + wPFacCurY]
    add a, a
    ld c, a
    ld b, 0
    ld hl, PFacRowOffsetTable
    add hl, bc
    ld a, [hli]
    ld e, a
    ld a, [hl]
    ld d, a
    pop hl
    add hl, de
    ld a, [wBuffer + wPFacCurX]
    add a, l
    ld l, a
    jr nc, .noCarry
    inc h
.noCarry
    ld a, [hl]
    pop bc
    ret

; OUTPUT: a = floor block. Facility ships a single floor block (14). Kept as a
; function so the ported carve code calls it identically to the forest's
; PFPickFloor (a floor-variety table can be added here later).
PFacPickFloor:
    ld a, PFAC_FLOOR
    ret

; ============================================================
; PFacFillWalls
; Seed the whole 20x20 player area with PFAC_WALL so the carve algorithm has
; walls to open paths through. The .blk's floor fill is only a placeholder;
; this always overwrites it. Border padding (already PFAC_WALL from the object
; file's border block) is untouched.
; ============================================================
PFacFillWalls:
    ld hl, wOverworldMap + PFAC_BASE
    ld b, PFAC_SIZE
.rowLoop
    push bc
    ld c, PFAC_SIZE
.colLoop
    ld a, PFAC_WALL
    ld [hli], a
    dec c
    jr nz, .colLoop
    ld a, l
    add a, PFAC_STRIDE - PFAC_SIZE
    ld l, a
    jr nc, .noCarry
    inc h
.noCarry
    pop bc
    dec b
    jr nz, .rowLoop
    ret

; ============================================================
; PFacCheckUnvisited
; INPUT: B=neighbor row (0-8), C=neighbor col (0-8).
; If cell (C,B) is unvisited (still PFAC_WALL), appends packed (C|B<<4) to
; wPFacNeighbors and increments wPFacNeighborCnt. Preserves B, C.
; (Forest's river guard is dropped - facility has no river.)
; ============================================================
PFacCheckUnvisited:
    ld a, c
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, b
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock        ; A = block; BC preserved
    cp PFAC_WALL
    ret nz                    ; already visited (floor)
    ld a, [wBuffer + wPFacNeighborCnt]
    ld e, a
    inc a
    ld [wBuffer + wPFacNeighborCnt], a
    ld a, b
    swap a
    or c
    ld d, 0
    ld hl, wBuffer + wPFacNeighbors
    add hl, de
    ld [hl], a
    ret

; ============================================================
; PFacCarveToNeighbor
; Pick a random entry from wPFacNeighbors, carve the wall between the current
; cell (wPFacCellCol/Row) and the neighbor, carve the neighbor cell, then make
; the neighbor current. Requires wPFacNeighborCnt > 0.
; ============================================================
PFacCarveToNeighbor:
    ld a, [wBuffer + wPFacNeighborCnt]
    ld c, a
    call Rangerandom
    ld e, a
    ld d, 0
    ld hl, wBuffer + wPFacNeighbors
    add hl, de
    ld a, [hl]
    ld b, a
    and $0F
    ld [wBuffer + wPFacNCol], a
    ld a, b
    swap a
    and $0F
    ld [wBuffer + wPFacNRow], a

    ; Carve wall block: (curCol+nCol+1, curRow+nRow+1)
    ld a, [wBuffer + wPFacCellCol]
    ld b, a
    ld a, [wBuffer + wPFacNCol]
    add a, b
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacCellRow]
    ld b, a
    ld a, [wBuffer + wPFacNRow]
    add a, b
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacPickFloor
    call PFacWriteBlock

    ; Carve neighbor cell: (2*nCol+1, 2*nRow+1)
    ld a, [wBuffer + wPFacNCol]
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacNRow]
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacPickFloor
    call PFacWriteBlock

    ld a, [wBuffer + wPFacNCol]
    ld [wBuffer + wPFacCellCol], a
    ld a, [wBuffer + wPFacNRow]
    ld [wBuffer + wPFacCellRow], a
    ret

; ============================================================
; PFacHuntAndKill
; Random walk from the entrance cell (4,8), carving unvisited neighbors; when
; stuck, scan for a visited cell with an unvisited neighbor and resume. Treats
; already-carved room cells as visited, so it fills corridor around rooms.
; Visited = block != PFAC_WALL.
; ============================================================
PFacHuntAndKill:
    ld a, 4
    ld [wBuffer + wPFacCellCol], a
    ld a, 8
    ld [wBuffer + wPFacCellRow], a
    ld a, 9
    ld [wBuffer + wPFacCurX], a
    ld a, 17
    ld [wBuffer + wPFacCurY], a
    call PFacPickFloor
    call PFacWriteBlock

.walk
    xor a
    ld [wBuffer + wPFacNeighborCnt], a
    ld a, [wBuffer + wPFacCellRow]
    ld b, a
    ld a, [wBuffer + wPFacCellCol]
    ld c, a
    ld a, b
    and a
    jr z, .skipN
    dec b
    call PFacCheckUnvisited
    inc b
.skipN
    ld a, b
    cp 8
    jr nc, .skipS
    inc b
    call PFacCheckUnvisited
    dec b
.skipS
    ld a, c
    and a
    jr z, .skipW
    dec c
    call PFacCheckUnvisited
    inc c
.skipW
    ld a, c
    cp 8
    jr nc, .skipE
    inc c
    call PFacCheckUnvisited
    dec c
.skipE
    ld a, [wBuffer + wPFacNeighborCnt]
    and a
    jr z, .hunt
    call PFacCarveToNeighbor
    jp .walk

.hunt
    xor a
    ld [wBuffer + wPFacCellRow], a
.huntRow
    xor a
    ld [wBuffer + wPFacCellCol], a
.huntCol
    ld a, [wBuffer + wPFacCellCol]
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacCellRow]
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_WALL
    jr z, .huntNext         ; unvisited: skip

    xor a
    ld [wBuffer + wPFacNeighborCnt], a
    ld a, [wBuffer + wPFacCellRow]
    ld b, a
    ld a, [wBuffer + wPFacCellCol]
    ld c, a
    ld a, b
    and a
    jr z, .hSkipN
    dec b
    call PFacCheckUnvisited
    inc b
.hSkipN
    ld a, b
    cp 8
    jr nc, .hSkipS
    inc b
    call PFacCheckUnvisited
    dec b
.hSkipS
    ld a, c
    and a
    jr z, .hSkipW
    dec c
    call PFacCheckUnvisited
    inc c
.hSkipW
    ld a, c
    cp 8
    jr nc, .hSkipE
    inc c
    call PFacCheckUnvisited
    dec c
.hSkipE
    ld a, [wBuffer + wPFacNeighborCnt]
    and a
    jr nz, .huntFound

.huntNext
    ld a, [wBuffer + wPFacCellCol]
    inc a
    ld [wBuffer + wPFacCellCol], a
    cp 9
    jr c, .huntCol
    ld a, [wBuffer + wPFacCellRow]
    inc a
    ld [wBuffer + wPFacCellRow], a
    cp 9
    jr c, .huntRow
    ret

.huntFound
    call PFacCarveToNeighbor
    jp .walk

; ============================================================
; PFacPlaceRooms
; Places up to 8 candidate rectangular rooms (2-3 cells per side) into the
; all-wall map BEFORE PFacHuntAndKill runs. Accepted rooms stored as
; (col,row,w,h) - 4 bytes each - in sProcFacilityGenScratch, count in
; wPFacRoomCount. (Direct port of PFPlaceRooms with PF_TREE -> PFAC_WALL.)
; ============================================================
PFacPlaceRooms:
    xor a
    ld [wBuffer + wPFacRoomCount], a
    ld [wBuffer + wPFacRoomTries], a

.tryLoop
    ld a, [wBuffer + wPFacRoomTries]
    cp 8
    ret nc

    ld c, PFAC_CELL_W
    call Rangerandom
    ld [wBuffer + wPFacRoomCol], a
    ld c, PFAC_CELL_H
    call Rangerandom
    ld [wBuffer + wPFacRoomRow], a
    ld c, 3
    call Rangerandom
    add a, 2                        ; width 2-4 cells (bigger vaults, fewer fit)
    ld [wBuffer + wPFacRoomW], a
    ld c, 3
    call Rangerandom
    add a, 2                        ; height 2-4 cells
    ld [wBuffer + wPFacRoomH], a

    ; Clip: col+w > 9 or row+h > 9 -> reject
    ld a, [wBuffer + wPFacRoomCol]
    ld b, a
    ld a, [wBuffer + wPFacRoomW]
    add a, b
    cp PFAC_CELL_W + 1
    jp nc, .nextTry
    ld a, [wBuffer + wPFacRoomRow]
    ld b, a
    ld a, [wBuffer + wPFacRoomH]
    add a, b
    cp PFAC_CELL_H + 1
    jp nc, .nextTry

    ; Overlap check: scan the rect expanded by a 1-cell margin (clamped);
    ; reject if any cell centre is already floor.
    ld a, [wBuffer + wPFacRoomCol]
    and a
    jr z, .colLoZero
    dec a
    jr .colLoDone
.colLoZero
    xor a
.colLoDone
    ld [wBuffer + wPFacScanColLo], a

    ld a, [wBuffer + wPFacRoomCol]
    ld b, a
    ld a, [wBuffer + wPFacRoomW]
    add a, b
    cp PFAC_CELL_W
    jr c, .colHiDone
    ld a, PFAC_CELL_W - 1
.colHiDone
    ld [wBuffer + wPFacScanColHi], a

    ld a, [wBuffer + wPFacRoomRow]
    and a
    jr z, .rowLoZero
    dec a
    jr .rowLoDone
.rowLoZero
    xor a
.rowLoDone
    ld b, a

    ld a, [wBuffer + wPFacRoomRow]
    ld c, a
    ld a, [wBuffer + wPFacRoomH]
    add a, c
    cp PFAC_CELL_H
    jr c, .rowHiDone
    ld a, PFAC_CELL_H - 1
.rowHiDone
    push af
.scanRowLoop
    pop af
    push af
    ld c, a
    ld a, [wBuffer + wPFacScanColLo]
    ld d, a
    ld e, d

.scanColLoop
    ld a, e
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, b
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    push bc
    push de
    call PFacReadBlock
    pop de
    pop bc
    cp PFAC_WALL
    jp nz, .rejectPopAF       ; already floor -> overlap

    ld a, [wBuffer + wPFacScanColHi]
    cp e
    jr z, .scanColDone
    inc e
    jr .scanColLoop
.scanColDone
    ld a, c
    cp b
    jr z, .scanRowDone
    inc b
    jr .scanRowLoop
.scanRowDone
    pop af

    ; Accepted: carve the whole room block span to floor.
    ld a, [wBuffer + wPFacRoomW]
    add a, a
    dec a
    ld [wBuffer + wPFacScanColHi], a   ; colCount = 2*w-1
    ld a, [wBuffer + wPFacRoomH]
    add a, a
    dec a
    ld [wBuffer + wPFacScanRowHi], a   ; rowCount = 2*h-1

    ld a, [wBuffer + wPFacRoomRow]
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a

.carveRowLoop
    ld a, [wBuffer + wPFacRoomCol]
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a

    ld a, [wBuffer + wPFacScanColHi]
    ld b, a
.carveColLoop
    call PFacPickFloor
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    dec b
    jr nz, .carveColLoop

    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacScanRowHi]
    dec a
    ld [wBuffer + wPFacScanRowHi], a
    jr nz, .carveRowLoop

    ; Append accepted room to sProcFacilityGenScratch[count*4..+3]
    ld a, [wBuffer + wPFacRoomCount]
    add a, a
    add a, a
    ld e, a
    ld d, 0
    ld hl, sProcFacilityGenScratch
    add hl, de
    ld a, [wBuffer + wPFacRoomCol]
    ld [hli], a
    ld a, [wBuffer + wPFacRoomRow]
    ld [hli], a
    ld a, [wBuffer + wPFacRoomW]
    ld [hli], a
    ld a, [wBuffer + wPFacRoomH]
    ld [hl], a

    ld a, [wBuffer + wPFacRoomCount]
    inc a
    ld [wBuffer + wPFacRoomCount], a
    jr .nextTry

.rejectPopAF
    pop af

.nextTry
    ld a, [wBuffer + wPFacRoomTries]
    inc a
    ld [wBuffer + wPFacRoomTries], a
    jp .tryLoop

; ============================================================
; PFacConnectRooms
; For each stored room, carve 1-2 doorways through the wall between the room
; and a bordering corridor cell, one pass per side. (Direct port of
; PFConnectRooms.)
; ============================================================
PFacConnectRooms:
    xor a
    ld [wBuffer + wPFacRoomIdx], a

.roomLoop
    ld a, [wBuffer + wPFacRoomIdx]
    ld hl, wBuffer + wPFacRoomCount
    cp [hl]
    ret nc

    ld a, [wBuffer + wPFacRoomIdx]
    add a, a
    add a, a
    ld e, a
    ld d, 0
    ld hl, sProcFacilityGenScratch
    add hl, de
    ld a, [hli]
    ld [wBuffer + wPFacRoomCol], a
    ld a, [hli]
    ld [wBuffer + wPFacRoomRow], a
    ld a, [hli]
    ld [wBuffer + wPFacRoomW], a
    ld a, [hl]
    ld [wBuffer + wPFacRoomH], a

    xor a
    ld [wBuffer + wPFacDoorCount], a

    ; --- North side (row > 0) ---
    ld a, [wBuffer + wPFacRoomRow]
    and a
    jr z, .noNorth
    ld a, [wBuffer + wPFacDoorCount]
    cp 2
    jr nc, .noNorth

    ld a, [wBuffer + wPFacRoomCol]
    ld b, a
    ld c, a
    ld a, [wBuffer + wPFacRoomW]
    dec a
    add a, c
    ld [wBuffer + wPFacSideBound], a

.northLoop
    ld a, b
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRoomRow]
    add a, a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_WALL
    jr nz, .northNext

    ld a, [wBuffer + wPFacCurY]
    dec a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_WALL
    jr z, .northNext

    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacPickFloor
    call PFacWriteBlock
    ld a, [wBuffer + wPFacDoorCount]
    inc a
    ld [wBuffer + wPFacDoorCount], a
    cp 2
    jr nc, .noNorth

.northNext
    ld a, [wBuffer + wPFacSideBound]
    cp b
    jr z, .noNorth
    inc b
    jr .northLoop
.noNorth

    ; --- South side (row+h < 9) ---
    ld a, [wBuffer + wPFacRoomRow]
    ld c, a
    ld a, [wBuffer + wPFacRoomH]
    add a, c
    cp PFAC_CELL_H
    jr nc, .noSouth
    ld a, [wBuffer + wPFacDoorCount]
    cp 2
    jr nc, .noSouth

    ld a, [wBuffer + wPFacRoomCol]
    ld b, a
    ld c, a
    ld a, [wBuffer + wPFacRoomW]
    dec a
    add a, c
    ld [wBuffer + wPFacSideBound], a

.southLoop
    ld a, b
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRoomRow]
    ld c, a
    ld a, [wBuffer + wPFacRoomH]
    add a, c
    add a, a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_WALL
    jr nz, .southNext

    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_WALL
    jr z, .southNext

    ld a, [wBuffer + wPFacCurY]
    dec a
    ld [wBuffer + wPFacCurY], a
    call PFacPickFloor
    call PFacWriteBlock
    ld a, [wBuffer + wPFacDoorCount]
    inc a
    ld [wBuffer + wPFacDoorCount], a
    cp 2
    jr nc, .noSouth

.southNext
    ld a, [wBuffer + wPFacSideBound]
    cp b
    jr z, .noSouth
    inc b
    jr .southLoop
.noSouth

    ; --- West side (col > 0) ---
    ld a, [wBuffer + wPFacRoomCol]
    and a
    jr z, .noWest
    ld a, [wBuffer + wPFacDoorCount]
    cp 2
    jr nc, .noWest

    ld a, [wBuffer + wPFacRoomRow]
    ld b, a
    ld c, a
    ld a, [wBuffer + wPFacRoomH]
    dec a
    add a, c
    ld [wBuffer + wPFacSideBound], a

.westLoop
    ld a, b
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRoomCol]
    add a, a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_WALL
    jr nz, .westNext

    ld a, [wBuffer + wPFacCurX]
    dec a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_WALL
    jr z, .westNext

    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    call PFacPickFloor
    call PFacWriteBlock
    ld a, [wBuffer + wPFacDoorCount]
    inc a
    ld [wBuffer + wPFacDoorCount], a
    cp 2
    jr nc, .noWest

.westNext
    ld a, [wBuffer + wPFacSideBound]
    cp b
    jr z, .noWest
    inc b
    jr .westLoop
.noWest

    ; --- East side (col+w < 9) ---
    ld a, [wBuffer + wPFacRoomCol]
    ld c, a
    ld a, [wBuffer + wPFacRoomW]
    add a, c
    cp PFAC_CELL_W
    jr nc, .noEast
    ld a, [wBuffer + wPFacDoorCount]
    cp 2
    jr nc, .noEast

    ld a, [wBuffer + wPFacRoomRow]
    ld b, a
    ld c, a
    ld a, [wBuffer + wPFacRoomH]
    dec a
    add a, c
    ld [wBuffer + wPFacSideBound], a

.eastLoop
    ld a, b
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRoomCol]
    ld c, a
    ld a, [wBuffer + wPFacRoomW]
    add a, c
    add a, a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_WALL
    jr nz, .eastNext

    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_WALL
    jr z, .eastNext

    ld a, [wBuffer + wPFacCurX]
    dec a
    ld [wBuffer + wPFacCurX], a
    call PFacPickFloor
    call PFacWriteBlock
    ld a, [wBuffer + wPFacDoorCount]
    inc a
    ld [wBuffer + wPFacDoorCount], a
    cp 2
    jr nc, .noEast

.eastNext
    ld a, [wBuffer + wPFacSideBound]
    cp b
    jr z, .noEast
    inc b
    jr .eastLoop
.noEast

    ld a, [wBuffer + wPFacRoomIdx]
    inc a
    ld [wBuffer + wPFacRoomIdx], a
    jp .roomLoop

; ============================================================
; PFacGenerateRoomsDungeon
; Rooms/Dungeon layout: place rooms, fill the rest with corridor, connect.
; ============================================================
PFacGenerateRoomsDungeon:
    call PFacPlaceRooms
    call PFacCarveEntranceRoom     ; guaranteed room at the spawn so prune can't
                                   ; isolate the entrance (a multi-cell room is
                                   ; never a dead end and stays connected)
    call PFacHuntAndKill
    call PFacConnectRooms
    call PFacPruneDeadEnds
    ret

; ============================================================
; PFacCarveEntranceRoom
; Carve a small floor room (blocks 7..9 x 15..17 = cells col 3-4, row 7-8)
; around the fixed entrance cell (4,8) = block (9,17), and register it in
; sProcFacilityGenScratch's room list (col=3,row=7,w=2,h=2) exactly like a
; PFacPlaceRooms room, so PFacConnectRooms treats it identically and
; guarantees it a doorway. Without this registration the entrance was floor
; but had NO guaranteed connection - HuntAndKill's initial walk step only
; carves outward opportunistically, so the entrance could end up fully
; walled off with no path out (confirmed bug: "trapped, no connection to
; the room I spawned in").
; ============================================================
PFacCarveEntranceRoom:
    ld a, 15
    ld [wBuffer + wPFacCurY], a
.rowLoop
    ld a, 7
    ld [wBuffer + wPFacCurX], a
.colLoop
    ld a, PFAC_FLOOR
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    cp 10
    jr c, .colLoop
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    cp 18
    jr c, .rowLoop

    ; Register as room (col=3, row=7, w=2, h=2) so PFacConnectRooms guarantees
    ; it a doorway, same append format as PFacPlaceRooms uses.
    ld a, [wBuffer + wPFacRoomCount]
    add a, a
    add a, a
    ld e, a
    ld d, 0
    ld hl, sProcFacilityGenScratch
    add hl, de
    ld a, 3
    ld [hli], a                 ; col
    ld a, 7
    ld [hli], a                 ; row
    ld a, 2
    ld [hli], a                 ; w
    ld a, 2
    ld [hl], a                  ; h
    ld a, [wBuffer + wPFacRoomCount]
    inc a
    ld [wBuffer + wPFacRoomCount], a
    ret

; ============================================================
; PFacPruneDeadEnds  (hauberk's dead-end removal)
; Iteratively refill dead-end corridor cells - floor cells with exactly ONE
; open passage - back to solid wall, until a full sweep changes nothing. Rooms
; and through-corridors have >=2 passages so they survive; only stub corridors
; vanish, leaving rooms + minimal connecting corridors in a solid-wall field.
; Runs on the 9x9 cell grid BEFORE autotiling (walls are still PFAC_WALL/floor).
; The entrance/exit are re-carved afterward in PFacFinalize, so no cell needs
; protection here.
; ============================================================
PFacPruneDeadEnds:
.sweep
    xor a
    ld [wBuffer + wPFacPruneChanged], a
    ld [wBuffer + wPFacPruneRow], a
.rowLoop
    xor a
    ld [wBuffer + wPFacPruneCol], a
.colLoop
    ; Is this cell floor?
    ld a, [wBuffer + wPFacPruneCol]
    ld [wBuffer + wPFacCellCol], a
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacPruneRow]
    ld [wBuffer + wPFacCellRow], a
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .next

    ; Count open passages around it (wPFacCellCol/Row already set).
    xor a
    ld [wBuffer + wPFacPassCount], a
    ld a, [wBuffer + wPFacPruneRow]
    and a
    jr z, .pNoN
    dec a
    ld b, a
    ld a, [wBuffer + wPFacPruneCol]
    ld c, a
    call PFacScanWallPassOnly
.pNoN
    ld a, [wBuffer + wPFacPruneRow]
    cp 8
    jr nc, .pNoS
    inc a
    ld b, a
    ld a, [wBuffer + wPFacPruneCol]
    ld c, a
    call PFacScanWallPassOnly
.pNoS
    ld a, [wBuffer + wPFacPruneCol]
    and a
    jr z, .pNoW
    ld a, [wBuffer + wPFacPruneRow]
    ld b, a
    ld a, [wBuffer + wPFacPruneCol]
    dec a
    ld c, a
    call PFacScanWallPassOnly
.pNoW
    ld a, [wBuffer + wPFacPruneCol]
    cp 8
    jr nc, .pNoE
    ld a, [wBuffer + wPFacPruneRow]
    ld b, a
    ld a, [wBuffer + wPFacPruneCol]
    inc a
    ld c, a
    call PFacScanWallPassOnly
.pNoE
    ld a, [wBuffer + wPFacPassCount]
    cp 1
    jr nz, .next                ; not a dead end
    call PFacUncarveDeadEnd
    ld a, 1
    ld [wBuffer + wPFacPruneChanged], a

.next
    ld a, [wBuffer + wPFacPruneCol]
    inc a
    ld [wBuffer + wPFacPruneCol], a
    cp PFAC_CELL_W
    jr c, .colLoop
    ld a, [wBuffer + wPFacPruneRow]
    inc a
    ld [wBuffer + wPFacPruneRow], a
    cp PFAC_CELL_H
    jp c, .rowLoop
    ld a, [wBuffer + wPFacPruneChanged]
    and a
    jp nz, .sweep
    ret

; ============================================================
; PFacUncarveDeadEnd
; Refill the current prune cell (wPFacPruneCol/Row) AND its single open passage
; wall back to PFAC_WALL. Called only when the cell has exactly 1 passage, so
; exactly one of the 4 walls is floor; the others are already wall.
; ============================================================
PFacUncarveDeadEnd:
    ld a, [wBuffer + wPFacPruneCol]
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacPruneRow]
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_WALL
    call PFacWriteBlock

    ; North wall (2col+1, 2row)
    ld a, [wBuffer + wPFacPruneRow]
    and a
    jr z, .noN
    ld a, [wBuffer + wPFacPruneCol]
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacPruneRow]
    add a, a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_WALL
    jr z, .noN
    ld a, PFAC_WALL
    call PFacWriteBlock
.noN
    ; South wall (2col+1, 2row+2)
    ld a, [wBuffer + wPFacPruneRow]
    cp 8
    jr nc, .noS
    ld a, [wBuffer + wPFacPruneCol]
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacPruneRow]
    add a, a
    add a, 2
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_WALL
    jr z, .noS
    ld a, PFAC_WALL
    call PFacWriteBlock
.noS
    ; West wall (2col, 2row+1)
    ld a, [wBuffer + wPFacPruneCol]
    and a
    jr z, .noW
    ld a, [wBuffer + wPFacPruneCol]
    add a, a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacPruneRow]
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_WALL
    jr z, .noW
    ld a, PFAC_WALL
    call PFacWriteBlock
.noW
    ; East wall (2col+2, 2row+1)
    ld a, [wBuffer + wPFacPruneCol]
    cp 8
    jr nc, .noE
    ld a, [wBuffer + wPFacPruneCol]
    add a, a
    add a, 2
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacPruneRow]
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_WALL
    jr z, .noE
    ld a, PFAC_WALL
    call PFacWriteBlock
.noE
    ret

; ============================================================
; PFacGenerateGrid  (PowerPlant / green path)
; Partition the 1..18 interior into a coarse rows x cols grid (each 2 or 3) of
; big rectangular rooms separated by a 1-block solid-wall band, and punch one
; 1-block doorway between each spanning-tree-adjacent room pair. No maze, no
; prune - the space between rooms is left as solid wall (46). Connectivity is
; guaranteed by construction (grid graph, spanning tree of doorways).
; ============================================================
PFacGenerateGrid:
    ld c, 2
    call Rangerandom
    add a, 2                        ; 2 or 3 rows
    ld [wBuffer + wPFacGridRows], a
    ld c, 2
    call Rangerandom
    add a, 2                        ; 2 or 3 cols
    ld [wBuffer + wPFacGridCols], a

    ; Fill every grid room with floor.
    xor a
    ld [wBuffer + wPFacGridR], a
.fillRowLoop
    xor a
    ld [wBuffer + wPFacGridC], a
.fillColLoop
    call PFacFillGridRoom
    ld a, [wBuffer + wPFacGridC]
    inc a
    ld [wBuffer + wPFacGridC], a
    ld hl, wBuffer + wPFacGridCols
    cp [hl]
    jr c, .fillColLoop
    ld a, [wBuffer + wPFacGridR]
    inc a
    ld [wBuffer + wPFacGridR], a
    ld hl, wBuffer + wPFacGridRows
    cp [hl]
    jr c, .fillRowLoop

    ; Horizontal doorways: within each row, connect col c to col c-1.
    xor a
    ld [wBuffer + wPFacGridR], a
.hRowLoop
    ld a, 1
    ld [wBuffer + wPFacGridC], a
.hColLoop
    ld a, [wBuffer + wPFacGridC]
    ld hl, wBuffer + wPFacGridCols
    cp [hl]
    jr nc, .hRowNext
    call PFacPunchHDoor
    ld a, [wBuffer + wPFacGridC]
    inc a
    ld [wBuffer + wPFacGridC], a
    jr .hColLoop
.hRowNext
    ld a, [wBuffer + wPFacGridR]
    inc a
    ld [wBuffer + wPFacGridR], a
    ld hl, wBuffer + wPFacGridRows
    cp [hl]
    jr c, .hRowLoop

    ; Vertical doorways: down column 0, connect row r to row r-1.
    ld a, 1
    ld [wBuffer + wPFacGridR], a
.vRowLoop
    ld a, [wBuffer + wPFacGridR]
    ld hl, wBuffer + wPFacGridRows
    cp [hl]
    ret nc
    call PFacPunchVDoor
    ld a, [wBuffer + wPFacGridR]
    inc a
    ld [wBuffer + wPFacGridR], a
    jr .vRowLoop

; INPUT: b = nDim (2 or 3), c = index (0..nDim-1)
; OUTPUT: d = room start block, e = room end block (inclusive)
PFacGridBounds:
    ld a, b
    cp 2
    jr z, .use2
    ld hl, PFacGridBounds3
    jr .index
.use2
    ld hl, PFacGridBounds2
.index
    ld a, c
    add a, a                        ; index*2
    add a, l
    ld l, a
    jr nc, .noCarry
    inc h
.noCarry
    ld a, [hli]
    ld d, a
    ld a, [hl]
    ld e, a
    ret

; (start,end) block ranges per room; a 1-block wall sits in the gaps (9; 6,12).
PFacGridBounds2: db 1, 8, 10, 18
PFacGridBounds3: db 1, 5, 7, 11, 13, 18

; Fill room (wPFacGridR, wPFacGridC) with floor.
PFacFillGridRoom:
    ld a, [wBuffer + wPFacGridCols]
    ld b, a
    ld a, [wBuffer + wPFacGridC]
    ld c, a
    call PFacGridBounds             ; d=x0, e=x1
    ld a, d
    ld [wBuffer + wPFacGridX0], a
    ld a, e
    ld [wBuffer + wPFacGridX1], a
    ld a, [wBuffer + wPFacGridRows]
    ld b, a
    ld a, [wBuffer + wPFacGridR]
    ld c, a
    call PFacGridBounds             ; d=y0, e=y1
    ld a, d
    ld [wBuffer + wPFacGridY0], a
    ld a, e
    ld [wBuffer + wPFacGridY1], a

    ld a, [wBuffer + wPFacGridY0]
    ld [wBuffer + wPFacCurY], a
.rowF
    ld a, [wBuffer + wPFacGridX0]
    ld [wBuffer + wPFacCurX], a
.colF
    ld a, PFAC_FLOOR
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacGridX1
    cp [hl]
    jr z, .colDone
    inc a
    ld [wBuffer + wPFacCurX], a
    jr .colF
.colDone
    ld a, [wBuffer + wPFacCurY]
    ld hl, wBuffer + wPFacGridY1
    cp [hl]
    ret z
    inc a
    ld [wBuffer + wPFacCurY], a
    jr .rowF

; Punch a doorway between room (gridR, gridC-1) and (gridR, gridC): a single
; floor block in the wall column just left of room gridC, at a random row in
; room gridR's Y range.
PFacPunchHDoor:
    ld a, [wBuffer + wPFacGridCols]
    ld b, a
    ld a, [wBuffer + wPFacGridC]
    ld c, a
    call PFacGridBounds             ; d = startX[gridC]
    ld a, d
    dec a
    ld [wBuffer + wPFacCurX], a      ; wall column = startX - 1
    ld a, [wBuffer + wPFacGridRows]
    ld b, a
    ld a, [wBuffer + wPFacGridR]
    ld c, a
    call PFacGridBounds             ; d=startY, e=endY
    ld a, e
    sub d
    inc a
    ld c, a                          ; count = endY-startY+1
    push de
    call Rangerandom                 ; a = 0..count-1
    pop de
    add a, d                         ; row = startY + offset
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_FLOOR
    call PFacWriteBlock
    ret

; Punch a doorway between room (gridR-1, 0) and (gridR, 0): a single floor block
; in the wall row just above room gridR, at a random col in room col 0's X range.
PFacPunchVDoor:
    ld a, [wBuffer + wPFacGridRows]
    ld b, a
    ld a, [wBuffer + wPFacGridR]
    ld c, a
    call PFacGridBounds             ; d = startY[gridR]
    ld a, d
    dec a
    ld [wBuffer + wPFacCurY], a      ; wall row = startY - 1
    ld a, [wBuffer + wPFacGridCols]
    ld b, a
    ld c, 0
    call PFacGridBounds             ; d=startX[0], e=endX[0]
    ld a, e
    sub d
    inc a
    ld c, a
    push de
    call Rangerandom
    pop de
    add a, d
    ld [wBuffer + wPFacCurX], a
    ld a, PFAC_FLOOR
    call PFacWriteBlock
    ret

; ============================================================
; PFacCarveExit  (both generators)
; Pick an exit block column whose row-1 block is ALREADY floor (a room/corridor
; that reaches the top), then carve only the top-edge opening at (exitX, 0).
; (exitX, 1) is already floor, so the exit joins the connected room network
; without tunnelling through - and never destroys a wall column. Since all
; surviving floor is one connected component, the exit always connects to the
; entrance. Stores exitX in sProcFacilityExitI. Runs BEFORE autotile.
; ============================================================
PFacCarveExit:
    ld a, 24
    ld [wBuffer + wPFacGridR], a     ; rejection-sample retry budget
.tryCol
    ld c, 18
    call Rangerandom                ; 0..17
    inc a                           ; candidate exitX 1..18
    ld [wBuffer + wPFacGridC], a
    ld [wBuffer + wPFacCurX], a
    ld a, 1
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr z, .found
    ld a, [wBuffer + wPFacGridR]
    dec a
    ld [wBuffer + wPFacGridR], a
    jr nz, .tryCol
    ; Fallback: first floor column found scanning row 1 left to right.
    ld a, 1
    ld [wBuffer + wPFacGridC], a
.scanFallback
    ld a, [wBuffer + wPFacGridC]
    ld [wBuffer + wPFacCurX], a
    ld a, 1
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr z, .found
    ld a, [wBuffer + wPFacGridC]
    inc a
    ld [wBuffer + wPFacGridC], a
    cp 19
    jr c, .scanFallback
    ld a, 9                          ; ultimate fallback (shouldn't happen)
    ld [wBuffer + wPFacGridC], a
.found
    ld a, [wBuffer + wPFacGridC]
    ld [sProcFacilityExitI], a
    ld [wBuffer + wPFacCurX], a
    xor a
    ld [wBuffer + wPFacCurY], a      ; opening at (exitX, 0)
    ld a, PFAC_FLOOR
    call PFacWriteBlock
    ret

; ============================================================
; PFacClassifyWall  (step 6)
; INPUT: wPFacCurX/Y = a wall-sentinel cell to classify.
; OUTPUT: a = the block to write there:
;   - a directional wall/corner (straight edge or a corner) if the cell borders
;     floor in a shape a half-height wall can represent;
;   - PFAC_PENDING if the cell should dissolve into floor (3+ orthogonal floor
;     sides, or floor on two opposite sides - no half-wall represents that, so
;     merge, same reasoning as the cave's peninsula rule);
;   - PFAC_WALL unchanged if no nearby floor gives it a meaning (handled by the
;     second pass, which floors it).
; Floor test is `== PFAC_FLOOR` so already-classified walls/pending sentinels
; written earlier in the same pass are NOT mistaken for floor (cascade-safe).
; wPFacCurX/Y restored before returning. Clobbers wPFacDX/DY/Flags/Diag, b, c.
; ============================================================
PFacClassifyWall:
    ld a, [wBuffer + wPFacCurX]
    ld [wBuffer + wPFacDX], a
    ld a, [wBuffer + wPFacCurY]
    ld [wBuffer + wPFacDY], a
    xor a
    ld [wBuffer + wPFacFlags], a

    ; north (y-1)
    ld a, [wBuffer + wPFacDY]
    and a
    jr z, .skN
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .skN
    ld a, [wBuffer + wPFacFlags]
    or 1
    ld [wBuffer + wPFacFlags], a
.skN
    ; south (y+1)
    ld a, [wBuffer + wPFacDY]
    cp PFAC_SIZE - 1
    jr z, .skS
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .skS
    ld a, [wBuffer + wPFacFlags]
    or 2
    ld [wBuffer + wPFacFlags], a
.skS
    ; east (x+1)
    ld a, [wBuffer + wPFacDX]
    cp PFAC_SIZE - 1
    jr z, .skE
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .skE
    ld a, [wBuffer + wPFacFlags]
    or 4
    ld [wBuffer + wPFacFlags], a
.skE
    ; west (x-1)
    ld a, [wBuffer + wPFacDX]
    and a
    jr z, .skW
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .skW
    ld a, [wBuffer + wPFacFlags]
    or 8
    ld [wBuffer + wPFacFlags], a
.skW
    ; restore cell coords (used by the caller's write, and by diagonal reads)
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a

    ld a, [wBuffer + wPFacFlags]
    ld b, a                     ; b = ortho mask

    ; count set bits -> c
    ld c, 0
    bit 0, b
    jr z, .cN
    inc c
.cN
    bit 1, b
    jr z, .cS
    inc c
.cS
    bit 2, b
    jr z, .cE
    inc c
.cE
    bit 3, b
    jr z, .cW
    inc c
.cW
    ld a, c
    cp 3
    jr nc, .dissolve            ; 3 or 4 floor sides -> merge to floor (peninsula)

    ; Floor on two OPPOSITE sides = a solid 1-block wall between two rooms /
    ; parallel corridors. A half-height directional block can only face ONE
    ; side, so it can't represent this - keep it SOLID (block 46). This is the
    ; hauberk/PowerPlant model: space between rooms/corridors stays solid wall.
    ld a, b
    cp %0011                    ; north+south
    jr z, .keepSolid
    cp %1100                    ; east+west
    jr z, .keepSolid

    ld a, c
    cp 2
    jr z, .twoAdj
    and a
    jr z, .zeroOrtho

    ; exactly one orthogonal floor side -> straight wall
    bit 0, b
    jr z, .not1N
    ld a, PFAC_W_BOTTOM         ; floor N
    ret
.not1N
    bit 1, b
    jr z, .not1S
    ld a, PFAC_W_TOP            ; floor S
    ret
.not1S
    bit 2, b
    jr z, .not1E
    ld a, PFAC_W_LEFT          ; floor E
    ret
.not1E
    ld a, PFAC_W_RIGHT         ; floor W
    ret

.twoAdj
    ld a, b
    cp %0101                    ; N+E
    jr nz, .notNE
    ld a, PFAC_C_BL             ; floor NE
    ret
.notNE
    cp %1001                    ; N+W
    jr nz, .notNW
    ld a, PFAC_C_BR             ; floor NW
    ret
.notNW
    cp %0110                    ; S+E
    jr nz, .notSE
    ld a, PFAC_C_TL             ; floor SE
    ret
.notSE
    ld a, PFAC_C_TR             ; S+W -> floor SW
    ret

.dissolve
    ld a, PFAC_PENDING
    ret

.keepSolid
    ld a, PFAC_WALL             ; stays solid interior wall (46)
    ret

.zeroOrtho
    ; No orthogonal floor. A room's outer corner post has floor only diagonally;
    ; give it the matching corner block. Any other diagonal pattern is left for
    ; the second pass to floor.
    xor a
    ld [wBuffer + wPFacDiag], a
    ; NE (x+1, y-1)
    ld a, [wBuffer + wPFacDX]
    cp PFAC_SIZE - 1
    jr z, .dSkNE
    ld a, [wBuffer + wPFacDY]
    and a
    jr z, .dSkNE
    ld a, [wBuffer + wPFacDX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    dec a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .dSkNE
    ld a, [wBuffer + wPFacDiag]
    or 1
    ld [wBuffer + wPFacDiag], a
.dSkNE
    ; NW (x-1, y-1)
    ld a, [wBuffer + wPFacDX]
    and a
    jr z, .dSkNW
    ld a, [wBuffer + wPFacDY]
    and a
    jr z, .dSkNW
    ld a, [wBuffer + wPFacDX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    dec a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .dSkNW
    ld a, [wBuffer + wPFacDiag]
    or 2
    ld [wBuffer + wPFacDiag], a
.dSkNW
    ; SE (x+1, y+1)
    ld a, [wBuffer + wPFacDX]
    cp PFAC_SIZE - 1
    jr z, .dSkSE
    ld a, [wBuffer + wPFacDY]
    cp PFAC_SIZE - 1
    jr z, .dSkSE
    ld a, [wBuffer + wPFacDX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .dSkSE
    ld a, [wBuffer + wPFacDiag]
    or 4
    ld [wBuffer + wPFacDiag], a
.dSkSE
    ; SW (x-1, y+1)
    ld a, [wBuffer + wPFacDX]
    and a
    jr z, .dSkSW
    ld a, [wBuffer + wPFacDY]
    cp PFAC_SIZE - 1
    jr z, .dSkSW
    ld a, [wBuffer + wPFacDX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .dSkSW
    ld a, [wBuffer + wPFacDiag]
    or 8
    ld [wBuffer + wPFacDiag], a
.dSkSW
    ; restore cell coords
    ld a, [wBuffer + wPFacDX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDY]
    ld [wBuffer + wPFacCurY], a

    ld a, [wBuffer + wPFacDiag]
    cp 4                        ; only SE
    jr nz, .notDSE
    ld a, PFAC_C_TL
    ret
.notDSE
    cp 8                        ; only SW
    jr nz, .notDSW
    ld a, PFAC_C_TR
    ret
.notDSW
    cp 1                        ; only NE
    jr nz, .notDNE
    ld a, PFAC_C_BL
    ret
.notDNE
    cp 2                        ; only NW
    jr nz, .notDNW
    ld a, PFAC_C_BR
    ret
.notDNW
    ld a, PFAC_WALL             ; nothing meaningful -> leave for pass 2
    ret

; ============================================================
; PFacAutotilePass  (step 6)
; Pass 1: classify every wall-sentinel cell into a directional wall (or a
; PENDING/leave marker). Pass 2: convert only PENDING -> floor; leftover
; PFAC_WALL (46) STAYS as the solid interior wall (hauberk/PowerPlant model -
; the space between rooms/corridors is solid, same block as the map border).
; ============================================================
PFacAutotilePass:
    ; --- Pass 1 ---
    xor a
    ld [wBuffer + wPFacLoopY], a
.p1Y
    xor a
    ld [wBuffer + wPFacLoopX], a
.p1X
    ld a, [wBuffer + wPFacLoopX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacLoopY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_WALL
    jr nz, .p1Next
    call PFacClassifyWall       ; a = result; wPFacCurX/Y still = this cell
    call PFacWriteBlock
.p1Next
    ld a, [wBuffer + wPFacLoopX]
    inc a
    ld [wBuffer + wPFacLoopX], a
    cp PFAC_SIZE
    jr nz, .p1X
    ld a, [wBuffer + wPFacLoopY]
    inc a
    ld [wBuffer + wPFacLoopY], a
    cp PFAC_SIZE
    jr nz, .p1Y

    ; --- Pass 2 ---
    xor a
    ld [wBuffer + wPFacLoopY], a
.p2Y
    xor a
    ld [wBuffer + wPFacLoopX], a
.p2X
    ld a, [wBuffer + wPFacLoopX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacLoopY]
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_PENDING
    jr nz, .p2Next             ; leftover PFAC_WALL (46) stays SOLID interior wall
    ld a, PFAC_FLOOR
    call PFacWriteBlock
.p2Next
    ld a, [wBuffer + wPFacLoopX]
    inc a
    ld [wBuffer + wPFacLoopX], a
    cp PFAC_SIZE
    jr nz, .p2X
    ld a, [wBuffer + wPFacLoopY]
    inc a
    ld [wBuffer + wPFacLoopY], a
    cp PFAC_SIZE
    jr nz, .p2Y
    ret

; ============================================================
; PFacAbs - a = |a| (two's complement). Port of PFAbs.
; ============================================================
PFacAbs:
    bit 7, a
    ret z
    cpl
    inc a
    ret

; ============================================================
; PFacScanWallPassOnly
; Counts a passage if the wall between the current cell (wPFacCellCol/Row) and
; neighbor (B=row, C=col) is carved (floor, i.e. != PFAC_WALL). Preserves B, C.
; MUST run before the autotile pass, while walls are still the sentinel.
; ============================================================
PFacScanWallPassOnly:
    push bc
    ld a, [wBuffer + wPFacCellCol]
    add a, c
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacCellRow]
    add a, b
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    pop bc
    cp PFAC_WALL
    ret z                   ; wall = no passage
    ld a, [wBuffer + wPFacPassCount]
    inc a
    ld [wBuffer + wPFacPassCount], a
    ret

; ============================================================
; PFacScanForBall
; Places 4 pokeballs in distinct, well-spaced floor cells with item dedup.
; Phase 1 collects every floor cell into sProcFacilityGenScratch; Phase 2 picks
; 4 with Chebyshev spacing + item-ID dedup. Leaves accepted block coords in
; sProcFacilityGenScratch[0..7] (X,Y interleaved) and rolled items in
; wPFacItemTemp[0..3]; the bake step copies both into SRAM. Run BEFORE autotile.
; ============================================================
PFacScanForBall:
    ; --- Phase 1: collect FLOOR cells as ball candidates ---
    ; (Post-prune / grid there are no dead ends, so every room/corridor floor
    ; cell is a candidate; Phase 2's spacing spreads the 4 balls out.)
    xor a
    ld [wBuffer + wPFacCandCount], a
    ld [wBuffer + wPFacRowJ], a

.row
    xor a
    ld [wBuffer + wPFacBraidCol], a

.col
    ; read cell block (2*col+1, 2*row+1)
    ld a, [wBuffer + wPFacBraidCol]
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRowJ]
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a
    call PFacReadBlock
    cp PFAC_FLOOR
    jr nz, .collectNext        ; only floor cells are candidates

    ld a, [wBuffer + wPFacCandCount]
    cp PFAC_MAX_DEADENDS
    jr nc, .collectNext        ; list full
    ld e, a
    ld d, 0
    ld hl, sProcFacilityGenScratch
    add hl, de
    ld a, [wBuffer + wPFacRowJ]
    swap a
    ld b, a
    ld a, [wBuffer + wPFacBraidCol]
    or b
    ld [hl], a                 ; packed col | row<<4
    ld a, [wBuffer + wPFacCandCount]
    inc a
    ld [wBuffer + wPFacCandCount], a

.collectNext
    ld a, [wBuffer + wPFacBraidCol]
    inc a
    ld [wBuffer + wPFacBraidCol], a
    cp PFAC_CELL_W
    jp nz, .col

    ld a, [wBuffer + wPFacRowJ]
    inc a
    ld [wBuffer + wPFacRowJ], a
    cp PFAC_CELL_H
    jp nz, .row

    ; --- Phase 2: pick 4 balls with spacing + item dedup ---
    ld a, [wBuffer + wPFacCandCount]
    and a
    jp z, .allFallback

    xor a
    ld [wBuffer + wPFacBallIdx], a

.pickBall
    ld a, 20
    ld [wBuffer + wPFacSpaceRetry], a

.spaceRetry
    ld a, [wBuffer + wPFacCandCount]
    ld c, a
    call Rangerandom
    ld e, a
    ld d, 0
    ld hl, sProcFacilityGenScratch
    add hl, de
    ld a, [hl]
    ld b, a
    and $0F
    add a, a
    inc a
    ld [wBuffer + wPFacCurX], a   ; block X = 2*col+1
    ld a, b
    swap a
    and $0F
    add a, a
    inc a
    ld [wBuffer + wPFacCurY], a   ; block Y = 2*row+1

    ld a, [wBuffer + wPFacBallIdx]
    and a
    jr z, .spaceOK
    ld b, a
    ld hl, wBuffer + wPFacAcceptedXY
.spaceCheckLoop
    ld a, [wBuffer + wPFacCurX]
    sub [hl]
    call PFacAbs
    ld c, a
    inc hl
    ld a, [wBuffer + wPFacCurY]
    sub [hl]
    call PFacAbs
    inc hl
    cp c
    jr nc, .haveMax
    ld a, c
.haveMax
    srl a                       ; block Chebyshev -> cell units
    cp PFAC_ITEM_MIN_DIST
    jr c, .spaceFail
    dec b
    jr nz, .spaceCheckLoop
.spaceOK
    jr .acceptPos
.spaceFail
    ld a, [wBuffer + wPFacSpaceRetry]
    dec a
    ld [wBuffer + wPFacSpaceRetry], a
    jr nz, .spaceRetry
.acceptPos
    ld a, [wBuffer + wPFacBallIdx]
    add a, a
    ld e, a
    ld d, 0
    ld hl, wBuffer + wPFacAcceptedXY
    add hl, de
    ld a, [wBuffer + wPFacCurX]
    ld [hli], a
    ld a, [wBuffer + wPFacCurY]
    ld [hl], a

    ; roll this ball's item, rejecting an exact duplicate of an earlier one
    ld a, 8
    ld [wBuffer + wPFacItemRetry], a
.rollItem
    ld c, 4
    call Rangerandom
    ld [wRogueDoorSelection], a
    farcall Random_Item_Selection
    ld a, [wBuffer + wPFacBallIdx]
    and a
    jr z, .itemOK
    ld b, a
    ld hl, wBuffer + wPFacItemTemp
    ld a, [wRogueItem]
    ld c, a
.itemDupCheck
    ld a, [hli]
    cp c
    jr z, .itemDup
    dec b
    jr nz, .itemDupCheck
    jr .itemOK
.itemDup
    ld a, [wBuffer + wPFacItemRetry]
    dec a
    ld [wBuffer + wPFacItemRetry], a
    jr nz, .rollItem
.itemOK
    ld a, [wBuffer + wPFacBallIdx]
    ld c, a
    ld b, 0
    ld hl, wBuffer + wPFacItemTemp
    add hl, bc
    ld a, [wRogueItem]
    ld [hl], a

    ld a, [wBuffer + wPFacBallIdx]
    inc a
    ld [wBuffer + wPFacBallIdx], a
    cp 4
    jp nz, .pickBall

    ; copy accepted (X,Y) into sProcFacilityGenScratch[0..7]
    ld hl, wBuffer + wPFacAcceptedXY
    ld de, sProcFacilityGenScratch
    ld b, 8
.copyXY
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .copyXY
    ret

.allFallback
    ; No dead ends: default every ball to the entrance block (9,17).
    ld hl, sProcFacilityGenScratch
    ld b, 4
.fallbackLoop
    ld a, 9
    ld [hli], a
    ld a, 17
    ld [hli], a
    dec b
    jr nz, .fallbackLoop
    xor a
    ld [wBuffer + wPFacBallIdx], a
.fallbackItemLoop
    ld a, 8
    ld [wBuffer + wPFacItemRetry], a
.fallbackRollItem
    ld c, 4
    call Rangerandom
    ld [wRogueDoorSelection], a
    farcall Random_Item_Selection
    ld a, [wBuffer + wPFacBallIdx]
    and a
    jr z, .fallbackItemOK
    ld b, a
    ld hl, wBuffer + wPFacItemTemp
    ld a, [wRogueItem]
    ld c, a
.fallbackDupCheck
    ld a, [hli]
    cp c
    jr z, .fallbackDup
    dec b
    jr nz, .fallbackDupCheck
    jr .fallbackItemOK
.fallbackDup
    ld a, [wBuffer + wPFacItemRetry]
    dec a
    ld [wBuffer + wPFacItemRetry], a
    jr nz, .fallbackRollItem
.fallbackItemOK
    ld a, [wBuffer + wPFacBallIdx]
    ld c, a
    ld b, 0
    ld hl, wBuffer + wPFacItemTemp
    add hl, bc
    ld a, [wRogueItem]
    ld [hl], a
    ld a, [wBuffer + wPFacBallIdx]
    inc a
    ld [wBuffer + wPFacBallIdx], a
    cp 4
    jr nz, .fallbackItemLoop
    ret

; ============================================================
; PFacRollMonClass
; Duplicate of PCRollMonClass/PFRollMonClass (takes rarity bump in B, so it
; can't be farcall'd - Bankswitch clobbers B). INPUT: b = rarity bump.
; OUTPUT: c = class 1-4. Clobbers a, d (b preserved).
; ============================================================
PFacRollMonClass:
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
    add a, b
    jr nc, .noShiftClamp
    ld a, 255
.noShiftClamp
    ld d, a
    call Random
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
; PFacRollBoss
; Rolls the facility boss species + OW sprite category, stores both to SRAM.
; Called from PFacPreload while SRAM is open. Same farcall rules as PFRollBoss.
; ============================================================
PFacRollBoss:
    farcall PCGetBossLevel           ; sets wCurEnemyLevel
    ld b, 60                         ; boss rarity bump (matches cave/forest)
    call PFacRollMonClass            ; c = rarity class (same-bank call)
    farcall Random_Pokemon_Selection ; -> d = species (survives farcall)
    ld a, d
    ld [wRoguePokemon1], a
    ld [sProcFacilityBossSpecies], a
    farcall PFacStoreBossOWSpriteToSRAM  ; stores SPRITE_* to sProcFacilityBossSprite
    ret

; ============================================================
; PFacPreload::  (step 5; boss roll wired in step 7)
; Called at Pallet Town entry. Resets bake flag + per-run SRAM state, rolls the
; palette variant and sign variant, and sets the wild budget. Mirrors
; PFPreloadForest minus the forest-specific bits.
; ============================================================
PFacPreload::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    ld a, BANK(sProcFacilityStagingBuffer)  ; facility SRAM is bank 1, NOT 0
    ld [rRAMB], a
    xor a
    ld [sProcFacilityBaked], a       ; 0 = needs fresh generation
    ld [sProcFacilityItemGot], a     ; clear ball-collected bits
    ld [sProcFacilityAlgoForce], a
    ld [sProcFacilityExitEdge], a    ; 0 = N (v1 ships north exit only)

    ; Roll the facility's own boss (species + OW sprite -> SRAM).
    call PFacRollBoss

    ; Roll palette variant: 0 = PowerPlant (green), 1 = Mansion (red).
    ; Read by SetPal_Overworld's FACILITY case (step 9).
    call Random
    and 1
    ld [sProcFacilityPalette], a

    ; Roll sign variant: 0 = items text, 1 = boss text.
    call Random
    and 1
    ld [sProcFacilitySignVariant], a

    ; Wild-battle budget: 10 + wBattleCount/5, saturating at 255 (cave formula).
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
    ld [wProcFacilityWildBudget], a

    ; Reset reused run events (shared cave events; facility never concurrent).
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
; PFacFinalize::  (steps 5-7)
; Called at PROCEDURAL_FACILITY warp-in.
;   First visit (sProcFacilityBaked=0): fill walls, generate Rooms/Dungeon,
;     scan for item dead-ends, autotile, carve the north exit, bake to SRAM,
;     stash exit column + ball positions/items in SRAM.
;   Re-entry (sProcFacilityBaked=1): fast-blit the staging buffer back.
;   Both paths then patch the exit warp entries and (re)place the boss + 4 ball
;     sprites from SRAM.
; SRAM is kept open through generation (RAMG/BMODE/RAMB only gate $A000-$BFFF,
; not WRAM), so sProcFacilityGenScratch is reachable during the carve.
; v1 ships a NORTH exit only (sProcFacilityExitEdge is always 0).
; ============================================================
PFacFinalize::
    ld a, RAMG_SRAM_ENABLE
    ld [rRAMG], a
    ld a, BMODE_ADVANCED
    ld [rBMODE], a
    ld a, BANK(sProcFacilityStagingBuffer)  ; facility SRAM is bank 1, NOT 0
    ld [rRAMB], a

    ld a, [sProcFacilityBaked]
    and a
    jp nz, .fastBlit

    ; === First visit: generate directly into wOverworldMap ===
    ld a, LOW(wOverworldMap + PFAC_BASE)
    ld [wBuffer + wPFacTargetBaseLo], a
    ld a, HIGH(wOverworldMap + PFAC_BASE)
    ld [wBuffer + wPFacTargetBaseHi], a

    call PFacFillWalls

    ; Branch generation on the palette variant (rolled at Pallet Town entry):
    ; 0 = PowerPlant/green -> grid of rooms; 1 = Mansion/red -> rooms + maze + prune.
    ld a, [sProcFacilityPalette]
    and a
    jr nz, .genDungeon
    call PFacGenerateGrid
    jr .genDone
.genDungeon
    call PFacGenerateRoomsDungeon
.genDone

    ; Entrance: guarantee the fixed spawn block (9,17) is floor and connected.
    ; The dungeon path already carves it; the grid path may leave it on a wall
    ; column, where carving it bridges the two adjacent bottom rooms.
    ld a, 9
    ld [wBuffer + wPFacCurX], a
    ld a, 17
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_FLOOR
    call PFacWriteBlock

    ; North exit: roll a block column, carve the opening + a short connector down
    ; to existing floor. Done BEFORE autotile so its corridor gets clean wall faces.
    call PFacCarveExit

    call PFacScanForBall            ; room-cell item scan (walls still sentinel 46)
    call PFacAutotilePass

    ; Save 4 ball positions as tile coords (Y,X order) to sProcFacilityBallXY.
    ; sProcFacilityGenScratch holds X0,Y0,X1,Y1,... block coords from the scan.
    ld hl, sProcFacilityBallXY
    ld de, sProcFacilityGenScratch
    ld b, 4
.ballSave
    ld a, [de]                      ; block X
    inc de
    add a, a
    add a, 4                        ; tile X = block*2+4
    ld c, a
    ld a, [de]                      ; block Y
    inc de
    add a, a
    add a, 4                        ; tile Y = block*2+4
    ld [hli], a                     ; store tile Y first
    ld a, c
    ld [hli], a                     ; then tile X
    dec b
    jr nz, .ballSave

    ; Save 4 rolled items (wPFacItemTemp) to sProcFacilityBallItems.
    ld hl, wBuffer + wPFacItemTemp
    ld de, sProcFacilityBallItems
    ld b, 4
.itemSave
    ld a, [hli]
    ld [de], a
    inc de
    dec b
    jr nz, .itemSave

    ; === Bake: copy wOverworldMap -> sProcFacilityStagingBuffer ===
    ld hl, wOverworldMap + PFAC_BASE
    ld de, sProcFacilityStagingBuffer + PFAC_BASE
    ld b, PFAC_SIZE
.bakeRowLoop
    push bc
    ld c, PFAC_SIZE
.bakeColLoop
    ld a, [hli]
    ld [de], a
    inc de
    dec c
    jr nz, .bakeColLoop
    ld a, l
    add a, PFAC_STRIDE - PFAC_SIZE
    ld l, a
    jr nc, .bakeNoCarryHL
    inc h
.bakeNoCarryHL
    ld a, e
    add a, PFAC_STRIDE - PFAC_SIZE
    ld e, a
    jr nc, .bakeNoCarryDE
    inc d
.bakeNoCarryDE
    pop bc
    dec b
    jr nz, .bakeRowLoop

    ld a, 1
    ld [sProcFacilityBaked], a
    jr .placeSprites

.fastBlit
    ; === Re-entry: blit SRAM staging buffer -> wOverworldMap ===
    ld hl, sProcFacilityStagingBuffer + PFAC_BASE
    ld de, wOverworldMap + PFAC_BASE
    ld b, PFAC_SIZE
.blitRowLoop
    push bc
    ld c, PFAC_SIZE
.blitColLoop
    ld a, [hli]
    ld [de], a
    inc de
    dec c
    jr nz, .blitColLoop
    ld a, l
    add a, PFAC_STRIDE - PFAC_SIZE
    ld l, a
    jr nc, .blitNoCarryHL
    inc h
.blitNoCarryHL
    ld a, e
    add a, PFAC_STRIDE - PFAC_SIZE
    ld e, a
    jr nc, .blitNoCarryDE
    inc d
.blitNoCarryDE
    pop bc
    dec b
    jr nz, .blitRowLoop

.placeSprites
    ; --- Patch the two exit warp entries (north edge, 2 tiles wide) ---
    ; sProcFacilityExitI holds the exit BLOCK column. Left exit tile X = 2*exitX.
    ; wWarpEntries+4 = entry 1 (Y,X,..), +8 = entry 2.
    ld a, [sProcFacilityExitI]
    add a, a
    ld c, a                         ; c = 2*exitX = left exit tile X
    ld hl, wWarpEntries + 4
    xor a
    ld [hli], a                     ; entry1 Y = 0
    ld a, c
    ld [hli], a                     ; entry1 X = 2*exitX
    inc hl
    inc hl
    xor a
    ld [hli], a                     ; entry2 Y = 0
    ld a, c
    inc a
    ld [hl], a                      ; entry2 X = 2*exitX+1

    ; --- Restore boss species and place its sprite (slot 1) ---
    ld a, [sProcFacilityBossSpecies]
    ld [wRoguePokemon1], a

    ; Boss stands on block (exitX, 1), one cell below the opening, facing DOWN so
    ; it guards the only approach. tile = block*2+4.
    ld a, [sProcFacilityExitI]
    add a, a
    add a, 4                        ; tile X = exitX*2+4
    ld [wSprite01StateData2MapX], a
    ld a, 1 * 2 + 4                 ; block Y=1 -> tile Y = 6
    ld [wSprite01StateData2MapY], a
    ld a, SPRITE_FACING_DOWN
    ld [wSprite01StateData1FacingDirection], a

    ; Boss species/level into wMapSpriteExtraData slot 1 (offset 0).
    farcall PCGetBossLevel          ; wCurEnemyLevel from wBattleCount (bank 7)
    ld hl, wMapSpriteExtraData + 0
    ld a, [wRoguePokemon1]
    ld [hli], a
    ld a, [wCurEnemyLevel]
    set 7, a                        ; OW_POKEMON bit
    ld [hl], a

    ; --- Restore the 4 pokeball sprites (slots 2-5) from SRAM ---
    ld hl, sProcFacilityBallXY      ; Y0,X0,Y1,X1,...
    ld de, wSprite01StateData2MapY + 16
    ld b, 4
.ballRestoreXY
    ld a, [hli]                     ; tile Y
    ld [de], a
    inc de
    ld a, [hli]                     ; tile X
    ld [de], a
    ld a, e
    add a, 15                       ; advance to next slot's MapY (+16 total)
    ld e, a
    jr nc, .ballNoCarry
    inc d
.ballNoCarry
    dec b
    jr nz, .ballRestoreXY

    ; Ball items -> wRogueItem..+6 (2 bytes/slot, low byte = ID)
    ld hl, sProcFacilityBallItems
    ld de, wRogueItem
    ld b, 4
.itemRestore
    ld a, [hli]
    ld [de], a
    inc de
    inc de
    dec b
    jr nz, .itemRestore

    ld a, BMODE_SIMPLE
    ld [rBMODE], a
    ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
    ld [rRAMG], a
    ret
