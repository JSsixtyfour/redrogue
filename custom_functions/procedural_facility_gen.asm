; custom_functions/procedural_facility_gen.asm
;
; Procedural facility generator for PROCEDURAL_FACILITY ($F3).
;
; Room-tree generator (ground-up redesign, see Red Rogue Files/
; 1-i-need-you-foamy-otter.md): 12 fixed-role rooms (0=entry, 1-4=item rooms,
; 5-10=explore, 11=exit) placed as a parent tree (each room's parent has a
; smaller id), stamped as floor, joined by direct-manhattan corridors toward
; each room's parent, enclosed in the FACILITY tileset's directional 9-slice
; wall (top/left/right/bottom + 4 corners), then converted down to real block
; IDs. The green/red palette roll is purely cosmetic now - it no longer
; branches generation.
;
; Buffer model: PFacFillUntouched seeds the whole 20x20 player area with the
; PFAC_UNTOUCHED sentinel ($FF, "nothing has touched this cell yet"). Rooms
; are stamped PFAC_ROOMFLOOR ($F0) and corridors PFAC_CORRIDOR ($FE) - both
; pseudo values distinct from every real block ID - so later passes can tell
; "claimed floor" apart from "never touched" without ambiguity. Two final
; sweeps convert the pseudo values down to real IDs: pseudo-floors -> PFAC_FLOOR
; (14), remaining untouched cells -> PFAC_WALL (46, the same block as the map
; border/void).
;
; SRAM: uses its own sProcFacility* fields (see ram/sram.asm). sProcFacilityBaked
; controls fast re-entry. Reuses the cave's boss/wild/item engine + PC_* events
; (never concurrent), exactly like the forest.
;
; Room data model: 12 records (see PFAC_ROOM_STRIDE/PFAC_ROOM_MAX below) live in
; sProcFacilityGenScratch, one per room id, in id order - array index IS the
; room id (0=entry, 1-4=items, 5-10=explore, 11=exit; role is derived from the
; index, never stored). An explore room (5-10) that fails to place after retries
; is NOT omitted from the array - its slot is written with W=0 as a "not placed"
; sentinel, so every other id keeps its fixed slot. wPFacRoomCount therefore
; always ends at PFAC_ROOM_MAX (12) once placement finishes; consumers (stamp,
; enclose, corridors) must skip any record whose W is 0. Item rooms (ids 1-4)
; are guaranteed placed (rule e) so PFacPlaceItems addresses them directly by id
; with no scan needed.
;
; Pipeline order (PFacGenerateFacility): fill untouched -> place entry(0)/exit(11)
; /middle(1-10) rooms -> assign exit parent -> stamp room floors -> carve
; corridors (rooms 11..1 -> parent) + entry corridor -> enclose rooms in
; directional walls -> punch the north exit opening -> convert pseudo floors ->
; convert untouched -> place items. v1 ships a NORTH exit only.

SECTION "ProceduralFacilityGen", ROMX

DEF PFAC_SIZE    EQU 20
DEF PFAC_STRIDE  EQU 26
DEF PFAC_BASE    EQU 81

DEF PFAC_FLOOR   EQU 14   ; facility floor block (all-$01, passable)
DEF PFAC_WALL    EQU 46   ; solid interior wall AND the map border/void block.

; --- Generation-time pseudo values (never written to the final map) ---
DEF PFAC_UNTOUCHED EQU $FF   ; PFacFillUntouched's seed value: "nothing has
                             ; claimed this cell yet". Converted to PFAC_WALL
                             ; by PFacConvertUntouched once generation is done.
DEF PFAC_CORRIDOR  EQU $FE   ; a corridor cell (PFacCarveCorridors/
                             ; PFacCarveEntryCorridor). Converted to PFAC_FLOOR
                             ; by PFacConvertPseudoFloors.
DEF PFAC_ROOMFLOOR EQU $F0   ; a room-interior floor cell (PFacStampRoomFloors).
                             ; Single value this pass; a decor follow-up can
                             ; widen this to $F0-$F3 keyed off the room's Type
                             ; field without touching the structural pipeline.
                             ; Converted to PFAC_FLOOR by
                             ; PFacConvertPseudoFloors.

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

; --- Room record model (sProcFacilityGenScratch, 81 bytes: 12*6 = 72 used) ---
; Record layout (6 bytes, read/written positionally via PFacRoomRecordAddr):
;   +0 X      floor-rect top-left block col
;   +1 Y      floor-rect top-left block row
;   +2 W      floor-rect width in blocks (0 = unplaced slot, see header note)
;   +3 H      floor-rect height in blocks
;   +4 Parent parent room id (PFAC_ROOM_NONE for room 0, which has no parent)
;   +5 Type   decor category 0-3 (rolled now, used by a later decor pass)
DEF PFAC_ROOM_STRIDE EQU 6
DEF PFAC_ROOM_MAX    EQU 12   ; entry(0) + items(1-4) + explore(5-10) + exit(11)
DEF PFAC_ROOM_NONE   EQU $FF  ; Parent sentinel for room 0

; wBuffer scratch offsets. Facility never runs concurrently with cave/cemetery/
; forest generation, so it reuses the same 30-byte wBuffer window they use
; (ram/wram.asm: wBuffer:: ds 30 - offsets 0-29 are the entire budget).
DEF wPFacTargetBaseLo EQU 0
DEF wPFacTargetBaseHi EQU 1
DEF wPFacCurX         EQU 2   ; block-space X for PFacWriteBlock/PFacReadBlock
DEF wPFacCurY         EQU 3   ; block-space Y

