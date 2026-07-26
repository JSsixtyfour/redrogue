; custom_functions/procedural_facility_gen.asm
;
; Procedural facility generator for PROCEDURAL_FACILITY ($F3).
;
; Wall-room map (redesign v2, "islands in a floor sea" / Model B, see Red Rogue
; Files/1-i-need-you-foamy-otter.md). Key insight from a flood-fill experiment:
; every directional wall block (65 top/73 bottom/68 left/70 right + corners
; 64/66/72/74) is HALF floor, half solid - walkable on its floor half. So a
; room's own walls provide the walkable floor, and a room only 2 blocks wide
; (walls included) IS a corridor. There are no separate carved corridors: the
; whole interior is floor from the start (PFacFillFloor), ringed by a perimeter
; wall with one exit gap (PFacDrawPerimeter), and rooms are directional-wall
; rectangles (2x4 minimum footprint, area >=8) dropped onto the floor with a
; random >=1-tile gap between them (PFacPlaceRooms), each punching one doorway
; into the surrounding floor (PFacPunchDoorway). Connectivity is that
; surrounding floor: rectangles separated by >=1-tile gaps can never seal off a
; pocket, so the spawn, every room's doorway, and the exit all open onto one
; connected sea - no parent tree, no flood-fill, no dead space. A 1-tile gap
; between two rooms reads as a walled corridor (walled by the rooms themselves).
; (Shared-wall 0-gap packing is a deferred option; PFacDrawRoom already takes a
; skip-edge parameter for it.)
;
; SRAM: uses its own sProcFacility* fields (see ram/sram.asm). sProcFacilityBaked
; controls fast re-entry. Reuses the cave's boss/wild/item engine + PC_* events
; (never concurrent), exactly like the forest.
;
; STAGED IMPLEMENTATION (see the plan's Model split table): this file currently
; has the constants, the shared primitives, and the 4 structural building
; blocks - PFacFillFloor, PFacDrawPerimeter, PFacDrawRoom, PFacPunchDoorway -
; that the growth-placement loop (Opus, step 7) will call. NOT YET WRITTEN: the
; growth-placement loop itself (picks a parent wall, rolls a room, validates
; share-not-abut, appends the SRAM record, calls PFacDrawRoom + PFacPunchDoorway),
; roles + the item-placement rewrite (step 8), and PFacGenerateFacility +
; PFacFinalize's rewiring (step 9). PFacFinalize (unchanged below) still calls
; the now-deleted PFacFillUntouched/PFacGenerateFacility, so this file will NOT
; assemble until step 9 lands - expected, matches the prior redesign's staging.

SECTION "ProceduralFacilityGen", ROMX

DEF PFAC_SIZE    EQU 20
DEF PFAC_STRIDE  EQU 26
DEF PFAC_BASE    EQU 81

DEF PFAC_FLOOR   EQU 14   ; facility floor block (all-$01, passable)
DEF PFAC_WALL    EQU 46   ; solid interior wall AND the map border/void block.

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

; --- Doorway jambs: a straight wall cell flanking a punched opening, IDs
; confirmed against facility.bst's raw tile-pattern bytes (not guessed) - each
; jamb is its base wall block with an end-cap texture on the edge FACING the
; gap. "[wall] to the [dir] becomes [jamb]" = the wall segment sitting on the
; [dir] side of the gap becomes [jamb]. ---
DEF PFAC_J_TOP_W    EQU 99   ; PFAC_W_TOP,    gap to its EAST
DEF PFAC_J_TOP_E    EQU 103  ; PFAC_W_TOP,    gap to its WEST
DEF PFAC_J_BOT_W    EQU 88   ; PFAC_W_BOTTOM, gap to its EAST
DEF PFAC_J_BOT_E    EQU 87   ; PFAC_W_BOTTOM, gap to its WEST
DEF PFAC_J_LEFT_N   EQU 85   ; PFAC_W_LEFT,   gap to its SOUTH
DEF PFAC_J_LEFT_S   EQU 89   ; PFAC_W_LEFT,   gap to its NORTH
DEF PFAC_J_RIGHT_N  EQU 86   ; PFAC_W_RIGHT,  gap to its SOUTH
DEF PFAC_J_RIGHT_S  EQU 90   ; PFAC_W_RIGHT,  gap to its NORTH

; --- Perimeter exit passage blocks (v1 ships north only; E/W kept for a
; later multi-edge pass). ---
DEF PFAC_EXIT_N EQU 8
DEF PFAC_EXIT_E EQU 4
DEF PFAC_EXIT_W EQU 5

; --- Room record model (SRAM sProcFacilityRoomBuf, see ram/sram.asm): each
; grown room is appended as it's placed, 5 bytes (X,Y,W,H,role). X,Y,W,H are
; the FULL FOOTPRINT (walls included - "size counts walls"). No Parent field:
; a room's doorway to its parent is punched into the map at growth time, so
; the spanning tree lives in the map itself. Room count lives in WRAM
; (wPFacRoomCount below), incremented as rooms are appended. ---
DEF PFAC_ROOM_REC_SIZE EQU 5
DEF PFAC_ROOM_MAX      EQU 48   ; sProcFacilityRoomBuf is 240 bytes = 48*5
DEF PFAC_ROLE_ENTRY EQU 0
DEF PFAC_ROLE_ITEM  EQU 1
DEF PFAC_ROLE_EXIT  EQU 2
DEF PFAC_ROLE_PLAIN EQU 3

; wBuffer scratch offsets. Facility never runs concurrently with cave/cemetery/
; forest generation, so it reuses the same 30-byte wBuffer window they use
; (ram/wram.asm: wBuffer:: ds 30 - offsets 0-29 are the entire budget).
DEF wPFacTargetBaseLo EQU 0
DEF wPFacTargetBaseHi EQU 1
DEF wPFacCurX         EQU 2   ; block-space X for PFacWriteBlock/PFacReadBlock
DEF wPFacCurY         EQU 3   ; block-space Y

; Room count persists across the WHOLE pipeline (placement through item
; placement), so it gets a fixed offset outside the per-phase reuse window
; below.
DEF wPFacRoomCount    EQU 25

; --- Per-phase scratch (offsets 4-24). Phases never run concurrently (mirrors
; the cave/forest/cemetery convention), so each phase freely reuses this same
; numeric range under its own names. The growth-placement loop (pending, step
; 7) may use 16-24 for its own candidate/parent/overlap-check scratch without
; colliding with anything below. ---

; PFacDrawRoom (offsets 4-9) / PFacPunchDoorway (offsets 4-5, reused - draw and
; punch are always called sequentially per room, never concurrently):
DEF wPFacDrawX        EQU 4   ; room footprint X (top-left block col)
DEF wPFacDrawY        EQU 5   ; room footprint Y (top-left block row)
DEF wPFacDrawW        EQU 6   ; room footprint W
DEF wPFacDrawH        EQU 7   ; room footprint H
DEF wPFacDrawSkip     EQU 8   ; 0=none,1=top,2=bottom,3=left,4=right: the ONE
                              ; edge already drawn by the parent room, not
                              ; redrawn here ("share a wall", never abut)
DEF wPFacDrawCounter  EQU 9   ; inner loop counter
DEF wPFacFlankExpect  EQU 4   ; PFacPunchDoorway: expected straight-wall ID
DEF wPFacFlankJamb    EQU 5   ; PFacPunchDoorway: jamb ID to write if it matches

; Item-placement scratch (kept at its existing offsets for continuity with
; PFacFinalize's unchanged bake tail, which reads wPFacItemTemp by name; the
; step-8 item-placement rewrite will reuse these).
DEF wPFacBallIdx      EQU 10  ; item-room loop index (0-3)
DEF wPFacItemRetry    EQU 11  ; item-dedup retry counter
DEF wPFacItemTemp     EQU 12  ; 4 bytes (12-15): rolled item IDs

; Growth-placement phase (step 7). wPFacGrowFail persists across the whole loop;
; the rest are per-attempt. wPFacChk{X,Y,W,H} is a dual-use temp: it first holds
; the chosen parent's rect (to derive the candidate), then is overwritten with
; the validity-scan rect (footprint + 3-side margin, minus the shared edge).
DEF wPFacGrowFail     EQU 16  ; consecutive placement failures ("pack until full")
DEF wPFacGrowParent   EQU 17  ; chosen parent room index
DEF wPFacGrowSide     EQU 18  ; 0=N,1=S,2=E,3=W: side of parent the child grows from
DEF wPFacChkX         EQU 19
DEF wPFacChkY         EQU 20
DEF wPFacChkW         EQU 21
DEF wPFacChkH         EQU 22
DEF wPFacNewRole      EQU 23  ; role for the next PFacAppendRoom; also an overlap/
                              ; scan index temp (both item/growth-phase only)
DEF wPFacAlong        EQU 24  ; growth: the along-the-shared-wall dimension temp

; ============================================================
; PFacRowOffsetTable / PFacWriteBlock / PFacReadBlock / PFacPickFloor
; Shared primitives used by every generation phase.
; ============================================================
PFacRowOffsetTable:
    FOR pfac_row, PFAC_SIZE
    dw pfac_row * PFAC_STRIDE
    ENDR

; INPUT: a = block ID; [wBuffer+wPFacCurX/Y] = logical coords (0-19). Preserves BC.
; Guards against out-of-range coords: a CurX/CurY >= PFAC_SIZE would index past
; the 20-entry PFacRowOffsetTable and write into the stack/other WRAM (crash).
; Such a write is silently skipped instead - a generator bug then shows as a
; missing block in the map rather than a hang.
PFacWriteBlock:
    push af
    ld a, [wBuffer + wPFacCurX]
    cp PFAC_SIZE
    jr nc, .skip
    ld a, [wBuffer + wPFacCurY]
    cp PFAC_SIZE
    jr nc, .skip
    pop af
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
.skip
    pop af
    ret

; INPUT: [wBuffer+wPFacCurX/Y] = logical coords. OUTPUT: a = block value. Preserves BC.
; Out-of-range coords return PFAC_WALL rather than reading past the row table.
PFacReadBlock:
    ld a, [wBuffer + wPFacCurX]
    cp PFAC_SIZE
    jr nc, .oob
    ld a, [wBuffer + wPFacCurY]
    cp PFAC_SIZE
    jr nc, .oob
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
.oob
    ld a, PFAC_WALL
    ret

; OUTPUT: a = floor block. Facility ships a single floor block (14). Kept as a
; function so ported/future carve code can call it identically to the forest's
; PFPickFloor (a floor-variety table can be added here later).
PFacPickFloor:
    ld a, PFAC_FLOOR
    ret

; ============================================================
; PFacFillFloor
; Seed the whole 20x20 player area with floor (14). Rooms only ever ADD wall/
; corner blocks on top of this; nothing needs a later "convert sentinel"
; sweep - the old two-pass pseudo-value model is gone entirely. Border padding
; (already PFAC_WALL from the object file's border block) is untouched.
; ============================================================
PFacFillFloor:
    ld hl, wOverworldMap + PFAC_BASE
    ld b, PFAC_SIZE
.rowLoop
    push bc
    ld c, PFAC_SIZE
.colLoop
    ld a, PFAC_FLOOR
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
; PFacDrawPerimeter
; Draws a solid directional wall ring around the FULL 20x20 player area's edge
; (row0/row19/col0/col19), like one giant room with no interior fill (the
; interior is already floor from PFacFillFloor). NO exit gap here - the north
; exit is punched later by PFacGrowExitRoom at the column its exit room lands
; on (block PFAC_EXIT_N at row 0, column stored in sProcFacilityExitI for the
; warp-patch code in PFacFinalize). v1 ships north-only.
; ============================================================
PFacDrawPerimeter:
    ; --- Top row (row 0): solid wall the whole way; the north exit gap is
    ; punched later by PFacGrowExitRoom, at the column its exit room lands on. ---
    xor a
    ld [wBuffer + wPFacCurY], a
    ld [wBuffer + wPFacCurX], a
    ld a, PFAC_C_TL
    call PFacWriteBlock
    ld a, 1
    ld [wBuffer + wPFacCurX], a
.topLoop
    ld a, PFAC_W_TOP
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    cp PFAC_SIZE - 1
    jr c, .topLoop
    ld a, PFAC_C_TR
    call PFacWriteBlock

    ; --- Bottom row (row 19) ---
    xor a
    ld [wBuffer + wPFacCurX], a
    ld a, PFAC_SIZE - 1
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_C_BL
    call PFacWriteBlock
    ld a, 1
    ld [wBuffer + wPFacCurX], a
.bottomLoop
    ld a, PFAC_W_BOTTOM
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    cp PFAC_SIZE - 1
    jr c, .bottomLoop
    ld a, PFAC_C_BR
    call PFacWriteBlock

    ; --- Left column (col 0), rows 1-18 ---
    xor a
    ld [wBuffer + wPFacCurX], a
    ld a, 1
    ld [wBuffer + wPFacCurY], a
.leftLoop
    ld a, PFAC_W_LEFT
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    cp PFAC_SIZE - 1
    jr c, .leftLoop

    ; --- Right column (col 19), rows 1-18 ---
    ld a, PFAC_SIZE - 1
    ld [wBuffer + wPFacCurX], a
    ld a, 1
    ld [wBuffer + wPFacCurY], a
.rightLoop
    ld a, PFAC_W_RIGHT
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    cp PFAC_SIZE - 1
    jr c, .rightLoop
    ret

; ============================================================
; PFacDrawRoom
; INPUT: wBuffer+wPFacDrawX/Y/W/H = room footprint (walls included; the
; caller enforces min 2x4 / area>=8). wBuffer+wPFacDrawSkip = which ONE edge
; (0=none,1=top,2=bottom,3=left,4=right) is already drawn as the parent room's
; wall and must NOT be redrawn here ("share a wall, never abut": the child's
; footprint overlaps the parent's wall row/col by exactly one cell; leaving it
; untouched is what makes it shared instead of double-thick). Draws the
; remaining 3 (or 4) directional walls + their corners, and fills any true
; interior (W>=3 AND H>=3) with plain floor - a 2-wide/2-tall room has no
; separate interior; its walkable channel is just the two facing walls' own
; floor halves, already true from PFacFillFloor and untouched here.
; Clobbers a, b, c, hl.
; ============================================================
PFacDrawRoom:
    ; --- Top edge (row Y): corners + PFAC_W_TOP, skip=1 ---
    ld a, [wBuffer + wPFacDrawSkip]
    cp 1
    jr z, .noTop
    ld a, [wBuffer + wPFacDrawY]
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDrawX]
    ld [wBuffer + wPFacCurX], a
    ld a, PFAC_C_TL
    call PFacWriteBlock
    ld a, [wBuffer + wPFacDrawW]
    sub 2
    ld [wBuffer + wPFacDrawCounter], a
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDrawCounter]
    and a
    jr z, .topStraightDone
