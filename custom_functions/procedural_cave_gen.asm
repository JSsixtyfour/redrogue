; custom_functions/procedural_cave_gen.asm
;
; Runtime procedural cave generator for ProceduralCave1.
;
; Called once per map load via homecall from LoadMapData (home/overworld.asm,
; verified bank 00/HOME), right after LoadTileBlockMap has copied the static
; 20x20 template (Prototype B border kit + top_level_fill interior, see
; maps/ProceduralCave1.blk) into wOverworldMap, and before LoadCurrentMapView
; converts wOverworldMap into the visible VRAM tilemap.
;
; wOverworldMap stores one byte per block, row-major, with a MAP_BORDER=3
; block pad on every side (see home/overworld.asm LoadTileBlockMap). So cell
; (x,y) for this fixed 20x20 map lives at:
;   wOverworldMap + MAP_BORDER + x + (y + MAP_BORDER) * (PC_SIZE + MAP_BORDER*2)
;   = wOverworldMap + 3 + x + (y+3)*26 = wOverworldMap + 81 + x + y*26
;
; Design (see Red Rogue Files/cavern-blockset-classification.md for the full
; block catalog this draws from):
;   - entrance: random point on one of the 4 edges
;   - 5 target points on the other 3 edges; exactly one is the exit
;   - decorate interior fill cells with obstacle blocks before carving, so
;     carving always overwrites any obstacle that lands on the path
;   - wobble-walk from entrance to each target, carving floor as it goes
;   - entrance/exit get a boundary opening + their wWarpEntries Y/X patched;
;     the other 4 targets dead-end against the inside face of the wall

SECTION "ProceduralCaveGen", ROMX

DEF PC_SIZE    EQU 20  ; map width/height in blocks
DEF PC_STRIDE  EQU 26  ; PC_SIZE + MAP_BORDER*2
DEF PC_BASE    EQU 81  ; MAP_BORDER + MAP_BORDER*PC_STRIDE

DEF PC_BLOCK_FLOOR    EQU 1
DEF PC_BLOCK_ENTRANCE EQU 36  ; distinct floor variant used for the entrance cell only
; Temporary sentinel used ONLY during PCAutotilePass's peninsula fix (see
; the comment there) - confirmed via a real before/after memory dump
; (2026-06-25) that writing PC_BLOCK_FLOOR directly during the main sweep
; let later-scanned cells mistake a JUST-converted cell for genuine
; pre-existing floor, cascading false peninsula triggers down a row. This
; value is never floor-like to PCClassifyCell during the main sweep, so it
; can't cascade; a cleanup pass at the end converts every leftover sentinel
; to real floor once the whole sweep (which can no longer see it) is done.
DEF PC_BLOCK_PENDING_FLOOR EQU 255

DEF PC_EDGE_TOP    EQU 0    ; procedural cave edge top of map, ect
DEF PC_EDGE_BOTTOM EQU 1
DEF PC_EDGE_LEFT   EQU 2
DEF PC_EDGE_RIGHT  EQU 3

DEF NUM_PC_OBSTACLES EQU 3
DEF NUM_PC_ROCKS     EQU 7  ; PCRockTable - stray-corner fallback decoration

; Scratch storage: WRAM0 has no free bytes left for a new dedicated section
; (confirmed via the linker map), so this borrows wBuffer (ram/wram.asm,
; generic 30-byte scratch already reused by many unrelated one-off systems).
; Safe here because the whole generator runs as one atomic, non-reentrant
; pass between LoadTileBlockMap and LoadCurrentMapView - nothing else touches
; wBuffer during that window.
;
; WATCH ITEM: if something unrelated misbehaves right after a map load (a
; naming screen, trade animation, or anything else that also borrows
; wBuffer), suspect this reuse first. These are plain numeric offsets, NOT
; addresses - every use site below references them as [wBuffer + offset],
; since wBuffer's actual address isn't known until link time and DEF/EQU
; can't fold a cross-file link-time symbol into a constant.
DEF wProcCaveEntranceX    EQU 0
DEF wProcCaveEntranceY    EQU 1
DEF wProcCaveEntranceEdge EQU 2
DEF wProcCaveExitX        EQU 3
DEF wProcCaveExitY        EQU 4
DEF wProcCaveExitIndex    EQU 5
DEF wProcCaveTargetX      EQU 6
DEF wProcCaveTargetY      EQU 7
DEF wProcCaveCurX         EQU 8
DEF wProcCaveCurY         EQU 9
DEF wProcCaveMaxSteps     EQU 10
DEF wProcCaveEdge         EQU 11
DEF wProcCaveOffset       EQU 12
DEF wProcCaveDX           EQU 13
DEF wProcCaveDY           EQU 14
DEF wProcCaveLoopI        EQU 15
DEF wProcCaveLoopX        EQU 16
DEF wProcCaveLoopY        EQU 17
; offsets 18/19/20/21 (SaveX/Y, BulgeX/Y) were used by an earlier live-
; during-carving autotiling design, now removed - see the note above
; PCAutotilePass for why. Free again; reuse before adding new offsets.
DEF wProcCaveFlags        EQU 22  ; PCClassifyCell's own scratch - must NOT reuse
                                  ; LoopI, which is live across PCCarveOne in the
                                  ; outer target loop in GenerateProceduralCave.
                                  ; ALSO safely reused by PCVerifyCorner (called
                                  ; only after PCClassifyCell has fully returned).