; Room count persists across the WHOLE pipeline (placement through item
; placement), so it gets a fixed offset outside the per-phase reuse window
; below. Always ends at PFAC_ROOM_MAX once placement finishes (see header note
; on the W=0 "unplaced slot" sentinel).
DEF wPFacRoomCount    EQU 25

; --- Per-phase scratch (offsets 4-24). Phases never run concurrently (mirrors
; the cave/forest/cemetery convention), so each phase freely reuses this same
; numeric range under its own names. Room-placement and corridor-carving
; (pending, see header note) may reuse 4-24 too, as long as they don't touch
; offset 25 (wPFacRoomCount) or write invalid room records. ---

; PFacStampRoomFloors / PFacEncloseRooms / PFacPlaceItems:
DEF wPFacRmIdx        EQU 4   ; room loop index (Stamp/Enclose)
DEF wPFacRmX          EQU 5   ; loaded room record: X
DEF wPFacRmY          EQU 6   ; loaded room record: Y
DEF wPFacRmW          EQU 7   ; loaded room record: W
DEF wPFacRmH          EQU 8   ; loaded room record: H
DEF wPFacRmCounter    EQU 9   ; inner row/col loop counter (Stamp/Enclose)
DEF wPFacBallIdx      EQU 10  ; PFacPlaceItems: item-room loop index (0-3)
DEF wPFacItemRetry    EQU 11  ; PFacPlaceItems: item-dedup retry counter
DEF wPFacItemTemp     EQU 12  ; 4 bytes (12-15): rolled item IDs. PFacFinalize's
                              ; existing bake step copies this to
                              ; sProcFacilityBallItems by name, unchanged.

; Room-placement phase (PFacPlaceEntryRoom/PFacPlaceExitRoom/PFacPlaceMiddleRooms
; and their helpers). Reuses 4-15; must not touch 25 (wPFacRoomCount).
DEF wPFacPlaceId      EQU 4   ; id of the room being placed / init loop var
DEF wPFacCandX        EQU 5   ; candidate room rect
DEF wPFacCandY        EQU 6
DEF wPFacCandW        EQU 7
DEF wPFacCandH        EQU 8
DEF wPFacParent       EQU 9   ; chosen parent id for the candidate
DEF wPFacRetry        EQU 10  ; placement retry counter
DEF wPFacScanId       EQU 11  ; overlap/parent/exit scan index
DEF wPFacBX           EQU 12  ; scanned room B rect (overlap test) / exit-parent temps
DEF wPFacBY           EQU 13
DEF wPFacBW           EQU 14
DEF wPFacBH           EQU 15
; Corridor phase (PFacCarveCorridors/PFacCarveEntryCorridor). Same 4-8 window,
; different names (placement is finished by the time corridors run).
DEF wPFacCorId        EQU 4   ; source room whose corridor we're carving
DEF wPFacCorTX        EQU 5   ; target center X
DEF wPFacCorTY        EQU 6   ; target center Y
DEF wPFacCorExited    EQU 7   ; 0 until the walk leaves the source room's floor
DEF wPFacCorStop      EQU 8   ; set when contact with another room/corridor stops it

; ============================================================
; PFacRowOffsetTable / PFacWriteBlock / PFacReadBlock / PFacPickFloor /
; PFacRoomRecordAddr
; Shared primitives used by every generation phase.
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
; function so ported/future carve code can call it identically to the forest's
; PFPickFloor (a floor-variety table can be added here later).
PFacPickFloor:
    ld a, PFAC_FLOOR
    ret

; INPUT: a = room id (0..PFAC_ROOM_MAX-1). OUTPUT: hl = address of that room's
; 6-byte record in sProcFacilityGenScratch. Clobbers de.
PFacRoomRecordAddr:
    ld h, 0
    ld l, a
    add hl, hl      ; hl = id*2
    ld d, h
    ld e, l         ; de = id*2
    add hl, hl      ; hl = id*4
    add hl, de      ; hl = id*4 + id*2 = id*6
    ld de, sProcFacilityGenScratch
    add hl, de
    ret

; ============================================================
; PFacFillUntouched
; Seed the whole 20x20 player area with PFAC_UNTOUCHED so every later pass can
; tell "nothing has claimed this cell yet" from real content. The .blk's floor
; fill is only a placeholder; this always overwrites it. Border padding
; (already PFAC_WALL from the object file's border block) is untouched.
; ============================================================
PFacFillUntouched:
    ld hl, wOverworldMap + PFAC_BASE
    ld b, PFAC_SIZE
.rowLoop
    push bc
    ld c, PFAC_SIZE
.colLoop
    ld a, PFAC_UNTOUCHED
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
; PFacStampRoomFloors
; Fills every registered room's floor rect with PFAC_ROOMFLOOR ($F0). Rooms are
; read from sProcFacilityGenScratch (populated by PFacPlaceEntryRoom/
; PFacPlaceExitRoom/PFacPlaceMiddleRooms). A W=0 record (an explore room that
; failed to place) is skipped. Runs after all placement, before corridors, so
; PFacCarveCorridors can test "is this cell already room floor".
; ============================================================
PFacStampRoomFloors:
    xor a
    ld [wBuffer + wPFacRmIdx], a
.roomLoop
    ld a, [wBuffer + wPFacRmIdx]
    ld hl, wBuffer + wPFacRoomCount
    cp [hl]
    ret nc

    ld a, [wBuffer + wPFacRmIdx]
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    ld a, [hl]
    ld [wBuffer + wPFacRmH], a

    ld a, [wBuffer + wPFacRmW]
    and a
    jr z, .roomNext            ; unplaced slot, skip

    ld a, [wBuffer + wPFacRmY]
    ld [wBuffer + wPFacCurY], a
.rowLoop
    ld a, [wBuffer + wPFacRmX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmW]
    ld [wBuffer + wPFacRmCounter], a
.colLoop
    ld a, PFAC_ROOMFLOOR
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmCounter]
    dec a
    ld [wBuffer + wPFacRmCounter], a
    jr nz, .colLoop

    ld a, [wBuffer + wPFacRmY]
    ld b, a
    ld a, [wBuffer + wPFacRmH]
    add a, b                    ; a = Y + H (exclusive row bound)
    ld c, a
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    cp c
    jr c, .rowLoop

