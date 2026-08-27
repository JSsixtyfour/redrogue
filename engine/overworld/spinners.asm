LoadSpinnerArrowTiles::
; Shin Red import: spinner speedup, 2026-08-26.
;
; This used to run its full tile-copy work unconditionally on every call (once
; per step while spinning), using CopyVideoData - a frame-budgeted transfer
; meant for bulk loads (c/8 frames via DelayFrame). On top of that,
; OverworldLoopLessDelay always called a plain DelayFrame regardless of
; spinning, so every step paid a full extra frame even when this routine's own
; transfer already consumed one. Two compounding costs, both fixed here by
; porting shinpokered's version verbatim:
;
;  1. Rate-limit: the arrow animation only actually updates every 4 overworld
;     ticks (2 in 60fps mode), via wSpinnerTileFrameCount below. Most calls now
;     return immediately without touching VRAM at all.
;  2. Fast transfer: CopySpinnerTiles (the di + ld sp,hl + pop trick) replaces
;     CopyVideoData - a single-shot copy with a manual VRAM-mode wait instead
;     of a multi-frame budgeted one.
;  3. OverworldLoopLessDelay now calls CheckForSpinAndDelay (home/overworld.asm)
;     instead of DelayFrame unconditionally, so a step that just paid for this
;     routine's own transfer does not ALSO pay for a separate delay frame.
;
; wUnusedD721 bit 4 (shinpokered's 60fps flag) is BIT_60_FPS in wOptions2 here.
	push bc
	ld b, 2
	ld a, [wOptions2]
	bit BIT_60_FPS, a
	jr z, .no60fps
	sla b
.no60fps
	ld c, b
	inc c
	ld a, [wSpinnerTileFrameCount]
	cp c
	jr c, .notGreater
	ld a, b
	ld [wSpinnerTileFrameCount], a
	jr .noAdjust
.notGreater
	cp 1
	jr nc, .noAdjust
	ld a, b
	ld [wSpinnerTileFrameCount], a
.noAdjust
	pop bc
	ld a, [wSpinnerTileFrameCount]
	dec a
	ld [wSpinnerTileFrameCount], a
	ret nz

	ld a, [wSpritePlayerStateData1ImageIndex]
	srl a
	srl a
	ld hl, SpinnerPlayerFacingDirections
	ld c, a
	ld b, $0
	add hl, bc
	ld a, [hl]
	ld [wSpritePlayerStateData1ImageIndex], a
	ld a, [wCurMapTileset]
	cp FACILITY
	ld hl, FacilitySpinnerArrows
	jr z, .gotSpinnerArrows
	ld hl, GymSpinnerArrows
.gotSpinnerArrows
	ldh a, [hSimulatedJoypadStatesIndex]
	bit 0, a ; even or odd?
	jr nz, .alternateGraphics
	ld de, 6 * 4
	add hl, de
.alternateGraphics
	ld a, $4
	ld bc, $0
.loop
	push af
	push hl
	push bc
	add hl, bc
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld b, a
	ld a, [hli]
	ld h, [hl]
	ld l, a
	call CopySpinnerTiles
	pop bc
	ld a, $6
	add c
	ld c, a
	pop hl
	pop af
	dec a
	jr nz, .loop
	call DelayFrame ; CopySpinnerTiles has no built-in delay, unlike CopyVideoData
	ret

CopySpinnerTiles:
; de = tile source address, hl = tile destination address. c/b (length/bank)
; are unused, same contract as CopyVideoData for drop-in compatibility.
;
; The di + ld sp,hl + pop trick: point the stack at the source and use `pop`
; as a 2-bytes-per-instruction reader, the fastest bulk copy the hardware
; allows. Independent of the spinner rate-limiting above; this is the fast-copy
; idea from shinpokered's LoadCurrentMapView the user separately asked to have
; imported (VRAM_BIBLE.md F1) - this is its first use in the tree.
;
; Interrupts are masked for the whole transfer: a bogus SP during an interrupt
; is fatal, and nothing may run between "SP = source" and "SP restored" below.
	di
	ld b, h
	ld c, l
	ld hl, sp + 0
	ld a, h
	ldh [hSPTemp], a
	ld a, l
	ldh [hSPTemp + 1], a
	ld h, d
	ld l, e
	ld sp, hl
	ld h, b
	ld l, c

	ld c, 8
.copyLoop
	pop de
; HBLANK (mode 0) length is highly variable, worst case 21 cycles; mode 2
; (OAM scan) is a constant 20 and is also VRAM-safe to write during.
.waitVRAM
	ldh a, [rSTAT]
	and %10 ; mode 2 or 3 (VRAM busy)?
	jr nz, .waitVRAM
	ld [hl], e
	inc l
	ld [hl], d
	inc l
	dec c
	jr nz, .copyLoop

	ldh a, [hSPTemp]
	ld h, a
	ldh a, [hSPTemp + 1]
	ld l, a
	ld sp, hl
	ei
	ret

INCLUDE "data/tilesets/spinner_tiles.asm"

SpinnerPlayerFacingDirections:
; This isn't the order of the facing directions.  Rather, it's a list of
; the facing directions that come next. For example, when the player is
; facing down (00), the next facing direction is left (08).
	db $08 ; down -> left
	db $0C ; up -> right
	db $04 ; left -> up
	db $00 ; right -> down

; these tiles are the animation for the tiles that push the player in dungeons like Rocket HQ
SpinnerArrowAnimTiles:
	INCBIN "gfx/overworld/spinners.2bpp"
