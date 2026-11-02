; Included inside "Map Graphics Reload". All entry/reload paths have LCD off.
; Patch only the active tree art, after the normal tileset copy. Block IDs,
; shared ground corners ($00/$30), collision and other FOREST maps stay intact.
LoadProcForestTreeTiles:
	ldh a, [hCurMap]
	cp PROCEDURAL_FOREST
	ret nz
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sProcForestPalette)
	ld [rRAMB], a
	ld a, [sProcForestPalette]
	ld e, a
	xor a
	ld [rBMODE], a
	ld [rRAMG], a
	ld a, e
	ld hl, ProcForestCherryTiles
	and a
	jr z, .patch
	cp 3 ; appended winter; 1 fall, 2 summer and invalid saves keep normal art
	ret nz
	ld hl, ProcForestWinterTiles
.patch
	ld a, [hli]
	ld e, a
	ld a, [hli]
	and a
	ret z
	ld d, a
	ld a, [hli]
	ld c, a
	ld b, 0
	; CopyData advances hl to the next inline record, never changes ROM banks.
	call CopyData
	jr .patch

; Each record is destination, byte count, inline patterns; dw 0 terminates.
; Generated sheets contain the 14 private full-tree tiles in block $02 order.
; $00/$30 are shared floor tiles and deliberately are not overwritten.
ProcForestCherryTiles:
	dw vTileset tile $04
	db 4 tiles
	INCBIN "gfx/tilesets/forest_cherry.2bpp", 0, 4 tiles
	dw vTileset tile $23
	db 1 tiles
	INCBIN "gfx/tilesets/forest_cherry.2bpp", 4 tiles, 1 tiles
	dw vTileset tile $15
	db 3 tiles
	INCBIN "gfx/tilesets/forest_cherry.2bpp", 5 tiles, 3 tiles
	dw vTileset tile $24
	db 4 tiles
	INCBIN "gfx/tilesets/forest_cherry.2bpp", 8 tiles, 4 tiles
	dw vTileset tile $35
	db 2 tiles
	INCBIN "gfx/tilesets/forest_cherry.2bpp", 12 tiles, 2 tiles
	dw 0

ProcForestWinterTiles:
	dw vTileset tile $04
	db 4 tiles
	INCBIN "gfx/tilesets/forest_winter.2bpp", 0, 4 tiles
	dw vTileset tile $23
	db 1 tiles
	INCBIN "gfx/tilesets/forest_winter.2bpp", 4 tiles, 1 tiles
	dw vTileset tile $15
	db 3 tiles
	INCBIN "gfx/tilesets/forest_winter.2bpp", 5 tiles, 3 tiles
	dw vTileset tile $24
	db 4 tiles
	INCBIN "gfx/tilesets/forest_winter.2bpp", 8 tiles, 4 tiles
	dw vTileset tile $35
	db 2 tiles
	INCBIN "gfx/tilesets/forest_winter.2bpp", 12 tiles, 2 tiles
	dw 0