.roomNext
    ld a, [wBuffer + wPFacRmIdx]
    inc a
    ld [wBuffer + wPFacRmIdx], a
    jp .roomLoop

; ============================================================
; PFacEncloseRooms
; For every registered room (W=0 slots skipped), draws the directional 9-slice
; wall ring on the cells immediately outside its floor rect (X-1..X+W,
; Y-1..Y+H). A ring cell already PFAC_CORRIDOR or PFAC_ROOMFLOOR (a doorway
; carved by PFacCarveCorridors/PFacCarveEntryCorridor, or another room's floor)
; is left untouched - that's how doorways survive. Everything else in the ring
; becomes a straight wall (65/68/70/73) or corner post (64/66/72/74). Relies on
; every placed room's floor rect staying within blocks 1..18 (guaranteed by
; PFacPlaceEntryRoom/PFacPlaceExitRoom/PFacPlaceMiddleRooms), so the ring never
; leaves the 20x20 player area.
; ============================================================
PFacEncloseRooms:
    xor a
    ld [wBuffer + wPFacRmIdx], a
.roomLoop
    ld a, [wBuffer + wPFacRmIdx]
    ld hl, wBuffer + wPFacRoomCount
    cp [hl]
    ret nc

    ld a, [wBuffer + wPFacRmIdx]
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    ld a, [hl]
    ld [wBuffer + wPFacRmH], a

    ld a, [wBuffer + wPFacRmW]
    and a
    jp z, .roomNext            ; unplaced slot, skip

    ; --- Top edge (row Y-1, cols X..X+W-1): PFAC_W_TOP ---
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmW]
    ld [wBuffer + wPFacRmCounter], a
.topLoop
    ld a, PFAC_W_TOP
    call PFacRingWrite
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmCounter]
    dec a
    ld [wBuffer + wPFacRmCounter], a
    jr nz, .topLoop

    ; --- Bottom edge (row Y+H, cols X..X+W-1): PFAC_W_BOTTOM ---
    ld a, [wBuffer + wPFacRmY]
    ld b, a
    ld a, [wBuffer + wPFacRmH]
    add a, b
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmW]
    ld [wBuffer + wPFacRmCounter], a
.bottomLoop
    ld a, PFAC_W_BOTTOM
    call PFacRingWrite
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmCounter]
    dec a
    ld [wBuffer + wPFacRmCounter], a
    jr nz, .bottomLoop

    ; --- Left edge (col X-1, rows Y..Y+H-1): PFAC_W_LEFT ---
    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmH]
    ld [wBuffer + wPFacRmCounter], a
.leftLoop
    ld a, PFAC_W_LEFT
    call PFacRingWrite
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmCounter]
    dec a
    ld [wBuffer + wPFacRmCounter], a
    jr nz, .leftLoop

    ; --- Right edge (col X+W, rows Y..Y+H-1): PFAC_W_RIGHT ---
    ld a, [wBuffer + wPFacRmX]
    ld b, a
    ld a, [wBuffer + wPFacRmW]
    add a, b
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmH]
    ld [wBuffer + wPFacRmCounter], a
.rightLoop
    ld a, PFAC_W_RIGHT
    call PFacRingWrite
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacRmCounter]
    dec a
    ld [wBuffer + wPFacRmCounter], a
    jr nz, .rightLoop

    ; --- 4 corners ---
    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_C_TL
    call PFacRingWrite

    ld a, [wBuffer + wPFacRmX]
    ld b, a
    ld a, [wBuffer + wPFacRmW]
    add a, b
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_C_TR
    call PFacRingWrite

    ld a, [wBuffer + wPFacRmX]
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld b, a
    ld a, [wBuffer + wPFacRmH]
    add a, b
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_C_BL
    call PFacRingWrite

    ld a, [wBuffer + wPFacRmX]
    ld b, a
    ld a, [wBuffer + wPFacRmW]
    add a, b
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmY]
    ld b, a
    ld a, [wBuffer + wPFacRmH]
    add a, b
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_C_BR
    call PFacRingWrite

.roomNext
    ld a, [wBuffer + wPFacRmIdx]
    inc a
    ld [wBuffer + wPFacRmIdx], a
    jp .roomLoop