DEF wProcCaveCount        EQU 23  ; PCCountFloorNeighbors' running tally
DEF wProcCaveCountX       EQU 24  ; PCCountFloorNeighbors' own save slots - must
DEF wProcCaveCountY       EQU 25  ; NOT reuse DX/DY, which PCVerifyCorner (its
                                  ; only caller) is using for its OWN save at the
                                  ; same time

; ============================================================
; GenerateProceduralCave
; Entry point. See header comment for the hook site and call convention.
; ============================================================
GenerateProceduralCave::
	; --- entrance: PINNED to a hardcoded interior block for now (2026-06-25) ---
	; Was: random edge + offset via two Rangerandom calls (see git history /
	; the [[redrogue-procedural-cave]] memory for the exact original lines -
	; not reproduced here since this is a bigger structural change than the
	; earlier pin, not a simple value swap).
	;
	; Earlier pin attempts (top edge, then bottom edge) kept the ENTIRE
	; runtime-patching approach: dynamically computing wYCoord/wXCoord,
	; wSpritePlayerStateData2MapY/MapX, and wCurrentTileBlockMapViewPointer
	; from a generator-chosen block position, mirroring the build tool's
	; own event_displacement formula by hand. Bottom edge (block Y=19, the
	; map's last row) broke badly (camera showed nothing but the border-fill
	; block everywhere, player couldn't move at all) and top edge worked
	; only for collision/logical-position - a separate parity-bit cache
	; (wYBlockCoord/wXBlockCoord, see engine/overworld/tilesets.asm) gets
	; derived from wYCoord/wXCoord BEFORE this generator runs and was never
	; re-synced by any of the hand-rolled patches, which may also explain
	; some of the inconsistent behavior. Rather than keep hand-mirroring
	; (and debugging) the engine's own position-setup logic, the entrance is
	; now a genuinely static warp_event (data/maps/objects/ProceduralCave1.asm,
	; tile coords 36,76 = block (9,19) - on the bottom boundary row itself,
	; same spot as the broken bottom-edge attempt, but now via the SAME
	; build-time mechanism already proven correct for every vanilla warp in
	; the game (confirmed via the Red's House 1F live test this session),
	; which computes wYCoord/wXCoord, the sprite-state pair, the view-
	; pointer, AND the parity-bit pair correctly with zero runtime patching.
	; If this position still doesn't work, that's real evidence the last
	; row specifically has some other issue (insufficient padding margin?
	; not yet root-caused), since this rules out a hand-rolled-formula bug
	; as the cause. Only the EXIT still needs a runtime wWarpEntries patch
	; below, since its position is still chosen by the generator.
	;
	; wProcCaveEntranceEdge is set to PC_EDGE_BOTTOM since the entrance
	; really is on the bottom edge again - PCOtherEdgesTable picks the 3
	; OTHER edges for targets, same as the original random-entrance design.
	ld a, PC_EDGE_BOTTOM
	ld [wBuffer + wProcCaveEntranceEdge], a
	ld a, 9
	ld [wBuffer + wProcCaveEntranceX], a
	ld a, 19
	ld [wBuffer + wProcCaveEntranceY], a

	; --- which of the 5 targets is the exit ---
	ld c, 5
	call Rangerandom
	ld [wBuffer + wProcCaveExitIndex], a

	; --- stamp the entrance cell with its own distinct floor variant ---
	ld a, [wBuffer + wProcCaveEntranceX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveEntranceY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, PC_BLOCK_ENTRANCE
	call PCWriteCell

	call PCDecorate

	; --- 5 target points, each walked from the entrance ---
	xor a
	ld [wBuffer + wProcCaveLoopI], a
.targetLoop
	; pick target edge: one of the 3 NOT equal to the entrance edge
	ld c, 3
	call Rangerandom
	ld b, a                        ; b = sub-index 0-2 (Rangerandom preserves b)
	ld a, [wBuffer + wProcCaveEntranceEdge]
	ld c, a
	add a, a                       ; a = edge*2
	add a, c                       ; a = edge*3
	add a, b                       ; + sub-index = table row*3 + col
	ld hl, PCOtherEdgesTable
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	ld [wBuffer + wProcCaveEdge], a

	ld c, 18
	call Rangerandom
	inc a
	ld [wBuffer + wProcCaveOffset], a
	call PCEdgePoint
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveTargetX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveTargetY], a

	; is this target the exit?
	ld a, [wBuffer + wProcCaveLoopI]
	ld b, a
	ld a, [wBuffer + wProcCaveExitIndex]
	cp b
	jr nz, .notExit
	ld a, [wBuffer + wProcCaveTargetX]
	ld [wBuffer + wProcCaveExitX], a
	ld a, [wBuffer + wProcCaveTargetY]
	ld [wBuffer + wProcCaveExitY], a
	ld a, [wBuffer + wProcCaveTargetX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveTargetY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell                ; punch the exit boundary opening
.notExit

	call PCCarveOne

	ld a, [wBuffer + wProcCaveLoopI]
	inc a
	ld [wBuffer + wProcCaveLoopI], a
	cp 5
	jr nz, .targetLoop

	; --- re-stamp the entrance: every walk above starts by resetting to the
	; entrance position and immediately overwrites it with plain floor on
	; its first loop iteration, so PC_BLOCK_ENTRANCE never survives carving
	; without this - just set it again now that all carving is done ---
	ld a, [wBuffer + wProcCaveEntranceX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveEntranceY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, PC_BLOCK_ENTRANCE
	call PCWriteCell

	; --- one final autotiling sweep over the whole map, now that all floor
	; is in its final position - see PCAutotilePass. Doing this once at the
	; end instead of live during carving avoids redundant re-classification
	; (the same wall cell could get reclassified repeatedly as different
	; walks/bulges carve floor near it over time) and removes the need for
	; the early-termination ambiguity that broke reachability - see
	; [[redrogue-procedural-cave]] memory for the full story. ---
	call PCAutotilePass

	; --- patch the exit warp (wWarpEntries entry 1) to its chosen position ---
	; The entrance is now a genuinely static warp_event (see the comment at
	; the top of this function), so it needs no runtime patching at all -
	; wWarpEntries entry 0, wYCoord/wXCoord, the sprite-state pair, the
	; view-pointer, and the parity-bit pair are all set correctly by the
	; normal map-load process before this generator even runs. Only the
	; exit's position is still chosen here at runtime, and only its
	; wWarpEntries entry needs patching - the player never initially lands
	; on it, so none of the position-cache machinery above applies to it.
	;
	; wWarpEntries stores TILE coordinates (same units as wYCoord/wXCoord) -
	; convert block -> tile by *4 (one block is 4x4 tiles) before writing.
	ld hl, wWarpEntries + 4
	ld a, [wBuffer + wProcCaveExitY]
	add a, a
	add a, a
	ld [hli], a
	ld a, [wBuffer + wProcCaveExitX]
	add a, a
	add a, a
	ld [hl], a
	ret

; ============================================================
; PCEntranceViewPointer
; Computes the build-time-equivalent view pointer for the generator's
; chosen entrance tile and writes it to wCurrentTileBlockMapViewPointer.
; Mirrors the event_displacement macro's formula (macros/scripts/maps.asm):
;   ptr = wOverworldMap + 7 + width + (width+6)*(tileY>>1) + (tileX>>1)
; tileY/tileX = entrance block coords * 4 (block -> tile), so
; tileY>>1 = entranceY*2 and tileX>>1 = entranceX*2. width = PC_SIZE, so
; width+6 = PC_STRIDE (26) - same numeric stride as PCWriteCell uses, but
; this is a DIFFERENT addressing scheme (base 7+width vs PC_BASE=81); see
; the comment at the call site.
; ============================================================
PCEntranceViewPointer:
	ld a, [wBuffer + wProcCaveEntranceY]
	add a, a            ; blockY*2 = (blockY*4)>>1 = tileY>>1
	ld b, a
	ld hl, wOverworldMap + 7 + PC_SIZE
	and a
	jr z, .doneRows
.rowLoop
	ld a, l
	add a, PC_STRIDE
	ld l, a
	jr nc, .noCarryRow
	inc h
.noCarryRow
	dec b
	jr nz, .rowLoop
.doneRows
	ld a, [wBuffer + wProcCaveEntranceX]
	add a, a            ; blockX*2 = tileX>>1
	add a, l
	ld l, a
	jr nc, .noCarryCol
	inc h
.noCarryCol
	ld a, l
	ld [wCurrentTileBlockMapViewPointer], a
	ld a, h
	ld [wCurrentTileBlockMapViewPointer + 1], a
	ret

; ============================================================
; PCEdgePoint
; INPUT: wProcCaveEdge (0-3), wProcCaveOffset (1-18)
; OUTPUT: wProcCaveCurX, wProcCaveCurY
; ============================================================
PCEdgePoint:
	ld a, [wBuffer + wProcCaveEdge]
	and a
	jr z, .top
	dec a
	jr z, .bottom
	dec a
	jr z, .left
	; right
	ld a, PC_SIZE - 1
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveOffset]
	ld [wBuffer + wProcCaveCurY], a
	ret
.left
	xor a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveOffset]
	ld [wBuffer + wProcCaveCurY], a
	ret
.bottom
	ld a, [wBuffer + wProcCaveOffset]
	ld [wBuffer + wProcCaveCurX], a
	ld a, PC_SIZE - 1
	ld [wBuffer + wProcCaveCurY], a
	ret
.top
	ld a, [wBuffer + wProcCaveOffset]
	ld [wBuffer + wProcCaveCurX], a
	xor a
	ld [wBuffer + wProcCaveCurY], a
	ret

PCOtherEdgesTable:
	db PC_EDGE_BOTTOM, PC_EDGE_LEFT,   PC_EDGE_RIGHT  ; entrance = TOP
	db PC_EDGE_TOP,    PC_EDGE_LEFT,   PC_EDGE_RIGHT  ; entrance = BOTTOM
	db PC_EDGE_TOP,    PC_EDGE_BOTTOM, PC_EDGE_RIGHT  ; entrance = LEFT
	db PC_EDGE_TOP,    PC_EDGE_BOTTOM, PC_EDGE_LEFT   ; entrance = RIGHT

; ============================================================
; PCWriteCell
; INPUT: a = block ID to write, wProcCaveCurX/Y = cell coords (0-19)
; ============================================================
PCWriteCell:
	push af
	ld hl, wOverworldMap + PC_BASE
	ld a, [wBuffer + wProcCaveCurX]
	add a, l
	ld l, a
	jr nc, .noCarryX
	inc h
.noCarryX
	ld a, [wBuffer + wProcCaveCurY]
	and a
	jr z, .doneY
	ld b, a
.yLoop
	ld a, l
	add a, PC_STRIDE
	ld l, a
	jr nc, .noCarryY
	inc h
.noCarryY
	dec b
	jr nz, .yLoop
.doneY
	pop af
	ld [hl], a
	ret

; ============================================================
; PCReadCell
; Read-only mirror of PCWriteCell, same addressing.
; INPUT: wProcCaveCurX/Y = cell coords (0-19). OUTPUT: a = current block ID.
; ============================================================
PCReadCell:
	ld hl, wOverworldMap + PC_BASE
	ld a, [wBuffer + wProcCaveCurX]
	add a, l
	ld l, a
	jr nc, .noCarryX
	inc h
.noCarryX
	ld a, [wBuffer + wProcCaveCurY]
	and a
	jr z, .doneY
	ld b, a
.yLoop
	ld a, l
	add a, PC_STRIDE
	ld l, a
	jr nc, .noCarryY
	inc h
.noCarryY
	dec b
	jr nz, .yLoop
.doneY
	ld a, [hl]
	ret

; ============================================================
; PCIsConvertible
; INPUT: a = a cell's current block ID.
; OUTPUT: carry SET if this is fill/decoration/a straight edge (eligible to
;   be (re)classified by PCClassifyCell); carry CLEAR for floor, entrance,
;   an already-finalized corner, or anything else (e.g. the border-fill
;   block, though that never appears inside the 0-19 range anyway).
; Edge IDs (21/29/26/24) are included so a cell already classified as a
; straight edge can later be upgraded to a corner once a second floor
; neighbor appears - see PCRecomputeNeighbors.
; ============================================================
PCIsConvertible:
	cp 25
	jr z, .yes
	cp 60
	jr z, .yes
	cp 61
	jr z, .yes
	cp 117
	jr z, .yes
	cp 21
	jr z, .yes
	cp 29
	jr z, .yes
	cp 26
	jr z, .yes
	cp 24
	jr z, .yes
	and a
	ret
.yes
	scf
	ret

; ============================================================
; PCClassifyCell
; INPUT: wProcCaveCurX/Y = the cell to classify (must not itself be floor).
; OUTPUT: if at least one orthogonal neighbor is floor-like (PC_BLOCK_FLOOR
;   or PC_BLOCK_ENTRANCE), carry SET and a = the correct block ID for this
;   cell (a corner if two adjacent sides are floor, else a straight edge).
;   If no neighbor is floor-like, carry CLEAR and a is undefined - caller
;   must leave the cell untouched.
; wProcCaveCurX/Y is restored to its input value before returning.
; Clobbers: wProcCaveDX/DY (used as save slots), wProcCaveFlags (used as a
;   4-bit neighbor-floor flags byte: bit0=north,1=south,2=east,3=west), b.
; Deliberately does NOT touch wProcCaveLoopI - that's the live target-loop
; counter in GenerateProceduralCave, which calls PCCarveOne (and so this,
; transitively) before re-reading it.
; ============================================================
PCClassifyCell:
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveDY], a
	xor a
	ld [wBuffer + wProcCaveFlags], a

	; north (y-1)
	ld a, [wBuffer + wProcCaveDY]
	and a
	jr z, .skipNorth
	dec a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .northFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipNorth
.northFloor
	ld a, [wBuffer + wProcCaveFlags]
	or 1
	ld [wBuffer + wProcCaveFlags], a
.skipNorth
	; south (y+1)
	ld a, [wBuffer + wProcCaveDY]
	cp PC_SIZE - 1
	jr z, .skipSouth
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .southFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipSouth
.southFloor
	ld a, [wBuffer + wProcCaveFlags]
	or 2
	ld [wBuffer + wProcCaveFlags], a
.skipSouth
	; east (x+1)
	ld a, [wBuffer + wProcCaveDX]
	cp PC_SIZE - 1
	jr z, .skipEast
	inc a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .eastFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipEast
.eastFloor
	ld a, [wBuffer + wProcCaveFlags]
	or 4
	ld [wBuffer + wProcCaveFlags], a
.skipEast
	; west (x-1)
	ld a, [wBuffer + wProcCaveDX]
	and a
	jr z, .skipWest
	dec a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .westFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipWest
.westFloor
	ld a, [wBuffer + wProcCaveFlags]
	or 8
	ld [wBuffer + wProcCaveFlags], a
.skipWest

	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a

	ld a, [wBuffer + wProcCaveFlags]
	and a
	jr z, .noFloorNeighbor
	ld b, a

	; if 3 or 4 sides are floor, this cell is almost surrounded already -
	; no 2-sided corner ID can represent that correctly (the priority check
	; below only ever looks at 2 of the 4 bits, so a 3rd floor side was
	; silently ignored before this check existed, leaving a "peninsula" of
	; solid material poking into open floor - confirmed by an actual
	; in-game screenshot, e.g. a 22/20 with floor ALSO to its south, or a
	; 28/30 with floor ALSO to its north). Just make it floor too.
	xor a
	ld c, a
	bit 0, b
	jr z, .skipCountN
	inc c
.skipCountN
	bit 1, b
	jr z, .skipCountS
	inc c
.skipCountS
	bit 2, b
	jr z, .skipCountE
	inc c
.skipCountE
	bit 3, b
	jr z, .skipCountW
	inc c
.skipCountW
	ld a, c
	cp 3
	jr c, .twoOrFewerSides
	; PC_BLOCK_PENDING_FLOOR, NOT PC_BLOCK_FLOOR - see the constant's comment.
	; Writing real floor here would let a cell scanned moments later mistake
	; this just-converted cell for genuine pre-existing floor, cascading
	; false peninsula triggers down a row - confirmed via a real before/after
	; memory dump, not theorized. PCAutotilePass's cleanup pass converts this
	; to real floor only after the whole sweep (which can't see it) is done.
	ld a, PC_BLOCK_PENDING_FLOOR
	scf
	ret
.twoOrFewerSides

	; IDs confirmed 2026-06-25 against the user's hand-drawn Polished Map
	; intersection reference (ground truth - the static border template
	; used for the EARLIER, wrong derivation has no actual carved floor
	; anywhere, so it couldn't prove a real floor-adjacency rule). Every
	; single direction is mirrored from the previous attempt: north<->south
	; AND east<->west both flipped, so corners flip too.
	ld a, b
	and %0101              ; north+east
	cp %0101
	jr nz, .notNE
	ld a, 22
	jr .haveResult
.notNE
	ld a, b
	and %1001              ; north+west
	cp %1001
	jr nz, .notNW
	ld a, 20
	jr .haveResult
.notNW
	ld a, b
	and %0110              ; south+east
	cp %0110
	jr nz, .notSE
	ld a, 30
	jr .haveResult
.notSE
	ld a, b
	and %1010              ; south+west
	cp %1010
	jr nz, .notSW
	ld a, 28
	jr .haveResult
.notSW
	bit 0, b                ; north
	jr z, .notN2
	ld a, 21
	jr .haveResult
.notN2
	bit 1, b                ; south
	jr z, .notS2
	ld a, 29
	jr .haveResult
.notS2
	bit 3, b                ; west
	jr z, .notW2
	ld a, 24
	jr .haveResult
.notW2
	ld a, 26                ; only east left
.haveResult
	scf
	ret
.noFloorNeighbor
	and a
	ret

; ============================================================
; PCCountFloorNeighbors
; INPUT: wProcCaveCurX/Y = a cell (typically a known floor cell).
; OUTPUT: a = count of its orthogonal neighbors that are floor-like (0-4).
; wProcCaveCurX/Y restored to its input value before returning.
; Clobbers: wProcCaveCount/CountX/CountY. Deliberately does NOT use DX/DY -
;   PCVerifyCorner (its only caller) needs those to survive across this call.
; ============================================================
PCCountFloorNeighbors:
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveCountX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveCountY], a
	xor a
	ld [wBuffer + wProcCaveCount], a

	; north
	ld a, [wBuffer + wProcCaveCountY]
	and a
	jr z, .skipN
	dec a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveCountX]
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .nFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipN
.nFloor
	ld a, [wBuffer + wProcCaveCount]
	inc a
	ld [wBuffer + wProcCaveCount], a
.skipN
	; south
	ld a, [wBuffer + wProcCaveCountY]
	cp PC_SIZE - 1
	jr z, .skipS
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveCountX]
	ld [wBuffer + wProcCaveCurX], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .sFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipS
.sFloor
	ld a, [wBuffer + wProcCaveCount]
	inc a
	ld [wBuffer + wProcCaveCount], a
.skipS
	; east
	ld a, [wBuffer + wProcCaveCountX]
	cp PC_SIZE - 1
	jr z, .skipE
	inc a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveCountY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .eFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipE
.eFloor
	ld a, [wBuffer + wProcCaveCount]
	inc a
	ld [wBuffer + wProcCaveCount], a
.skipE
	; west
	ld a, [wBuffer + wProcCaveCountX]
	and a
	jr z, .skipW
	dec a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveCountY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp PC_BLOCK_FLOOR
	jr z, .wFloor
	cp PC_BLOCK_ENTRANCE
	jr nz, .skipW
.wFloor
	ld a, [wBuffer + wProcCaveCount]
	inc a
	ld [wBuffer + wProcCaveCount], a
.skipW
	ld a, [wBuffer + wProcCaveCountX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveCountY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveCount]
	ret

; ============================================================
; PCVerifyCorner
; INPUT: a = a proposed corner ID (22/20/30/28), wProcCaveCurX/Y = the wall
;   cell that would receive it.
; OUTPUT: a = the SAME corner ID if both contributing floor neighbors have
;   2+ floor neighbors of their own (a genuine corridor turn); otherwise a
;   randomly-picked PCRockTable ID instead. A corner caused by two dead-end
;   nubs (most likely a PCBulge poke, which by construction has exactly 1
;   floor neighbor) coincidentally meeting at a right angle isn't a real
;   turn and shouldn't be drawn like one.
; wProcCaveCurX/Y restored to its input value before returning. Safe to
; reuse wProcCaveDX/DY and wProcCaveFlags here - PCClassifyCell (their only
; other owner) has always already returned by the time this runs.
; ============================================================
PCVerifyCorner:
	ld [wBuffer + wProcCaveFlags], a      ; stash the proposed ID
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveDY], a

	; first contributing neighbor: north for 22/20, south for 30/28
	ld a, [wBuffer + wProcCaveFlags]
	cp 22
	jr z, .firstIsNorth
	cp 20
	jr z, .firstIsNorth
	ld a, [wBuffer + wProcCaveDY]
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	jr .haveFirst
.firstIsNorth
	ld a, [wBuffer + wProcCaveDY]
	dec a
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
.haveFirst
	call PCCountFloorNeighbors
	cp 2
	jr c, .notReal

	; second contributing neighbor: east for 22/30, west for 20/28
	ld a, [wBuffer + wProcCaveFlags]
	cp 22
	jr z, .secondIsEast
	cp 30
	jr z, .secondIsEast
	ld a, [wBuffer + wProcCaveDX]
	dec a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	jr .haveSecond
