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

DEF PC_BLOCK_FLOOR  EQU 1

DEF PC_EDGE_TOP    EQU 0    ; procedural cave edge top of map, ect
DEF PC_EDGE_BOTTOM EQU 1
DEF PC_EDGE_LEFT   EQU 2
DEF PC_EDGE_RIGHT  EQU 3

DEF NUM_PC_OBSTACLES EQU 4

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

	; --- stamp the entrance cell as floor (interior now, not a boundary breach) ---
	ld a, [wBuffer + wProcCaveEntranceX]
	ld [wBuffer + wProcCaveCurX], a
	ld a, [wBuffer + wProcCaveEntranceY]
	ld [wBuffer + wProcCaveCurY], a
	ld a, PC_BLOCK_FLOOR
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
; Sprinkles obstacle blocks across the 18x18 interior (~1-in-8 cells) before
; any carving happens, so the carve pass below always overwrites obstacles
; that land on the path.
; ============================================================
PCDecorate:
	ld a, 1
	ld [wBuffer + wProcCaveLoopY], a
.yLoop
	ld a, 1
	ld [wBuffer + wProcCaveLoopX], a
.xLoop
	ld c, 8
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

; obstacle block IDs: a handful of Prototype A floor_obstacle entries, picked
; conservatively to avoid the warp_ladder/warp_hole/excluded IDs (see the
; classification doc). Revisit once Prototype A's review is more complete.
PCObstacleTable:
	db 16, 17, 18, 19

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

.moveXInc
	ld a, [wBuffer + wProcCaveCurX]
	cp PC_SIZE - 2
	ret z
	inc a
	ld [wBuffer + wProcCaveCurX], a
	ret
.moveXDec
	ld a, [wBuffer + wProcCaveCurX]
	cp 1
	ret z
	dec a
	ld [wBuffer + wProcCaveCurX], a
	ret
.moveYInc
	ld a, [wBuffer + wProcCaveCurY]
	cp PC_SIZE - 2
	ret z
	inc a
	ld [wBuffer + wProcCaveCurY], a
	ret
.moveYDec
	ld a, [wBuffer + wProcCaveCurY]
	cp 1
	ret z
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

	ld c, 4
	call Rangerandom
	and a
	jr nz, .notN
	ld a, [wBuffer + wProcCaveCurY]
	cp 1
	jr z, .skip
	dec a
	ld [wBuffer + wProcCaveCurY], a
	jr .doWrite
.notN
	cp 1
	jr nz, .notS
	ld a, [wBuffer + wProcCaveCurY]
	cp PC_SIZE - 2
	jr z, .skip
	inc a
	ld [wBuffer + wProcCaveCurY], a
	jr .doWrite
.notS
	cp 2
	jr nz, .isW
	ld a, [wBuffer + wProcCaveCurX]
	cp PC_SIZE - 2
	jr z, .skip
	inc a
	ld [wBuffer + wProcCaveCurX], a
	jr .doWrite
.isW
	ld a, [wBuffer + wProcCaveCurX]
	cp 1
	jr z, .skip
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