; Writes A (a wall/corner block) to [wPFacCurX/Y] UNLESS that cell is already
; PFAC_CORRIDOR or PFAC_ROOMFLOOR (a doorway or another room's floor), in which
; case it's left untouched so the doorway survives.
PFacRingWrite:
    push af
    call PFacReadBlock
    cp PFAC_CORRIDOR
    jr z, .skip
    cp PFAC_ROOMFLOOR
    jr z, .skip
    pop af
    jp PFacWriteBlock
.skip
    pop af
    ret

; ============================================================
; PFacConvertPseudoFloors
; Sweeps the full 20x20 player area, converting PFAC_ROOMFLOOR ($F0) and
; PFAC_CORRIDOR ($FE) to the real floor block (14). Runs after PFacEncloseRooms
; so doorway detection during enclosure still sees the pseudo values.
; ============================================================
PFacConvertPseudoFloors:
    xor a
    ld [wBuffer + wPFacCurY], a
.rowLoop
    xor a
    ld [wBuffer + wPFacCurX], a
.colLoop
    call PFacReadBlock
    cp PFAC_ROOMFLOOR
    jr z, .toFloor
    cp PFAC_CORRIDOR
    jr nz, .next
.toFloor
    ld a, PFAC_FLOOR
    call PFacWriteBlock
.next
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    cp PFAC_SIZE
    jr nz, .colLoop
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    cp PFAC_SIZE
    jr nz, .rowLoop
    ret

; ============================================================
; PFacConvertUntouched
; Sweeps the full 20x20 player area, converting any remaining PFAC_UNTOUCHED
; ($FF) cell to the solid wall block PFAC_WALL (46). Directional wall/corner
; blocks written by PFacEncloseRooms are real block IDs, not sentinels, and are
; left untouched. Runs after PFacConvertPseudoFloors.
; ============================================================
PFacConvertUntouched:
    xor a
    ld [wBuffer + wPFacCurY], a
.rowLoop
    xor a
    ld [wBuffer + wPFacCurX], a
.colLoop
    call PFacReadBlock
    cp PFAC_UNTOUCHED
    jr nz, .next
    ld a, 14 ; experimental
    call PFacWriteBlock
.next
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    cp PFAC_SIZE
    jr nz, .colLoop
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    cp PFAC_SIZE
    jr nz, .rowLoop
    ret

; ============================================================
; PFacPlaceItems
; One pokeball per item room (fixed room ids 1-4; rule e guarantees these are
; always placed, so no scan is needed - just address them directly). Picks a
; random floor tile within each room's interior, rolls a unique item (dedup
; against earlier rolls, same rejection-sampling pattern the retired
; PFacScanForBall used), and stores block coords + item IDs into
; sProcFacilityGenScratch[0..7] / wPFacItemTemp[0..3] - the exact contract
; PFacFinalize's existing bake step already reads (X,Y pairs per ball, then 4
; item IDs), so that copy-to-SRAM code needs no changes.
; Runs AFTER PFacConvertPseudoFloors/PFacConvertUntouched (room interiors are
; real PFAC_FLOOR by then). Room record bytes (X/Y/W/H) are never touched by
; the stamp/enclose/convert passes, only the map buffer is, so re-reading a
; room's record here is safe.
; ============================================================
PFacPlaceItems:
    xor a
    ld [wBuffer + wPFacBallIdx], a
.ballLoop
    ld a, [wBuffer + wPFacBallIdx]
    inc a                        ; item room ids are 1-4 (ball index 0-3 -> id 1-4)
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacRmX], a
    ld a, [hli]
    ld [wBuffer + wPFacRmY], a
    ld a, [hli]
    ld [wBuffer + wPFacRmW], a
    ld a, [hl]
    ld [wBuffer + wPFacRmH], a

    ld a, [wBuffer + wPFacRmW]
    and a
    jr nz, .havePosition
    ; Defensive fallback (should not happen - rule e guarantees item rooms
    ; always place): default to the fixed entrance block.
    ld a, 9
    ld [wBuffer + wPFacRmX], a
    ld a, 1
    ld [wBuffer + wPFacRmW], a
    ld a, 17
    ld [wBuffer + wPFacRmY], a
    ld a, 1
    ld [wBuffer + wPFacRmH], a
.havePosition
    ld a, [wBuffer + wPFacRmW]
    ld c, a
    call Rangerandom              ; 0..W-1
    ld b, a
    ld a, [wBuffer + wPFacRmX]
    add a, b
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacRmH]
    ld c, a
    call Rangerandom              ; 0..H-1
    ld b, a
    ld a, [wBuffer + wPFacRmY]
    add a, b
    ld [wBuffer + wPFacCurY], a

    ; Save block coords -> sProcFacilityGenScratch[ballIdx*2 .. +1] (X,Y)
    ld a, [wBuffer + wPFacBallIdx]
    add a, a
    ld e, a
    ld d, 0
    ld hl, sProcFacilityGenScratch
    add hl, de
    ld a, [wBuffer + wPFacCurX]
    ld [hli], a
    ld a, [wBuffer + wPFacCurY]
    ld [hl], a

    ; Roll this ball's item, rejecting an exact duplicate of an earlier one.
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
    jp nz, .ballLoop
    ret

; ============================================================
; PFacGenerateFacility  (top-level driver)
; Runs the whole room-tree pipeline into wOverworldMap (already seeded with
; PFAC_UNTOUCHED by PFacFillUntouched). On return the map holds only real block
; IDs (14 floor, 46 wall, 64-74 directional walls) and sProcFacilityGenScratch/
; wPFacItemTemp hold the 4 ball block-coords + item IDs for PFacFinalize to bake.
; ============================================================
PFacGenerateFacility:
    call PFacInitRoomRecords
    call PFacPlaceEntryRoom       ; room 0
    call PFacPlaceExitRoom        ; room 11 (+ sProcFacilityExitI)
    call PFacPlaceMiddleRooms     ; rooms 1-10 (items guaranteed, explore best-effort)
    call PFacAssignExitParent     ; room 11's parent = nearest placed room
    call PFacStampRoomFloors
    call PFacCarveCorridors        ; rooms 11..1 -> parent (spanning tree to entry)
    call PFacEncloseRooms
    call PFacCarveNorthExitOpening
    call PFacConvertPseudoFloors
    call PFacConvertUntouched
    call PFacPlaceItems
    ret