.secondIsEast
	ld a, [wBuffer + wProcCaveDX]
	inc a
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
.haveSecond
	call PCCountFloorNeighbors
	cp 2
	jr c, .notReal

	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, [wBuffer + wProcCaveFlags]
	ret
.notReal
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	ld c, NUM_PC_ROCKS
	call Rangerandom
	ld hl, PCRockTable
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	ret

; stray-corner fallback decoration - generic rocks/boulders that look fine
; regardless of orientation, used in place of a directional corner piece
; when PCVerifyCorner determines the "corner" is just two dead-end nubs
; (almost always a PCBulge poke) meeting by coincidence, not a real turn.
PCRockTable:
	db 2, 77, 78, 79, 81, 82, 83

; ============================================================
; NOTE ON AN EARLIER, ABANDONED APPROACH (2026-06-25)
;
; PCAutotilePass below replaced a live/during-carving design: every floor
; write (in GenerateProceduralCave's entrance stamp and exit punch, and in
; PCCarveOne's walk loop/done-stamp, and in PCBulge) was immediately
; followed by a call to a PCRecomputeNeighbors routine, which reclassified
; the 4 orthogonal neighbors of whatever cell had just become floor via
; PCClassifyCell (same classify logic that still exists below) and a
; PCRecomputeOne helper that gated the write on PCIsConvertible.
;
; Two real problems killed it, both confirmed by an actual test, not
; theorized:
; 1. CPU cost: the same wall/edge cell can get reclassified many times
;    over the course of generation, once per nearby floor write from any
;    walk or bulge - redundant work that scales with how much gets carved,
;    not with the fixed size of the map.
; 2. Correctness: it came with an early-termination feature (stop a walk
;    early if it stepped onto a cell some OTHER walk had already carved,
;    so paths could branch into each other). But all 5 walks start from
;    the SAME entrance, so "touched already-floor" couldn't distinguish a
;    genuine connection to a distant walk from just touching the shared
;    starting area near the entrance - walks 2-5 could (and did, in
;    testing) terminate within their first couple of steps, never
;    reaching their actual targets. The test screenshot showed exactly
;    this: most of the map never got carved at all.
;
; PCAutotilePass fixes both: one pass, fixed cost, no live connectivity
; detection needed (and so no early-termination ambiguity), since by the
; time it runs every walk has already unconditionally reached its own
; target the simple way (like before any of this existed).
;
; If live-during-carving ever comes back (e.g. for some effect a one-shot
; final pass genuinely can't do), the early-termination design needs a way
; to tell "this walk's own already-carved cells" apart from "a different
; walk's" - a per-cell "which walk carved this" tag, or a minimum-step
; count before allowing termination, would both need building first; don't
; just resurrect the old call sites as-is.
; ============================================================
; PCAutotilePass
; One full sweep over every cell in the map (0-19 x 0-19, boundary ring
; included), run once after all carving (all 5 walks, plus the entrance
; re-stamp) is finished. For each cell still convertible (plain fill or a
; decoration obstacle - never a cell carving already turned to floor),
; classify it from its neighbors' CURRENT (final) floor state and write
; the result. Since all floor placement is already final by the time this
; runs, a single pass is enough - no need to revisit a cell once it's been
; classified, unlike a live-during-carving approach would.
; ============================================================
; ============================================================
; PCAutotilePass
; Two genuinely separate passes over the whole map, not one combined sweep.
;
; Pass A resolves ALL peninsula-driven floor first (a cell with 3+ real
; floor neighbors becomes floor itself), using the same pending-sentinel
; trick to stop false cascades WITHIN this pass. Only after Pass A's own
; cleanup runs is the floor layout for the WHOLE map fully and finally
; settled - both originally-carved floor AND peninsula-created floor.
;
; Pass B then does edge/corner classification using that complete, final
; floor layout. This is necessary, not just tidier: even with Pass A's
; anti-cascade fix, a single combined sweep can still legitimately produce
; a cell that becomes new floor via the peninsula rule (using only ITS OWN
; real original neighbors - not a cascade, a perfectly correct conversion)
; AFTER an EARLIER-SCANNED neighbor has already been finalized as a plain
; edge. That earlier neighbor never gets a chance to learn it now also
; borders real floor. Confirmed via real before/after dumps: a `26` cell
; with floor genuinely to its south too (which should have made it a `30`
; corner) - the south neighbor only became floor moments later in the
; same sweep, after the `26` was already written and never revisited.
; Splitting into two passes removes the order-dependency entirely instead
; of patching around it - by the time Pass B runs, ALL floor is fixed, so
; it doesn't matter what order Pass B itself visits cells in.
; ============================================================
PCAutotilePass:
	; --- Pass A: peninsula resolution only ---
	xor a
	ld [wBuffer + wProcCaveLoopY], a
.aYLoop
	xor a
	ld [wBuffer + wProcCaveLoopX], a
.aXLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a

	call PCReadCell
	call PCIsConvertible
	jr nc, .aSkipCell
	call PCClassifyCell
	jr nc, .aSkipCell
	cp PC_BLOCK_PENDING_FLOOR
	jr nz, .aSkipCell           ; an edge/corner result - leave it for Pass B
	call PCWriteCell
.aSkipCell
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE
	jr nz, .aXLoop
	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE
	jr nz, .aYLoop

	; Pass A cleanup: convert this pass's own pending-floor sentinels to
	; real floor now that Pass A's own sweep is fully finished.
	xor a
	ld [wBuffer + wProcCaveLoopY], a
.cleanYLoop
	xor a
	ld [wBuffer + wProcCaveLoopX], a
.cleanXLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a
	call PCReadCell
	cp PC_BLOCK_PENDING_FLOOR
	jr nz, .cleanSkip
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell
.cleanSkip
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE
	jr nz, .cleanXLoop
	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE
	jr nz, .cleanYLoop

	; --- Pass B: edge/corner classification, floor layout now fully fixed ---
	xor a
	ld [wBuffer + wProcCaveLoopY], a
.yLoop
	xor a
	ld [wBuffer + wProcCaveLoopX], a
.xLoop
	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a

	call PCReadCell
	call PCIsConvertible
	jr nc, .skipCell
	call PCClassifyCell
	jr nc, .skipCell

	; Pass A already resolved every real peninsula case, so this shouldn't
	; fire - but if it somehow does, just write floor directly (no cascade
	; risk: this is the last pass, nothing left to read it as a false signal).
	cp PC_BLOCK_PENDING_FLOOR
	jr nz, .notPending
	ld a, PC_BLOCK_FLOOR
	jr .haveValue
.notPending
	; if the result is a corner, verify it's a real turn and not just two
	; dead-end nubs (almost always a PCBulge poke) meeting by coincidence
	cp 22
	jr z, .checkCorner
	cp 20
	jr z, .checkCorner
	cp 30
	jr z, .checkCorner
	cp 28
	jr z, .checkCorner
	jr .haveValue
.checkCorner
	call PCVerifyCorner
.haveValue
	call PCWriteCell
.skipCell

	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE
	jr nz, .xLoop

	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE
	jr nz, .yLoop
	ret

; ============================================================
; PCAbs
; INPUT: a = signed byte. OUTPUT: a = absolute value. Only touches a/flags.
; ============================================================
PCAbs:
	bit 7, a
	ret z
	cpl
	inc a
	ret

; ============================================================
; PCDecorate
; Sprinkles obstacle blocks across the 18x18 interior (~1-in-40 cells,
; deliberately rare) before any carving happens, so the carve pass below
; always overwrites obstacles that land on the path. Obstacles are treated
; just like plain fill by the autotiling in PCClassifyCell/PCIsConvertible -
; any obstacle that survives next to carved floor gets edge/corner-ified
; the same way a fill cell would.
; ============================================================
PCDecorate:
	ld a, 1
	ld [wBuffer + wProcCaveLoopY], a
.yLoop
	ld a, 1
	ld [wBuffer + wProcCaveLoopX], a
.xLoop
	ld c, 40
	call Rangerandom
	and a
	jr nz, .skipCell

	ld a, [wBuffer + wProcCaveLoopX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveLoopY]
	ld [wBuffer + wProcCaveCurY], a

	ld c, NUM_PC_OBSTACLES
	call Rangerandom
	ld hl, PCObstacleTable
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hl]
	call PCWriteCell

.skipCell
	ld a, [wBuffer + wProcCaveLoopX]
	inc a
	ld [wBuffer + wProcCaveLoopX], a
	cp PC_SIZE - 1
	jr nz, .xLoop

	ld a, [wBuffer + wProcCaveLoopY]
	inc a
	ld [wBuffer + wProcCaveLoopY], a
	cp PC_SIZE - 1
	jr nz, .yLoop
	ret

; obstacle block IDs: 60/61 are classified as warp_ladder in the catalog, but
; confirmed safe here - warp behavior is driven entirely by wWarpEntries
; entries, not tile ID, and nothing ever creates a warp_event at a random
; decoration position, so these are purely cosmetic when sprinkled. 117 is
; an irregular_corner/corner-bucket piece that isn't a true corner (see the
; classification doc's Prototype B note) but reads fine as a rare obstacle.
PCObstacleTable:
	db 60, 61, 117

; ============================================================
; PCCarveOne
; Wobble-walks from the entrance to wProcCaveTargetX/Y, writing floor along
; the way, then force-stamps the exact target cell regardless of how the
; walk ended (guarantees the breach/dead-end point is always connected).
; ============================================================
PCCarveOne:
	ld a, [wBuffer + wProcCaveEntranceX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveEntranceY]
	ld [wBuffer + wProcCaveCurY], a

	call PCManhattan          ; a = manhattan distance, entrance to target
	ld b, a
	add a, b
	add a, b                 ; a = distance * 3
	and a
	jr nz, .haveMax
	inc a                     ; avoid a zero step budget if already on target
.haveMax
	ld [wBuffer + wProcCaveMaxSteps], a

.walkLoop
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell

	ld c, 20
	call Rangerandom
	cp 3
	call c, PCBulge            ; ~15% chance: also carve one random neighbor

	ld a, [wBuffer + wProcCaveCurX]
	ld b, a
	ld a, [wBuffer + wProcCaveTargetX]
	cp b
	jr nz, .notAtTarget
	ld a, [wBuffer + wProcCaveCurY]
	ld b, a
	ld a, [wBuffer + wProcCaveTargetY]
	cp b
	jr z, .done
.notAtTarget
	ld a, [wBuffer + wProcCaveMaxSteps]
	and a
	jr z, .done
	dec a
	ld [wBuffer + wProcCaveMaxSteps], a

	call PCStep
	jr .walkLoop

.done
	ld a, [wBuffer + wProcCaveTargetX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveTargetY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell
	ret

; ============================================================
; PCManhattan
; OUTPUT: a = |targetX-curX| + |targetY-curY|
; ============================================================
PCManhattan:
	ld a, [wBuffer + wProcCaveTargetX]
	ld b, a
	ld a, [wBuffer + wProcCaveCurX]
	ld c, a
	ld a, b
	sub c
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveTargetY]
	ld b, a
	ld a, [wBuffer + wProcCaveCurY]
	ld c, a
	ld a, b
	sub c
	ld [wBuffer + wProcCaveDY], a

	ld a, [wBuffer + wProcCaveDX]
	call PCAbs
	ld b, a
	ld a, [wBuffer + wProcCaveDY]
	call PCAbs
	add a, b
	ret

; ============================================================
; PCStep
; Moves wProcCaveCurX/Y one step toward wProcCaveTargetX/Y: 70% along
; whichever axis has the larger remaining distance, 30% a random nudge on
; the other axis. Clamped to the 1-18 interior (never steps onto the
; boundary ring itself; the exact target cell is force-stamped separately).
; ============================================================
PCStep:
	ld a, [wBuffer + wProcCaveTargetX]
	ld b, a
	ld a, [wBuffer + wProcCaveCurX]
	ld c, a
	ld a, b
	sub c
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveTargetY]
	ld b, a
	ld a, [wBuffer + wProcCaveCurY]
	ld c, a
	ld a, b
	sub c
	ld [wBuffer + wProcCaveDY], a

	ld a, [wBuffer + wProcCaveDX]
	call PCAbs
	ld b, a
	ld a, [wBuffer + wProcCaveDY]
	call PCAbs
	ld c, a
	ld a, b
	cp c
	jr c, .yDominant

