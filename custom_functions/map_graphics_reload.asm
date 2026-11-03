; Argument-free graphics setup routines moved from HOME. Their original labels
; remain as far-jump stubs, so callers keep the same interface. These bodies
; either use bank-aware helpers or tail-jump back into always-mapped HOME code.
; This complete reload unit lives with the seasonal tree patches in $1A.
SECTION "Map Graphics Reload", ROMX
LoadFontTilePatterns_::
	ldh a, [rLCDC]
	bit B_LCDC_ENABLE, a
	jr nz, .on
	ld hl, FontGraphics
	ld de, vFont
	ld bc, FontGraphicsEnd - FontGraphics
	ld a, BANK(FontGraphics)
	jp FarCopyDataDouble
.on
	ld de, FontGraphics
	ld hl, vFont
	lb bc, BANK(FontGraphics), (FontGraphicsEnd - FontGraphics) / TILE_1BPP_SIZE
	jp CopyVideoDataDouble

; Moved from home/overworld.asm. Callers: LoadMapData, ReloadMapData,
; ReloadTilesetTilePatterns (Bill's PC, evolution, trades, slots), all with the
; LCD off. DORM also owns vChars2 $60-$78 (constants/tileset_constants.asm), so
; it copies NUM_EXTENDED_TILESET_TILES; that is why every path that reloads the
; tileset also restores the Dorm's extra art.
LoadTilesetTilePatternData_::
	call LoadProcForestTreeTiles
	ret c ; seasonal path copied the complete sheet once
	ld a, [wTilesetGfxPtr]
	ld l, a
	ld a, [wTilesetGfxPtr + 1]
	ld h, a
	ld de, vTileset
	ld bc, NUM_TILESET_TILES tiles
	ld a, [wCurMapTileset]
	cp DORM
	jr nz, .copy
	ld bc, NUM_EXTENDED_TILESET_TILES tiles
.copy
	ld a, [wTilesetBank]
	jp FarCopyData2

LoadTextBoxTilePatterns_::
	; In the Dorm, $60-$78 are map tiles: load only the borders ($79-$7F) and
	; put the Dorm's own $60-$78 back, so every menu that restores the text box
	; also restores the room. Keyed on hCurMap, not wCurMapTileset: LoadMapData
	; calls this BEFORE LoadMapHeader, when the tileset (and wTilesetGfxPtr)
	; still belong to the previous map but hCurMap is already the destination.
	; That is also why the source is Dorm_GFX directly. SILPH_CO_DORM is the
	; only DORM map.
	ldh a, [hCurMap]
	cp SILPH_CO_DORM
	jr nz, .fullFont
	ldh a, [hIsInBattle]
	and a
	jr z, .dorm
.fullFont
	ldh a, [rLCDC]
	bit B_LCDC_ENABLE, a
	jr nz, .on
	ld hl, TextBoxGraphics
	ld de, vChars2 tile $60
	ld bc, TextBoxGraphicsEnd - TextBoxGraphics
	ld a, BANK(TextBoxGraphics)
	jp FarCopyData2
.on
	ld de, TextBoxGraphics
	ld hl, vChars2 tile $60
	lb bc, BANK(TextBoxGraphics), (TextBoxGraphicsEnd - TextBoxGraphics) / TILE_SIZE
	jp CopyVideoData

DEF DORM_BORDER_TILES EQU $80 - NUM_EXTENDED_TILESET_TILES
DEF DORM_EXTRA_TILES  EQU NUM_EXTENDED_TILESET_TILES - NUM_TILESET_TILES
ASSERT TextBoxGraphicsEnd - TextBoxGraphics == ($80 - NUM_TILESET_TILES) tiles, \
	"font_extra must cover vChars2 $60-$7F for the Dorm split below"
.dorm
	ldh a, [rLCDC]
	bit B_LCDC_ENABLE, a
	jr nz, .dormOn
	ld hl, TextBoxGraphics + DORM_EXTRA_TILES tiles
	ld de, vChars2 tile NUM_EXTENDED_TILESET_TILES
	ld bc, DORM_BORDER_TILES tiles
	ld a, BANK(TextBoxGraphics)
	call FarCopyData2
	ld hl, Dorm_GFX + NUM_TILESET_TILES tiles
	ld de, vChars2 tile NUM_TILESET_TILES
	ld bc, DORM_EXTRA_TILES tiles
	ld a, BANK(Dorm_GFX)
	jp FarCopyData2
.dormOn
	ld de, TextBoxGraphics + DORM_EXTRA_TILES tiles
	ld hl, vChars2 tile NUM_EXTENDED_TILESET_TILES
	lb bc, BANK(TextBoxGraphics), DORM_BORDER_TILES
	call CopyVideoData
	ld de, Dorm_GFX + NUM_TILESET_TILES tiles
	ld hl, vChars2 tile NUM_TILESET_TILES
	lb bc, BANK(Dorm_GFX), DORM_EXTRA_TILES
	jp CopyVideoData

INCLUDE "custom_functions/procedural_forest_graphics.asm"