.topStraightLoop
    ld a, PFAC_W_TOP
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDrawCounter]
    dec a
    ld [wBuffer + wPFacDrawCounter], a
    jr nz, .topStraightLoop
.topStraightDone
    ld a, PFAC_C_TR
    call PFacWriteBlock
.noTop

    ; --- Bottom edge (row Y+H-1): corners + PFAC_W_BOTTOM, skip=2 ---
    ld a, [wBuffer + wPFacDrawSkip]
    cp 2
    jr z, .noBottom
    ld a, [wBuffer + wPFacDrawY]
    ld b, a
    ld a, [wBuffer + wPFacDrawH]
    add a, b
    dec a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDrawX]
    ld [wBuffer + wPFacCurX], a
    ld a, PFAC_C_BL
    call PFacWriteBlock
    ld a, [wBuffer + wPFacDrawW]
    sub 2
    ld [wBuffer + wPFacDrawCounter], a
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDrawCounter]
    and a
    jr z, .bottomStraightDone
.bottomStraightLoop
    ld a, PFAC_W_BOTTOM
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDrawCounter]
    dec a
    ld [wBuffer + wPFacDrawCounter], a
    jr nz, .bottomStraightLoop
.bottomStraightDone
    ld a, PFAC_C_BR
    call PFacWriteBlock