; ============================================================
; PFacRoomCenter
; INPUT a = room id. OUTPUT b = center block col (X + W/2), c = center row
; (Y + H/2). Clobbers a, d, e, hl. Only valid for placed rooms.
; ============================================================
PFacRoomCenter:
    call PFacRoomRecordAddr
    ld a, [hli]                 ; X
    ld d, a
    ld a, [hli]                 ; Y
    ld e, a
    ld a, [hli]                 ; W
    srl a
    add a, d
    ld b, a                     ; cx = X + W/2
    ld a, [hl]                  ; H
    srl a
    add a, e
    ld c, a                     ; cy = Y + H/2
    ret

; ============================================================
; PFacInitRoomRecords
; Zero the W (unplaced) byte of all 12 room slots and set wPFacRoomCount = 12.
; ============================================================
PFacInitRoomRecords:
    xor a
    ld [wBuffer + wPFacPlaceId], a
.loop
    ld a, [wBuffer + wPFacPlaceId]
    call PFacRoomRecordAddr
    inc hl
    inc hl
    xor a
    ld [hl], a                  ; W = 0 = unplaced
    ld a, [wBuffer + wPFacPlaceId]
    inc a
    ld [wBuffer + wPFacPlaceId], a
    cp PFAC_ROOM_MAX
    jr c, .loop
    ld a, PFAC_ROOM_MAX
    ld [wBuffer + wPFacRoomCount], a
    ret

; ============================================================
; PFacStoreRoom
; Write wPFacCand{X,Y,W,H} + wPFacParent + a freshly rolled Type into the record
; for room wPFacPlaceId. Clobbers a, de, hl.
; ============================================================
PFacStoreRoom:
    ld a, [wBuffer + wPFacPlaceId]
    call PFacRoomRecordAddr
    ld a, [wBuffer + wPFacCandX]
    ld [hli], a
    ld a, [wBuffer + wPFacCandY]
    ld [hli], a
    ld a, [wBuffer + wPFacCandW]
    ld [hli], a
    ld a, [wBuffer + wPFacCandH]
    ld [hli], a
    ld a, [wBuffer + wPFacParent]
    ld [hli], a
    call Random
    and 3
    ld [hl], a                  ; Type 0-3 (decor category, used by a later pass)
    ret

; ============================================================
; PFacRollRoomDim
; OUTPUT a = a floor dimension in [1,7] (room footprint 3-9 per side once the
; 1-cell wall ring is added), HEAVILY biased toward small. Full max is retained
; (7 floor = 9 footprint) but big rooms are rare: taking the minimum of two
; independent 0-6 rolls skews the result low. Resulting floor distribution ~=
; 1:27% 2:22% 3:18% 4:14% 5:10% 6:6% 7:2%. Clobbers a, b, c.
; ============================================================
PFacRollRoomDim:
    ld c, 7
    call Rangerandom            ; r1 = 0..6
    push af
    ld c, 7
    call Rangerandom            ; r2 = 0..6 (in a)
    pop bc                      ; b = r1
    cp b
    jr c, .haveMin              ; a < b -> a is the min
    ld a, b
.haveMin
    inc a                       ; 1..7
    ret

; ============================================================
; PFacPlaceEntryRoom  (room 0)
; Small floor rect, bottom-aligned (floor bottom = row 18, wall ring at row 19),
; positioned so the fixed spawn block (9,17) is inside it. Always succeeds.
; ============================================================
PFacPlaceEntryRoom:
    xor a
    ld [wBuffer + wPFacPlaceId], a
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandW], a  ; floor W 1-7, biased small
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandH], a  ; floor H 1-7, biased small
    ; Y = 19 - H
    ld a, 19
    ld hl, wBuffer + wPFacCandH
    sub [hl]
    ld [wBuffer + wPFacCandY], a
    ; X = 9 - rand(W), clamped to [1, 19-W]
    ld a, [wBuffer + wPFacCandW]
    ld c, a
    call Rangerandom
    ld b, a
    ld a, 9
    sub b
    cp 1
    jr nc, .xLowOK
    ld a, 1
.xLowOK
    ld b, a
    ld a, 19
    ld hl, wBuffer + wPFacCandW
    sub [hl]                     ; a = maxX = 19 - W
    cp b
    jr nc, .xHiOK                ; maxX >= b, keep b
    ld b, a
.xHiOK
    ld a, b
    ld [wBuffer + wPFacCandX], a
    ld a, PFAC_ROOM_NONE
    ld [wBuffer + wPFacParent], a
    jp PFacStoreRoom

; ============================================================
; PFacPlaceExitRoom  (room 11, north edge)
; Floor top at row 2 (ring at row 1, warp opening at row 0). Rolls an exit block
; column inside the room's width -> sProcFacilityExitI. Parent set later.
; ============================================================
PFacPlaceExitRoom:
    ld a, 11
    ld [wBuffer + wPFacPlaceId], a
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandW], a
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandH], a
    ld a, 2
    ld [wBuffer + wPFacCandY], a
    ; X = 1 + rand(19 - W)
    ld a, 19
    ld hl, wBuffer + wPFacCandW
    sub [hl]
    ld c, a
    call Rangerandom
    inc a
    ld [wBuffer + wPFacCandX], a
    ; exit column = X + rand(W)
    ld a, [wBuffer + wPFacCandW]
    ld c, a
    call Rangerandom
    ld hl, wBuffer + wPFacCandX
    add a, [hl]
    ld [sProcFacilityExitI], a
    ld a, PFAC_ROOM_NONE
    ld [wBuffer + wPFacParent], a
    jp PFacStoreRoom

; ============================================================
; PFacPlaceMiddleRooms  (rooms 1-10)
; Item rooms (1-4) are guaranteed a spot (retry hard, then a linear-scan 3x3
; fallback). Explore rooms (5-10) are best-effort and left W=0 if they can't fit.
; ============================================================
PFacPlaceMiddleRooms:
    ld a, 1
    ld [wBuffer + wPFacPlaceId], a
