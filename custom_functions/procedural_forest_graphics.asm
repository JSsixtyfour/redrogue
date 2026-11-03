; Included inside Map Graphics Reload. Every caller owns an LCD-off reload.
; Carry: the complete seasonal sheet was copied. Clear: use ordinary loader.
LoadProcForestTreeTiles:
	ldh a, [hCurMap]
	cp PROCEDURAL_FOREST
	jr z, .forest
	cp PROCEDURAL_FOREST_GROTTO
	jr nz, .normal
.forest
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
	ld hl, ProcForestCherryRuns
	and a
	jr z, .seasonal
	cp 3 ; fall, summer and invalid saved values retain ordinary graphics
	jr nz, .normal
	ld hl, ProcForestWinterRuns
.seasonal
	ld de, vTileset
.copy
	push hl
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld b, a
	or c
	jr z, .done
	ld a, [hli]
	ld h, [hl]
	ld l, a
	; Forest_GFX and both sparse payloads share this bank. CopyData advances
	; DE; BC reaches zero and HL is clobbered. The descriptor is stack-owned.
	call CopyData
	pop hl
	ld bc, 4
	add hl, bc
	jr .copy
.done
	pop hl
	scf
	ret
.normal
	and a
	ret

; One authoritative tile/payload layout generates ascending, gap-free ranges.
; Source payload order remains block-$02 order, including $23 before $15.
MACRO forest_tree_runs
	forest_tree_run $04, 4, 0
	forest_tree_run $15, 3, 5
	forest_tree_run $23, 1, 4
	forest_tree_run $24, 4, 8
	forest_tree_run $35, 2, 12
ENDM

MACRO forest_tree_run
	ASSERT \1 >= forest_next_tile
	ASSERT \3 + \2 <= 14
	IF \1 > forest_next_tile
		dw (\1 - forest_next_tile) tiles, Forest_GFX + forest_next_tile tiles
	ENDC
	dw \2 tiles, forest_patch_source + \3 tiles
	REDEF forest_next_tile = \1 + \2
	REDEF forest_private_tiles = forest_private_tiles + \2
ENDM

MACRO forest_season_runs
	DEF forest_patch_source EQUS "\1"
	DEF forest_next_tile = 0
	DEF forest_private_tiles = 0
	forest_tree_runs
	ASSERT forest_private_tiles == 14
	ASSERT forest_next_tile < NUM_TILESET_TILES
	dw (NUM_TILESET_TILES - forest_next_tile) tiles, Forest_GFX + forest_next_tile tiles
	dw 0
	PURGE forest_patch_source, forest_next_tile, forest_private_tiles
ENDM

ProcForestCherryRuns:
	forest_season_runs ProcForestCherryTiles
ProcForestWinterRuns:
	forest_season_runs ProcForestWinterTiles

ProcForestCherryTiles:
	INCBIN "gfx/tilesets/forest_cherry.2bpp"
ProcForestWinterTiles:
	INCBIN "gfx/tilesets/forest_winter.2bpp"
	ASSERT BANK(Forest_GFX) == BANK(LoadProcForestTreeTiles)
	ASSERT BANK(ProcForestCherryTiles) == BANK(LoadProcForestTreeTiles)
	ASSERT BANK(ProcForestWinterTiles) == BANK(LoadProcForestTreeTiles)
	PURGE forest_tree_runs, forest_tree_run, forest_season_runs