.noBottom

    ; --- Left edge (col X), straight segment rows Y+1..Y+H-2, skip=3 ---
    ld a, [wBuffer + wPFacDrawSkip]
    cp 3
    jr z, .noLeft
    ld a, [wBuffer + wPFacDrawH]
    sub 2
    ld [wBuffer + wPFacDrawCounter], a
    jr z, .noLeft                ; H=2: no straight segment (2-wide corridor)
    ld a, [wBuffer + wPFacDrawX]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDrawY]
    inc a
    ld [wBuffer + wPFacCurY], a
.leftLoop
    ld a, PFAC_W_LEFT
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDrawCounter]
    dec a
    ld [wBuffer + wPFacDrawCounter], a
    jr nz, .leftLoop
.noLeft

    ; --- Right edge (col X+W-1), straight segment rows Y+1..Y+H-2, skip=4 ---
    ld a, [wBuffer + wPFacDrawSkip]
    cp 4
    jr z, .noRight
    ld a, [wBuffer + wPFacDrawH]
    sub 2
    ld [wBuffer + wPFacDrawCounter], a
    jr z, .noRight
    ld a, [wBuffer + wPFacDrawX]
    ld b, a
    ld a, [wBuffer + wPFacDrawW]
    add a, b
    dec a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDrawY]
    inc a
    ld [wBuffer + wPFacCurY], a
.rightLoop
    ld a, PFAC_W_RIGHT
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, [wBuffer + wPFacDrawCounter]
    dec a
    ld [wBuffer + wPFacDrawCounter], a
    jr nz, .rightLoop
.noRight

    ; --- Interior floor: rows Y+1..Y+H-2, cols X+1..X+W-2 (only if W>=3,H>=3) ---
    ld a, [wBuffer + wPFacDrawW]
    sub 2
    jr z, .noInterior
    jr c, .noInterior
    ld [wBuffer + wPFacDrawCounter], a   ; interior width, reloaded each row
    ld a, [wBuffer + wPFacDrawH]
    sub 2
    jr z, .noInterior
    jr c, .noInterior
    ld b, a                       ; b = interior height (row count)
    ld a, [wBuffer + wPFacDrawY]
    inc a
    ld [wBuffer + wPFacCurY], a
.interiorRowLoop
    push bc
    ld a, [wBuffer + wPFacDrawX]
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDrawCounter]
    ld c, a
.interiorColLoop
    ld a, PFAC_FLOOR
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurX]
    inc a
    ld [wBuffer + wPFacCurX], a
    dec c
    jr nz, .interiorColLoop
    ld a, [wBuffer + wPFacCurY]
    inc a
    ld [wBuffer + wPFacCurY], a
    pop bc
    dec b
    jr nz, .interiorRowLoop
.noInterior
    ret

; ============================================================
; PFacPunchDoorway
; INPUT: wBuffer+wPFacCurX/Y = the gap cell to open - currently one of the 4
; plain straight-wall blocks (65/68/70/73), NOT a corner; the caller (growth
; loop) is responsible for only choosing straight-wall positions. Converts
; that cell to floor, then rewrites its two flanking cells along the same wall
; run to the matching jamb variant, IF they're still a plain straight wall of
; the same orientation (defends against a flanking cell already being a
; corner or another jamb - left untouched rather than corrupted). Geometry
; confirmed against facility.bst's raw tile-pattern bytes: each jamb is its
; base wall block with an end-cap texture on the edge FACING the gap.
;   PFAC_W_TOP    -> west:PFAC_J_TOP_W    east:PFAC_J_TOP_E
;   PFAC_W_BOTTOM -> west:PFAC_J_BOT_W    east:PFAC_J_BOT_E
;   PFAC_W_LEFT   -> north:PFAC_J_LEFT_N  south:PFAC_J_LEFT_S
;   PFAC_W_RIGHT  -> north:PFAC_J_RIGHT_N south:PFAC_J_RIGHT_S
; If the gap cell isn't one of those 4 IDs, it's still opened to floor but no
; jambs are written (unknown/corner - shouldn't happen per the caller
; contract, but never corrupts an unrelated block). Clobbers a, b, c, hl.
; ============================================================
PFacPunchDoorway:
    call PFacReadBlock
    ld b, a                      ; b = the wall block being punched

    ld a, PFAC_FLOOR
    call PFacWriteBlock

    ld a, b
    cp PFAC_W_TOP
    jr z, .doTop
    cp PFAC_W_BOTTOM
    jr z, .doBottom
    cp PFAC_W_LEFT
    jr z, .doLeft
    cp PFAC_W_RIGHT
    jr z, .doRight
    ret                          ; unknown/corner - already opened, no jambs

.doTop
    ld a, PFAC_W_TOP
    ld b, PFAC_J_TOP_W
    ld c, PFAC_J_TOP_E
    jp PFacPunchFlanksH
.doBottom
    ld a, PFAC_W_BOTTOM
    ld b, PFAC_J_BOT_W
    ld c, PFAC_J_BOT_E
    jp PFacPunchFlanksH
.doLeft
    ld a, PFAC_W_LEFT
    ld b, PFAC_J_LEFT_N
    ld c, PFAC_J_LEFT_S
    jp PFacPunchFlanksV
.doRight
    ld a, PFAC_W_RIGHT
    ld b, PFAC_J_RIGHT_N
    ld c, PFAC_J_RIGHT_S
    jp PFacPunchFlanksV

; Horizontal wall run (top/bottom): flank west (X-1) and east (X+1) of the
; already-opened gap. INPUT a=expected straight-wall ID, b=west jamb, c=east
; jamb. wPFacCurX/Y point at the (now floor) gap cell on entry.
PFacPunchFlanksH:
    ld [wBuffer + wPFacFlankExpect], a
    ld a, b
    ld [wBuffer + wPFacFlankJamb], a
    ld a, [wBuffer + wPFacCurX]
    dec a
    ld [wBuffer + wPFacCurX], a
    call PFacFlankRewrite
    ld a, [wBuffer + wPFacCurX]
    inc a
    inc a
    ld [wBuffer + wPFacCurX], a
    ld a, c
    ld [wBuffer + wPFacFlankJamb], a
    jp PFacFlankRewrite

; Vertical wall run (left/right): flank north (Y-1) and south (Y+1).
PFacPunchFlanksV:
    ld [wBuffer + wPFacFlankExpect], a
    ld a, b
    ld [wBuffer + wPFacFlankJamb], a
    ld a, [wBuffer + wPFacCurY]
    dec a
    ld [wBuffer + wPFacCurY], a
    call PFacFlankRewrite
    ld a, [wBuffer + wPFacCurY]
    inc a
    inc a
    ld [wBuffer + wPFacCurY], a
    ld a, c
    ld [wBuffer + wPFacFlankJamb], a
    jp PFacFlankRewrite

; Rewrites [wPFacCurX/Y] to wPFacFlankJamb IF it currently equals
; wPFacFlankExpect (a plain straight wall); leaves any other value (corner,
; another jamb, floor) untouched. Clobbers a, hl.
PFacFlankRewrite:
    call PFacReadBlock
    ld hl, wBuffer + wPFacFlankExpect
    cp [hl]
    ret nz
    ld a, [wBuffer + wPFacFlankJamb]
    jp PFacWriteBlock

; ============================================================
; PFacRollRoomDim
; OUTPUT a = a room dimension in [2,9], covering the FULL footprint (walls
; included - "size counts walls"). HEAVILY biased toward small: taking the
; minimum of two independent 0-7 rolls skews the result low. Distribution ~=
; 2:24% 3:20% 4:17% 5:14% 6:11% 7:8% 8:5% 9:1%. The caller (growth loop) is
; responsible for enforcing area>=8 (e.g. reroll or bump the other dimension
; up when both come out at 2-3). Clobbers a, b, c.
; ============================================================
PFacRollRoomDim:
    ld c, 8
    call Rangerandom            ; r1 = 0..7
    push af
    ld c, 8
    call Rangerandom            ; r2 = 0..7 (in a)
    pop bc                      ; b = r1
    cp b
    jr c, .haveMin               ; a < b -> a is the min
    ld a, b
.haveMin
    add a, 2                     ; 2..9
    ret

; ============================================================
; PFacRoomRecAddr
; INPUT a = room index (0..PFAC_ROOM_MAX-1). OUTPUT hl = address of that room's
; 5-byte record in sProcFacilityRoomBuf. a preserved, de clobbered.
; ============================================================
PFacRoomRecAddr:
    ld h, 0
    ld l, a
    add hl, hl          ; idx*2
    add hl, hl          ; idx*4
    ld d, 0
    ld e, a
    add hl, de          ; idx*5
    ld de, sProcFacilityRoomBuf
    add hl, de
    ret

