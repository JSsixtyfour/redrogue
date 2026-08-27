PokemonLogoGraphics: INCBIN "gfx/title/pokemon_logo.2bpp"
FontGraphics::
	; Replace unused kana $e9/$ea without changing the 128-tile font layout.
	INCBIN "gfx/font/font.1bpp", 0, ($e9 - $80) * TILE_1BPP_SIZE
	; User-supplied 7x7 percent glyph, padded with a blank final row/column.
	db $c2, $c4, $08, $10, $20, $46, $86, $00
	; Yume 35d3bf9 font tile $ef: left arrow, remapped to our free $ea.
	db $0c, $1c, $3c, $7c, $3c, $1c, $0c, $00
	INCBIN "gfx/font/font.1bpp", ($eb - $80) * TILE_1BPP_SIZE
FontGraphicsEnd::
	ASSERT FontGraphicsEnd - FontGraphics == 128 * TILE_1BPP_SIZE

ABTiles: INCBIN "gfx/font/AB.2bpp"

HpBarAndStatusGraphics::
	; Yume 35d3bf9 HP artwork, reordered for our unchanged DrawHPBar IDs.
	; $62: label's right half; $63-$6b: empty through full; $6c: plain tip.
	INCBIN "gfx/font/hp_bar.2bpp", TILE_SIZE, 11 * TILE_SIZE
	; Preserve $6d's connected battle tip and $6e-$70's status glyphs.
	INCBIN "gfx/font/font_battle_extra.2bpp", 11 * TILE_SIZE, 4 * TILE_SIZE
	; $71 is our HP label's left half (Yume loads this at $62).
	INCBIN "gfx/font/hp_bar.2bpp", 0, TILE_SIZE
	; Preserve $72-$7f, including status, HUD borders and EXP-bar aliases.
	INCBIN "gfx/font/font_battle_extra.2bpp", 16 * TILE_SIZE
HpBarAndStatusGraphicsEnd::
	ASSERT HpBarAndStatusGraphicsEnd - HpBarAndStatusGraphics == 30 * TILE_SIZE

BattleHudTiles1: INCBIN "gfx/battle/battle_hud_1.1bpp"
BattleHudTiles1End:
BattleHudTiles2: INCBIN "gfx/battle/battle_hud_2.1bpp"
BattleHudTiles3: INCBIN "gfx/battle/battle_hud_3.1bpp"
BattleHudTiles3End:

NintendoCopyrightLogoGraphics: INCBIN "gfx/splash/copyright.2bpp"

GameFreakLogoGraphics: INCBIN "gfx/title/gamefreak_inc.2bpp"
GameFreakLogoGraphicsEnd:

TextBoxGraphics:: INCBIN "gfx/font/font_extra.2bpp"
TextBoxGraphicsEnd::

PokedexTileGraphics: INCBIN "gfx/pokedex/pokedex.2bpp"
PokedexTileGraphicsEnd:

WorldMapTileGraphics: INCBIN "gfx/town_map/town_map.2bpp"
WorldMapTileGraphicsEnd:

PlayerCharacterTitleGraphics: INCBIN "gfx/title/player.2bpp"
PlayerCharacterTitleGraphicsEnd:
