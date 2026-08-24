; Loads tile patterns for tiles used in the pokedex.
LoadPokedexTilePatterns:
	call LoadHpBarAndStatusTilePatterns
	ld de, PokedexTileGraphics
	ld hl, vChars2 tile $60
	lb bc, BANK(PokedexTileGraphics), (PokedexTileGraphicsEnd - PokedexTileGraphics) / TILE_SIZE
	call CopyVideoData
	ld de, PokeballTileGraphics
	ld hl, vChars2 tile $72
	lb bc, BANK(PokeballTileGraphics), 1
	call CopyVideoData ; load pokeball tile for marking caught mons
	; Yume base-stat bars temporarily replace unused Pokedex-screen tiles
	; $40-$50. ReloadMapData restores the overworld tileset after the menu exits.
	ld de, StatsBarGraphics
	ld hl, vChars2 tile $40
	lb bc, BANK(StatsBarGraphics), (StatsBarGraphicsEnd - StatsBarGraphics) / TILE_SIZE
	jp CopyVideoData