; ============================================================
; PFacPlaceRooms  (shared-wall growth tree, plan step 7 rewrite)
; Seeds an entry room over the spawn, then grows rooms off existing rooms'
; walls: each new room shares ONE wall with a parent room (its footprint
; overlaps the parent's wall by one row/col, drawn with that edge skipped) and
; punches a doorway through the shared wall to the parent. That makes the whole
; thing one connected network (a spanning tree rooted at the entry) with no
; wasted gaps - dense, and reachable by construction. Repeats until the room
; table is full or N consecutive growth failures ("pack until full"). The exit
; room + boss chamber is chosen afterward by PFacMakeExit.
; ============================================================
PFacPlaceRooms:
    call PFacPlaceEntryRoom
    xor a
    ld [wBuffer + wPFacGrowFail], a
.loop
    ld a, [wBuffer + wPFacRoomCount]
    cp PFAC_ROOM_MAX
    ret nc
    call PFacTryGrow
    and a
    jr z, .success
    ld a, [wBuffer + wPFacGrowFail]
    inc a
    ld [wBuffer + wPFacGrowFail], a
    cp 120                      ; N consecutive failures = map effectively full
    ret nc
    jr .loop
.success
    xor a
    ld [wBuffer + wPFacGrowFail], a
    jr .loop

; Seed room 0 = the entry, covering the fixed spawn block (9,17). Shares the
; south perimeter wall (skip bottom = row 19), so no double wall there. role
; ENTRY, no doorway (it's the tree root; its children punch doorways into it).
PFacPlaceEntryRoom:
    xor a
    ld [wBuffer + wPFacRoomCount], a
.rollW
    call PFacRollRoomDim
    ld [wBuffer + wPFacDrawW], a
    cp 3
    jr c, .rollW                ; need W>=3 so (9,17) can be interior
.rollH
    call PFacRollRoomDim
    ld [wBuffer + wPFacDrawH], a
    cp 4
    jr c, .rollH                ; need H>=4 so row 17 is interior (bottom=19)
    ; Y = 20 - H  (footprint rows [20-H .. 19]; row 19 is the perimeter, skipped)
    ld a, 20
    ld hl, wBuffer + wPFacDrawH
    sub [hl]
    ld [wBuffer + wPFacDrawY], a
    ; X = 9 - W/2, clamped to [2, 18-W] so col 9 sits in the interior
    ld a, [wBuffer + wPFacDrawW]
    srl a
    ld b, a
    ld a, 9
    sub b
    cp 2
    jr nc, .xLo
    ld a, 2
.xLo
    ld b, a
    ld a, 18
    ld hl, wBuffer + wPFacDrawW
    sub [hl]                    ; 18 - W
    cp b
    jr nc, .xHi                 ; 18-W >= X -> keep X
    ld b, a
.xHi
    ld a, b
    ld [wBuffer + wPFacDrawX], a
    ld a, 2                     ; skip bottom (share perimeter)
    ld [wBuffer + wPFacDrawSkip], a
    ld a, PFAC_ROLE_ENTRY
    ld [wBuffer + wPFacNewRole], a
    call PFacAppendRoom
    jp PFacDrawRoom

; One growth attempt: pick a parent room + side, roll a child that shares that
; wall, validate, and on success append + draw (skip shared edge) + punch the
; shared-wall doorway. OUT a=0 success, a=1 fail. Child footprint is counted
; INCLUDING walls; the shared edge overlaps the parent by exactly one row/col.
PFacTryGrow:
    ld a, [wBuffer + wPFacRoomCount]
    cp 1
    jr nz, .randParent
    xor a                       ; first growth: force it off the entry (root)
    jr .haveParent
.randParent
    ld a, [wBuffer + wPFacRoomCount]
    ld c, a
    call Rangerandom
.haveParent
    ld [wBuffer + wPFacGrowParent], a
    call PFacRoomRecAddr
    ld a, [hli]
    ld [wBuffer + wPFacChkX], a
    ld a, [hli]
    ld [wBuffer + wPFacChkY], a
    ld a, [hli]
    ld [wBuffer + wPFacChkW], a
    ld a, [hl]
    ld [wBuffer + wPFacChkH], a
    ; pick a side (0=N,1=S,2=E,3=W)
    ld c, 4
    call Rangerandom
    ld [wBuffer + wPFacGrowSide], a
    cp 2
    jr nc, .sideEW
    ld a, [wBuffer + wPFacChkW]  ; N/S: parent needs a straight top/bottom wall
    cp 3
    jp c, .fail
    jr .haveBound
.sideEW
    ld a, [wBuffer + wPFacChkH]  ; E/W: parent needs a straight left/right wall
    cp 3
    jp c, .fail
.haveBound
    ld [wBuffer + wPFacAlong], a   ; parentAlong bound (PW for N/S, PH for E/W)
    ; along = min(roll, parentAlong)
    call PFacRollRoomDim
    ld hl, wBuffer + wPFacAlong
    cp [hl]
    jr c, .alongOK
    ld a, [hl]
.alongOK
    ld [wBuffer + wPFacAlong], a
    ; perp = roll, bumped up so along*perp >= 8
    call PFacRollRoomDim
    ld b, a
    ld a, [wBuffer + wPFacAlong]
    cp 4
    jr nc, .areaOK              ; along>=4 -> any perp>=2 is fine
    cp 3
    jr nz, .alongIs2
    ld a, b                     ; along==3 -> perp>=3
    cp 3
    jr nc, .areaOK
    ld b, 3
    jr .areaOK
.alongIs2
    ld a, b                     ; along==2 -> perp>=4
    cp 4
    jr nc, .areaOK
    ld b, 4
.areaOK
    ; assign W/H from along/perp per side orientation
    ld a, [wBuffer + wPFacGrowSide]
    cp 2
    jr nc, .assignEW
    ld a, [wBuffer + wPFacAlong]   ; N/S: W=along, H=perp
    ld [wBuffer + wPFacDrawW], a
    ld a, b
    ld [wBuffer + wPFacDrawH], a
    jr .placeBySide
.assignEW
    ld a, b                        ; E/W: W=perp, H=along
    ld [wBuffer + wPFacDrawW], a
    ld a, [wBuffer + wPFacAlong]
    ld [wBuffer + wPFacDrawH], a
.placeBySide
    ld a, [wBuffer + wPFacGrowSide]
    and a
    jp z, .growN
    cp 1
    jp z, .growS
    cp 2
    jp z, .growE
    jp .growW
.growS
    ld a, [wBuffer + wPFacChkY]     ; child top row = parent bottom row (shared)
    ld hl, wBuffer + wPFacChkH
    add a, [hl]
    dec a
    ld [wBuffer + wPFacDrawY], a
    call PFacGrowColInParent
    ld a, 1                        ; skip top
    ld [wBuffer + wPFacDrawSkip], a
    jp .validate
.growN
    ld a, [wBuffer + wPFacChkY]     ; child bottom row = parent top row (shared)
    ld hl, wBuffer + wPFacDrawH
    sub [hl]
    inc a
    ld [wBuffer + wPFacDrawY], a
    call PFacGrowColInParent
    ld a, 2                        ; skip bottom
    ld [wBuffer + wPFacDrawSkip], a
    jp .validate
.growE
    ld a, [wBuffer + wPFacChkX]     ; child left col = parent right col (shared)
    ld hl, wBuffer + wPFacChkW
    add a, [hl]
    dec a
    ld [wBuffer + wPFacDrawX], a
    call PFacGrowRowInParent
    ld a, 3                        ; skip left
    ld [wBuffer + wPFacDrawSkip], a
    jp .validate
.growW
    ld a, [wBuffer + wPFacChkX]     ; child right col = parent left col (shared)
    ld hl, wBuffer + wPFacDrawW
    sub [hl]
    inc a
    ld [wBuffer + wPFacDrawX], a
    call PFacGrowRowInParent
    ld a, 4                        ; skip right
    ld [wBuffer + wPFacDrawSkip], a
.validate
    call PFacGrowBounds
    and a
    jp nz, .fail
    call PFacGrowOverlap
    and a
    jp nz, .fail
    ld a, PFAC_ROLE_PLAIN
    ld [wBuffer + wPFacNewRole], a
    call PFacAppendRoom
    call PFacDrawRoom
    call PFacGrowDoorway
    xor a
    ret
.fail
    ld a, 1
    ret

; N/S growth: pick child X so its shared top/bottom edge sits within the parent
; column span: X = PX + rand(PW - CW + 1). Parent rect in Chk*, child W in DrawW.
PFacGrowColInParent:
    ld a, [wBuffer + wPFacChkW]
    ld hl, wBuffer + wPFacDrawW
    sub [hl]
    inc a
    ld c, a
    call Rangerandom
    ld hl, wBuffer + wPFacChkX
    add a, [hl]
    ld [wBuffer + wPFacDrawX], a
    ret

; E/W growth: pick child Y within the parent row span: Y = PY + rand(PH-CH+1).
PFacGrowRowInParent:
    ld a, [wBuffer + wPFacChkH]
    ld hl, wBuffer + wPFacDrawH
    sub [hl]
    inc a
    ld c, a
    call Rangerandom
    ld hl, wBuffer + wPFacChkY
    add a, [hl]
    ld [wBuffer + wPFacDrawY], a
    ret

; a=1 if the child footprint leaves the interior (cols/rows must be in [1..18],
; X+W<=19, Y+H<=19); else a=0. Also catches under/overflow from the growth math.
PFacGrowBounds:
    ld a, [wBuffer + wPFacDrawX]
    and a
    jr z, .bad
    cp 19
    jr nc, .bad
    ld a, [wBuffer + wPFacDrawY]
    and a
    jr z, .bad
    cp 19
    jr nc, .bad
    ld a, [wBuffer + wPFacDrawX]
    ld hl, wBuffer + wPFacDrawW
    add a, [hl]
    cp 20
    jr nc, .bad
    ld a, [wBuffer + wPFacDrawY]
    ld hl, wBuffer + wPFacDrawH
    add a, [hl]
    cp 20
    jr nc, .bad
    xor a
    ret
.bad
    ld a, 1
    ret

; a=1 if the child properly overlaps any room OTHER than its parent (touching /
; shared edges are allowed - that's dense packing); a=0 otherwise. The parent is
; skipped because the child intentionally overlaps its shared wall by one cell.
PFacGrowOverlap:
    xor a
    ld [wBuffer + wPFacNewRole], a   ; scan index
.loop
    ld a, [wBuffer + wPFacNewRole]
    ld hl, wBuffer + wPFacRoomCount
    cp [hl]
    jr nc, .clear
    ld hl, wBuffer + wPFacGrowParent
    cp [hl]
    jr z, .next                      ; skip the parent
    ld a, [wBuffer + wPFacNewRole]
    call PFacRoomRecAddr
    ld a, [hli]
    ld [wBuffer + wPFacChkX], a
    ld a, [hli]
    ld [wBuffer + wPFacChkY], a
    ld a, [hli]
    ld [wBuffer + wPFacChkW], a
    ld a, [hl]
    ld [wBuffer + wPFacChkH], a
    ; separated (touching allowed) if any of the 4 "<=" hold
    ld a, [wBuffer + wPFacDrawX]
    ld hl, wBuffer + wPFacDrawW
    add a, [hl]
    ld hl, wBuffer + wPFacChkX
    cp [hl]
    jr c, .next
    jr z, .next                      ; candX+candW <= Bx
    ld a, [wBuffer + wPFacChkX]
    ld hl, wBuffer + wPFacChkW
    add a, [hl]
    ld hl, wBuffer + wPFacDrawX
    cp [hl]
    jr c, .next
    jr z, .next                      ; Bx+Bw <= candX
    ld a, [wBuffer + wPFacDrawY]
    ld hl, wBuffer + wPFacDrawH
    add a, [hl]
    ld hl, wBuffer + wPFacChkY
    cp [hl]
    jr c, .next
    jr z, .next                      ; candY+candH <= By
    ld a, [wBuffer + wPFacChkY]
    ld hl, wBuffer + wPFacChkH
    add a, [hl]
    ld hl, wBuffer + wPFacDrawY
    cp [hl]
    jr c, .next
    jr z, .next                      ; By+Bh <= candY
    ld a, 1                          ; none separated -> proper overlap
    ret
.next
    ld a, [wBuffer + wPFacNewRole]
    inc a
    ld [wBuffer + wPFacNewRole], a
    jr .loop
.clear
    xor a
    ret

; Append wPFacDraw{X,Y,W,H} + wPFacNewRole to sProcFacilityRoomBuf[count], count++.
PFacAppendRoom:
    ld a, [wBuffer + wPFacRoomCount]
    call PFacRoomRecAddr
    ld a, [wBuffer + wPFacDrawX]
    ld [hli], a
    ld a, [wBuffer + wPFacDrawY]
    ld [hli], a
    ld a, [wBuffer + wPFacDrawW]
    ld [hli], a
    ld a, [wBuffer + wPFacDrawH]
    ld [hli], a
    ld a, [wBuffer + wPFacNewRole]
    ld [hl], a
    ld a, [wBuffer + wPFacRoomCount]
    inc a
    ld [wBuffer + wPFacRoomCount], a
    ret

; Punch the doorway through the just-grown child's shared wall into the parent.
; Reloads the parent rect (Chk*), computes the doorway cell (a straight wall in
; the parent's shared edge, clamped to its straight span) into wPFacCurX/Y, and
; PFacPunchDoorway's it (opens + jambs). Child rect is still in wPFacDraw*.
PFacGrowDoorway:
    ld a, [wBuffer + wPFacGrowParent]
    call PFacRoomRecAddr
    ld a, [hli]
    ld [wBuffer + wPFacChkX], a
    ld a, [hli]
    ld [wBuffer + wPFacChkY], a
    ld a, [hli]
    ld [wBuffer + wPFacChkW], a
    ld a, [hl]
    ld [wBuffer + wPFacChkH], a
    ld a, [wBuffer + wPFacGrowSide]
    and a
    jp z, .dN
    cp 1
    jp z, .dS
    cp 2
    jp z, .dE
    jp .dW
.dS
    ld a, [wBuffer + wPFacChkY]     ; shared row = parent bottom
    ld hl, wBuffer + wPFacChkH
    add a, [hl]
    dec a
    ld [wBuffer + wPFacCurY], a
    call PFacDoorColH
    jp PFacPunchDoorway
.dN
    ld a, [wBuffer + wPFacChkY]     ; shared row = parent top
    ld [wBuffer + wPFacCurY], a
    call PFacDoorColH
    jp PFacPunchDoorway
.dE
    ld a, [wBuffer + wPFacChkX]     ; shared col = parent right
    ld hl, wBuffer + wPFacChkW
    add a, [hl]
    dec a
    ld [wBuffer + wPFacCurX], a
    call PFacDoorRowV
    jp PFacPunchDoorway
.dW
    ld a, [wBuffer + wPFacChkX]     ; shared col = parent left
    ld [wBuffer + wPFacCurX], a
    call PFacDoorRowV
    jp PFacPunchDoorway

; Doorway COLUMN for a horizontal shared wall (N/S): clamp(childX + childW/2,
; PX+1, PX+PW-2) -> wPFacCurX. Guarantees a straight parent wall (not a corner).
PFacDoorColH:
    ld a, [wBuffer + wPFacDrawW]
    srl a
    ld b, a
    ld a, [wBuffer + wPFacDrawX]
    add a, b
    ld hl, wBuffer + wPFacChkX
    ld b, [hl]
    inc b
    cp b
    jr nc, .loOK
    ld a, b
.loOK
    ld c, a
    ld a, [wBuffer + wPFacChkX]
    ld hl, wBuffer + wPFacChkW
    add a, [hl]
    dec a
    dec a
    ld b, a
    ld a, c
    cp b
    jr c, .hiOK
    jr z, .hiOK
    ld a, b
.hiOK
    ld [wBuffer + wPFacCurX], a
    ret

; Doorway ROW for a vertical shared wall (E/W): clamp(childY + childH/2, PY+1,
; PY+PH-2) -> wPFacCurY.
PFacDoorRowV:
    ld a, [wBuffer + wPFacDrawH]
    srl a
    ld b, a
    ld a, [wBuffer + wPFacDrawY]
    add a, b
    ld hl, wBuffer + wPFacChkY
    ld b, [hl]
    inc b
    cp b
    jr nc, .loOK
    ld a, b
.loOK
    ld c, a
    ld a, [wBuffer + wPFacChkY]
    ld hl, wBuffer + wPFacChkH
    add a, [hl]
    dec a
    dec a
    ld b, a
    ld a, c
    cp b
    jr c, .hiOK
    jr z, .hiOK
    ld a, b
.hiOK
    ld [wBuffer + wPFacCurY], a
    ret

; ============================================================
; PFacMakeExit
; Chooses the topmost placed room (smallest Y) as the boss/exit chamber (role
; EXIT), sets sProcFacilityExitI to a straight cell in its top wall, punches a
; doorway there, opens a floor channel straight up to row 0, and stamps the exit
; passage block (PFAC_EXIT_N) at row 0. The player reaches this room through the
; tree, the boss (placed by PFacFinalize at block (exitCol,1)) guards the
; approach, and the channel connects it out. Runs after PFacPlaceRooms.
; ============================================================
PFacMakeExit:
    ld a, [wBuffer + wPFacRoomCount]
    and a
    ret z
    xor a
    ld [wBuffer + wPFacGrowParent], a   ; scan index
    ld a, 255
    ld [wBuffer + wPFacChkY], a          ; best (min) Y so far
    xor a
    ld [wBuffer + wPFacChkX], a          ; best room index
.scan
    ld a, [wBuffer + wPFacGrowParent]
    ld hl, wBuffer + wPFacRoomCount
    cp [hl]
    jr nc, .found
    ld a, [wBuffer + wPFacGrowParent]
    call PFacRoomRecAddr
    inc hl                               ; -> Y
    ld a, [hl]
    ld hl, wBuffer + wPFacChkY
    cp [hl]
    jr nc, .scanNext                     ; not higher (smaller Y)
    ld [hl], a
    ld a, [wBuffer + wPFacGrowParent]
    ld [wBuffer + wPFacChkX], a
.scanNext
    ld a, [wBuffer + wPFacGrowParent]
    inc a
    ld [wBuffer + wPFacGrowParent], a
    jr .scan
.found
    ; load the chosen room's rect into wPFacDraw*, set its role = EXIT
    ld a, [wBuffer + wPFacChkX]
    call PFacRoomRecAddr
    push hl
    ld a, [hli]
    ld [wBuffer + wPFacDrawX], a
    ld a, [hli]
    ld [wBuffer + wPFacDrawY], a
    ld a, [hli]
    ld [wBuffer + wPFacDrawW], a
    ld a, [hli]
    ld [wBuffer + wPFacDrawH], a
    ld a, PFAC_ROLE_EXIT
    ld [hl], a
    pop hl
    ; exitCol = clamp(X + W/2, X+1, X+W-2)
    ld a, [wBuffer + wPFacDrawW]
    srl a
    ld b, a
    ld a, [wBuffer + wPFacDrawX]
    add a, b
    ld hl, wBuffer + wPFacDrawX
    ld b, [hl]
    inc b
    cp b
    jr nc, .exLo
    ld a, b
.exLo
    ld c, a
    ld a, [wBuffer + wPFacDrawX]
    ld hl, wBuffer + wPFacDrawW
    add a, [hl]
    dec a
    dec a
    ld b, a
    ld a, c
    cp b
    jr c, .exHi
    jr z, .exHi
    ld a, b
.exHi
    ld [sProcFacilityExitI], a
    ; punch the doorway in the room's top wall at (exitCol, roomY)
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDrawY]
    ld [wBuffer + wPFacCurY], a
    call PFacPunchDoorway
    ; open a floor channel from (exitCol, roomY-1) up to row 1
    ld a, [sProcFacilityExitI]
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacDrawY]
    dec a
    ld [wBuffer + wPFacCurY], a
.channel
    ld a, [wBuffer + wPFacCurY]
    and a
    jr z, .chanDone
    ld a, PFAC_FLOOR
    call PFacWriteBlock
    ld a, [wBuffer + wPFacCurY]
    dec a
    ld [wBuffer + wPFacCurY], a
    jr .channel
.chanDone
    ; stamp the exit passage block at (exitCol, 0)
    ld a, [sProcFacilityExitI]
    ld [wBuffer + wPFacCurX], a
    xor a
    ld [wBuffer + wPFacCurY], a
    ld a, PFAC_EXIT_N
    jp PFacWriteBlock

; ============================================================
; PFacPlaceItems  (plan step 8)
; Places one pokeball in each of up to 4 rooms that have real interior floor
; (W>=3 AND H>=3), tagging each chosen room's role as PFAC_ROLE_ITEM. Rolls a
; unique item per ball (dedup against earlier picks, rejection-sampling)
; and stores block coords + item IDs into sProcFacilityGenScratch[0..7] /
; wPFacItemTemp[0..3] - the exact contract PFacFinalize's existing bake step
; reads (X,Y pairs per ball, then 4 item IDs), so that copy-to-SRAM code needs
; no changes. If fewer than 4 rooms qualify (shouldn't happen once the map is
; packed - PFacRollRoomDim's bias still puts >=3 on a side more than half the
; time - but defensive), any remaining ball(s) default to the fixed spawn
; block (9,17), which PFacHitsSpawn guarantees stays clear floor. No entry
; room in Model B - the player just spawns on the floor sea. Runs after
; PFacPlaceRooms. Reuses wPFacFlankExpect/wPFacFlankJamb (PFacPunchDoorway's
; scratch, item-placement phase only - room placement has already finished).
; ============================================================
PFacPlaceItems:
    xor a
    ld [wBuffer + wPFacBallIdx], a
.ballLoop
    ld a, [wBuffer + wPFacBallIdx]
    cp 4
    ret z

    call PFacCountEligible          ; a = # placed rooms W>=3,H>=3,role!=ITEM
    and a
    jr z, .fallback

    ld c, a
    call Rangerandom                ; 0..count-1
    call PFacMarkNthEligible        ; marks it ITEM; wPFacChkX/Y/W/H = its rect

    ; random interior cell: X+1..X+W-2, Y+1..Y+H-2
    ld a, [wBuffer + wPFacChkW]
    sub 2
    ld c, a
    call Rangerandom
    ld b, a
    ld a, [wBuffer + wPFacChkX]
    inc a
    add a, b
    ld [wBuffer + wPFacCurX], a
    ld a, [wBuffer + wPFacChkH]
    sub 2
    ld c, a
    call Rangerandom
    ld b, a
    ld a, [wBuffer + wPFacChkY]
    inc a
    add a, b
    ld [wBuffer + wPFacCurY], a
    jr .savePos

.fallback
    ld a, 9
    ld [wBuffer + wPFacCurX], a
    ld a, 17
    ld [wBuffer + wPFacCurY], a

.savePos
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
    jp .ballLoop

; OUTPUT a = count of placed rooms eligible for an item (W>=3, H>=3, role PLAIN).
; Clobbers wPFacGrowParent (scan index) and wPFacFlankExpect (running count) -
; both PFacPlaceRooms/PFacPunchDoorway scratch, safe to reuse here since room
; placement has already finished by the time items are placed.
PFacCountEligible:
    xor a
    ld [wBuffer + wPFacGrowParent], a
    xor a
    ld [wBuffer + wPFacFlankExpect], a
.loop
    ld a, [wBuffer + wPFacGrowParent]
    ld hl, wBuffer + wPFacRoomCount
    cp [hl]
    jr nc, .done
    call PFacRoomEligible
    and a
    jr z, .next
    ld a, [wBuffer + wPFacFlankExpect]
    inc a
    ld [wBuffer + wPFacFlankExpect], a
.next
    ld a, [wBuffer + wPFacGrowParent]
    inc a
    ld [wBuffer + wPFacGrowParent], a
    jr .loop
.done
    ld a, [wBuffer + wPFacFlankExpect]
    ret

; INPUT: wPFacGrowParent = room index. OUTPUT a=1 if the room has real interior
; (W>=3, H>=3) AND role == PLAIN (so the entry and boss/exit rooms are never
; picked as item rooms), else a=0.
PFacRoomEligible:
    ld a, [wBuffer + wPFacGrowParent]
    call PFacRoomRecAddr
    inc hl
    inc hl                    ; hl -> W
    ld a, [hl]
    cp 3
    jr c, .no
    inc hl                    ; hl -> H
    ld a, [hl]
    cp 3
    jr c, .no
    inc hl                    ; hl -> role
    ld a, [hl]
    cp PFAC_ROLE_PLAIN
    jr nz, .no
    ld a, 1
    ret
.no
    xor a
    ret

; INPUT a = N (0-indexed among eligible rooms, per PFacCountEligible's
; definition). Finds the Nth such room, marks its role PFAC_ROLE_ITEM, and
; loads its rect into wPFacChkX/Y/W/H. Clobbers wPFacGrowParent,
; wPFacFlankJamb (target-N countdown, item-placement phase reuse).
PFacMarkNthEligible:
    ld [wBuffer + wPFacFlankJamb], a
    xor a
    ld [wBuffer + wPFacGrowParent], a
.loop
    call PFacRoomEligible
    and a
    jr z, .next
    ld a, [wBuffer + wPFacFlankJamb]
    and a
    jr z, .found
    dec a
    ld [wBuffer + wPFacFlankJamb], a
.next
    ld a, [wBuffer + wPFacGrowParent]
    inc a
    ld [wBuffer + wPFacGrowParent], a
    jr .loop
.found
    ld a, [wBuffer + wPFacGrowParent]
    call PFacRoomRecAddr
    ld a, [hli]
    ld [wBuffer + wPFacChkX], a
    ld a, [hli]
    ld [wBuffer + wPFacChkY], a
    ld a, [hli]
    ld [wBuffer + wPFacChkW], a
    ld a, [hli]
    ld [wBuffer + wPFacChkH], a
    ld a, PFAC_ROLE_ITEM
    ld [hl], a
    ret

; ============================================================
; PFacGenerateFacility  (top-level driver, plan step 9)
; Runs the whole Model B pipeline into wOverworldMap (the target base is set by
; the caller, PFacFinalize). On return the map holds only real block IDs (floor
; 14, walls 65/68/70/73, corners 64/66/72/74, jambs 85-90/99/103, perimeter exit
; 8) and sProcFacilityGenScratch[0..7] / wPFacItemTemp hold the 4 ball block
; coords + item IDs for PFacFinalize to bake. The perimeter exit (block 8 at
; sProcFacilityExitI, row 0) opens onto the floor sea at row 1, which the
; existing boss/warp tail in PFacFinalize guards and warps from - no dedicated
; exit-room wiring needed.
; ============================================================
PFacGenerateFacility:
    call PFacFillFloor
    call PFacDrawPerimeter
    call PFacPlaceRooms
    call PFacMakeExit
    call PFacPlaceItems
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
; not WRAM).
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

    ; Run the Model B pipeline (fill floor -> perimeter -> place rooms ->
    ; place items). On return the map holds only real block IDs and
    ; sProcFacilityGenScratch[0..7] / wPFacItemTemp hold the ball coords + items.
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