.roomLoop
    ld a, [wBuffer + wPFacPlaceId]
    cp 11
    ret nc                       ; done after id 10
    cp 5
    jr nc, .exploreRetries
    ld a, 40                     ; item rooms get more tries
    jr .setRetries
.exploreRetries
    ld a, 16
.setRetries
    ld [wBuffer + wPFacRetry], a
.attempt
    call PFacRollCandidate        ; a=0 accept, a=1 reject
    and a
    jr z, .accepted
    ld a, [wBuffer + wPFacRetry]
    dec a
    ld [wBuffer + wPFacRetry], a
    jr nz, .attempt
    ; retries exhausted
    ld a, [wBuffer + wPFacPlaceId]
    cp 5
    jr nc, .roomNext             ; explore: leave unplaced (W already 0)
    call PFacForceItemRoom        ; item room: guaranteed 3x3
    jr .roomNext
.accepted
    call PFacStoreRoom
.roomNext
    ld a, [wBuffer + wPFacPlaceId]
    inc a
    ld [wBuffer + wPFacPlaceId], a
    jp .roomLoop

; Roll one placement candidate near a chosen parent. OUT a=0 accept, a=1 reject.
PFacRollCandidate:
    call PFacPickParent           ; -> wPFacParent (a placed id < placeId)
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandW], a
    call PFacRollRoomDim
    ld [wBuffer + wPFacCandH], a
    ld a, [wBuffer + wPFacParent]
    call PFacRoomCenter           ; b=pcx c=pcy
    ; candidate center X = pcx + rand(-5..5), then X = centerX - W/2
    push bc
    ld c, 11
    call Rangerandom
    sub 5
    pop bc
    add a, b
    ld hl, wBuffer + wPFacCandW
    ld d, [hl]
    srl d
    sub d
    ld [wBuffer + wPFacCandX], a
    ; center Y = pcy + rand(-5..5), Y = centerY - H/2
    push bc
    ld c, 11
    call Rangerandom
    sub 5
    pop bc
    add a, c
    ld hl, wBuffer + wPFacCandH
    ld d, [hl]
    srl d
    sub d
    ld [wBuffer + wPFacCandY], a
    call PFacCandInBounds
    and a
    jr z, .checkOverlap
    ld a, 1
    ret
.checkOverlap
    jp PFacCandOverlaps           ; a=0 clear (accept), a=1 overlap (reject)

; Pick a placed room id < placeId into wPFacParent (room 0 is always placed).
PFacPickParent:
    ld a, [wBuffer + wPFacPlaceId]
    ld c, a
    call Rangerandom              ; 0..placeId-1
    ld [wBuffer + wPFacParent], a
.check
    ld a, [wBuffer + wPFacParent]
    call PFacRoomRecordAddr
    inc hl
    inc hl
    ld a, [hl]
    and a
    ret nz                        ; placed
    ld a, [wBuffer + wPFacParent]
    and a
    jr z, .useZero
    dec a
    ld [wBuffer + wPFacParent], a
    jr .check
.useZero
    xor a
    ld [wBuffer + wPFacParent], a
    ret

; a=0 if wPFacCand rect is within blocks [1,18] with X+W<=19, Y+H<=19; else a=1.
PFacCandInBounds:
    ld a, [wBuffer + wPFacCandX]
    and a
    jr z, .bad
    cp 19
    jr nc, .bad
    ld a, [wBuffer + wPFacCandY]
    and a
    jr z, .bad
    cp 19
    jr nc, .bad
    ld a, [wBuffer + wPFacCandX]
    ld hl, wBuffer + wPFacCandW
    add a, [hl]
    cp 20
    jr nc, .bad
    ld a, [wBuffer + wPFacCandY]
    ld hl, wBuffer + wPFacCandH
    add a, [hl]
    cp 20
    jr nc, .bad
    xor a
    ret
.bad
    ld a, 1
    ret

; a=0 if wPFacCand rect keeps >=2 gap from every placed room; a=1 on overlap.
PFacCandOverlaps:
    xor a
    ld [wBuffer + wPFacScanId], a
.loop
    ld a, [wBuffer + wPFacScanId]
    cp PFAC_ROOM_MAX
    jr nc, .clear
    ld a, [wBuffer + wPFacScanId]
    call PFacRoomRecordAddr
    ld a, [hli]
    ld [wBuffer + wPFacBX], a
    ld a, [hli]
    ld [wBuffer + wPFacBY], a
    ld a, [hli]
    ld [wBuffer + wPFacBW], a
    ld a, [hl]
    ld [wBuffer + wPFacBH], a
    ld a, [wBuffer + wPFacBW]
    and a
    jr z, .next                  ; unplaced, ignore
    ; separated (>=2 gap) if any of the 4 hold; else overlap. The +1 before
    ; each cp is deliberate: a >=1 gap lets two rooms' wall rings (each 1 cell
    ; wide) land on the same shared cell, so whichever room's PFacEncloseRooms
    ; pass runs later silently overwrites the other's corner/edge there. >=2
    ; gap gives every room's ring its own dedicated cell.
    ld a, [wBuffer + wPFacCandX]
    ld hl, wBuffer + wPFacCandW
    add a, [hl]
    inc a
    ld hl, wBuffer + wPFacBX
    cp [hl]
    jr c, .next                  ; candX+candW+1 < Bx
    ld a, [wBuffer + wPFacBX]
    ld hl, wBuffer + wPFacBW
    add a, [hl]
    inc a
    ld hl, wBuffer + wPFacCandX
    cp [hl]
    jr c, .next                  ; Bx+Bw+1 < candX
    ld a, [wBuffer + wPFacCandY]
    ld hl, wBuffer + wPFacCandH
    add a, [hl]
    inc a
    ld hl, wBuffer + wPFacBY
    cp [hl]
    jr c, .next                  ; candY+candH+1 < By
    ld a, [wBuffer + wPFacBY]
    ld hl, wBuffer + wPFacBH
    add a, [hl]
    inc a
    ld hl, wBuffer + wPFacCandY
    cp [hl]
    jr c, .next                  ; By+Bh+1 < candY
    ld a, 1                      ; none separated -> overlap
    ret