.xDominant
	ld c, 10
	call Rangerandom
	cp 7
	jr nc, .wobbleY
	ld a, [wBuffer + wProcCaveDX]
	bit 7, a
	jr nz, .moveXDec
	jr .moveXInc

.yDominant
	ld c, 10
	call Rangerandom
	cp 7
	jr nc, .wobbleX
	ld a, [wBuffer + wProcCaveDY]
	bit 7, a
	jr nz, .moveYDec
	jr .moveYInc

.wobbleY
	ld c, 2
	call Rangerandom
	and a
	jr z, .moveYDec
	jr .moveYInc

.wobbleX
	ld c, 2
	call Rangerandom
	and a
	jr z, .moveXDec
	jr .moveXInc

; NOTE: these clamps use >=/<= checks (cp + ret nc/ret c), not exact-match
; (cp + ret z). The entrance is hardcoded on the boundary ring (Y=19), so a
; walk can legitimately START at 19 - one off from PC_SIZE-2's exact-match
; check, which only blocked incrementing FROM exactly 18, not from 19 or
; beyond. The wobble mechanic picks a direction independent of the target,
; so it could roll "increment Y" while still sitting at 19 and push to 20 -
; carving directly into the border-fill padding ring (block 46) and
; corrupting it, confirmed by an actual in-game crash when walking into the
; resulting hole. Exact-match clamps are only safe if the starting position
; is already known to be within range; >=/<= clamps are safe regardless.
.moveXInc
	ld a, [wBuffer + wProcCaveCurX]
	cp PC_SIZE - 2
	ret nc
	inc a
	ld [wBuffer + wProcCaveCurX], a
	ret
