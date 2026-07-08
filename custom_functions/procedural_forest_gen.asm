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

; wBuffer scratch offsets (forest-specific; safe since forest never runs
; concurrently with cave/cemetery gen)
DEF wPFTargetBaseLo EQU 0
DEF wPFTargetBaseHi EQU 1
DEF wPFCurX         EQU 2
DEF wPFCurY         EQU 3
DEF wPFRowJ         EQU 4   ; Sidewinder outer loop row counter (0-8)
DEF wPFRunStart     EQU 5   ; Sidewinder current run's start column

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

    ld a, [sProcForestBaked]
    and a
    jr nz, .fastBlit

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

    ; Run Sidewinder to carve the maze into wOverworldMap
    call PFSidewinder

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