.next
    ld a, [wBuffer + wPFacScanId]
    inc a
    ld [wBuffer + wPFacScanId], a
    jr .loop
.clear
    xor a
    ret

; Guaranteed 3x3 placement for an item room: linear-scan the first non-
; overlapping spot, or (never expected) drop a 3x3 at (1,1) ignoring overlap.
PFacForceItemRoom:
    ld a, 3
    ld [wBuffer + wPFacCandW], a
    ld [wBuffer + wPFacCandH], a
    call PFacPickParent
    ld a, 1
    ld [wBuffer + wPFacCandY], a
.scanY
    ld a, 1
    ld [wBuffer + wPFacCandX], a
.scanX
    call PFacCandOverlaps
    and a
    jr z, .found
    ld a, [wBuffer + wPFacCandX]
    inc a
    ld [wBuffer + wPFacCandX], a
    cp 17
    jr c, .scanX
    ld a, [wBuffer + wPFacCandY]
    inc a
    ld [wBuffer + wPFacCandY], a
    cp 17
    jr c, .scanY
    ld a, 1
    ld [wBuffer + wPFacCandX], a
    ld [wBuffer + wPFacCandY], a
.found
    jp PFacStoreRoom

; ============================================================
; PFacAssignExitParent
; Set room 11's Parent to the placed room (0-10) whose center is nearest the
; exit center (manhattan). Room 0 always qualifies, so a parent always exists.
; ============================================================
PFacAssignExitParent:
    ld a, 11
    call PFacRoomCenter
    ld a, b
    ld [wBuffer + wPFacBX], a    ; exit cx
    ld a, c
    ld [wBuffer + wPFacBY], a    ; exit cy
    ld a, 255
    ld [wBuffer + wPFacBW], a    ; best distance
    xor a
    ld [wBuffer + wPFacBH], a    ; best parent id
    ld [wBuffer + wPFacScanId], a
.loop
    ld a, [wBuffer + wPFacScanId]
    cp 11
    jr nc, .done
    ld a, [wBuffer + wPFacScanId]
    call PFacRoomRecordAddr
    inc hl
    inc hl
    ld a, [hl]
    and a
    jr z, .next                  ; unplaced
    ld a, [wBuffer + wPFacScanId]
    call PFacRoomCenter          ; b=cx c=cy
    ld a, b
    ld hl, wBuffer + wPFacBX
    sub [hl]
    call PFacAbs
    ld d, a
    ld a, c
    ld hl, wBuffer + wPFacBY
    sub [hl]
    call PFacAbs
    add a, d                     ; manhattan distance
    ld hl, wBuffer + wPFacBW
    cp [hl]
    jr nc, .next                 ; not closer
    ld [hl], a
    ld a, [wBuffer + wPFacScanId]
    ld [wBuffer + wPFacBH], a
.next
    ld a, [wBuffer + wPFacScanId]
    inc a
    ld [wBuffer + wPFacScanId], a
    jr .loop
.done
    ld a, 11
    call PFacRoomRecordAddr
    ld de, 4
    add hl, de
    ld a, [wBuffer + wPFacBH]
    ld [hl], a
    ret

; ============================================================
; PFacCarveCorridors
; For room ids 11 down to 1 (skipping unplaced W=0 slots): carve a corridor to
; the room's parent, plus a 20% chance of an extra corridor to a random other
; placed room.
; ============================================================
PFacCarveCorridors:
    ld a, 11
    ld [wBuffer + wPFacCorId], a
.loop
    ld a, [wBuffer + wPFacCorId]
    and a
    ret z                        ; room 0 (entry) needs no corridor of its own -
                                 ; it is the parent tree's root, reached by the
                                 ; corridors its children (incl. item room 1) carve.
    call PFacCorRoomPlaced
    jr z, .next                  ; unplaced, skip
    ; parent
    ld a, [wBuffer + wPFacCorId]
    call PFacRoomRecordAddr
    ld de, 4
    add hl, de
    ld a, [hl]
    call PFacCarveOneCorridor
.next
    ld a, [wBuffer + wPFacCorId]
    dec a
    ld [wBuffer + wPFacCorId], a
    jp .loop

; ============================================================
; PFacCarveEntryCorridor
; Room 0 -> a random placed room, +25% chance of a second one.
; ============================================================
PFacCarveEntryCorridor:
    xor a
    ld [wBuffer + wPFacCorId], a
    call PFacRandOtherRoom
    cp 255
    ret z
    call PFacCarveOneCorridor
    call Random
    cp 64
    ret nc
    call PFacRandOtherRoom
    cp 255
    ret z
    jp PFacCarveOneCorridor

; Z set (a=0) if room wPFacCorId is unplaced (W=0); else NZ.
PFacCorRoomPlaced:
    ld a, [wBuffer + wPFacCorId]
    call PFacRoomRecordAddr
    inc hl
    inc hl
    ld a, [hl]
    and a
    ret

; OUT a = a random placed room id != wPFacCorId, or 255 if none exists.
PFacRandOtherRoom:
    ld c, PFAC_ROOM_MAX
    call Rangerandom
    ld e, a                      ; start id
    ld b, PFAC_ROOM_MAX