.moveXDec
	ld a, [wBuffer + wProcCaveCurX]
	cp 2
	ret c
	dec a
	ld [wBuffer + wProcCaveCurX], a
	ret
.moveYInc
	ld a, [wBuffer + wProcCaveCurY]
	cp PC_SIZE - 2
	ret nc
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ret
.moveYDec
	ld a, [wBuffer + wProcCaveCurY]
	cp 2
	ret c
	dec a
	ld [wBuffer + wProcCaveCurY], a
	ret

; ============================================================
; PCBulge
; Carves one random orthogonal neighbor of the current cell, clamped to the
; 1-18 interior. Saves and restores wProcCaveCurX/Y around the write.
; ============================================================
PCBulge:
	ld a, [wBuffer + wProcCaveCurX]
	ld [wBuffer + wProcCaveDX], a
	ld a, [wBuffer + wProcCaveCurY]
	ld [wBuffer + wProcCaveDY], a

	; same >=/<= clamp fix as PCStep - exact-match (cp+jr z) checks are only
	; safe if the starting position is known in-range; the entrance starts
	; AT the boundary (Y=19), so this must tolerate an out-of-the-usual-
	; range starting value too, not just block the one exact value below it
	ld c, 4
	call Rangerandom
	and a
	jr nz, .notN
	ld a, [wBuffer + wProcCaveCurY]
	cp 2
	jr c, .skip
	dec a
	ld [wBuffer + wProcCaveCurY], a
	jr .doWrite
.notN
	cp 1
	jr nz, .notS
	ld a, [wBuffer + wProcCaveCurY]
	cp PC_SIZE - 2
	jr nc, .skip
	inc a
	ld [wBuffer + wProcCaveCurY], a
	jr .doWrite
.notS
	cp 2
	jr nz, .isW
	ld a, [wBuffer + wProcCaveCurX]
	cp PC_SIZE - 2
	jr nc, .skip
	inc a
	ld [wBuffer + wProcCaveCurX], a
	jr .doWrite
.isW
	ld a, [wBuffer + wProcCaveCurX]
	cp 2
	jr c, .skip
	dec a
	ld [wBuffer + wProcCaveCurX], a
.doWrite
	ld a, PC_BLOCK_FLOOR
	call PCWriteCell
.skip
	ld a, [wBuffer + wProcCaveDX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveDY]
	ld [wBuffer + wProcCaveCurY], a
	ret