.loop
    ld a, e
    cp PFAC_ROOM_MAX
    jr c, .noWrap
    xor a
    ld e, a
.noWrap
    ld a, [wBuffer + wPFacCorId]
    cp e
    jr z, .advance
    ld a, e
    call PFacRoomRecordAddr
    inc hl
    inc hl
    ld a, [hl]
    and a
    jr z, .advance
    ld a, e
    ret
.advance
    inc e
    dec b
    jr nz, .loop
    ld a, 255
    ret

; ============================================================
; PFacCarveOneCorridor
; INPUT a = target room id; wPFacCorId = source room id. Carves a 1-wide
; direct-manhattan (L-shaped) corridor of PFAC_CORRIDOR from the source center
; toward the target center, stopping on first contact with a room (ROOMFLOOR)
; once it has left the source room's floor.
; ============================================================
PFacCarveOneCorridor:
    push af
    ld a, [wBuffer + wPFacCorId]
    call PFacRoomCenter
    ld a, b
    ld [wBuffer + wPFacCurX], a
    ld a, c
    ld [wBuffer + wPFacCurY], a
    pop af
    call PFacRoomCenter
    ld a, b
    ld [wBuffer + wPFacCorTX], a
    ld a, c
    ld [wBuffer + wPFacCorTY], a
    xor a
    ld [wBuffer + wPFacCorExited], a
    ld [wBuffer + wPFacCorStop], a
.hLeg
    call PFacCorStampWideH
    ld a, [wBuffer + wPFacCorStop]
    and a
    ret nz
    ld a, [wBuffer + wPFacCurX]
    ld hl, wBuffer + wPFacCorTX
    cp [hl]
    jr z, .vLeg
    jr c, .hInc
    dec a
    ld [wBuffer + wPFacCurX], a
    jr .hLeg
.hInc
    inc a
    ld [wBuffer + wPFacCurX], a
    jr .hLeg
.vLeg
    call PFacCorStampWideV
    ld a, [wBuffer + wPFacCorStop]
    and a
    ret nz
    ld a, [wBuffer + wPFacCurY]
    ld hl, wBuffer + wPFacCorTY
    cp [hl]
    ret z
    jr c, .vInc
    dec a
    ld [wBuffer + wPFacCurY], a
    jr .vLeg
.vInc
    inc a
    ld [wBuffer + wPFacCurY], a
    jr .vLeg

; Corridors are 1 tile wide: a 2-wide corridor exactly fills the 2-cell gap
; between adjacent rooms, leaving no wall so the rooms merge into one blob.
; 1-wide leaves wall on either side -> a clean doorway, distinct rooms. Both leg
; stamps are now just the primary cell with contact logic (PFacCorFillCell, the
; old width-lane fill, is unused - kept in case 2-wide + corridor walls returns).
PFacCorStampWideH:
    jp PFacCorStampCell

PFacCorStampWideV:
    jp PFacCorStampCell

; Primary cell: carve UNTOUCHED -> CORRIDOR (and mark exited); if it's already
; ROOMFLOOR and we've exited the source room, set the stop flag (contact reached
; a room). CORRIDOR is deliberately pass-through, NOT contact: the L-bend cell
; the horizontal leg just carved would otherwise stop the vertical leg dead at
; the corner (the "road to nowhere" bug), and letting corridors cross each other
; guarantees every corridor runs all the way to a room.
PFacCorStampCell:
    call PFacReadBlock
    cp PFAC_UNTOUCHED
    jr z, .carve
    cp PFAC_ROOMFLOOR
    jr z, .contact
    ret                          ; CORRIDOR or anything else: pass through
.contact
    ld a, [wBuffer + wPFacCorExited]
    and a
    ret z
    ld a, 1
    ld [wBuffer + wPFacCorStop], a
    ret
.carve
    ld a, PFAC_CORRIDOR
    call PFacWriteBlock
    ld a, 1
    ld [wBuffer + wPFacCorExited], a
    ret

; Width cell: carve UNTOUCHED -> CORRIDOR only; no contact/stop side effects.
PFacCorFillCell:
    call PFacReadBlock
    cp PFAC_UNTOUCHED
    ret nz
    ld a, PFAC_CORRIDOR
    jp PFacWriteBlock

; ============================================================
; PFacCarveNorthExitOpening
; Open the 1-wide warp gap at (exitCol, 0) and punch the exit room's top wall
; ring at (exitCol, 1), connecting the north-edge warp down into the exit room.
; Runs AFTER PFacEncloseRooms (so it overwrites the ring wall) and writes real
; PFAC_FLOOR (untouched by the later convert sweeps).
; ============================================================
PFacCarveNorthExitOpening:
    ld a, [sProcFacilityExitI]
    ld [wBuffer + wPFacCurX], a
    xor a
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_FLOOR
    call PFacWriteBlock
    ld a, 1
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_FLOOR
    jp PFacWriteBlock

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
; PFacPreload::
; Called at Pallet Town entry. Resets bake flag + per-run SRAM state, rolls the
; palette variant and sign variant, and sets the wild budget.
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

    ; Roll palette variant: 0 = PowerPlant (green), 1 = Mansion (red). Cosmetic
    ; only now - read by SetPal_Overworld's FACILITY case, no longer branches
    ; generation.
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
; PFacFinalize::
; Called at PROCEDURAL_FACILITY warp-in.
;   First visit (sProcFacilityBaked=0): generate, bake to SRAM.
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

    ; Seed the whole player area with the untouched sentinel, then run the
    ; room-tree pipeline. On return the map holds only real block IDs and
    ; sProcFacilityGenScratch[0..7] / wPFacItemTemp hold the ball coords + items.
    call PFacFillUntouched
    call PFacGenerateFacility

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
